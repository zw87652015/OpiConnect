package com.opiconnect.companion

import android.content.Context
import com.opiconnect.companion.core.Crypto
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

// Hand-made cards (pickup / redeem codes) the user can push to the watch.
// Stored as a JSON array in the same SharedPreferences file as ForwardPrefs.
data class OpiCard(
    val id: String,
    val label: String,
    val code: String,
    val note: String,
    val onWatch: Boolean,
) {
    fun toJson() = JSONObject()
        .put("id", id)
        .put("label", label)
        .put("code", code)
        .put("note", note)
        .put("onWatch", onWatch)

    companion object {
        fun fromJson(o: JSONObject) = OpiCard(
            id = o.getString("id"),
            label = o.optString("label"),
            code = o.getString("code"),
            note = o.optString("note"),
            onWatch = o.optBoolean("onWatch"),
        )

        fun newId(): String = Crypto.notifId("opi-card-" + UUID.randomUUID())
    }
}

object CardStore {
    private const val PREFS = "opi"
    private const val KEY_CARDS = "cards"

    fun all(context: Context): List<OpiCard> = runCatching {
        val arr = JSONArray(prefs(context).getString(KEY_CARDS, "[]") ?: "[]")
        (0 until arr.length()).map { OpiCard.fromJson(arr.getJSONObject(it)) }
    }.getOrDefault(emptyList())

    fun upsert(context: Context, card: OpiCard) =
        save(context, all(context).filter { it.id != card.id } + card)

    fun delete(context: Context, id: String) =
        save(context, all(context).filter { it.id != id })

    fun setOnWatch(context: Context, id: String, onWatch: Boolean) =
        save(context, all(context).map { if (it.id == id) it.copy(onWatch = onWatch) else it })

    fun onWatchIds(context: Context): List<String> =
        all(context).filter { it.onWatch }.map { it.id }

    fun isCard(context: Context, id: String): Boolean =
        all(context).any { it.id == id }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun save(context: Context, cards: List<OpiCard>) {
        val arr = JSONArray()
        cards.forEach { arr.put(it.toJson()) }
        prefs(context).edit().putString(KEY_CARDS, arr.toString()).apply()
    }
}
