package com.opiconnect.companion.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import javax.crypto.spec.SecretKeySpec

class PayloadTest {

    private val encKey: SecretKeySpec by lazy {
        SecretKeySpec(Vectors.hex(Vectors.root.getString("encKeyHex")), "AES")
    }

    private val sample = NotifPayload(
        i = "AbCdEfGhIjKlMnOpQrStUv",
        p = "com.example.chat",
        a = "示例应用",
        t = "新消息",
        b = "你好 👋 晚上一起吃饭吗？",
        w = 1730000000000,
        x = listOf(ActionInfo("回复", true), ActionInfo("标为已读", false)),
    )

    @Test
    fun jsonRoundTrip() {
        val back = NotifPayload.fromJson(sample.toJson())
        assertEquals(sample, back)
    }

    @Test
    fun sealForRelayTruncates() {
        val big = sample.copy(b = "字".repeat(20_000))
        val c = RelaySeal.sealForRelay(big, encKey)
        assertTrue("c too long: ${c.length}", c.length <= 3000)
        val opened = Crypto.open(Crypto.base64urlDecode(c), encKey)
        val payload = NotifPayload.fromJson(String(opened, Charsets.UTF_8))!!
        assertTrue(payload.b.endsWith("…"))
        assertTrue(payload.b.length < 20_000)
    }

    @Test
    fun actionsCappedAtThree() {
        val big = sample.copy(x = (1..6).map { ActionInfo("a$it", it % 2 == 0) })
        val c = RelaySeal.sealForRelay(big, encKey)
        val opened = Crypto.open(Crypto.base64urlDecode(c), encKey)
        val payload = NotifPayload.fromJson(String(opened, Charsets.UTF_8))!!
        assertEquals(3, payload.x.size)
    }

    @Test
    fun shortBodyKeepsAllFields() {
        val c = RelaySeal.sealForRelay(sample, encKey)
        val opened = Crypto.open(Crypto.base64urlDecode(c), encKey)
        val payload = NotifPayload.fromJson(String(opened, Charsets.UTF_8))!!
        assertEquals(sample, payload)
    }

    @Test
    fun bleMessageRoundTrip() {
        val action = Messages.parse(
            """{"type":"action","id":"abc","idx":1,"label":"Reply","text":"hi"}""".toByteArray(),
        )
        assertTrue(action is Messages.Action)
        action as Messages.Action
        assertEquals(1, action.idx)
        assertEquals("hi", action.text)
        assertTrue(Messages.parse("{\"type\":\"hello\",\"state\":\"active\"}".toByteArray()) is Messages.Hello)
    }
}
