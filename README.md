# SoftEther VPN Client — iOS (IPA) Branch

本分支为 **SoftEther VPN iOS 原生客户端（ARM64 / iOS 15.0+）** 专用分支。

> 本仓库包含三个主要平台分支：
> - **`Macos`**：macOS (Apple Silicon ARM64) 原生桌面客户端（`.app` / `.dmg` / `.pkg`）
> - **`IOS`**（当前分支）：iOS 原生 Swift 协议客户端与 `NEPacketTunnelProvider` 打包（`.ipa`）
> - **`OpenWrt`**：OpenWrt 路由器多架构客户端套件与 LuCI Web 管理界面（`.ipk`）

---

## ✨ 核心特性

- **纯 Swift 实现 SoftEther SSL-VPN 协议**：`SoftEtherUI/iOS/SoftEtherProtocolClient.swift` 直接完成 SSL-VPN 握手（`/vpnsvc/connect.cgi`）、认证（`/vpnsvc/vpn.cgi`）、`Pack` 序列化、SHA-0 密码哈希及 L2/L3 ARP+DHCP 数据包转换。
- **双模式安装包输出**（由 `build_ios_ipa.sh` 一键生成）：
  - **`SoftEtherUI-iOS.ipa`**：完整版，包含 `PacketTunnel.appex` (`NEPacketTunnelProvider`) 系统级网络扩展，适用于具备 `com.apple.developer.networking.networkextension` 权限的企业/付费开发者证书。
  - **`SoftEtherUI-iOS-Lite.ipa`**：免权限单包版，不包含 `appex` 扩展，兼容普通个人 `.p12` 证书直接自签安装（内置直连协议会话引擎）。

---

## 🛠️ 本地与云端构建

### 本地 macOS (Xcode) 一键打包

```bash
chmod +x build_ios_ipa.sh
./build_ios_ipa.sh
# 或使用 Makefile
make ios
```

生成的 `.ipa` 文件位于仓库根目录：`SoftEtherUI-iOS.ipa` 与 `SoftEtherUI-iOS-Lite.ipa`。

### GitHub Actions 自动构建

推送到 `IOS` 分支后，`.github/workflows/ios_build.yml` 会自动在 `macos-latest` 上编译并在 **Artifacts** 中上传 `SoftEtherUI-iOS-Full-IPA` 与 `SoftEtherUI-iOS-Lite-IPA`。
