package com.opiconnect.companion.core

import org.json.JSONArray
import org.json.JSONObject
import javax.crypto.SecretKey

// Notification payload (docs/PROTOCOL.md): {"i","p","a","t","b","w","x":[{"l","r"}]}
data class ActionInfo(val l: String, val r: Boolean) {
    fun toJson() = JSONObject().put("l", l).put("r", r)
}

data class NotifPayload(
    val i: String,
    val p: String,
    val a: String,
    val t: String,
    val b: String,
    val w: Long,
    val x: List<ActionInfo>,
    val bt: Int? = null,    // phone battery 0-100 (keeps the watch fresh over APNs too)
    val bc: Boolean? = null, // phone charging
) {
    fun toJson(): String {
        val o = JSONObject()
            .put("i", i)
            .put("p", p)
            .put("a", a)
            .put("t", t)
            .put("b", b)
            .put("w", w)
            .put("x", JSONArray().apply { x.forEach { put(it.toJson()) } })
        if (bt != null) o.put("bt", bt)
        if (bc != null) o.put("bc", bc)
        return o.toString()
    }

    companion object {
        fun fromJson(s: String): NotifPayload? = runCatching {
            val o = JSONObject(s)
            val arr = o.optJSONArray("x")
            val actions = ArrayList<ActionInfo>()
            if (arr != null) {
                for (idx in 0 until arr.length()) {
                    val e = arr.getJSONObject(idx)
                    actions.add(ActionInfo(e.getString("l"), e.getBoolean("r")))
                }
            }
            NotifPayload(
                i = o.getString("i"),
                p = o.getString("p"),
                a = o.getString("a"),
                t = o.getString("t"),
                b = o.getString("b"),
                w = o.getLong("w"),
                x = actions,
                bt = if (o.has("bt")) o.getInt("bt") else null,
                bc = if (o.has("bc")) o.getBoolean("bc") else null,
            )
        }.getOrNull()
    }
}

// Relay pushes carry a sealed payload in "c" capped at 3000 base64url chars
// (APNs alert payloads are limited to 4 KB). The body is truncated by code points
// and a "…" marker is appended. Title is capped at 200 chars, actions at 3.
object RelaySeal {
    private const val MAX_C = 3000
    private const val MAX_TITLE = 200
    private const val ELLIPSIS = "…"

    fun sealForRelay(payload: NotifPayload, encKey: SecretKey): String {
        val p = payload.copy(t = payload.t.takeCodePoints(MAX_TITLE), x = payload.x.take(3))
        var body = p.b
        var c = sealString(p.copy(b = body), encKey)
        while (c.length > MAX_C && body.isNotEmpty()) {
            body = body.dropLastCodePoint()
            c = sealString(p.copy(b = body + ELLIPSIS), encKey)
        }
        return c
    }

    private fun sealString(p: NotifPayload, encKey: SecretKey): String =
        Crypto.base64url(Crypto.seal(p.toJson().toByteArray(Charsets.UTF_8), encKey))
}

private fun String.dropLastCodePoint(): String {
    if (isEmpty()) return this
    val last = codePointBeforeLast(length)
    return substring(0, length - if (Character.isSupplementaryCodePoint(last)) 2 else 1)
}

private fun String.codePointBeforeLast(end: Int): Int = Character.codePointBefore(this, end)

// BLE messages, discriminated by "type" (docs/PROTOCOL.md). Plaintext is UTF-8 JSON
// sealed with encKey before chunking.
object Messages {
    sealed interface Out { fun toJson(): JSONObject }
    sealed interface In

    // watch -> phone (inbound for us)
    data class Hello(val state: String, val cal: String? = null) : In
    data class State(val state: String) : In
    data class Ack(val id: String) : In
    data class Dismiss(val id: String) : In
    data class Action(val id: String, val idx: Int, val label: String, val text: String?) : In
    data class FindPhone(val on: Boolean) : In
    data class MediaCmd(val cmd: String, val v: Float?) : In
    object CalSync : In

    // phone -> watch (outbound for us)
    object Welcome : Out { override fun toJson() = JSONObject().put("type", "welcome") }
    data class Notif(val payload: NotifPayload) : Out {
        override fun toJson() = JSONObject(payload.toJson()).put("type", "notif")
    }
    data class Remove(val id: String) : Out {
        override fun toJson() = JSONObject().put("type", "remove").put("id", id)
    }
    data class Sync(val ids: List<String>) : Out {
        override fun toJson() = JSONObject().put("type", "sync").put("ids", JSONArray(ids))
    }
    data class Status(val bt: Int, val bc: Boolean) : Out {
        override fun toJson() = JSONObject().put("type", "status").put("bt", bt).put("bc", bc)
    }
    data class MediaState(
        val on: Boolean, val app: String, val t: String, val ar: String,
        val pl: Boolean, val v: Float,
    ) : Out {
        override fun toJson() = JSONObject().put("type", "media_state")
            .put("on", on).put("app", app).put("t", t).put("ar", ar)
            .put("pl", pl).put("v", v.toDouble())
    }
    data class FindPhoneState(val on: Boolean) : Out {
        override fun toJson() = JSONObject().put("type", "findphone_state").put("on", on)
    }
    data class Cal(val msg: CalMessage) : Out {
        override fun toJson() = JSONObject()
            .put("type", "cal").put("h", msg.h).put("from", msg.from).put("to", msg.to)
            .put("ev", JSONArray(msg.evJson))
    }

    fun parse(data: ByteArray): In? = runCatching {
        val o = JSONObject(String(data, Charsets.UTF_8))
        when (o.getString("type")) {
            "hello" -> Hello(o.getString("state"), if (o.has("cal")) o.getString("cal") else null)
            "state" -> State(o.getString("state"))
            "ack" -> Ack(o.getString("id"))
            "dismiss" -> Dismiss(o.getString("id"))
            "action" -> Action(
                id = o.getString("id"),
                idx = o.getInt("idx"),
                label = o.getString("label"),
                text = if (o.has("text")) o.getString("text") else null,
            )
            "findphone" -> FindPhone(o.getBoolean("on"))
            "media" -> MediaCmd(
                cmd = o.getString("cmd"),
                v = if (o.has("v")) o.getDouble("v").toFloat() else null,
            )
            "cal_sync" -> CalSync
            else -> null
        }
    }.getOrNull()

    fun encode(out: Out): ByteArray = out.toJson().toString().toByteArray(Charsets.UTF_8)
}
