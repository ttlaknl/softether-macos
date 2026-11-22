#!/bin/bash

# Multi-platform Build Script for SoftEther UI Client (arm64 Only - Apple Silicon)
set -euo pipefail

APP_NAME="SoftEtherUI"
APP_BUNDLE="${APP_NAME}.app"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${PROJECT_DIR}"
BUILD_TEMP="$(mktemp -d /tmp/softether_build_XXXXXX)"
trap 'rm -rf "${BUILD_TEMP}"' EXIT

STAGING_BUNDLE="${BUILD_TEMP}/${APP_BUNDLE}"
APP_EXECUTABLE_DIR="${STAGING_BUNDLE}/Contents/MacOS"
APP_RESOURCES_DIR="${STAGING_BUNDLE}/Contents/Resources"

echo "============================================================"
echo " Building SoftEther UI Client App for Apple Silicon (arm64)"
echo " Target OS: macOS (12.0+) & iOS (15.0+ NetworkExtension)"
echo "============================================================"

# 0. Kill existing running instance to release file locks
pkill -f "${APP_NAME}" 2>/dev/null || true

# 1. Create App Bundle structure in clean temp directory
mkdir -p "${APP_EXECUTABLE_DIR}"
mkdir -p "${APP_RESOURCES_DIR}"

# 2. Source Files
# NOTE: Do NOT include root-level "SoftEtherUI.swift" — it is a legacy AppKit
# entry point (manual NSApplication.run()) that conflicts with the SwiftUI
# @main entry in SoftEtherUI/App.swift. Including both causes duplicate
# entry-point compilation errors.
SWIFT_SOURCES=(
    "SoftEtherUI/App.swift"
    "SoftEtherUI/Views/MainView.swift"
    "SoftEtherUI/Views/ServerConfigView.swift"
    "SoftEtherUI/Views/LogConsoleView.swift"
    "SoftEtherUI/Views/SettingsView.swift"
    "code/SoftEtherEngine.swift"
)

echo "[1/3] Compiling Swift UI with Apple Silicon (arm64) Target..."
if command -v swiftc &> /dev/null; then
    swiftc -target arm64-apple-macos12.0 \
           "${SWIFT_SOURCES[@]}" \
           -o "${APP_EXECUTABLE_DIR}/${APP_NAME}" \
           -parse-as-library
    
    echo "  - Swift Compilation Successful!"
else
    echo "  - swiftc command not found. Ensure Xcode is installed."
    exit 1
fi

# 3. Copy Core binaries AND dynamic libraries into App Bundle
echo "[2/3] Bundling native arm64 core binaries & dylibs (vpnclient, vpncmd, libcedar, libmayaqua)..."

DYLIB_SRC_DIR="softether_src/build"

if [ -f "vpnclient" ]; then cp -f vpnclient "${APP_EXECUTABLE_DIR}/"; fi
if [ -f "vpncmd" ]; then cp -f vpncmd "${APP_EXECUTABLE_DIR}/"; fi
# hamcore.se2 是资源文件，必须放在 Contents/Resources/ 中，放入 Contents/MacOS 会导致 Xcode codesign 报错
if [ -f "hamcore.se2" ]; then cp -f hamcore.se2 "${APP_RESOURCES_DIR}/"; fi
rm -f "${APP_EXECUTABLE_DIR}/hamcore.se2"

# 嵌入 App 图标
if [ -f "AppIcon.icns" ]; then
    cp -f "AppIcon.icns" "${APP_RESOURCES_DIR}/"
    echo "  - [Bundle] 已嵌入 AppIcon.icns"
fi

# 关键: 拷贝动态库到 App Bundle (缺少它们 vpnclient/vpncmd 会 dyld 崩溃)
for dylib in libcedar.dylib libmayaqua.dylib; do
    if [ -f "${dylib}" ]; then
        cp -f "${dylib}" "${APP_EXECUTABLE_DIR}/"
        echo "  - [Bundle] 已嵌入 ${dylib}"
    elif [ -f "${DYLIB_SRC_DIR}/${dylib}" ]; then
        cp -f "${DYLIB_SRC_DIR}/${dylib}" "${APP_EXECUTABLE_DIR}/"
        echo "  - [Bundle] 已从 build/ 嵌入 ${dylib}"
    else
        echo "  - [Warning] 未找到 ${dylib}，vpnclient 可能无法启动!"
    fi
