package com.opiconnect.companion

import android.Manifest
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.CalendarContract
import android.util.Log
import androidx.core.content.ContextCompat
import com.opiconnect.companion.core.CalEvent
import com.opiconnect.companion.core.CalMessage
import com.opiconnect.companion.core.CalendarPayload
import com.opiconnect.companion.core.Messages

// Reads CalendarContract (visible events, not declined) for the next 30 days and
// builds the `cal` message. A ContentObserver re-sends it (debounced) on change.
object CalendarSync {
    private const val TAG = "OpiCal"
    private const val DEBOUNCE_MS = 3000L
    private const val DAYS = 30L

    private val handler = Handler(Looper.getMainLooper())
    private var context: Context? = null
    private var observer: ContentObserver? = null
    var lastBuilt: CalMessage? = null
        private set
    private var queryFailed = false

    fun hasPermission(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CALENDAR) ==
            PackageManager.PERMISSION_GRANTED

    fun start(context: Context) {
        this.context = context.applicationContext
        if (!hasPermission(context)) return
        if (observer != null) return
        val obs = object : ContentObserver(handler) {
            override fun onChange(selfChange: Boolean) { schedule() }
        }
        observer = obs
        val cr = context.contentResolver
        cr.registerContentObserver(CalendarContract.Events.CONTENT_URI, true, obs)
        cr.registerContentObserver(CalendarContract.Instances.CONTENT_URI, true, obs)
    }

    fun stop(context: Context) {
        observer?.let { context.contentResolver.unregisterContentObserver(it) }
        observer = null
        handler.removeCallbacks(sendNow)
    }

    fun schedule() {
        handler.removeCallbacks(sendNow)
        handler.postDelayed(sendNow, DEBOUNCE_MS)
    }

    private val sendNow = Runnable { sendUpdates() }

    // Rebuilds and sends cal to every connection whose last-seen hash differs.
    fun sendUpdates() {
        val ctx = context ?: return
        if (!hasPermission(ctx)) return
        val msg = build(ctx) ?: return
        lastBuilt = msg
        LinkService.instance?.sendCal(msg)
    }

    fun build(context: Context): CalMessage? {
        val from = run {
            val c = java.util.Calendar.getInstance()
            c.set(java.util.Calendar.HOUR_OF_DAY, 0)
            c.set(java.util.Calendar.MINUTE, 0)
            c.set(java.util.Calendar.SECOND, 0)
            c.set(java.util.Calendar.MILLISECOND, 0)
            c.timeInMillis
        }
        val to = System.currentTimeMillis() + DAYS * 24 * 3600 * 1000

        val instancesUri = ContentUris.withAppendedId(
            CalendarContract.Instances.CONTENT_URI, from,
        ).let { ContentUris.withAppendedId(it, to) }

        val projection = arrayOf(
            CalendarContract.Instances.EVENT_ID,
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END,
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.ALL_DAY,
            CalendarContract.Instances.EVENT_LOCATION,
            CalendarContract.Instances.DESCRIPTION,
            CalendarContract.Instances.CALENDAR_DISPLAY_NAME,
            CalendarContract.Instances.DISPLAY_COLOR,
        )
        val selection = "${CalendarContract.Instances.VISIBLE} = 1 AND " +
            "(${CalendarContract.Instances.SELF_ATTENDEE_STATUS} IS NULL OR " +
            "${CalendarContract.Instances.SELF_ATTENDEE_STATUS} != ?)"
        val events = ArrayList<CalEvent>()
        val remindersCache = HashMap<Long, List<Int>>()
        queryFailed = false

        runCatching {
            context.contentResolver.query(
                instancesUri, projection, selection,
                arrayOf(CalendarContract.Attendees.ATTENDEE_STATUS_DECLINED.toString()),
                "${CalendarContract.Instances.BEGIN} ASC",
            )?.use { c ->
                while (c.moveToNext()) {
                    val eventId = c.getLong(0)
                    val reminders = remindersCache.getOrPut(eventId) { loadReminders(context, eventId) }
                    events.add(
                        CalendarPayload.makeEvent(
                            eventId = eventId,
                            beginMs = c.getLong(1),
                            endMs = c.getLong(2),
                            title = c.getString(3) ?: "",
                            allDay = c.getInt(4) == 1,
                            location = c.getString(5) ?: "",
                            notes = c.getString(6) ?: "",
                            calendar = c.getString(7) ?: "",
                            color = c.getLong(8),
                            reminders = reminders,
                        ),
                    )
                }
            }
        }.onFailure {
            Log.w(TAG, "calendar query failed: $it")
            queryFailed = true
            AppState.setCalendarFound(
                context.getString(R.string.cal_query_failed, it.javaClass.simpleName, it.message),
            )
        }

        val msg = CalendarPayload.build(events, from, to)
        val (total, visible) = calendarCounts(context)
        val found = context.getString(R.string.cal_found, total, visible, events.size)
        Log.i(TAG, "$found · json ${msg.evJson.length} chars")
        if (events.isNotEmpty() || !queryFailed) {
            AppState.setCalendarFound(found)
        }
        return msg
    }

    // (all calendars, visible calendars) as seen through CalendarContract.
    private fun calendarCounts(context: Context): Pair<Int, Int> = runCatching {
        var total = 0
        var visible = 0
        context.contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            arrayOf(CalendarContract.Calendars.VISIBLE), null, null, null,
        )?.use { c ->
            while (c.moveToNext()) {
                total++
                if (c.getInt(0) == 1) visible++
            }
        }
        total to visible
    }.getOrDefault(-1 to -1)

    private fun loadReminders(context: Context, eventId: Long): List<Int> = runCatching {
        val out = ArrayList<Int>()
        context.contentResolver.query(
            CalendarContract.Reminders.CONTENT_URI,
            arrayOf(CalendarContract.Reminders.MINUTES, CalendarContract.Reminders.METHOD),
            "${CalendarContract.Reminders.EVENT_ID} = ?",
            arrayOf(eventId.toString()),
            null,
        )?.use { c ->
            while (c.moveToNext()) {
                val method = c.getInt(1)
                if (method == CalendarContract.Reminders.METHOD_ALERT ||
                    method == CalendarContract.Reminders.METHOD_DEFAULT
                ) {
                    out.add(c.getInt(0))
                }
            }
        }
        out
    }.getOrDefault(emptyList())
}
