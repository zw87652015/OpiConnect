package com.opiconnect.companion

import android.content.ComponentName
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class OpiListenerService : NotificationListenerService() {

    companion object {
        @Volatile var instance: OpiListenerService? = null
            private set
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