done

chmod +x "${APP_EXECUTABLE_DIR}/vpnclient" 2>/dev/null || true
chmod +x "${APP_EXECUTABLE_DIR}/vpncmd" 2>/dev/null || true

# 修复 rpath: 将 @rpath 引用改为 @executable_path/ (App Bundle 自包含加载)
echo "  - 修复 App Bundle 内动态库加载路径..."
for bin in vpnclient vpncmd; do
    if [ -f "${APP_EXECUTABLE_DIR}/${bin}" ]; then
        install_name_tool -change @rpath/libcedar.dylib @executable_path/libcedar.dylib "${APP_EXECUTABLE_DIR}/${bin}" 2>/dev/null || true
        install_name_tool -change @rpath/libmayaqua.dylib @executable_path/libmayaqua.dylib "${APP_EXECUTABLE_DIR}/${bin}" 2>/dev/null || true
        echo "    ✓ ${bin} rpath -> @executable_path/"
    fi
done

# 修复 dylib install_name (id) 和交叉依赖
for dylib in libcedar.dylib libmayaqua.dylib; do
    if [ -f "${APP_EXECUTABLE_DIR}/${dylib}" ]; then
        install_name_tool -id "@executable_path/${dylib}" "${APP_EXECUTABLE_DIR}/${dylib}" 2>/dev/null || true
        install_name_tool -change @rpath/libmayaqua.dylib @executable_path/libmayaqua.dylib "${APP_EXECUTABLE_DIR}/${dylib}" 2>/dev/null || true
        install_name_tool -change @rpath/libcedar.dylib @executable_path/libcedar.dylib "${APP_EXECUTABLE_DIR}/${dylib}" 2>/dev/null || true
    fi
done

# 4. Generate Info.plist
echo "[3/4] Generating Info.plist with AppIcon configuration..."
cat <<EOF > "${STAGING_BUNDLE}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.softether.ui</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# 5. Code Signing in clean temp directory
echo "[4/4] Signing App Bundle (Ad-Hoc) for Apple Silicon..."
# 规范化权限 (目录 755, 可执行/动态库 755, 资源/plist 644)，确保所有用户均有读取和执行权限
find "${STAGING_BUNDLE}" -type d -exec chmod 755 {} +
find "${STAGING_BUNDLE}" -type f -exec chmod 644 {} +
chmod 755 "${APP_EXECUTABLE_DIR}/${APP_NAME}"
for item in libmayaqua.dylib libcedar.dylib vpnclient vpncmd; do
    if [ -f "${APP_EXECUTABLE_DIR}/${item}" ]; then
        chmod 755 "${APP_EXECUTABLE_DIR}/${item}"
    fi
done

xattr -cr "${STAGING_BUNDLE}"
for item in libmayaqua.dylib libcedar.dylib vpnclient vpncmd "${APP_NAME}"; do
    if [ -f "${APP_EXECUTABLE_DIR}/${item}" ]; then
        codesign --force --sign - "${APP_EXECUTABLE_DIR}/${item}" 2>/dev/null || true
    fi
done
codesign --force --deep --sign - "${STAGING_BUNDLE}"
echo "  - ✓ Code signing completed (Ad-Hoc)"

# 6. 安全部署到项目根目录
echo "  - 部署到项目目录..."
rm -rf "${PROJECT_DIR}/${APP_BUNDLE}"
cp -R "${STAGING_BUNDLE}" "${PROJECT_DIR}/"

echo "============================================================"
echo " ${APP_BUNDLE} Built successfully with new AppIcon!"
echo " Location: ${PROJECT_DIR}/${APP_BUNDLE}"
echo "============================================================"
