package com.opiconnect.companion

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class OpiListenerService : NotificationListenerService() {

    companion object {
        @Volatile var instance: OpiListenerService? = null
            private set

        // After a force-stop or an OEM kill the system often doesn't rebind the listener
        // even though access is still granted. Ask for a rebind; if that doesn't take,
        // toggling the component makes NotificationManagerService bind it again.
        fun ensureBound(context: Context) {
            if (instance != null) return
            val component = ComponentName(context, OpiListenerService::class.java)
            runCatching { NotificationListenerService.requestRebind(component) }
            Handler(Looper.getMainLooper()).postDelayed({
                if (instance != null) return@postDelayed
                val pm = context.packageManager
                pm.setComponentEnabledSetting(component,
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
                pm.setComponentEnabledSetting(component,
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
            }, 2000)
        }
    }

    override fun onListenerConnected() {
        instance = this
        if (PairingStore.isPaired(this)) LinkService.start(this)
    }

    override fun onListenerDisconnected() {
        instance = null
        requestRebind(ComponentName(this, OpiListenerService::class.java))
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        Router.onPosted(sbn)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification, rankingMap: RankingMap?, reason: Int) {
        Router.onRemoved(sbn, reason)
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }
}
