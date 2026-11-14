# SoftEther VPN Client for OpenWrt (with LuCI Web GUI)

> 本仓库包含三个主要平台分支：
> - **`Macos`**：macOS (Apple Silicon ARM64) 原生桌面客户端（`.app` / `.dmg` / `.pkg`）
> - **`IOS`**：iOS 原生 Swift 协议客户端与 `NEPacketTunnelProvider` 打包（`.ipa`）
> - **`OpenWrt`**（当前分支）：OpenWrt 路由器多架构客户端套件与 LuCI Web 管理界面（`.ipk`）


本项目为 OpenWrt 系统专门定制开发的 **SoftEther VPN 客户端套件**，支持 **ARM（32位/64位）** 与 **X86/x64** 架构，提供标准 **opkg** 安装包（`.ipk`），并原生集成 **LuCI Web 管理界面**。

---

## 🌟 核心特性

- **跨架构兼容**：支持 `x86_64`、`x86`、`aarch64`（ARM64，如树莓派、NanoPi、RK3399/MT798x）以及 `arm_cortex-a7`（ARM32）。
- **标准 OpenWrt 服务化**：采用 OpenWrt `procd` 守护进程管理，支持崩溃自动拉起、开机自启和热重载。
- **UCI 自动化集成**：VPN 虚拟网卡创建、连接账户配置、加密与并发流加速均通过 UCI（`/etc/config/softether_client`）自动同步到 `vpnclient`，无需手动在终端反复敲命令。
- **智能防回环路由（Anti-Loop Routing）**：
  - 针对全局 VPN 网关模式，自动注入服务器主机直连路由，彻底解决客户端连接后默认网关被劫持导致 VPN 隧道断连的经典网络死锁问题。
  - 支持 **全局路由模式**、**指定内网网段分流模式（Split Tunneling）** 及 **仅网卡模式（配合 MWAN3 或自定义策略）**。
- **LuCI 双架构 Web 管理界面**：
  - **现代 LuCI**（OpenWrt 21.02 / 22.03 / 23.05 / 24.x）：纯异步 JavaScript 视图，毫秒级轮询实时流量统计、会话名称、IP 状态及一键连接控制。
  - **经典 LuCI**（OpenWrt 18.06 / 19.07）：内置 Lua CBI 兼容层。
- **断线保活看门狗**：集成 Watchdog 检测脚本，隧道断开或 Ping 丢包超限时自动重启重连。
- **内置诊断控制台**：在 Web 界面中直接执行 `vpncmd` 交互命令查看状态。

---

## 📂 项目结构

```
softether-openwrt/
├── Makefile                          # 统一构建入口 Makefile
├── README.md                         # 本说明文档
├── build.sh                          # Docker/SDK 多架构一键打包脚本
├── Dockerfile.build                  # 构建容器镜像
├── .github/
│   └── workflows/
│       └── build-ipk.yml             # GitHub Actions CI 跨架构自动构建流
└── package/
    ├── softether-client/             # 核心服务包
    │   ├── Makefile                  # OpenWrt 官方标准 Package Makefile
    │   └── files/
    │       ├── softether-client.init     # procd 启动脚本
    │       ├── softether-client.config   # UCI 默认配置文件
    │       ├── softether-helper.sh       # 账户/网卡/路由/DHCP 辅助管理工具
    │       ├── softether-watchdog.sh     # 隧道保活与重连看门狗
    │       ├── udhcpc.sh                 # DHCP 绑定事件路由注入脚本
    │       ├── launcher.sh               # 运行环境包装脚本
    │       └── hamcore.se2               # 预构建 SoftEther 核心资源包
    │
    └── luci-app-softether-client/    # LuCI Web 界面包
        ├── Makefile                  # LuCI Package Makefile
        ├── po/zh_Hans/               # 完整简体中文语言包
        ├── root/
        │   ├── etc/uci-defaults/     # 缓存刷新与 ACL 注册
        │   ├── usr/share/luci/menu.d # 现代 LuCI 菜单路由 JSON
        │   ├── usr/share/rpcd/acl.d  # RPCD 权限 ACL 定义
        │   ├── usr/lib/lua/luci/     # 经典 Lua CBI / Controller 兼容层
        │   └── www/luci-static/resources/view/softether-client/
        │       ├── overview.js       # 状态监控总览面板（实时轮询）
        │       ├── settings.js       # 基础与账户参数配置面板
        │       ├── routing.js        # 路由策略与 NAT 分流配置面板
        │       └── log.js            # 系统日志与 vpncmd 控制台
```

---

## 🚀 安装指南 (通过 opkg)

### 1. 准备依赖

在 OpenWrt 路由器终端中执行：

```bash
opkg update
opkg install kmod-tun libpthread librt libreadline libopenssl libncurses zlib ip-full iptables
```

### 2. 安装软件包

将编译生成的两个 `.ipk` 包上传至路由器的 `/tmp` 目录（例如 `softether-client_*.ipk` 与 `luci-app-softether-client_*.ipk`），执行：

```bash
cd /tmp
opkg install softether-client_*.ipk
opkg install luci-app-softether-client_*.ipk
```

安装完成后，刷新 LuCI Web 界面，即可在左侧导航栏 **VPN** 菜单下看到 **SoftEther 客户端**。

