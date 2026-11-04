# OpiLink — App Store Connect answers

These are the non-listing fields, with the reasoning behind each answer so you can check them against the code. Items marked **DECIDE** need your call.

## App Information

| Field | Value |
| --- | --- |
| Name | OpiLink |
| Bundle ID | `<BUNDLE_PREFIX>.opiconnect` (the container app record; unchanged) |
| SKU | `opilink-watch` (any unique string; it can't be changed later) |
| Primary language | English (U.S.) |
| Primary category | Utilities |
| Secondary category | Productivity |
| Content rights | No third-party content. The app only shows the user's own notifications. |
| Price | Free, no in-app purchases (**DECIDE** if otherwise) |
| Availability | All countries **except China mainland** (no MIIT/ICP app filing). EU needs a Digital Services Act trader declaration; see below. |
| watchOS-only | Yes (`WKWatchOnly`), so screenshots are only needed for Apple Watch |

**China mainland:** new apps need an MIIT app filing (ICP) number, which generally requires a Chinese entity or a local partner. Deselect China mainland in Pricing and Availability. The zh-Hans listing still serves Simplified Chinese users in Singapore, Malaysia and elsewhere.

**EU (Digital Services Act):** you must declare in App Store Connect (Business → trader status) whether you're a trader. Selling a paid app generally makes you one, and then your address, phone and email appear publicly on the EU product page. If you don't want that, remove the EU countries.

## App Privacy (nutrition label)

What leaves the device, based on `server/index.mjs` and `docs/PROTOCOL.md`:

| Data | Where it goes | Retention | Counts as "collected"? |
| --- | --- | --- | --- |
| APNs device token, random `pairId`, SHA-256 of the pairing secret | Relay (`pairings.json`) | Until unpair, or until APNs reports the token dead | **Yes.** It's stored beyond the request. |
| Notification content (title, body, app name, actions) | Relay → APNs, AES-256-GCM ciphertext only | Not stored; forwarded in real time | No. The relay can't read it and doesn't keep it. |
| Calendar, media, battery, Find Phone, replies, dismissals | Bluetooth between phone and watch (battery level also rides inside the encrypted push) | Devices only | No |
| IP address | Seen by the relay for in-memory rate limiting; not written to the app's logs | Minutes, in memory | No, unless your Caddy access log keeps IPs (**DECIDE**: check `/etc/caddy` logging for the `/opi` route) |

Recommended answers:

1. "Do you or your third-party partners collect data from this app?" → **Yes**
2. Data type: **Identifiers → Device ID** (the APNs token and the random pairing ID)
   - Purpose: **App Functionality** only
   - Linked to the user's identity: **No** (no account, name, email or phone number)
   - Used for tracking: **No**
3. No other data types.

This label shows "Data Not Linked to You: Identifiers". Selecting "Data Not Collected" is also arguable, because the token isn't tied to a person. The Device ID answer is the conservative choice and matches the privacy policy.

Privacy manifests: the app, NSE and widget already ship `PrivacyInfo.xcprivacy` (no tracking, UserDefaults reason `1C8F.1`). No change needed.

## Age Rating

Answer **None / No** to every content question: violence, sexual content, profanity, horror, drugs, gambling, contests, medical, unrestricted web access, user-generated content, and advertising.

**DECIDE: "Messaging and chat" capability.** The app lets the user reply to messages from their own Android apps, but it doesn't provide a messaging service or let strangers contact the user. "No" is defensible. If you'd rather not risk a reviewer disagreeing, answer "Yes". Either way the expected rating is **4+**, or 9+/13+ if Apple's questionnaire maps messaging to a higher tier.

## Export Compliance (**DECIDE**: this is your legal call)

What the code does: CryptoKit **AES-256-GCM** encrypts user data end to end between the watch and the phone, with **HKDF-SHA256** key derivation and HTTPS to the relay. These are standard algorithms only, and nothing is proprietary.

Current state: `ITSAppUsesNonExemptEncryption = NO` is set in `watch/OpiConnect Watch App/Info.plist` and on the container target, so App Store Connect won't ask the question. **This is probably not accurate.** Apple's "exempt" options cover encryption used only for authentication, HTTPS/OS-provided transport, copy protection and similar uses. Encrypting user content yourself, even with CryptoKit, generally falls outside them.

The usual path for an app like this:

1. Uses encryption: **Yes**.
2. Proprietary or non-standard algorithms: **No**, standard algorithms only.
3. This is typically mass-market (US EAR 5D992.c). Under current US rules, mass-market apps using standard crypto generally don't need an annual self-classification report, and publicly available source code is generally outside the EAR. Confirm this for your situation.
4. **France:** Apple's [documentation table](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/) requires no documentation when encryption is limited to what the Apple OS provides. The watch binary uses only CryptoKit and HTTPS, so pick that option and no French declaration is needed. A French declaration is only required for standard algorithms implemented outside the OS (for example, a bundled crypto library).
5. Once settled, set `ITSAppUsesNonExemptEncryption` to match (and `ITSEncryptionExportComplianceCode` if Apple issues one) so TestFlight and App Store uploads stop prompting.

## Version information

| Field | Value |
| --- | --- |
| Version | 1.0 |
| Copyright | `2026 Luojia Jiang`|
| Build | The latest TestFlight build after the OpiLink rename (the build uploaded on 2026-11-04 still says "OpiConnect" on the watch) |
| Release | Manual release recommended for 1.0 |

## License note

The repo is source-available under PolyForm Shield 1.0.0 (commits up to `cde6865` were GPL-3.0). As the sole copyright holder you can publish your own build on the App Store, and the license bars others from shipping competing copies. Don't call the project "open source" in store copy; PolyForm Shield isn't an OSI license. The README's Contributing section asks contributors to allow relicensing; keep it that way before merging outside code.
