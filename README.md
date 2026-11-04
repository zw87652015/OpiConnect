# OpiConnect

OpiConnect mirrors Android notifications to an Apple Watch. It is published on the App
Store as **OpiLink**. It has three parts:

- a **watch-only watchOS app** (`watch/`) — shows a pairing QR, receives notifications,
  syncs dismissals, runs Android notification actions (including text replies),
- an **Android companion app** (`android/`) — reads notifications, talks BLE while the
  watch app is open, calls the relay the rest of the time,
- a **relay server** (`server/`) — a small Node 22 service that forwards
  end-to-end-encrypted payloads to APNs.

## How it works

```
Android NotificationListenerService
        │
        ├── watch app open  ──>  BLE GATT (encrypted, chunked)  ──>  watch app
        │
        └── otherwise  ──>  POST relay /v1/push  ──>  APNs  ──>  watch NSE decrypts
                                                              ──>  notification
```

All payloads are sealed with AES-256-GCM using a key derived from a master key that only
the watch and the phone hold (paired via QR code). The relay sees only ciphertext, a
pair id, and the APNs token. See `docs/PROTOCOL.md` for the wire spec and
`docs/test-vectors.json` for shared crypto test vectors.

Watch → Android traffic (dismissals, actions) travels over BLE while the watch app is
connected; otherwise it's queued on the watch and sent when it next connects.

## Features

- Notification mirroring (BLE when the watch app is open, encrypted APNs otherwise)
- Dismiss sync both directions + Android notification actions (incl. text replies)
- **Find my phone** — ring the phone from the watch (max alarm volume + vibration)
- **Music control** — play/pause/next/prev + Digital Crown volume
- **Phone battery on the watch** — status line plus a complication; stays fresh via
  pushes (every push carries the battery level) and background refresh
- **Calendar sync** — next 30 days of events mirrored to the watch with on-wrist
  reminders; calendar app notifications are not forwarded to avoid double alerts
- **Complications** — phone battery, next event, Find Phone and Music quick-launch

Adding complications: long-press the watch face → Edit → Complications → pick a slot →
OpiConnect. They're also available in the Smart Stack.

## Limitations

- **BLE only while the watch app is open.** watchOS severely caps background BLE
  (a handful of timely alerts per 24 h), so when the watch app is closed, delivery
  falls back to APNs via the relay.
- **Remote dismissal is best-effort** in the background: watchOS throttles background
  pushes, so an Android-side dismiss may lag until the next connection.
- **Watch → Android actions queue on the watch** and are sent the next time the watch
  app connects (or during background refresh).
- **Push payloads are capped at 4 KB**; long notification bodies are truncated with an
  ellipsis.
- **An Apple Watch still needs its paired iPhone** for setup and for push delivery
  (APNs reaches the watch through the iPhone or Wi-Fi).

## Repo layout

```
watch/    watchOS app: Xcode project, watch app + NotificationService extension, Shared code
android/  Android companion app (Kotlin + Compose, Gradle 8.11.1 wrapper, AGP 8.7.3)
server/   Node 22 single-file APNs relay + deploy README
docs/     PROTOCOL.md (authoritative spec), gen-test-vectors.mjs, test-vectors.json
```

## Setup

### 1. Apple portal + relay server

Register the App IDs / App Group and deploy the relay on your Ubuntu server —
follow **`server/README.md`** step by step (it also covers the Caddy route at
`https://push.luojiajiang.uk/opi/*`).

### 2. Watch app

```sh
cp watch/Local.xcconfig.example watch/Local.xcconfig
```

Fill in `DEVELOPMENT_TEAM` and `BUNDLE_PREFIX`. They must match the App IDs and App
Group from step 1 (`<BUNDLE_PREFIX>.opiconnect.watchkitapp`, `group.<BUNDLE_PREFIX>.opiconnect`;
Xcode automatic signing can also create them for you). If you run the relay elsewhere,
adjust `RELAY_URL` in `watch/OpiConnect.xcconfig`.

Open `watch/OpiConnect.xcodeproj` in Xcode, select the **"OpiConnect Watch App"**
scheme and your physical watch, and Run. DEBUG builds use the APNs **sandbox**
automatically; TestFlight/App Store builds use production.

**TestFlight/App Store:** select the **"OpiConnect"** scheme (the container), destination
"Any iOS Device", then *Product > Archive* and *Distribute App > App Store Connect*.
Or run `scripts/testflight.sh` (archive + upload; `DESTINATION=export` builds a local
.ipa without uploading). TestFlight builds expire after 90 days, so re-run it before then.
App Store Connect will ask about **export compliance**: the app uses AES-GCM for
end-to-end encryption — answer the questionnaire for your situation (standard
OS-provided crypto usually qualifies for an exemption, but the answer is your
responsibility). For **App Review**, note that the reviewer has no Android phone:
attach a demo video and explain in the review notes.

### 3. Android app

Copy the `android/` folder to a machine with Android Studio (its bundled JDK 17+ is
fine — Windows works), or clone the repo there. Set your relay URL in
`android/gradle.properties` (`opi.relayUrl`), then Run the app on your phone.
Unit tests: `gradlew.bat :app:testDebugUnitTest`.

Walk through the in-app setup cards: grant Bluetooth + notification permissions,
enable notification access, allow the battery exemption, and optionally grant
**calendar access** (powers the watch calendar + reminders — skipped if denied).
**OPPO/ColorOS:** also
enable *Battery > App battery management > OpiConnect > allow background activity*
and *auto launch*, and lock OpiConnect in Recents so ColorOS doesn't kill it.

### 4. Pairing

Open the watch app — it shows a QR code and scans for the phone. In the Android app tap
"Scan watch QR" and scan it. The watch flips to the home screen as soon as the BLE
handshake completes — keep the watch app open and near the phone during pairing.

### 5. Device test checklist

1. `curl https://push.luojiajiang.uk/opi/healthz` → `ok`.
2. Pair (QR). Both apps show connected.
3. Watch app **open**: trigger a notification (message yourself) — arrives over BLE instantly.
4. Watch app **closed** (lower wrist): another notification arrives via APNs with decrypted content.
5. Dismiss on Android → disappears from the watch (immediately over BLE; best-effort in background).
6. Dismiss on the watch, reopen the watch app → disappears on Android.
7. Tap an action (e.g. "Mark as read") and reply to a message by dictation → check on Android.
8. Reboot the phone → the link service comes back.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| "Watch not registered yet" | Open the watch app once with network coverage and allow notifications — registration happens on launch. |
| Nothing arrives over BLE | Bluetooth permissions granted on Android? Watch app must be **open**. The Android foreground notification shows the link status. |
| Push arrives as "New notification" with no content | The Notification Service Extension couldn't decrypt — keys out of sync; re-pair. |
| Service keeps dying | ColorOS/OEM battery management — see step 3 settings and the in-app tips. |
| Relay errors | See the troubleshooting table in `server/README.md`. |

## Licenses

- OpiConnect / OpiLink: [PolyForm Shield 1.0.0](https://polyformproject.org/licenses/shield/1.0.0) (`LICENSE`).
  The source is available for reading, auditing and building for your own use; you may not
  use it to provide a product that competes with OpiLink. Commits up to and including
  `cde6865` were published under GPL-3.0.
- swift-qrcode-generator: MIT

The OpiLink name and app icon are not covered by the license. Forks must use a different
name and icon.

## Contributing

By submitting a contribution you agree that it may be distributed under the project's
current license and any future license the maintainer chooses, including in the paid
App Store build.
