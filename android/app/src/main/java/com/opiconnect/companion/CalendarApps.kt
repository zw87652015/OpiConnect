package com.opiconnect.companion

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri

// Detects calendar apps on the phone. When READ_CALENDAR is granted the watch reminds
// the user itself, so notifications from these apps are skipped in the Router to
// avoid double alerts.
object CalendarApps {
    private var cached: List<String>? = null

    fun packages(context: Context): List<String> {
        cached?.let { return it }
        val pm = context.packageManager
        val found = linkedSetOf<String>()
        listOf(
            Intent(Intent.ACTION_MAIN).addCategory("android.intent.category.APP_CALENDAR"),
            Intent(Intent.ACTION_VIEW).setDataAndType(
                Uri.parse("content://com.android.calendar/"),
                "vnd.android.cursor.item/event",
            ),
            Intent(Intent.ACTION_VIEW).setDataAndType(
                Uri.parse("content://com.android.calendar/"),
                "vnd.android.cursor.dir/event",
            ),
        ).forEach { intent ->
            pm.queryIntentActivities(intent, PackageManager.MATCH_ALL).forEach {
                found.add(it.activityInfo.packageName)
            }
        }
        // Our own package is never a calendar app.
        found.remove(context.packageName)
        cached = found.toList()
        return cached!!
    }

    fun labels(context: Context): List<String> {
        val pm = context.packageManager
        return packages(context).map { pkg ->
            runCatching {
                pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
            }.getOrDefault(pkg)
        }
    }

    fun enabled(context: Context): Boolean = CalendarSync.hasPermission(context)
}
