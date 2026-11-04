package com.opiconnect.companion.core

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MessagesTest {

    @Test
    fun parseFindPhone() {
        val m = Messages.parse("""{"type":"findphone","on":true}""".toByteArray())
        assertTrue(m is Messages.FindPhone)
        assertEquals(true, (m as Messages.FindPhone).on)
        val off = Messages.parse("""{"type":"findphone","on":false}""".toByteArray()) as Messages.FindPhone
        assertEquals(false, off.on)
    }

    @Test
    fun parseMedia() {
        val vol = Messages.parse("""{"type":"media","cmd":"vol","v":0.65}""".toByteArray())
        assertTrue(vol is Messages.MediaCmd)
        assertEquals("vol", (vol as Messages.MediaCmd).cmd)
        assertEquals(0.65f, vol.v)
        val next = Messages.parse("""{"type":"media","cmd":"next"}""".toByteArray()) as Messages.MediaCmd
        assertEquals("next", next.cmd)
        assertNull(next.v)
    }

    @Test
    fun parseHelloWithCal() {
        val h = Messages.parse("""{"type":"hello","state":"active","cal":"abc123"}""".toByteArray())
        assertTrue(h is Messages.Hello)
        assertEquals("abc123", (h as Messages.Hello).cal)
        val plain = Messages.parse("""{"type":"hello","state":"background"}""".toByteArray()) as Messages.Hello
        assertNull(plain.cal)
    }

    @Test
    fun outStatus() {
        val o = Messages.Status(76, true).toJson()
        assertEquals("status", o.getString("type"))
        assertEquals(76, o.getInt("bt"))
        assertTrue(o.getBoolean("bc"))
    }

    @Test
    fun outMediaState() {
        val o = Messages.MediaState(true, "Spotify", "Song", "Artist", true, 0.5f).toJson()
        assertEquals("media_state", o.getString("type"))
        assertEquals("Spotify", o.getString("app"))
        assertEquals("Song", o.getString("t"))
        assertEquals(0.5, o.getDouble("v"), 0.0001)
        val off = Messages.MediaState(false, "", "", "", false, 0f).toJson()
        assertEquals("", off.getString("t"))
    }

    @Test
    fun parseCalSync() {
        assertTrue(Messages.parse("""{"type":"cal_sync"}""".toByteArray()) is Messages.CalSync)
    }

    @Test
    fun outFindPhoneState() {
        assertTrue(Messages.FindPhoneState(true).toJson().getBoolean("on"))
    }

    @Test
    fun notifPayloadBtBc() {
        val p = NotifPayload("i", "p", "a", "t", "b", 1, emptyList(), bt = 55, bc = true)
        val back = NotifPayload.fromJson(p.toJson())!!
        assertEquals(55, back.bt)
        assertEquals(true, back.bc)
        // back-compat: no bt/bc keys
        val p2 = NotifPayload("i", "p", "a", "t", "b", 1, emptyList())
        assertTrue(!JSONObject(p2.toJson()).has("bt"))
        val back2 = NotifPayload.fromJson(p2.toJson())!!
        assertNull(back2.bt)
        assertNull(back2.bc)
    }
}
