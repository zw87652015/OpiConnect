package com.opiconnect.companion

import android.app.Notification
import android.content.Context
import android.content.pm.PackageManager
import android.os.PowerManager
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import com.opiconnect.companion.core.ActionInfo
import com.opiconnect.companion.core.Crypto
import com.opiconnect.companion.core.Messages
import com.opiconnect.companion.core.NotifPayload
import com.opiconnect.companion.core.RelaySeal
import com.opiconnect.companion.core.cardPayload
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap

// Decides BLE vs relay for each notification and builds the payload (docs/PROTOCOL.md).
object Router {
    private const val TAG = "OpiRouter"
    private const val ACK_TIMEOUT_MS = 3000L

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    // id -> hash of forwarded content, for dedupe of re-posted notifications
    private val forwarded = ConcurrentHashMap<String, Int>()
    private val acks = ConcurrentHashMap<String, CompletableDeferred<Unit>>()
    private val dismissedByWatch = ConcurrentHashMap.newKeySet<String>()

    private val labels = ConcurrentHashMap<String, String>()

    fun onPosted(sbn: StatusBarNotification) {
        val context = OpiListenerService.instance ?: return
        if (ForwardPrefs.screenOffOnly(context) &&
            context.getSystemService(PowerManager::class.java)?.isInteractive == true
        ) return
        val payload = buildPayload(context, sbn) ?: return
        val hash = contentHash(payload)
        if (forwarded[payload.i] == hash) return // same content re-posted
        forwarded[payload.i] = hash
        deliver(payload)
    }

    fun onRemoved(sbn: StatusBarNotification, reason: Int) {
        val id = Crypto.notifId(sbn.key)
        if (!forwarded.containsKey(id)) return
        // A dismiss we triggered ourselves from the watch is already reflected there.
        if (reason == NotificationListenerService.REASON_LISTENER_CANCEL && dismissedByWatch.remove(id)) {
            forwarded.remove(id)
            return
        }
        forwarded.remove(id)
        sendRemove(id)
    }

    // Called by LinkService when the watch acks a notification id.
    fun onAck(id: String) {
        acks.remove(id)?.complete(Unit)
    }

    fun markDismissedByWatch(id: String) {
        dismissedByWatch.add(id)
    }

    // Ids of currently active notifications that would be forwarded (for BLE sync).
    fun activeIds(): List<String> {
        val service = OpiListenerService.instance ?: return emptyList()
        return service.activeNotifications
            .filter { passesFilter(it) }
            .map { Crypto.notifId(it.key) } + CardStore.onWatchIds(service)
    }

    // Synthetic notification routed through the normal delivery path (test button).
    fun test() {
        val payload = NotifPayload(
            i = Crypto.notifId("opi-test-" + System.currentTimeMillis()),
            p = "com.opiconnect.test",
            a = "OpiLink",
            t = "Test",
            b = "Hello from Android — 你好",
            w = System.currentTimeMillis(),
            x = listOf(ActionInfo("Reply", true), ActionInfo("Mark read", false)),
        )
        deliver(payload)
    }

    // Sends a DIY card through the normal delivery path and marks it on the watch.
    fun sendCard(context: Context, card: OpiCard) {
        val snap = PhoneStatus.current()
        deliver(
            cardPayload(
                id = card.id,
                label = card.label.ifEmpty { "OpiLink" },
                code = card.code,
                note = card.note,
                bt = snap.bt.takeIf { it >= 0 },
                bc = snap.bc,
            ),
        )
        CardStore.setOnWatch(context, card.id, true)
    }

    // Removes a card from the watch and marks it off-watch in the library.
    fun removeCard(context: Context, id: String) {
        sendRemove(id)
        CardStore.setOnWatch(context, id, false)
    }

    // MARK: internals

