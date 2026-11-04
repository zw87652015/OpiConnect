# OpiLink Privacy Policy

Last updated: 4 November 2026

OpiLink consists of an Apple Watch app, an Android companion app, and a push relay server, all operated by Luojia Jiang ("we"). This policy explains what data OpiLink handles and why.

## Summary

- No accounts, no advertising, no analytics, no tracking.
- Your notifications are end-to-end encrypted. We can't read them.
- The relay server stores only what it needs to send a push to your watch.

## How OpiLink works

When you pair, your Apple Watch generates a random encryption key and shows it as a QR code. Your Android phone scans it. The key stays on your two devices: in the watch's Keychain, and wrapped by the Android Keystore on the phone. It's never sent to us.

The phone encrypts every notification with AES-256-GCM before sending it. While the watch app is open, the phone sends it directly over Bluetooth. Otherwise, the phone sends the encrypted data to our relay server, which passes it to Apple Push Notification service (APNs) for delivery to your watch, where it's decrypted.

## Data the relay server stores

| Data | Purpose | Retention |
| --- | --- | --- |
| APNs device token of your watch | Deliver pushes to your watch | Until you unpair, or until Apple reports the token is no longer valid |
| Random pairing ID | Identify your pairing; not linked to your name or any account | Same as above |
| Hash of a pairing secret | Make sure only your phone can send pushes to your watch | Same as above |
| Creation/update timestamps | Maintenance | Same as above |

## Data passed through but not stored

- **Notification content** (app name, title, text, available actions, and your phone's battery level) reaches the relay only as encrypted data. The relay can't decrypt it, forwards it to APNs immediately, and doesn't keep it. Apple handles push delivery under its own privacy policy.
- **IP addresses** are used briefly in memory to limit abuse (rate limiting) and aren't written to the app's logs. Standard web-server logs may record connection metadata for a short period for security and operations.

## Data that stays on your devices

Calendar events, music and playback information, Find Phone commands, replies, and dismissals travel only between your phone and your watch over encrypted Bluetooth. Received notifications are stored on the watch until you dismiss them or unpair.

## Permissions

- **Apple Watch:** notifications (to show mirrored notifications), Bluetooth (to talk to your phone).
- **Android:** notification access (to read the notifications you choose to mirror), Bluetooth, calendar (optional, to show events and reminders on the watch), battery-optimization exemption (to keep the link running).

## Sharing

We don't sell, rent or share your data. Apart from Apple delivering pushes, no third parties are involved.

## Deleting your data

Tap **Settings → Unpair** on the watch. The watch deletes its key and local data and tells the relay to delete your registration. Uninstalling the apps also deletes their local data.

## Children

OpiLink isn't directed at children and doesn't knowingly collect personal information from them.

## Source code

The source code of all three components is public at https://github.com/zw87652015/OpiConnect, so you can check these statements yourself.

## Changes

We'll post any changes on this page and update the date above.

## Contact

Questions: open an issue at https://github.com/zw87652015/OpiConnect/issues or email `<your email>`.

---

# OpiLink 隐私政策

最后更新：2026 年 11 月 4 日

OpiLink 由 Apple Watch App、安卓配套 App 和推送中转服务器组成，均由 Luojia Jiang（"我们"）运营。本政策说明 OpiLink 处理哪些数据以及处理目的。

## 概要

- 无需账户，无广告，无数据分析，无跟踪。
- 你的通知经端到端加密，我们无法读取。
- 中转服务器只保存向你的手表发送推送所必需的信息。

## 工作原理

配对时，Apple Watch 会生成一个随机加密密钥，并以二维码形式显示，由安卓手机扫描获取。该密钥只保存在你的两台设备上：手表的钥匙串中，以及手机上经 Android Keystore 加密保护的存储中，绝不会发送给我们。

手机在发送每条通知前都会用 AES-256-GCM 加密。手表 App 打开时，手机通过蓝牙直接发送；其他时候，手机把加密数据发送到我们的中转服务器，再由服务器转交 Apple 推送通知服务（APNs）送达手表，在手表上解密。

## 中转服务器保存的数据

| 数据 | 用途 | 保存期限 |
| --- | --- | --- |
| 手表的 APNs 设备令牌 | 向你的手表发送推送 | 直到你解除配对，或 Apple 告知该令牌失效 |
| 随机配对 ID | 标识你的配对，不与你的姓名或任何账户关联 | 同上 |
| 配对密钥的哈希值 | 确保只有你的手机能向你的手表发送推送 | 同上 |
| 创建/更新时间 | 维护 | 同上 |

## 经过但不保存的数据

- **通知内容**（App 名称、标题、正文、可用操作及手机电量）到达中转服务器时已经加密。服务器无法解密，会立即转发给 APNs，且不会保存。推送送达由 Apple 依据其隐私政策处理。
- **IP 地址**仅在内存中短暂用于防滥用（频率限制），不会写入 App 日志。标准的 Web 服务器日志可能出于安全和运维目的短期记录连接元数据。

## 只保存在你设备上的数据

日历日程、音乐与播放信息、查找手机指令、回复和清除操作，只通过加密蓝牙在手机和手表之间传输。收到的通知保存在手表上，直到你清除通知或解除配对。

## 权限

- **Apple Watch：** 通知（显示同步的通知）、蓝牙（与手机通信）。
- **安卓：** 通知使用权（读取你要同步的通知）、蓝牙、日历（可选，用于在手表上显示日程和提醒）、忽略电池优化（保持连接）。

## 共享

我们不会出售、出租或共享你的数据。除 Apple 负责推送送达外，不涉及任何第三方。

## 删除数据

在手表上点按**设置 → 解除配对**。手表会删除密钥和本地数据，并通知中转服务器删除你的注册信息。卸载 App 也会删除其本地数据。

## 儿童

OpiLink 并非面向儿童，我们不会有意收集儿童的个人信息。

## 源代码

三个组件的源代码均公开于 https://github.com/zw87652015/OpiConnect，你可以自行核实上述说明。

## 变更

如有变更，我们会在本页面发布并更新上方日期。

## 联系方式

如有疑问，请在 https://github.com/zw87652015/OpiConnect/issues 提交 issue，或发送邮件至 `<your email>`。
