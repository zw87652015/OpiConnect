package com.opiconnect.companion

import android.app.ActivityOptions
import android.app.PendingIntent
import android.app.RemoteInput
import android.content.Intent
import android.os.Bundle
import android.service.notification.StatusBarNotification
import android.util.Log
import com.opiconnect.companion.core.Crypto

// Executes watch-initiated dismiss/actions on the live Android notifications.
object ActionExecutor {
    private const val TAG = "OpiActions"

    private fun find(id: String): StatusBarNotification? =
        OpiListenerService.instance?.activeNotifications?.firstOrNull {
            Crypto.notifId(it.key) == id
        }

    fun dismiss(id: String) {
        val context = OpiListenerService.instance ?: LinkService.instance
        if (context != null && CardStore.isCard(context, id)) {
            CardStore.setOnWatch(context, id, false)
            return
        }
        val sbn = find(id) ?: return
        Router.markDismissedByWatch(id)
        OpiListenerService.instance?.cancelNotification(sbn.key)
    }

    fun run(id: String, idx: Int, label: String, text: String?) {
        val service = OpiListenerService.instance ?: return
        val sbn = find(id) ?: run {
            AppState.setError(service.getString(R.string.error_notif_gone))
            return
        }
        val action = sbn.notification.actions?.getOrNull(idx)
        if (action == null || action.title?.toString() != label) {
            Log.w(TAG, "action $idx label mismatch for $id")
            AppState.setError(service.getString(R.string.error_action_gone))
            return
        }
        val options = ActivityOptions.makeBasic()
            .setPendingIntentBackgroundActivityStartMode(ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED)
            .toBundle()
        try {
            val remoteInputs = action.remoteInputs
            if (text != null && !remoteInputs.isNullOrEmpty()) {
                val results = Bundle().apply {
                    remoteInputs.forEach { putCharSequence(it.resultKey, text) }
                }
                val intent = Intent()
                RemoteInput.addResultsToIntent(remoteInputs, intent, results)
                action.actionIntent.send(service, 0, intent, null, null, null, options)
            } else {
                action.actionIntent.send(service, 0, null, null, null, null, options)
            }
        } catch (e: PendingIntent.CanceledException) {
            Log.w(TAG, "action intent canceled for $id")
            AppState.setError(service.getString(R.string.error_action_gone))
        }
    }
}
