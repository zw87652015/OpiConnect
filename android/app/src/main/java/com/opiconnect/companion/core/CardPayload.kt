package com.opiconnect.companion.core

// DIY cards ride the normal notification path: the label goes in `a`, the code
// in `t`, the note in `b`, and a fixed far-future `w` pins the card at the top
// of the watch list (the watch sorts by `w` newest first and never shows it).
const val CARD_PACKAGE = "com.opiconnect.card"
const val CARD_PIN_TIME = 4102444800000L

fun cardPayload(
    id: String,
    label: String,
    code: String,
    note: String,
    bt: Int? = null,
    bc: Boolean? = null,
): NotifPayload = NotifPayload(
    i = id,
    // Per-card package: the watch threads notifications by `p`, so a shared value
    // would stack every card under the newest one.
    p = "$CARD_PACKAGE.$id",
    a = label,
    t = code,
    b = note,
    w = CARD_PIN_TIME,
    x = emptyList(),
    bt = bt,
    bc = bc,
)
