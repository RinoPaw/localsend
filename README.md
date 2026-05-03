# LocalSend RinoPaw 便携版

一个自用整理版的 LocalSend Windows 便携包。重点是：解压即用、默认只走局域网、不主动连接公共 signaling / STUN 服务。

当前版本：`1.17.1`

## 下载

[下载 LocalSend.zip](https://github.com/RinoPaw/localsend/releases/latest/download/LocalSend.zip)

更多版本见 [Releases](https://github.com/RinoPaw/localsend/releases/latest)。

解压后运行 `localsend_app.exe`。压缩包内带有空的 `settings.json`，因此默认使用便携模式，设置会保存在程序目录旁边。

这个构建没有代码签名证书。如果 Windows SmartScreen 拦截，选择“更多信息”后继续运行。

## 这个版本改了什么

`1.17.1` 基于 LocalSend `1.17.0`，整理了这次自用构建需要的修复：

- 默认不再连接 `public.localsend.org`。
- 默认不再使用 `stun.localsend.org`。
- 同一局域网内仍可正常发现设备和传文件。
- 手动配置 signaling / STUN 服务器时仍然生效。
- 修复 signaling 设备列表里可能出现本机的问题。
- 修复 signaling 连接忽略用户配置、总是连接默认公网地址的问题。
- 修复上传查询中 `sessionId` 被遮蔽导致 session 查不到的问题。
- 整理发布流程，Windows zip 可以从 Releases 稳定下载。

## 默认网络行为

- 局域网发现和传输照常使用。
- 默认不连接公共 signaling server。
- 默认不连接公共 STUN server。
- 没有外网时，同一局域网内仍可使用。

需要跨网段、NAT 或 WebRTC signaling 时，可以在设置里填写自己的 signaling / STUN 服务器。

## 说明

LocalSend 是开源项目。本仓库保留原许可证，许可证见 [LICENSE](LICENSE)。
