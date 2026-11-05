package com.opiconnect.companion

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.VibratorManager
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

// "Find my phone": loops the alarm sound at max alarm volume + vibrates, until the
// watch stops it, the notification action fires, the app opens, or 2 min elapse.
// Each part (sound, volume, vibration, notification) is started independently so one
// failing step doesn't cancel the others; failures are surfaced via AppState.
object FindPhone {
    private const val TAG = "OpiFindPhone"
    private const val CHANNEL = "findphone"
    private const val NOTIF_ID = 2
    private const val ACTION_STOP = "com.opiconnect.companion.FINDPHONE_STOP"
    private const val AUTO_STOP_MS = 120_000L
    private const val TONE_REPEAT_MS = 1_500L

    private val _ringing = MutableStateFlow(false)
    val ringing: StateFlow<Boolean> = _ringing

    private val handler = Handler(Looper.getMainLooper())
    private var appContext: Context? = null
    private var ringtone: Ringtone? = null
    private var tone: ToneGenerator? = null
    private var vibrating = false
    private var savedVolume = -1
    private val autoStop = Runnable { appContext?.let { stopNow(it) } }
    private val toneLoop = object : Runnable {
        override fun run() {
            tone?.startTone(ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD, 1_000)
            handler.postDelayed(this, TONE_REPEAT_MS)
        }
    }

    // Called from GATT Binder threads: all work happens on the main looper.
    fun set(context: Context, on: Boolean) {
        val app = context.applicationContext
        handler.post { if (on) startNow(app) else stopNow(app) }
    }

    fun stop(context: Context) {
        val app = context.applicationContext
        handler.post { stopNow(app) }
    }

    private fun startNow(app: Context) {
        if (_ringing.value) return
        appContext = app
        val am = app.getSystemService(AudioManager::class.java)

        attempt("volume") {
            savedVolume = am.getStreamVolume(AudioManager.STREAM_ALARM)
            am.setStreamVolume(AudioManager.STREAM_ALARM, am.getStreamMaxVolume(AudioManager.STREAM_ALARM), 0)
        }
        val sound = attempt("sound") { startSound(app) } == true
        val vibration = attempt("vibration") {
            val vibrator = app.getSystemService(VibratorManager::class.java).defaultVibrator
            val effect = VibrationEffect.createWaveform(longArrayOf(0, 500, 300, 500), 0)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                vibrator.vibrate(effect, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_ALARM))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(effect, AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build())
            }
            vibrating = true
            true
        } == true

        if (!sound && !vibration) {
            restoreVolume(app)
            AppState.setError(app.getString(R.string.findphone_no_output))
            broadcastState()
            return
        }
        _ringing.value = true
        attempt("notification") { showNotification(app) }
        handler.postDelayed(autoStop, AUTO_STOP_MS)
        broadcastState()
    }

    // Ringtone handles content URIs itself; fall back through alarm → ringtone →
    // notification sounds, then to a generated tone on the alarm stream.
    private fun startSound(app: Context): Boolean {
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        for (type in intArrayOf(RingtoneManager.TYPE_ALARM, RingtoneManager.TYPE_RINGTONE, RingtoneManager.TYPE_NOTIFICATION)) {
            val uri = RingtoneManager.getDefaultUri(type) ?: continue
            val r = runCatching { RingtoneManager.getRingtone(app, uri) }.getOrNull() ?: continue
            val ok = runCatching {
                r.audioAttributes = attrs
                r.isLooping = true
                r.play()
                true
            }.getOrElse { Log.w(TAG, "ringtone type $type failed: $it"); false }
            if (ok) {
                ringtone = r
                return true
            }
        }
        tone = ToneGenerator(AudioManager.STREAM_ALARM, ToneGenerator.MAX_VOLUME)
        handler.post(toneLoop)
        return true
    }

    private fun stopNow(app: Context) {
        if (!_ringing.value) return
        _ringing.value = false
        handler.removeCallbacks(autoStop)
        handler.removeCallbacks(toneLoop)
        runCatching { ringtone?.stop() }
        ringtone = null
        runCatching { tone?.release() }
        tone = null
        if (vibrating) runCatching { app.getSystemService(VibratorManager::class.java).defaultVibrator.cancel() }
        vibrating = false
        restoreVolume(app)
        runCatching { app.getSystemService(NotificationManager::class.java).cancel(NOTIF_ID) }
        broadcastState()
    }

    private fun restoreVolume(app: Context) {
        if (savedVolume < 0) return
        runCatching {
            app.getSystemService(AudioManager::class.java).setStreamVolume(AudioManager.STREAM_ALARM, savedVolume, 0)
        }
        savedVolume = -1
    }

    // Runs one step; logs and reports a failure without throwing.
    private fun <T> attempt(step: String, block: () -> T): T? = try {
        block()
    } catch (e: Exception) {
        Log.w(TAG, "$step failed", e)
        appContext?.let {
            AppState.setError(
                it.getString(R.string.findphone_step_failed, step, e.javaClass.simpleName),
            )
        }
        null
    }

    private fun broadcastState() {
        LinkService.instance?.sendAll(com.opiconnect.companion.core.Messages.FindPhoneState(_ringing.value))
    }

    private fun showNotification(context: Context) {
        val nm = context.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(
                CHANNEL,
                context.getString(R.string.findphone_channel),
                NotificationManager.IMPORTANCE_HIGH,
            ),
        )
        val stopPi = PendingIntent.getBroadcast(
            context, 0,
            Intent(ACTION_STOP).setPackage(context.packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val contentPi = PendingIntent.getActivity(
            context, 0, Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )
        nm.notify(
            NOTIF_ID,
            NotificationCompat.Builder(context, CHANNEL)
                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setContentTitle(context.getString(R.string.findphone_notif_title))
                .setContentIntent(contentPi)
                .addAction(0, context.getString(R.string.findphone_stop), stopPi)
                .setOngoing(true)
                .build(),
        )
    }

    // Receives the notification "Stop" action (registered in the manifest, not exported).
    class StopReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == ACTION_STOP) stop(context)
        }
    }
}
