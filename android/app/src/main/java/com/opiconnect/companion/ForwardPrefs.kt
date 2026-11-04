package com.opiconnect.companion

import android.content.Context

// Which apps' notifications are forwarded, and whether to forward only while
// the screen is off. Stored in the same SharedPreferences file as PairingStore.
object ForwardPrefs {
    private const val PREFS = "opi"
    private const val KEY_MODE = "fwd_mode"
    private const val KEY_APPS = "fwd_apps"
    private const val KEY_SCREEN_OFF = "fwd_screen_off"

    enum class Mode { ALL, ALLOW, BLOCK }

    fun mode(context: Context): Mode =
        runCatching {
            Mode.valueOf(
                context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                    .getString(KEY_MODE, null) ?: return Mode.ALL,
            )
        }.getOrDefault(Mode.ALL)

    fun setMode(context: Context, mode: Mode) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY_MODE, mode.name).apply()
    }

    fun apps(context: Context): Set<String> =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getStringSet(KEY_APPS, emptySet()) ?: emptySet()

    fun setApps(context: Context, apps: Set<String>) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putStringSet(KEY_APPS, HashSet(apps)).apply()
    }

    fun screenOffOnly(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_SCREEN_OFF, false)

    fun setScreenOffOnly(context: Context, value: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_SCREEN_OFF, value).apply()
    }

    fun allows(context: Context, pkg: String): Boolean = when (mode(context)) {
        Mode.ALL -> true
        Mode.ALLOW -> pkg in apps(context)
        Mode.BLOCK -> pkg !in apps(context)
    }
}
