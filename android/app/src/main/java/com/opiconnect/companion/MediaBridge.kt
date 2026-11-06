package com.opiconnect.companion

import android.content.ComponentName
import android.content.Context
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.VolumeProvider
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.opiconnect.companion.core.Messages
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlin.math.roundToInt

// Mirrors the phone's media session to the watch and executes watch media commands.
// We can read sessions because OpiConnect is an enabled notification listener.
object MediaBridge {
    private const val TAG = "OpiMedia"
    private const val DEBOUNCE_MS = 300L
    private const val VOLUME_READ_INTERVAL_MS = 40L
    private const val VOLUME_READ_ATTEMPTS = 5

    data class State(
        val on: Boolean = false,
        val app: String = "",
        val title: String = "",
        val artist: String = "",
        val playing: Boolean = false,
        val volume: Float = 0f,
    )

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state

    private var context: Context? = null
    private var sessionManager: MediaSessionManager? = null
    private var listenerComponent: ComponentName? = null
    private val controllers = mutableMapOf<String, MediaController>()
    private val handler = Handler(Looper.getMainLooper())
    private var started = false
    private var volumeReadback: Runnable? = null

    private val sessionsListener =
        MediaSessionManager.OnActiveSessionsChangedListener { list -> onSessionsChanged(list) }

    private val sendDebounced = Runnable {
        if (context != null) sendStateNow()
    }

    fun start(context: Context) {
        if (started) return
        this.context = context.applicationContext
        listenerComponent = ComponentName(context, OpiListenerService::class.java)
        sessionManager = context.getSystemService(MediaSessionManager::class.java)
        started = true
        refreshControllers()
        runCatching {
            sessionManager?.addOnActiveSessionsChangedListener(sessionsListener, listenerComponent)
        }.onFailure { Log.w(TAG, "sessions listener failed: $it") }
        updateState()
    }

    fun stop(context: Context) {
        cancelVolumeReadback()
        runCatching {
            sessionManager?.removeOnActiveSessionsChangedListener(sessionsListener)
        }
        controllers.values.forEach { it.unregisterCallback(controllerCallback) }
        controllers.clear()
        started = false
        this.context = null
    }

    private fun onSessionsChanged(list: MutableList<MediaController>?) {
        refreshControllers(list)
        updateState()
    }

    private fun refreshControllers(list: List<MediaController>? = null) {
        val active = list ?: runCatching {
            sessionManager?.getActiveSessions(listenerComponent)
        }.getOrNull() ?: emptyList()
        val wanted = active.associateBy { it.packageName }
        (controllers.keys - wanted.keys).forEach {
            controllers.remove(it)?.unregisterCallback(controllerCallback)
        }
        wanted.forEach { (pkg, controller) ->
            if (!controllers.containsKey(pkg)) {
                controllers[pkg] = controller
                runCatching { controller.registerCallback(controllerCallback, handler) }
            }
        }
    }

    private val controllerCallback = object : MediaController.Callback() {
        override fun onMetadataChanged(metadata: MediaMetadata?) = scheduleUpdate()
        override fun onPlaybackStateChanged(state: PlaybackState?) = scheduleUpdate()
        override fun onSessionDestroyed() {
            scheduleUpdate()
        }
    }

    private fun scheduleUpdate() {
        updateState()
        handler.removeCallbacks(sendDebounced)
        handler.postDelayed(sendDebounced, DEBOUNCE_MS)
    }

    private fun updateState() {
        val ctx = context ?: return
        val playing = controllers.values.firstOrNull {
            it.playbackState?.state == PlaybackState.STATE_PLAYING
        }
        val controller = playing ?: controllers.values.firstOrNull()
        val vol = ctx.getSystemService(AudioManager::class.java)?.let { musicVolume(it) } ?: 0f
        if (controller == null) {
            _state.value = State(volume = vol)
            return
        }
        val md = controller.metadata
        _state.value = State(
            on = true,
            app = appLabel(ctx, controller.packageName),
            title = md?.getString(MediaMetadata.METADATA_KEY_TITLE).orEmpty(),
            artist = md?.getString(MediaMetadata.METADATA_KEY_ARTIST).orEmpty(),
            playing = controller.playbackState?.state == PlaybackState.STATE_PLAYING,
            volume = vol,
        )
    }

