# LocalSend RinoPaw 版

一个自用整理版的 LocalSend 构建，提供 Windows 便携包和 Android APK。重点是：默认只走局域网、不主动连接公共 signaling / STUN 服务。

当前版本：`1.17.1`

## 下载

Windows：

[下载 LocalSend.zip](https://github.com/RinoPaw/localsend/releases/latest/download/LocalSend.zip)

Android：

- [arm64-v8a](https://github.com/RinoPaw/localsend/releases/latest/download/LocalSend-1.17.1-android-arm64v8.apk)：大多数现代 Android 手机和平板
- [armeabi-v7a](https://github.com/RinoPaw/localsend/releases/latest/download/LocalSend-1.17.1-android-arm32v7.apk)：较旧的 32 位 Android 设备
- [x86_64](https://github.com/RinoPaw/localsend/releases/latest/download/LocalSend-1.17.1-android-x64.apk)：模拟器或少数 x86 Android 设备

更多版本见 [Releases](https://github.com/RinoPaw/localsend/releases/latest)。

Windows 解压后运行 `localsend_app.exe`。压缩包内带有空的 `settings.json`，因此默认使用便携模式，设置会保存在程序目录旁边。

这些构建没有代码签名证书。Windows SmartScreen 拦截时，选择“更多信息”后继续运行；Android 安装 APK 时，需要允许来自浏览器或文件管理器的安装。

## 这个版本改了什么

`1.17.1` 基于 LocalSend `1.17.0`，整理了这次自用构建需要的修复：

- 默认不再连接 `public.localsend.org`。
- 默认不再使用 `stun.localsend.org`。
- 同一局域网内仍可正常发现设备和传文件。
- 手动配置 signaling / STUN 服务器时仍然生效。
- 修复 signaling 设备列表里可能出现本机的问题。
- 修复 signaling 连接忽略用户配置、总是连接默认公网地址的问题。
- 修复上传查询中 `sessionId` 被遮蔽导致 session 查不到的问题。
- 整理发布流程，Windows zip 和 Android APK 可以从 Releases 下载。

## 默认网络行为

- 局域网发现和传输照常使用。
- 默认不连接公共 signaling server。
- 默认不连接公共 STUN server。
- 没有外网时，同一局域网内仍可使用。

需要跨网段、NAT 或 WebRTC signaling 时，可以在设置里填写自己的 signaling / STUN 服务器。

## 说明

LocalSend 是开源项目。本仓库保留原许可证，许可证见 [LICENSE](LICENSE)。
