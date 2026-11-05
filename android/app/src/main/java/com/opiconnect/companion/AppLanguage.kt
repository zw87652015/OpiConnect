package com.opiconnect.companion

import android.app.LocaleManager
import android.content.Context
import android.os.Build
import android.os.LocaleList

// Per-app language via the platform LocaleManager (API 33+). "" = system.
object AppLanguage {
    val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU

    data class Option(val tag: String, val nameRes: Int)

    val options = listOf(
        Option("", R.string.language_system),
        Option("en", R.string.language_en),
        Option("zh-Hans", R.string.language_zh_hans),
        Option("zh-Hant", R.string.language_zh_hant),
    )

    fun current(context: Context): String = if (!supported) "" else
        context.getSystemService(LocaleManager::class.java)
            ?.applicationLocales?.toLanguageTags().orEmpty()

    fun set(context: Context, tag: String) {
        if (!supported) return
        context.getSystemService(LocaleManager::class.java)?.applicationLocales =
            if (tag.isEmpty()) LocaleList.getEmptyLocaleList() else LocaleList.forLanguageTags(tag)
    }
}
