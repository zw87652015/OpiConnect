package com.opiconnect.companion.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import javax.crypto.spec.SecretKeySpec

class CardPayloadTest {

    private val encKey: SecretKeySpec by lazy {
        SecretKeySpec(Vectors.hex(Vectors.root.getString("encKeyHex")), "AES")
    }

    @Test
    fun fieldMapping() {
        val p = cardPayload("cardId123", "McDonald's · Pickup code", "365", "Counter 3")
        assertEquals("cardId123", p.i)
        assertEquals(CARD_PACKAGE, p.p)
        assertEquals("McDonald's · Pickup code", p.a)
        assertEquals("365", p.t)
        assertEquals("Counter 3", p.b)
        assertEquals(CARD_PIN_TIME, p.w)
        assertTrue(p.x.isEmpty())
        assertEquals(p, NotifPayload.fromJson(p.toJson()))
    }

    @Test
    fun codeSurvivesRelayTruncation() {
        val p = cardPayload("cardId123", "Card", "365", "note ".repeat(1000))
        val c = RelaySeal.sealForRelay(p, encKey)
        val opened = Crypto.open(Crypto.base64urlDecode(c), encKey)
        val payload = NotifPayload.fromJson(String(opened, Charsets.UTF_8))!!
        assertEquals("365", payload.t)
        assertTrue(payload.b.endsWith("…"))
    }
}
