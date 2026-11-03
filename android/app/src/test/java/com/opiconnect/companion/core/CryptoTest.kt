package com.opiconnect.companion.core

import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File
import javax.crypto.spec.SecretKeySpec

object Vectors {
    val root: JSONObject by lazy {
        var dir = File(".").absoluteFile
        while (!File(dir, "docs/test-vectors.json").exists()) {
            dir = dir.parentFile ?: error("docs/test-vectors.json not found")
        }
        JSONObject(File(dir, "docs/test-vectors.json").readText())
    }

    fun hex(s: String): ByteArray =
        ByteArray(s.length / 2) { s.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
}

class CryptoTest {
    private lateinit var vectors: JSONObject
    private lateinit var k: ByteArray
    private lateinit var keys: Keys
    private lateinit var encKey: SecretKeySpec

    @Before
    fun setUp() {
        vectors = Vectors.root
        k = Vectors.hex(vectors.getString("masterKeyHex"))
        keys = Keys(k)
        encKey = SecretKeySpec(Vectors.hex(vectors.getString("encKeyHex")), "AES")
    }

    @Test
    fun parseQr() {
        assertNull(Crypto.parseQr(null))
        assertNull(Crypto.parseQr("nope"))
        assertNull(Crypto.parseQr("opi1:AAAA"))
        assertArrayEquals(k, Crypto.parseQr(vectors.getString("qr")))
    }

    @Test
    fun derivations() {
        assertEquals(vectors.getString("qr"), keys.qrString)
        assertEquals(vectors.getString("pairId"), keys.pairId)
        assertEquals(vectors.getString("secret"), keys.secret)
        val encBytes = Crypto.hkdf(k, "opi/enc", 32)
        assertEquals(vectors.getString("encKeyHex"), encBytes.joinToString("") { "%02x".format(it) })
    }

    @Test
    fun sealVectors() {
        val arr = vectors.getJSONArray("seal")
        for (idx in 0 until arr.length()) {
            val v = arr.getJSONObject(idx)
            val sealed = Crypto.base64urlDecode(v.getString("sealedBase64url"))
            // open
            val opened = Crypto.open(sealed, encKey)
            assertEquals(v.getString("plaintext"), String(opened, Charsets.UTF_8))
            // re-seal with the fixed nonce -> identical bytes
            val nonce = Vectors.hex(v.getString("nonceHex"))
            val resealed = Crypto.seal(v.getString("plaintext").toByteArray(Charsets.UTF_8), encKey, nonce)
            assertEquals(v.getString("sealedBase64url"), Crypto.base64url(resealed))
        }
    }

    @Test
    fun notificationId() {
        val v = vectors.getJSONObject("notificationId")
        assertEquals(v.getString("id"), Crypto.notifId(v.getString("sbnKey")))
        assertEquals(22, Crypto.notifId(v.getString("sbnKey")).length)
    }

    @Test
    fun sealRoundTripRandomNonce() {
        val plain = "你好 👋".toByteArray(Charsets.UTF_8)
        val sealed = Crypto.seal(plain, encKey)
        assertNotNull(sealed)
        assertArrayEquals(plain, Crypto.open(sealed, encKey))
    }
}
