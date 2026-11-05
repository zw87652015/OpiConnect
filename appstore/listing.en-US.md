# OpiLink — App Store listing (English, en-US / primary)

Character limits are App Store Connect's; every field below is within them.

## Name (max 30)

```
OpiLink
```

## Subtitle (max 30)

```
Android notifications on Watch
```

## Promotional text (max 170; can be changed without a new build)

```
Wear an Apple Watch with an Android phone? OpiLink brings your phone's notifications, replies, calendar, music and Find My Phone to your wrist, end-to-end encrypted.
```

## Description (max 4000)

```
OpiLink brings your Android phone's notifications to your Apple Watch.

Pair once by scanning a QR code on the watch with the free OpiLink companion app on your Android phone. From then on, messages, mail, deliveries and other app notifications appear on your wrist. You can read them, reply, and dismiss them without taking out your phone.

NOTIFICATIONS
• Mirrors notifications from any app on your Android phone
• Reply to messages by dictation or keyboard, and use the app's own actions such as "Mark as read"
• Dismissals sync both ways: clear a notification on one device and it disappears on the other
• One-time codes are spotted automatically and shown in large type, so sign-in codes are easy to read

MORE ON YOUR WRIST
• Find My Phone: make your phone ring and vibrate at full alarm volume, even in silent mode
• Now Playing: play, pause and skip tracks, and turn the Digital Crown to change the volume
• Phone battery: see your phone's charge on the watch and on a complication
• Calendar: your next 30 days of events, with reminders on the watch
• Complications and Smart Stack widgets for phone battery, the next event, Find My Phone and music

PRIVATE BY DESIGN
• End-to-end encrypted with AES-256-GCM. The key is created on your watch and shared with your phone only through the pairing QR code.
• When the watch app is open, the phone talks to it directly over Bluetooth. Otherwise, notifications are delivered through Apple Push Notification service by a small relay that only ever sees encrypted data.
• No accounts, no ads, no analytics, no tracking.
• Source available: the code for the watch app, Android app and relay is published on GitHub, so anyone can check how it works.

REQUIREMENTS
• An Apple Watch running watchOS 10 or later
• An Android phone running Android 14 or later with the OpiLink companion app, free from https://github.com/zw87652015/OpiConnect/releases
• Notification access granted to the companion app on Android

GOOD TO KNOW
• Background delivery uses Apple's push service, so your watch needs a connection through its iPhone, Wi-Fi or cellular.
• Very long notifications are shortened to fit Apple's push size limit.
• watchOS limits background Bluetooth, so replies and dismissals made while the phone is out of reach are queued and sent the next time the watch app connects.
```

## Keywords (max 100, comma-separated, no spaces)

Words already in the name and subtitle (OpiLink, Android, notifications, watch) are indexed automatically, so they aren't repeated here.

```
mirror,phone,notify,find my phone,battery,otp,code,reply,calendar,music remote,sync,bluetooth,alerts
```

## What's New (not shown for version 1.0)

Leave empty for 1.0. Template for later releases:

```
• <change>
• Bug fixes and reliability improvements
```

## URLs

| Field | Value |
| --- | --- |
| Support URL (required) | https://github.com/zw87652015/OpiConnect/issues |
| Marketing URL (optional) | https://github.com/zw87652015/OpiConnect |
| Privacy Policy URL (required) | https://github.com/zw87652015/OpiConnect/blob/main/appstore/privacy-policy.md |

The privacy policy URL only works after `appstore/privacy-policy.md` is pushed to `main`.

## Screenshots (Apple Watch, 422 × 514 — Ultra 4 size, same size in every localization)

Upload in this order from `appstore/screenshots/en-US/`:

| # | File | What it shows |
| --- | --- | --- |
| 1 | 01-home.png | Notification list, with a one-time code highlighted |
| 2 | 02-detail.png | A message with Reply and Mark as read |
| 3 | 03-otp.png | One-time code shown in large type |
| 4 | 04-calendar.png | Upcoming events synced from the phone |
| 5 | 05-music.png | Now Playing controls |
| 6 | 06-findphone.png | Find My Phone |
| 7 | 07-pairing.png | QR pairing screen |

Screenshots are captured from the Debug build's demo mode (`-OpiDemo en`), which uses made-up content.

## App icon

The 1024 × 1024 marketing icon comes from the build (`watch/OpiConnect/Assets.xcassets/AppIcon.appiconset/icon.png`), so nothing needs to be uploaded separately.
