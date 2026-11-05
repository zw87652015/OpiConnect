# OpiLink — App Review information

## Sign-in information

"Sign-in required": **No**. There's no account; pairing uses a QR code.

## Contact information

Luojia Jiang, email: me@luojiajiang.uk.

## Notes for the reviewer (paste into "Notes", max 4000)

```
1. SCREEN RECORDING
Recorded on a physical Apple Watch running watchOS <VERSION> (with a physical Android phone): <VIDEO LINK>
watchOS has no built-in screen recording and the flow involves two devices, so the video films the watch and phone screens together in one continuous shot.
It starts by launching OpiLink on the watch and shows the typical flow:
- The watch shows a pairing QR code. On the Android phone, the OpiLink companion is granted notification access and scans the code. The watch switches to its home screen.
- A message arrives on the phone and appears on the watch. We reply by dictation and the reply is sent from the phone.
- A sign-in SMS arrives and its one-time code is shown in large type.
- Dismissing a notification on the watch clears it on the phone, and the other way round.
- With the watch app closed, a notification still arrives through Apple Push Notification service.
- Find My Phone rings the phone, Now Playing controls the phone's music, the Calendar screen shows events, and complications show phone battery and the next event.
- Settings > Unpair, which removes the pairing from the watch and the relay.
The app has no accounts, no login, no user-generated content shared with others, and no paid content or In-App Purchases.

2. PURPOSE AND AUDIENCE
For people who wear an Apple Watch but use an Android phone. Apple Watch normally gets notifications only from an iPhone, so these users miss their phone's messages, codes and reminders on the wrist. OpiLink mirrors the Android phone's notifications to the watch, lets the user reply and dismiss them, and adds Find My Phone, music control and calendar.

3. SETUP AND MAIN FEATURES
- Install the free OpiLink companion app on an Android 14+ phone: https://github.com/zw87652015/OpiConnect/releases (source code is public in the same repository).
- Open OpiLink on the watch and allow notifications. A QR code appears.
- In the companion app, grant notification access and tap "Scan watch QR". Pairing completes; no login or credentials are needed.
- Notifications then appear on the watch. Find My Phone, Now Playing, Calendar and Settings are on the watch home screen.
Without an Android phone, the watch app launches to the pairing screen, requests notification permission and registers for push; the Bluetooth prompt appears when it looks for the phone.

4. EXTERNAL SERVICES
- Apple Push Notification service: delivers notifications when the watch app isn't open.
- Our own relay server (push.luojiajiang.uk): forwards end-to-end encrypted (AES-256-GCM) data to APNs. It stores only the APNs token, a random pairing ID and a hash of a pairing secret, and can't read notification content.
- Bluetooth LE: direct link to the user's own paired phone while the app is open.
- GitHub Releases: distribution of the free Android companion app.
No third-party data providers, authentication, payment, analytics, advertising or AI services are used.

5. REGIONAL DIFFERENCES
None. The app works the same in all regions.

6. REGULATED INDUSTRY / THIRD-PARTY MATERIAL
Not applicable. The app isn't in a regulated industry and contains no protected third-party content. It shows only the user's own notifications from their own phone.

Background modes: bluetooth-central (keeps the link to the paired phone while the app is in use) and remote-notification (removes notifications dismissed on the phone).
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
