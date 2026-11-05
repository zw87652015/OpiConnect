package com.opiconnect.companion

import android.util.Log
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
                    Log.i("OpiRelay", "push $kind ${id.take(6)} -> ${resp.code}")
                    when (resp.code) {
                        200 -> {
                            AppState.setRelay(string(R.string.relay_sent))
                            return
                        }
                        404 -> AppState.setRelay(string(R.string.relay_not_registered))
                        401 -> AppState.setRelay(string(R.string.relay_rejected))
                        410 -> AppState.setRelay(string(R.string.relay_expired))
                        429 -> AppState.setRelay(string(R.string.relay_rate_limited))
                        else -> {
                            if (resp.code >= 500 && attempt == 0) {
                                delay(5000)
                                return@use
                            }
                            AppState.setRelay(string(R.string.relay_error, resp.code))
                            return
                        }
                    }
                    return
                }
            } catch (e: IOException) {
                Log.w("OpiRelay", "push $kind ${id.take(6)} failed: $e")
                if (attempt == 0) {
                    delay(5000)
                } else {
                    AppState.setRelay(string(R.string.relay_no_connection))
                    return
                }
            }
        }
    }

    private fun string(id: Int, vararg args: Any): String =
        (OpiListenerService.instance ?: LinkService.instance)
            ?.getString(id, *args).orEmpty()
}
