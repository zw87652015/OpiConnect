package com.opiconnect.companion

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

// Phone battery status; kept fresh by the sticky ACTION_BATTERY_CHANGED broadcast.
object PhoneStatus {
    data class Snapshot(val bt: Int, val bc: Boolean)

    private val _snapshot = MutableStateFlow(Snapshot(-1, false))
    val snapshot: StateFlow<Snapshot> = _snapshot

    fun register(context: Context) {
        val intent: Intent? = context.registerReceiver(receiver, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        update(intent)
    }

    fun unregister(context: Context) {
        runCatching { context.unregisterReceiver(receiver) }
    }

    fun current(): Snapshot = _snapshot.value

    private fun update(intent: Intent?) {
        intent ?: return
        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        if (level < 0 || scale <= 0) return
        val plugged = intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0)
        val bc = plugged != 0 ||
            intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1) == BatteryManager.BATTERY_STATUS_CHARGING
        val s = Snapshot((level * 100) / scale, bc)
        if (s != _snapshot.value) {
            _snapshot.value = s
            LinkService.instance?.sendAll(com.opiconnect.companion.core.Messages.Status(s.bt, s.bc))
        }
    }

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == Intent.ACTION_BATTERY_CHANGED) update(intent)
        }
    }
}
