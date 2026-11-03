package com.opiconnect.companion.core

import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

// Crypto per docs/PROTOCOL.md: base64url without padding, HKDF-SHA256 with a
// zero-length salt (= HashLen zero bytes; javax Mac rejects a zero-length key, so we
// pass 32 zero bytes explicitly), AES-256-GCM sealed as nonce(12) || ciphertext || tag(16).
object Crypto {
    private val random = SecureRandom()

    fun base64url(data: ByteArray): String =
        Base64.getUrlEncoder().withoutPadding().encodeToString(data)

    fun base64urlDecode(s: String): ByteArray =
        Base64.getUrlDecoder().decode(s)

    fun hkdf(ikm: ByteArray, info: String, length: Int): ByteArray {
        // RFC 5869: salt absent -> HashLen zero bytes.
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(ByteArray(32), "HmacSHA256"))
        val prk = mac.doFinal(ikm)
        val infoBytes = info.toByteArray(Charsets.US_ASCII)
        val out = ByteArray(length)
        var t = ByteArray(0)
        var offset = 0
        var counter = 1
        mac.init(SecretKeySpec(prk, "HmacSHA256"))
        while (offset < length) {
            mac.update(t)
            mac.update(infoBytes)
            mac.update(counter.toByte())
            t = mac.doFinal()
            val n = minOf(t.size, length - offset)
            System.arraycopy(t, 0, out, offset, n)
            offset += n
            counter++
        }
        return out
    }

    fun seal(plain: ByteArray, key: SecretKey, nonce: ByteArray = randomNonce()): ByteArray {
        require(nonce.size == 12) { "GCM nonce must be 12 bytes" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(128, nonce))
        return nonce + cipher.doFinal(plain)
    }

    fun open(sealed: ByteArray, key: SecretKey): ByteArray {
        require(sealed.size >= 28) { "sealed payload too short" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, sealed.copyOfRange(0, 12)))
        return cipher.doFinal(sealed.copyOfRange(12, sealed.size))
    }

    fun sha256(data: ByteArray): ByteArray = MessageDigest.getInstance("SHA-256").digest(data)

    fun notifId(sbnKey: String): String =
        base64url(sha256(sbnKey.toByteArray(Charsets.UTF_8))).take(22)

    private fun randomNonce(): ByteArray = ByteArray(12).also { random.nextBytes(it) }

    // Parses a pairing QR string ("opi1:" + base64url(K)) into the 32-byte master key.
    fun parseQr(raw: String?): ByteArray? {
        if (raw == null || !raw.startsWith("opi1:")) return null
        val k = runCatching { base64urlDecode(raw.substring(5)) }.getOrNull() ?: return null
        return if (k.size == 32) k else null
    }
}

// Everything derived from the master key K (docs/PROTOCOL.md).
class Keys(k: ByteArray) {
    val masterKey: ByteArray = k.copyOf()
    val pairId: String = Crypto.base64url(Crypto.hkdf(k, "opi/id", 16))
    val secret: String = Crypto.base64url(Crypto.hkdf(k, "opi/auth", 32))
    val encKey: SecretKey = SecretKeySpec(Crypto.hkdf(k, "opi/enc", 32), "AES")
    val qrString: String get() = "opi1:" + Crypto.base64url(masterKey)
}
