#!/bin/bash
# build_pkg.sh
# 生成 SoftEtherUI 标准 macOS PKG 安装包
set -euo pipefail

APP_NAME="SoftEtherUI"
VERSION="1.0.0"
PKG_NAME="SoftEtherUI-v${VERSION}.pkg"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(mktemp -d /tmp/softether_pkg_XXXXXX)"

# Ensure cleanup on exit (normal or error)
trap 'rm -rf "${PKG_ROOT}"' EXIT

cd "${PROJECT_DIR}"

echo "============================================================"
echo " Building ${PKG_NAME} (macOS Installer Package)"
echo "============================================================"

if [ ! -d "${APP_NAME}.app" ]; then
    echo "[Error] 未找到 ${APP_NAME}.app，请先执行 build_ui.sh。"
    exit 1
fi

# 规范化权限与清理属性 (755/644)，确保所有用户均有读取和执行权限
find "${APP_NAME}.app" -type d -exec chmod 755 {} +
find "${APP_NAME}.app" -type f -exec chmod 644 {} +
chmod 755 "${APP_NAME}.app/Contents/MacOS"/* 2>/dev/null || true

# 清理扩展属性以防打包进 AppleDouble 临时文件
dot_clean -m "${APP_NAME}.app" 2>/dev/null || true
xattr -cr "${APP_NAME}.app" 2>/dev/null || true

# 创建 postinstall 脚本，确保安装到 /Applications 后权限全局可读可执行 (防止普通用户运行时 dyld errno=13)
mkdir -p "${PKG_ROOT}/scripts"
cat > "${PKG_ROOT}/scripts/postinstall" <<'SCRIPTEOF'
#!/bin/bash
set -e
chmod -R u=rwX,go=rX "/Applications/SoftEtherUI.app" 2>/dev/null || true
chmod 755 "/Applications/SoftEtherUI.app/Contents/MacOS"/* 2>/dev/null || true
exit 0
SCRIPTEOF
chmod 755 "${PKG_ROOT}/scripts/postinstall"

echo "[1/3] pkgbuild 生成 component package (目标: /Applications)..."

# 使用标准的 --component 模式，严格将目标指定为 /Applications，杜绝系统宗卷 (System Volume) 冲突
pkgbuild \
    --component "${APP_NAME}.app" \
    --install-location "/Applications" \
    --scripts "${PKG_ROOT}/scripts" \
    --identifier "com.softether.ui" \
    --version "${VERSION}" \
    "${PKG_ROOT}/SoftEtherUI_component.pkg"

echo "[2/3] productbuild 添加 distribution XML..."

# 3. distribution XML
cat > "${PKG_ROOT}/distribution.dist" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
    <title>SoftEtherUI VPN Client</title>
    <organization>com.softether</organization>
    <options customize="never" require-scripts="false" hostArchitectures="arm64"/>
    <domains enable_anywhere="true" enable_currentUserHome="false" enable_localSystem="true"/>
    <choices-outline>
        <line choice="default">
            <line choice="com.softether.ui"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="com.softether.ui" visible="false">
        <pkg-ref id="com.softether.ui"/>
    </choice>
    <pkg-ref id="com.softether.ui" version="${VERSION}" onConclusion="none">SoftEtherUI_component.pkg</pkg-ref>
    <installation-check script="install_check();"/>
    <script>
    function install_check() {
        if (system.compareVersions(system.version.ProductVersion, '12.0') &lt; 0) {
            my.result.title = 'macOS 12.0+ Required';
            my.result.message = 'Please upgrade macOS to 12.0 or later before installing SoftEtherUI.';
            my.result.type = 'Fatal';
            return false;
        }
        return true;
    }
    </script>
    <welcome file="welcome.html"/>
    <conclusion file="conclusion.html"/>
</installer-gui-script>
EOF

# 欢迎页
cat > "${PKG_ROOT}/welcome.html" <<'HTML'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<style>
body { font-family: -apple-system, "PingFang SC", sans-serif; padding: 24px; line-height: 1.6; color: #1d1d1f; }
h2 { color: #007aff; margin-top: 0; }
code { background: #f5f5f7; padding: 2px 6px; border-radius: 4px; font-size: 0.9em; }
</style>
</head>
<body>
<h2>欢迎使用 SoftEtherUI VPN Client</h2>
<p>SoftEtherUI 是 SoftEther VPN 的 macOS 原生客户端，支持：</p>
<ul>
    <li><b>UDP Acceleration</b> 加速协议 (默认启用)</li>
    <li><b>8 通道 TCP 并发</b> 突破拥塞窗口</li>
    <li><b>DNS 智能分流</b>：SecureNAT 主 DNS + 223.5.5.5 国内直连</li>
    <li><b>Apple Silicon arm64</b> 原生编译</li>
    <li><b>SoftEther v5.02 核心</b> 内嵌</li>
</ul>
<p>安装后将自动创建 <code>/Applications/SoftEtherUI.app</code>。</p>
</body>
</html>
HTML

# 完成页
cat > "${PKG_ROOT}/conclusion.html" <<'HTML'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<style>
body { font-family: -apple-system, "PingFang SC", sans-serif; padding: 24px; line-height: 1.6; color: #1d1d1f; }
h2 { color: #34c759; margin-top: 0; }
code { background: #f5f5f7; padding: 2px 6px; border-radius: 4px; }
</style>
</head>
<body>
<h2>安装完成！</h2>
<p>SoftEtherUI 已成功安装到 <code>/Applications</code>。</p>
<p><b>下一步：</b></p>
<ol>
    <li>从启动台或 <code>/Applications</code> 打开 SoftEtherUI</li>
    <li>首次运行会请求管理员权限启动 vpnclient 守护进程</li>
    <li>在"服务器配置"中填入 VPN 服务器信息后点击连接</li>
</ol>
<p>提示：请确保系统已安装 <code>libsodium</code>（<code>brew install libsodium</code>）。</p>
</body>
</html>
HTML

# 合成最终安装包
# productbuild: --distribution 不能与 --package 同用
# 使用 --distribution 作为主输入，--package-path 指定 component pkg 位置
productbuild \
    --distribution "${PKG_ROOT}/distribution.dist" \
    --package-path "${PKG_ROOT}" \
    --resources "${PKG_ROOT}" \
    "${PKG_NAME}"

echo "[3/3] 完成！"

echo "============================================================"
echo " [Success] PKG 安装包生成完成！"
echo " 文件: ${PROJECT_DIR}/${PKG_NAME}"
echo "============================================================"
echo ""
echo "安装方式: 双击 ${PKG_NAME} 或执行 sudo installer -pkg ${PKG_NAME} -target /"
