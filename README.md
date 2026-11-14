# SoftEther VPN Multi-Platform Client Suite

本项目是基于 SoftEther VPN 打造的**多平台全套客户端解决方案**，针对不同平台分别维护专有架构与分支：

- **macOS (Apple Silicon ARM64)**：原生现代 SwiftUI 客户端（`.app` / `.dmg` / `.pkg`）
- **iOS (iPhone / iPad)**：纯 Swift 实现 Direct SSL-VPN 协议与 NetworkExtension（`.ipa`）
- **OpenWrt**：路由器多架构核心服务与 LuCI Web 管理界面（`.ipk`）

---

## 🌿 分支导航与功能说明

仓库按平台职责划分为以下三个主维护分支，请按需切换分支获取对应源码与构建脚本：

### 1. [`Macos`](https://github.com/ttlaknl/softether-macos/tree/Macos) 分支
- **适用平台**：macOS 12.0+（Apple Silicon M1/M2/M3/M4 系列芯片原生编译）。
- **主要内容**：
  - 原生 C 核心二进制及动态库（`vpnclient`、`vpncmd`、`libcedar.dylib`、`libmayaqua.dylib`）。
  - 原生 SwiftUI 界面（暗黑毛玻璃风格、实时上下行速率监控、配置持久化、一键网络诊断）。
  - 内置 `v1.0` 增强特性：UDP Acceleration 自动加速、8 通道 TCP 并发、系统 DNS 安全备份与 `/etc/resolver` 分流、防回环路由注入。
  - 标准打包套件：支持一键生成拖拽式 `.dmg` 与标准 macOS `.pkg` 安装包，提供 Xcode 原生工程（`SoftEtherUI.xcodeproj`）。

### 2. [`IOS`](https://github.com/ttlaknl/softether-macos/tree/IOS) 分支
- **适用平台**：iOS 15.0+（iPhone 18 及兼容设备，ARM64 架构）。
- **主要内容**：
  - **纯 Swift 实现 SoftEther SSL-VPN 客户端**：无须编译庞大 C 依赖，直接在 Swift 内实现 `/vpnsvc/connect.cgi` 握手、`/vpnsvc/vpn.cgi` 认证、`Pack` 二进制序列化、SHA-0 密码哈希与 L2 以太网帧 ⇋ L3 IPv4 数据包双向转换。
  - **双模式 `.ipa` 构建脚本（`build_ios_ipa.sh`）**：
    - `SoftEtherUI-iOS.ipa`：完整版，包含 `PacketTunnel.appex` (`NEPacketTunnelProvider`) 系统级网络扩展（需带 VPN 权限证书签名）。
    - `SoftEtherUI-iOS-Lite.ipa`：单 App 免权限版，不包含 `appex` 插件，支持所有普通个人 `.p12` 证书直接自签安装并运行内置直连会话。

### 3. [`OpenWrt`](https://github.com/ttlaknl/softether-macos/tree/OpenWrt) 分支
- **适用平台**：OpenWrt 18.06 / 19.07 / 21.02 / 22.03 / 23.05+，兼容 `x86_64`、`aarch64`（ARM64）及 `arm_cortex-a7`（ARM32）。
- **主要内容**：
  - 核心服务包 `softether-client`：标准 `procd` 守护进程管理、UCI 自动化配置同步、看门狗自动保活与防回环全局/分流路由策略。
  - Web 界面包 `luci-app-softether-client`：现代 JS + 经典 Lua 双架构 LuCI 控制台，支持网页端一键连接/断开、实时流量轮询及交互式 `vpncmd` 诊断。
  - Docker 一键多架构编译脚本（`build.sh`）与全自动 GitHub Actions CI 工作流。

---

## 🛠️ GitHub Actions 云端自动构建

各分支均配置有专属的 CI 构建工作流：
- `Macos` 分支推送自动编译 macOS App 并打包 `.zip` 供下载测试。
- `IOS` 分支推送自动编译并生成两种规格的 `.ipa` 安装包。
- `OpenWrt` 分支推送自动启动各架构 SDK 编译矩阵并产出对应 `.ipk` 包。
