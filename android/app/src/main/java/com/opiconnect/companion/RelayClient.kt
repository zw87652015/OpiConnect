package com.opiconnect.companion

import com.opiconnect.companion.core.Keys
import kotlinx.coroutines.delay
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.TimeUnit

// POSTs sealed payloads to the relay (docs/PROTOCOL.md). One retry after 5 s on
// IO error or 5xx.
object RelayClient {
    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .build()

    suspend fun push(keys: Keys, kind: String, id: String, c: String) {
        val body = JSONObject()
            .put("pairId", keys.pairId)
            .put("secret", keys.secret)
            .put("kind", kind)
            .put("id", id)
            .put("c", c)
            .toString()
            .toRequestBody("application/json".toMediaType())
        val request = Request.Builder()
            .url(BuildConfig.RELAY_URL + "/v1/push")
            .post(body)
            .build()

        repeat(2) { attempt ->
            try {
                client.newCall(request).execute().use { resp ->
                    when (resp.code) {
                        200 -> {
                            AppState.setRelay("Sent via relay")
                            return
                        }
                        404 -> AppState.setRelay("Watch not registered yet — open OpiLink on the watch")
                        401 -> AppState.setRelay("Relay rejected credentials — re-pair")
                        410 -> AppState.setRelay("Watch push token expired — open the watch app")
                        429 -> AppState.setRelay("Relay rate-limited, will retry later")
                        else -> {
                            if (resp.code >= 500 && attempt == 0) {
                                delay(5000)
                                return@use
                            }
                            AppState.setRelay("Relay error ${resp.code}")
                            return
                        }
                    }
                    return
                }
            } catch (e: IOException) {
                if (attempt == 0) {
                    delay(5000)
                } else {
                    AppState.setRelay("No connection to relay")
                    return
                }
            }
        }
    }
}
