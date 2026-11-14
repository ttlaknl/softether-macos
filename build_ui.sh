#!/bin/bash

# Multi-platform Build Script for SoftEther UI Client (arm64 Only - Apple Silicon)
set -euo pipefail

# 自动切换到脚本所在目录，支持从任意终端目录调用
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

APP_NAME="SoftEtherUI"
APP_BUNDLE="${APP_NAME}.app"
APP_EXECUTABLE_DIR="${APP_BUNDLE}/Contents/MacOS"
APP_RESOURCES_DIR="${APP_BUNDLE}/Contents/Resources"

echo "============================================================"
echo " Building SoftEther UI Client App for Apple Silicon (arm64)"
echo " Target OS: macOS (12.0+) & iOS (15.0+ NetworkExtension)"
echo "============================================================"

# 0. Kill existing running instance to release file locks
pkill -f "${APP_NAME}" 2>/dev/null || true

# Safe removal of old bundle
if [ -d "${APP_BUNDLE}" ]; then
    rm -rf "${APP_BUNDLE}" 2>/dev/null || mv "${APP_BUNDLE}" "/tmp/${APP_NAME}_$(date +%s).app" 2>/dev/null || true
fi

# 1. Create App Bundle structure
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
    "SoftEtherUI/iOS/SoftEtherProtocolClient.swift"
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
echo "[3/3] Generating Info.plist..."
cat <<EOF > "${APP_BUNDLE}/Contents/Info.plist"
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
    <string>2.3</string>
    <key>CFBundleVersion</key>
    <string>2.3.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# 5. Code Signing (Required for Apple Silicon arm64 - AMFI enforcement)
echo "[4/4] Signing App Bundle (Ad-Hoc) for Apple Silicon..."
for item in libmayaqua.dylib libcedar.dylib vpnclient vpncmd; do
    if [ -f "${APP_EXECUTABLE_DIR}/${item}" ]; then
        codesign --force --sign - "${APP_EXECUTABLE_DIR}/${item}" 2>/dev/null || true
    fi
done
codesign --force --deep --sign - "${APP_BUNDLE}"
echo "  - ✓ Code signing completed (Ad-Hoc)"

echo "============================================================"
echo " ${APP_BUNDLE} Built successfully for ARM64!"
echo "============================================================"
