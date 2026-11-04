# OpiLink — App Review information

## Sign-in information

"Sign-in required": **No**. There's no account; pairing uses a QR code.

## Contact information

First name, last name, phone, email: your details (**fill in**).

## Notes for the reviewer (paste into "Notes", max 4000)

```
OpiLink is a watch-only app that mirrors notifications from an Android phone to Apple Watch. It needs the free OpiLink companion app on an Android phone (Android 14+). The companion's source is public and it is distributed on GitHub Releases: https://github.com/zw87652015/OpiConnect/releases

Because reviewers usually don't have an Android phone, we attached a demo video showing the complete flow on real devices: <VIDEO LINK>

What the video shows:
1. Launch OpiLink on Apple Watch. It shows a pairing QR code.
2. On the Android phone, open the OpiLink companion, grant notification access, and scan the QR code. The watch switches to the home screen.
3. A message arrives on the phone and appears on the watch. We reply by dictation, and the reply is sent from the phone.
4. A sign-in SMS with a one-time code arrives, and the code is shown in large type on the watch.
5. Dismissing the notification on the watch clears it on the phone, and the other way round.
6. With the watch app closed, a notification still arrives through Apple Push Notification service and is decrypted by the Notification Service Extension.
7. Find Phone rings the phone. Now Playing controls the phone's music. The Calendar screen shows synced events. Complications show the phone battery and the next event.

Without a phone you can still check the following on the watch: the app launches to the pairing screen, requests notification permission, and registers for push. The Bluetooth permission prompt appears when the app starts looking for the phone.

Privacy: all notification content is end-to-end encrypted (AES-256-GCM) with a key created on the watch and shared only through the QR code. Our relay server forwards ciphertext to APNs and stores only the APNs token and a random pairing ID. There are no accounts, ads or analytics.

Bluetooth is used only to talk to the user's own paired phone while the app is open. Background modes: bluetooth-central (keeps the link while the app is in use) and remote-notification (removes notifications dismissed on the phone).
```

## Attachment: demo video

Record on real hardware (screen-record the phone, and film the watch or use Xcode's device screenshot tool), about 2–3 minutes. Follow the 7 steps in the notes above. Upload it to an unlisted YouTube/Vimeo link or a cloud drive, put the link in the notes, and also attach the file in App Review → Attachment if it's under the size limit.

## Likely review questions and suggested replies

| Concern | Reply |
| --- | --- |
| **2.1 Can't test without Android** | Point to the video, and offer a TestFlight walkthrough or a video call. |
| **2.3.10 Mentions another platform (Android)** | Android interoperability is the app's only purpose. The metadata names Android only to explain compatibility, and the screenshots show no Android branding. |
| **4.2 Minimal functionality** | Two-way notification actions, replies, Find Phone, media control, calendar with on-watch reminders, and four complications. |
| **5.1.1 Data use** | Point to the privacy policy and the end-to-end encryption design (`docs/PROTOCOL.md`). |
| **Background modes** | `bluetooth-central` is used only for the active link to the paired phone. `remote-notification` handles dismiss pushes. |
