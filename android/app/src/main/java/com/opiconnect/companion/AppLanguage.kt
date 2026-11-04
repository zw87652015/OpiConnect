package com.opiconnect.companion

import android.app.LocaleManager
import android.content.Context
import android.os.LocaleList

// Per-app language via the platform LocaleManager (minSdk 34). "" = system.
object AppLanguage {
    data class Option(val tag: String, val nameRes: Int)

    val options = listOf(
        Option("", R.string.language_system),
        Option("en", R.string.language_en),
        Option("zh-Hans", R.string.language_zh_hans),
        Option("zh-Hant", R.string.language_zh_hant),
    )

    fun current(context: Context): String =
        context.getSystemService(LocaleManager::class.java)
            ?.applicationLocales?.toLanguageTags().orEmpty()

    fun set(context: Context, tag: String) {
        context.getSystemService(LocaleManager::class.java)?.applicationLocales =
            if (tag.isEmpty()) LocaleList.getEmptyLocaleList() else LocaleList.forLanguageTags(tag)
    }
}
