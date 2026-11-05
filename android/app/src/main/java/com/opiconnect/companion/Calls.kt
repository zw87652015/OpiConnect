package com.opiconnect.companion

import android.app.Notification
import android.app.PendingIntent
import android.app.Person
import android.content.Context
import android.graphics.drawable.Icon

// Incoming-call helpers. CallStyle keeps Answer/Decline as PendingIntents in extras (not in
// Notification.actions), and "android.callType" is the literal key for EXTRA_CALL_TYPE (API 34+).
object Calls {
    private const val EXTRA_CALL_TYPE = "android.callType"
    private const val CALL_TYPE_INCOMING = 1
    private const val CALL_TYPE_SCREENING = 3

    fun isRinging(n: Notification): Boolean {
        if (n.category != Notification.CATEGORY_CALL) return false
        val e = n.extras
        if (e.containsKey(EXTRA_CALL_TYPE)) {
            val type = e.getInt(EXTRA_CALL_TYPE)
            return type == CALL_TYPE_INCOMING || type == CALL_TYPE_SCREENING
        }
        return n.fullScreenIntent != null
    }

    @Suppress("DEPRECATION")
    fun caller(n: Notification): String? =
        n.extras.getParcelable<Person>(Notification.EXTRA_CALL_PERSON)
            ?.name?.toString()?.takeIf { it.isNotBlank() }

    @Suppress("DEPRECATION")
    fun actions(context: Context, n: Notification): List<Notification.Action> {
        val e = n.extras
        fun action(label: Int, key: String): Notification.Action? =
            e.getParcelable<PendingIntent>(key)?.let {
                Notification.Action.Builder(null as Icon?, context.getString(label), it).build()
            }
        val decline = action(R.string.call_decline, Notification.EXTRA_DECLINE_INTENT)
            ?: action(R.string.call_decline, Notification.EXTRA_HANG_UP_INTENT)
        val answer = action(R.string.call_answer, Notification.EXTRA_ANSWER_INTENT)
        return listOfNotNull(decline, answer) + n.actions.orEmpty()
    }
}