    private fun appLabel(ctx: Context, pkg: String): String = runCatching {
        ctx.packageManager.getApplicationLabel(
            ctx.packageManager.getApplicationInfo(pkg, 0),
        ).toString()
    }.getOrDefault(pkg)

    private fun musicVolume(am: AudioManager, index: Int = am.getStreamVolume(AudioManager.STREAM_MUSIC)): Float {
        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        return if (max > 0) index.toFloat() / max else 0f
    }

    // MARK: commands from the watch

    // GATT callbacks arrive on Binder threads; controllers are only touched on the main looper.
    fun command(cmd: String, v: Float?) {
        handler.post { runCommand(cmd, v) }
    }

    private fun runCommand(cmd: String, v: Float?) {
        val ctx = context ?: return
        val controller = controllers.values.firstOrNull {
            it.playbackState?.state == PlaybackState.STATE_PLAYING
        } ?: controllers.values.firstOrNull()
        when (cmd) {
            "toggle" -> controller?.transportControls?.let {
                if (controller.playbackState?.state == PlaybackState.STATE_PLAYING) it.pause() else it.play()
            }
            "play" -> controller?.transportControls?.play()
            "pause" -> controller?.transportControls?.pause()
            "next" -> controller?.transportControls?.skipToNext()
            "prev" -> controller?.transportControls?.skipToPrevious()
            "vol" -> {
                setMusicVolume(ctx, controller, v ?: 0f)
                return
            }
        }
        scheduleUpdate()
    }

    private fun setMusicVolume(ctx: Context, controller: MediaController?, target: Float) {
        if (!target.isFinite()) return
        val am = ctx.getSystemService(AudioManager::class.java) ?: return
        val stream = AudioManager.STREAM_MUSIC
        val index = (target.coerceIn(0f, 1f) * am.getStreamMaxVolume(stream)).roundToInt()
        cancelVolumeReadback()

        val playback = controller?.playbackInfo
        if (controller != null && playback != null &&
            playback.playbackType == MediaController.PlaybackInfo.PLAYBACK_TYPE_LOCAL &&
            playback.volumeControl == VolumeProvider.VOLUME_CONTROL_ABSOLUTE
        ) {
            val sessionStream = playback.audioAttributes.volumeControlStream
            if (sessionStream == stream || sessionStream == AudioManager.USE_DEFAULT_STREAM_TYPE) {
                try {
                    // Route through the local session so Android handles its output volume.
                    controller.setVolumeTo(index, 0)
                    readBackSessionVolume(am, index)
                    return
                } catch (e: SecurityException) {
                    Log.w(TAG, "Couldn't set media session volume", e)
                }
            }
        }

        try {
            am.setStreamVolume(stream, index, 0)
        } catch (e: SecurityException) {
            Log.w(TAG, "Couldn't set media stream volume", e)
        }
        publishVolume(musicVolume(am))
    }

    private fun readBackSessionVolume(am: AudioManager, requestedIndex: Int) {
        // MediaController dispatches asynchronously. Check for the applied index without
        // writing again if Android caps the volume or the user changes it on the phone.
        val readback = object : Runnable {
            private var attempts = 0

            override fun run() {
                val index = am.getStreamVolume(AudioManager.STREAM_MUSIC)
                val volume = musicVolume(am, index)
                attempts++
                val done = index == requestedIndex || attempts >= VOLUME_READ_ATTEMPTS
                if (done || volume != _state.value.volume) publishVolume(volume)
                if (done) {
                    volumeReadback = null
                } else {
                    handler.postDelayed(this, VOLUME_READ_INTERVAL_MS)
                }
            }
        }
        volumeReadback = readback
        handler.postDelayed(readback, VOLUME_READ_INTERVAL_MS)
    }

    private fun cancelVolumeReadback() {
        volumeReadback?.let { handler.removeCallbacks(it) }
        volumeReadback = null
    }

    private fun publishVolume(volume: Float) {
        _state.value = _state.value.copy(volume = volume)
        handler.removeCallbacks(sendDebounced)
        sendStateNow()
    }

    private fun sendStateNow() {
        val s = _state.value
        LinkService.instance?.sendAll(
            Messages.MediaState(s.on, s.app, s.title, s.artist, s.playing, s.volume),
        )
    }
}