    private fun sendRemove(id: String) {
        scope.launch {
            val link = LinkService.instance
            val sentBle = link != null && link.anyAuthenticated() && link.sendAll(Messages.Remove(id))
            if (!sentBle) {
                val keys = keys() ?: return@launch
                val o = JSONObject().put("i", id)
                val snap = PhoneStatus.current()
                if (snap.bt >= 0) o.put("bt", snap.bt).put("bc", snap.bc)
                val sealed = Crypto.base64url(
                    Crypto.seal(o.toString().toByteArray(Charsets.UTF_8), keys.encKey),
                )
                RelayClient.push(keys, "remove", id, sealed)
            }
        }
    }

    private fun deliver(payload: NotifPayload) {
        scope.launch {
            val link = LinkService.instance
            val watch = link?.activeWatch()
            if (watch != null && link != null) {
                val ack = CompletableDeferred<Unit>()
                acks[payload.i] = ack
                link.send(watch, Messages.Notif(payload))
                if (withTimeoutOrNull(ACK_TIMEOUT_MS) { ack.await() } != null) return@launch
                Log.i(TAG, "no BLE ack for ${payload.i}, falling back to relay")
            }
            val keys = keys() ?: return@launch
            RelayClient.push(keys, "alert", payload.i, RelaySeal.sealForRelay(payload, keys.encKey))
        }
    }

    private fun keys() = OpiListenerService.instance?.let { PairingStore.keys(it) }

    private fun passesFilter(sbn: StatusBarNotification): Boolean {
        val context = OpiListenerService.instance
        if (sbn.packageName == context?.packageName) return false
        if (context != null && !ForwardPrefs.allows(context, sbn.packageName)) return false
        if (sbn.isOngoing) return false
        // Calendar apps: when watch reminders are active, their notifications would duplicate.
        if (context != null && CalendarSync.hasPermission(context) &&
            sbn.packageName in CalendarApps.packages(context)
        ) return false
        val flags = sbn.notification.flags
        if (flags and Notification.FLAG_GROUP_SUMMARY != 0) return false
        if (flags and Notification.FLAG_FOREGROUND_SERVICE != 0) return false
        val e = sbn.notification.extras
        val title = e.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = e.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()
        if (title.isEmpty() && text.isEmpty()) return false
        return true
    }

    private fun buildPayload(context: Context, sbn: StatusBarNotification): NotifPayload? {
        if (!passesFilter(sbn)) return null
        val n = sbn.notification
        val e = n.extras
        val title = e.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        var body = e.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
            ?: e.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()
        if (body.isEmpty()) {
            // MessagingStyle: use the last message text when EXTRA_TEXT is empty.
            body = messagingStyleText(e) ?: ""
        }
        val actions = n.actions?.take(3)?.map { action ->
            ActionInfo(
                l = action.title?.toString().orEmpty(),
                r = action.remoteInputs?.any { it.allowFreeFormInput } == true,
            )
        } ?: emptyList()
        return NotifPayload(
            i = Crypto.notifId(sbn.key),
            p = sbn.packageName,
            a = appLabel(context, sbn.packageName),
            t = title,
            b = body,
            w = sbn.postTime,
            x = actions,
            bt = PhoneStatus.current().bt.takeIf { it >= 0 },
            bc = PhoneStatus.current().bc,
        )
    }

    private fun messagingStyleText(e: android.os.Bundle): String? {
        val messages = e.getParcelableArray(Notification.EXTRA_MESSAGES) ?: return null
        val last = messages.lastOrNull() as? android.os.Bundle ?: return null
        return last.getCharSequence("text")?.toString()
    }

    private fun appLabel(context: Context, pkg: String): String =
        labels.getOrPut(pkg) {
            runCatching {
                context.packageManager.getApplicationLabel(
                    context.packageManager.getApplicationInfo(pkg, PackageManager.ApplicationInfoFlags.of(0)),
                ).toString()
            }.getOrDefault(pkg)
        }

    private fun contentHash(p: NotifPayload): Int = listOf(p.t, p.b, p.x.toString()).hashCode()
}
