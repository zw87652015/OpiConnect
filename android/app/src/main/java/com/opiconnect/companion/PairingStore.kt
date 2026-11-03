package com.opiconnect.companion

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import com.opiconnect.companion.core.Crypto
import com.opiconnect.companion.core.Keys
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.spec.GCMParameterSpec

// Stores the 32-byte master key K wrapped by an AndroidKeyStore AES-256-GCM key.
object PairingStore {
    private const val PREFS = "opi"
    private const val KEY_WRAPPED = "wrapped_k"
    private const val KEYSTORE = "AndroidKeyStore"
    private const val ALIAS = "opi_wrap"

    @Volatile private var cached: Keys? = null

    fun isPaired(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).contains(KEY_WRAPPED)

    fun keys(context: Context): Keys? {
        cached?.let { return it }
        if (!isPaired(context)) return null
        return unwrap(context)?.also { cached = it }
    }

    fun pair(context: Context, k: ByteArray): Boolean {
        val wrapped = wrap(k) ?: return false
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY_WRAPPED, Crypto.base64url(wrapped)).apply()
        cached = Keys(k)
        return true
    }

    fun unpair(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().remove(KEY_WRAPPED).apply()
        cached = null
    }

    private fun wrapKey(): javax.crypto.SecretKey {
        val ks = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (ks.getEntry(ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        gen.init(
            KeyGenParameterSpec.Builder(
                ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return gen.generateKey()
    }

    // wrapped = nonce(12) || ciphertext || tag(16)
    private fun wrap(k: ByteArray): ByteArray? = runCatching {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, wrapKey())
        cipher.iv + cipher.doFinal(k)
    }.getOrNull()

    private fun unwrap(context: Context): Keys? = runCatching {
        val encoded = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_WRAPPED, null) ?: return null
        val wrapped = Crypto.base64urlDecode(encoded)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, wrapKey(), GCMParameterSpec(128, wrapped.copyOfRange(0, 12)))
        Keys(cipher.doFinal(wrapped.copyOfRange(12, wrapped.size)))
    }.getOrNull()
}
