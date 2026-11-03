package com.opiconnect.companion.core

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CalendarPayloadTest {

    private fun event(
        id: Long, s: Long, t: String = "e$id", rm: List<Int> = listOf(10),
    ) = CalendarPayload.makeEvent(
        eventId = id, beginMs = s, endMs = s + 3_600_000, title = t,
        allDay = false, location = "", notes = "", calendar = "cal", color = 0, reminders = rm,
    )

    @Test
    fun eventKeyDerivation() {
        // k = first 16 chars of base64url(sha256("<eventId>|<beginMs>"))
        val expected = Crypto.base64url(
            java.security.MessageDigest.getInstance("SHA-256")
                .digest("42|1700000000000".toByteArray(Charsets.UTF_8)),
        ).take(16)
        assertEquals(expected, CalendarPayload.eventKey(42, 1700000000000))
        assertEquals(16, CalendarPayload.eventKey(42, 1700000000000).length)
    }

    @Test
    fun sortingAndCap() {
        val events = (1..310).map { event(it.toLong(), (311 - it) * 1000L) }
        val msg = CalendarPayload.build(events, 0, Long.MAX_VALUE)
        val arr = JSONArray(msg.evJson)
        assertEquals(300, arr.length())
        var prev = -1L
        for (i in 0 until arr.length()) {
            val s = arr.getJSONObject(i).getLong("s")
            assertTrue(s >= prev)
            prev = s
        }
    }

    @Test
    fun truncationByCodePoints() {
        val emojiTitle = "x".repeat(199) + "😀" + "y".repeat(10) // 210 code points
        val e = CalendarPayload.makeEvent(
            1, 0, 0, emojiTitle, false, "loc", "n".repeat(400), "cal", 0, emptyList(),
        )
        // 200 code points: 199 x + emoji (2 UTF-16 units)
        assertEquals(201, e.t.length)
        assertEquals(199 + 1, e.t.codePointCount(0, e.t.length))
        assertTrue(e.t.endsWith("😀"))
        assertEquals(300, e.n.length)
    }

    @Test
    fun hashDeterminism() {
        val events = listOf(event(1, 1000), event(2, 2000))
        val m1 = CalendarPayload.build(events, 0, 10)
        val m2 = CalendarPayload.build(events, 0, 10)
        assertEquals(m1.h, m2.h)
        // h = first 16 chars of base64url(sha256(evJson))
        val expected = Crypto.base64url(
            java.security.MessageDigest.getInstance("SHA-256")
                .digest(m1.evJson.toByteArray(Charsets.UTF_8)),
        ).take(16)
        assertEquals(expected, m1.h)
        assertEquals(16, m1.h.length)
        // different events -> different hash
        val m3 = CalendarPayload.build(events + event(3, 3000), 0, 10)
        assertTrue(m1.h != m3.h)
    }

    @Test
    fun calMessageJson() {
        val msg = CalendarPayload.build(listOf(event(1, 1000)), 5, 5000)
        val o = Messages.Cal(msg).toJson()
        assertEquals("cal", o.getString("type"))
        assertEquals(msg.h, o.getString("h"))
        assertEquals(5, o.getLong("from"))
        assertEquals(5000, o.getLong("to"))
        assertEquals(1, o.getJSONArray("ev").length())
        val ev = o.getJSONArray("ev").getJSONObject(0)
        assertEquals(listOf(10), ev.getJSONArray("rm").let { (0 until it.length()).map { i -> it.getInt(i) } })
    }
}
