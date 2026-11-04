# OpiLink — App Store listing (Simplified Chinese, zh-Hans)

Add this localization in App Store Connect under App Information → Localizable Information → "Chinese (Simplified)". The watch app's interface is currently English only. The complications are localized, and the Chinese demo screenshots use Chinese content.

## 名称 Name (max 30)

```
OpiLink
```

## 副标题 Subtitle (max 30)

```
在 Apple Watch 上收安卓手机通知
```

## 推广文本 Promotional text (max 170)

```
用安卓手机，也能戴 Apple Watch。OpiLink 把手机通知、消息回复、日历、音乐控制和查找手机带到手腕上，全程端到端加密。
```

## 描述 Description (max 4000)

```
OpiLink 把安卓手机上的通知同步到你的 Apple Watch。

在安卓手机上安装免费的 OpiLink 配套 App，扫描手表上的二维码即可完成配对。之后，消息、邮件、快递等各类 App 的通知都会出现在手腕上，无需掏出手机就能查看、回复和清除。

通知
• 同步安卓手机上任意 App 的通知
• 通过听写或键盘回复消息，并可使用"标为已读"等 App 自带操作
• 双向同步清除：在一台设备上清除通知，另一台设备上也会同步消失
• 自动识别验证码并以大字号显示，登录时一眼就能看清

更多手腕功能
• 查找手机：让手机以最大闹钟音量响铃并振动，静音模式下也有效
• 正在播放：播放、暂停、切换曲目，旋转数码表冠调节音量
• 手机电量：在手表和表盘复杂功能上查看手机电量
• 日历：同步未来 30 天的日程，并在手表上提醒
• 表盘复杂功能和智能叠放小组件：手机电量、下一个日程、查找手机、音乐控制

隐私优先
• 采用 AES-256-GCM 端到端加密。密钥在手表上生成，仅通过配对二维码分享给你的手机。
• 手表 App 打开时，手机通过蓝牙直接与手表通信；其他时候，通知经由 Apple 推送通知服务送达，中转服务器只能看到加密后的数据。
• 无需注册账户，无广告，无数据分析，无跟踪。
• 源代码公开：手表 App、安卓 App 和中转服务器的代码均在 GitHub 上公开，任何人都可以查看其工作方式。

使用要求
• 运行 watchOS 10 或更高版本的 Apple Watch
• 运行 Android 14 或更高版本的安卓手机，并安装 OpiLink 配套 App（可在项目的 GitHub Releases 页面免费下载，见技术支持链接）
• 在安卓系统中为配套 App 开启通知使用权

须知
• 后台推送依赖 Apple 推送服务，手表需要通过配对的 iPhone、Wi-Fi 或蜂窝网络联网。
• 过长的通知会被截断，以符合 Apple 推送的大小限制。
• watchOS 会限制后台蓝牙，手机不在附近时，回复和清除操作会先保存在手表上，等手表 App 下次连接时再发送。
```

## 关键词 Keywords (max 100, comma-separated)

The name and subtitle are already indexed, so 安卓, 通知 and Apple Watch aren't repeated here. This list is 56 characters (126 UTF-8 bytes). If App Store Connect says it's too long, drop keywords from the end.

```
手表,同步,镜像,查找手机,手机电量,验证码,回复,日历,音乐,遥控,蓝牙,提醒,Android,消息,安卓手表
```

## 新内容 What's New

Leave empty for 1.0.

## URLs

Same as en-US (the URL fields are per-localization, so enter them again):

| Field | Value |
| --- | --- |
| Support URL | https://github.com/zw87652015/OpiConnect/issues |
| Marketing URL | https://github.com/zw87652015/OpiConnect |
| Privacy Policy URL | https://github.com/zw87652015/OpiConnect/blob/main/appstore/privacy-policy.md |

## Screenshots (422 × 514, from `appstore/screenshots/zh-Hans/`)

Same order and screens as en-US, with Chinese demo content (`-OpiDemo zh`, zh-Hans locale):
01-home, 02-detail, 03-otp, 04-calendar, 05-music, 06-findphone, 07-pairing.