---

## 🖥️ Web 管理界面使用说明

### 1. 状态总览 (Overview)
- **客户端守护进程**：实时显示 `vpnclient` 运行状态与 PID。
- **隧道连接状态**：直观展示已连接（绿色徽章）、正在连接（黄色）或未连接（灰色）。
- **接口与 IP**：显示虚拟网卡（`vpn_vpn0`）状态与 DHCP 获取到的内网 IP 地址。
- **流量统计**：实时统计当前会话的接收（RX）与发送（TX）字节数。
- **一键快捷按钮**：支持在网页中直接触发【连接 VPN】、【断开连接】与【重启服务】。

### 2. 参数设置 (Settings)
- **基本设置**：
  - `启用客户端服务`：勾选后随路由器开机自动启动并连接。
  - `虚拟网卡名称`：默认 `vpn0`，对应的 Linux 内核网卡设备为 `vpn_vpn0`。
  - `连接看门狗`：定时向指定目标发送探测 Ping，网络异常时自动重连。
- **连接账户设置**：
  - `VPN 服务器地址`：填入远程 SoftEther 服务器域名或 IP。
  - `服务器端口`：如 `443`、`992`、`1194`、`5555`。
  - `虚拟 Hub 名称`：远程服务端配置的 Hub 名（如 `DEFAULT`）。
  - `认证方式`：支持标准密码认证与 RADIUS 认证。
  - `并发 TCP 连接数`：**SoftEther 独家加速特性**，推荐配置为 `8` 或 `16` 条并发流，可大幅提升跨运营商和高丢包网络下的吞吐速度。
  - `SSL 数据传输加密` / `数据包压缩`：根据安全与性能需求勾选。

### 3. 路由策略 (Routing)
- **路由分流模式**：
  - **全局 VPN**：所有上网流量均通过 VPN 隧道转发。自动添加防回环路由保护底层连接。
  - **规则分流**：仅将指定的 CIDR 网段（如 `10.0.0.0/8`, `192.168.0.0/16`）走 VPN 隧道，其余国内流量直连。
  - **仅创建接口**：仅启动网卡并获取 IP，不自动配置系统路由表，适合使用 MWAN3 或自定义策略路由的高级用户。
- **NAT 地址伪装**：自动开启 iptables MASQUERADE，让局域网所有设备无需配置即可无感接入 VPN 隧道。

### 4. 日志与诊断 (Log & Tools)
- 实时查看带有 `softether` 标识的系统运行日志。
- **交互式 `vpncmd` 控制台**：直接在浏览器输入指令（例如 `AccountStatusGet default`、`NicList`、`AccountList`）并实时查看底层返回结果。

---

## 🛠️ 编译与打包指南

本项目提供多种便捷的打包方式：

### 方法一：使用本地 Docker 一键打包（推荐）

如果本地安装了 Docker（支持 Linux、macOS 或 Windows WSL2）：

```bash
cd Z:\softther\openwrt

# 编译 X86_64 架构 IPK
bash build.sh x86_64

# 编译 ARM64 架构 IPK（如 NanoPi R2S/R4S, 树莓派4/5, MT798x）
bash build.sh aarch64

# 编译 ARM32 架构 IPK
bash build.sh arm_cortex-a7

# 一键编译全部架构
bash build.sh all
```

打包完成后，生成的 `.ipk` 文件将输出在 `openwrt/bin/` 目录下。

### 方法二：集成到已有 OpenWrt 源码树中

1. 将 `package/softether-client` 与 `package/luci-app-softether-client` 复制到您的 OpenWrt 源码目录下的 `package/` 中：
   ```bash
   cp -r openwrt/package/* /path/to/openwrt/package/
   ```
2. 进入 OpenWrt 源码目录配置菜单：
   ```bash
   make menuconfig
   ```
3. 勾选对应软件包：
   - `Network -> VPN -> <M> softether-client`
   - `LuCI -> 3. Applications -> <M> luci-app-softether-client`
4. 执行编译：
   ```bash
   make package/softether-client/compile V=s
   make package/luci-app-softether-client/compile V=s
   ```

### 方法三：GitHub Actions 云端自动构建

项目已内置 `.github/workflows/build-ipk.yml`。将代码推送到 GitHub 仓库后，GitHub Actions 会自动启动官方 SDK 容器矩阵，全自动编译 `x86_64`、`aarch64`、`arm_cortex-a7` 的安装包，并以 Artifacts 形式供您下载。

---

## 🔍 命令行日常管理与维护

在路由器 SSH 终端中也可以直接使用管理指令：

```bash
# 查看连接状态 JSON
/etc/init.d/softether-client status
# 或使用 helper 查看
/usr/libexec/softether/softether-helper.sh status

# 手动连接 / 断开
/etc/init.d/softether-client connect
/etc/init.d/softether-client disconnect

# 手动重启服务
/etc/init.d/softether-client restart

# 交互式调用 vpncmd 配置客户端
vpncmd localhost /client
```

---

## 📄 开源许可证

- SoftEther VPN 核心源码遵循 GPL-2.0 / Apache-2.0 许可证。
- LuCI 管理套件遵循 Apache-2.0 许可证。
