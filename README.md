# RinoPaw LocalSend

这是 [RinoPaw/localsend](https://github.com/RinoPaw/localsend) 维护的 LocalSend fork，用来打包一个更适合自己使用的 Windows 便携版本。

上游项目是 [localsend/localsend](https://github.com/localsend/localsend)。LocalSend 本身是一个开源的局域网文件传输工具，可以在同一网络内安全地发送文件、文本和文件夹。

当前 fork 版本：`1.17.1`

## 这个版本

`1.17.1` 基于上游 `1.17.0`，整理了目前这个 fork 里的改动：

- 默认只走局域网发现和传输，不再自动连接 `public.localsend.org`。
- 默认不再使用 `stun.localsend.org`。
- 手动配置 signaling / STUN 服务器时仍然生效。
- 修复 signaling 发现时可能把本机显示成 Nearby Devices 的问题。
- 修复 signaling 连接忽略用户配置、总是连公网默认地址的问题。
- 修复上传查询里 `sessionId` 被遮蔽导致 session 查不到的问题。
- 修复这个 fork 的 GitHub Actions、CI 和 Windows zip 构建流程。

## 下载

最新 Windows zip：

[下载 LocalSend.zip](https://github.com/RinoPaw/localsend/releases/latest/download/LocalSend.zip)

Release 页面：

[https://github.com/RinoPaw/localsend/releases/latest](https://github.com/RinoPaw/localsend/releases/latest)

解压后运行 `localsend_app.exe`。这个 zip 会带一个空的 `settings.json`，所以默认是便携模式，设置会保存在程序目录旁边。

如果 Windows SmartScreen 拦截，点“更多信息”后再运行即可。这个 fork 没有代码签名证书。

## 默认网络行为

- 同一局域网内通过 UDP / HTTP(S) 发现和传输。
- 默认不连接公网 signaling server。
- 默认不连接公网 STUN server。
- 没有外网时，同一局域网内仍可使用。

需要跨网段、NAT 或 WebRTC signaling 时，可以在设置里手动填写自己的 signaling / STUN 服务器。

## 构建

推荐直接用 GitHub Actions：

- `CI`：格式化、分析、测试和版本一致性检查。
- `Release Windows zip`：构建 Windows 便携 zip，并发布到 GitHub Releases。

本地构建 Windows 版本：

```powershell
cd app
flutter pub get
flutter build windows
```

便携模式：

```powershell
New-Item build/windows/x64/runner/Release/settings.json -ItemType File
```

## 上游关系

这个仓库只是个人 fork。协议、应用主体和绝大部分代码仍来自 LocalSend 上游项目。

上游仓库：

[https://github.com/localsend/localsend](https://github.com/localsend/localsend)

许可证：

[MIT License](LICENSE)
