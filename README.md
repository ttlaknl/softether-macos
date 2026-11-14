# SoftEther VPN Client — macOS (Apple Silicon ARM64) Branch

本分支为 **SoftEther VPN macOS 原生客户端（Apple Silicon ARM64）** 专用分支。

> 本仓库包含三个主要平台分支：
> - **`Macos`**（当前分支）：macOS (Apple Silicon ARM64) 原生桌面客户端（`.app` / `.dmg` / `.pkg`）
> - **`IOS`**：iOS 原生 Swift 协议客户端与 `NEPacketTunnelProvider` 打包（`.ipa`）
> - **`OpenWrt`**：OpenWrt 路由器多架构客户端套件与 LuCI Web 管理界面（`.ipk`）

---

## ✨ 核心特性

- **Native ARM64 核心**：原生编译 SoftEther `vpnclient`、`vpncmd` 及 `libcedar.dylib` / `libmayaqua.dylib`，告别 Rosetta 2 转译损耗。
- **SwiftUI 现代桌面界面**：支持节点管理（UserDefaults 持久化 + 表单校验）、实时流量速率、连接日志控制台与一键网络诊断。
- **v1.0 网络与系统增强**：
  - `vpncmd` v5.02 `AccountDetailSet` 完整参数兼容，默认启用 **UDP Acceleration** 与 **8 通道 TCP 并发**。
  - 连接前自动备份系统原始 DNS（`savedOriginalDNS`），断开时精确恢复，支持 `/etc/resolver` 智能分流。
  - 修复 `hamcore.se2` 在 `Contents/Resources/` 中的路径及 Apple Silicon Ad-Hoc `codesign` 签名问题。
  - 修复 `utun` 缓冲区溢出、ARP 劫持与网关防回环路由。

---

## 🛠️ 本地构建与打包

```bash
# 1. 编译 macOS 原生 UI 应用 (SoftEtherUI.app)
make ui

# 2. 生成拖拽式 DMG 安装包
make dmg

# 3. 生成 PKG 安装包
make pkg
```

也可直接用 Xcode 打开 `SoftEtherUI.xcodeproj` 进行开发、调试与 Archive。
