package com.opiconnect.companion.core

import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest

// Calendar payload for the BLE `cal` message (docs/PROTOCOL.md). Pure Kotlin so the
// building/sorting/truncating/hashing is unit-testable; cursor reading lives in
// CalendarSync on the Android side.
data class CalEvent(
    val k: String,
    val t: String,
    val s: Long,
    val e: Long,
    val ad: Boolean,
    val loc: String,
    val n: String,
    val cal: String,
    val col: Long,
    val rm: List<Int>,
) {
    fun toJson() = JSONObject()
        .put("k", k).put("t", t).put("s", s).put("e", e).put("ad", ad)
        .put("loc", loc).put("n", n).put("cal", cal).put("col", col)
        .put("rm", JSONArray(rm))
}

object CalendarPayload {
    const val MAX_EVENTS = 300
    private const val TITLE_MAX = 200
    private const val NOTES_MAX = 300
    private const val LOC_MAX = 200

    // k = first 16 chars of base64url(sha256(utf8("<eventId>|<beginMs>")))
    fun eventKey(eventId: Long, beginMs: Long): String =
        Crypto.base64url(MessageDigest.getInstance("SHA-256")
            .digest("$eventId|$beginMs".toByteArray(Charsets.UTF_8))).take(16)

    fun makeEvent(
        eventId: Long, beginMs: Long, endMs: Long, title: String, allDay: Boolean,
        location: String, notes: String, calendar: String, color: Long, reminders: List<Int>,
    ) = CalEvent(
        k = eventKey(eventId, beginMs),
        t = title.takeCodePoints(TITLE_MAX),
        s = beginMs,
        e = endMs,
        ad = allDay,
        loc = location.takeCodePoints(LOC_MAX),
        n = notes.takeCodePoints(NOTES_MAX),
        cal = calendar,
        col = color,
        rm = reminders.distinct().sorted(),
    )

    // Returns the ev-array JSON string and its hash h (first 16 chars of
    // base64url(sha256(utf8(exact JSON string)))).
    fun build(events: List<CalEvent>, from: Long, to: Long): CalMessage {
        val sorted = events.sortedWith(compareBy({ it.s }, { it.k })).take(MAX_EVENTS)
        val evJson = JSONArray().apply { sorted.forEach { put(it.toJson()) } }.toString()
        val h = Crypto.base64url(MessageDigest.getInstance("SHA-256")
            .digest(evJson.toByteArray(Charsets.UTF_8))).take(16)
        return CalMessage(h = h, from = from, to = to, evJson = evJson)
    }
}

data class CalMessage(val h: String, val from: Long, val to: Long, val evJson: String)

internal fun String.takeCodePoints(n: Int): String {
    var count = 0
    var idx = 0
    while (idx < length && count < n) {
        idx += if (Character.isSupplementaryCodePoint(codePointAt(idx))) 2 else 1
        count++
    }
    return substring(0, idx)
}
