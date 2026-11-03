package com.opiconnect.companion

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

// UI-visible state shared across services.
object AppState {
    enum class WatchLink { NONE, CONNECTED, ACTIVE, BACKGROUND }

    data class RelayResult(val text: String, val time: Long)

    private val _watchLink = MutableStateFlow(WatchLink.NONE)
    val watchLink: StateFlow<WatchLink> = _watchLink

    private val _lastRelay = MutableStateFlow<RelayResult?>(null)
    val lastRelay: StateFlow<RelayResult?> = _lastRelay

    private val _lastError = MutableStateFlow<String?>(null)
    val lastError: StateFlow<String?> = _lastError

    // Calendar diagnostics shown on the Calendar card: what was found and what was sent.
    private val _calendarFound = MutableStateFlow<String?>(null)
    val calendarFound: StateFlow<String?> = _calendarFound
    private val _calendarSent = MutableStateFlow<String?>(null)
    val calendarSent: StateFlow<String?> = _calendarSent

    fun setCalendarFound(text: String) { _calendarFound.value = text }
    fun setCalendarSent(text: String) { _calendarSent.value = text }

    fun setWatchLink(v: WatchLink) { _watchLink.value = v }
    fun setRelay(text: String) { _lastRelay.value = RelayResult(text, System.currentTimeMillis()) }
    fun setError(text: String?) { _lastError.value = text }
}
