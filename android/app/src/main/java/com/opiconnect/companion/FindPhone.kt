package com.opiconnect.companion

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

// "Find my phone": loops the alarm ringtone at max alarm volume + vibrates, until the
// watch stops it, the notification action fires, the app opens, or 2 min elapse.
object FindPhone {
    private const val CHANNEL = "findphone"
    private const val NOTIF_ID = 2
    private const val ACTION_STOP = "com.opiconnect.companion.FINDPHONE_STOP"
    private const val AUTO_STOP_MS = 120_000L

    private val _ringing = MutableStateFlow(false)
    val ringing: StateFlow<Boolean> = _ringing

    private var player: MediaPlayer? = null
    private var savedVolume = -1
    private var appContext: Context? = null
    private val handler = Handler(Looper.getMainLooper())
    private val autoStop = Runnable { appContext?.let { stop(it) } }

    fun start(context: Context) {
        if (_ringing.value) return
        val app = context.applicationContext
        appContext = app
        _ringing.value = true
        broadcastState(app)
        try {
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            player = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .build(),
                )
                setDataSource(app, uri)
                isLooping = true
                prepare()
                start()
            }
            val am = app.getSystemService(AudioManager::class.java)
            savedVolume = am?.getStreamVolume(AudioManager.STREAM_ALARM) ?: -1
            am?.setStreamVolume(
                AudioManager.STREAM_ALARM,
                am.getStreamMaxVolume(AudioManager.STREAM_ALARM), 0,
            )
            val vibrator = (app.getSystemService(VibratorManager::class.java))?.defaultVibrator
            vibrator?.vibrate(
                VibrationEffect.createWaveform(longArrayOf(0, 500, 300, 500), 0),
            )
            showNotification(app)
            handler.postDelayed(autoStop, AUTO_STOP_MS)
        } catch (e: Exception) {
            stop(app)
        }
    }

    fun stop(context: Context) {
        if (!_ringing.value) return
        val app = context.applicationContext
        _ringing.value = false
        handler.removeCallbacks(autoStop)
        runCatching { player?.stop() }
        player?.release()
        player = null
        val am = app.getSystemService(AudioManager::class.java)
        if (savedVolume >= 0) am?.setStreamVolume(AudioManager.STREAM_ALARM, savedVolume, 0)
        savedVolume = -1
        (app.getSystemService(VibratorManager::class.java))?.defaultVibrator?.cancel()
        app.getSystemService(NotificationManager::class.java)?.cancel(NOTIF_ID)
        broadcastState(app)
    }

    fun set(context: Context, on: Boolean) {
        if (on) start(context) else stop(context)
    }

    private fun broadcastState(context: Context) {
        LinkService.instance?.sendAll(com.opiconnect.companion.core.Messages.FindPhoneState(_ringing.value))
    }

    private fun showNotification(context: Context) {
        val nm = context.getSystemService(NotificationManager::class.java) ?: return
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL, "Find phone", NotificationManager.IMPORTANCE_HIGH),
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
                .setContentTitle("Your watch is looking for this phone")
                .setContentIntent(contentPi)
                .addAction(0, "Stop", stopPi)
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
