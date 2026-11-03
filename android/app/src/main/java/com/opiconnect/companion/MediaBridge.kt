package com.opiconnect.companion

import android.content.ComponentName
import android.content.Context
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.opiconnect.companion.core.Messages
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

// Mirrors the phone's media session to the watch and executes watch media commands.
// We can read sessions because OpiConnect is an enabled notification listener.
object MediaBridge {
    private const val TAG = "OpiMedia"
    private const val DEBOUNCE_MS = 300L

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

    private val sessionsListener =
        MediaSessionManager.OnActiveSessionsChangedListener { list -> onSessionsChanged(list) }

    private val sendDebounced = Runnable {
        context?.let { ctx ->
            val s = _state.value
            LinkService.instance?.sendAll(
                Messages.MediaState(s.on, s.app, s.title, s.artist, s.playing, s.volume),
            )
        }
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
        val am = ctx.getSystemService(AudioManager::class.java)
        val max = am?.getStreamMaxVolume(AudioManager.STREAM_MUSIC) ?: 1
        val vol = if (max > 0) (am?.getStreamVolume(AudioManager.STREAM_MUSIC) ?: 0).toFloat() / max else 0f
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
                val am = ctx.getSystemService(AudioManager::class.java) ?: return
                val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                am.setStreamVolume(
                    AudioManager.STREAM_MUSIC,
                    ((v ?: 0f).coerceIn(0f, 1f) * max).toInt(), 0,
                )
            }
        }
        scheduleUpdate()
    }

    // Push the current state to a connection right after hello.
    fun sendStateNow() {
        val s = _state.value
        LinkService.instance?.sendAll(
            Messages.MediaState(s.on, s.app, s.title, s.artist, s.playing, s.volume),
        )
    }
}
