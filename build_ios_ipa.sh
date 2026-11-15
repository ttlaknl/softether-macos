#!/bin/bash
# build_ios_ipa.sh
# 一键编译并打包 iOS (iPhone / iPad ARM64) IPA 安装包
# 生成两个版本:
#   1. SoftEtherUI-iOS.ipa      (完整 NetworkExtension 版，包含 PacketTunnel.appex，需带 VPN 权限的 .p12 证书自签)
#   2. SoftEtherUI-iOS-Lite.ipa (免权限单包版，不含扩展插件，任何普通个人 .p12 证书均可 100% 签名安装)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

APP_NAME="SoftEtherUI"
BUNDLE_ID="org.softether.SoftEtherUI"
EXT_NAME="PacketTunnel"
EXT_BUNDLE_ID="${BUNDLE_ID}.PacketTunnel"

BUILD_ROOT="/tmp/softether_ios_build"
PAYLOAD_FULL="${BUILD_ROOT}/full/Payload"
APP_FULL="${PAYLOAD_FULL}/${APP_NAME}.app"
EXT_FULL="${APP_FULL}/PlugIns/${EXT_NAME}.appex"

PAYLOAD_LITE="${BUILD_ROOT}/lite/Payload"
APP_LITE="${PAYLOAD_LITE}/${APP_NAME}.app"

echo "============================================================"
echo " Building SoftEther VPN for iOS (iPhone 18 / iOS 15.0+ ARM64)"
echo "============================================================"

if ! command -v xcrun &> /dev/null; then
    echo "[Error] 未检测到 xcrun (Xcode)。请在 macOS 上运行此脚本，或通过 GitHub Actions 自动构建。"
    exit 1
fi

IOS_SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
echo "[1/5] 检测到 iOS SDK: ${IOS_SDK_PATH}"

rm -rf "${BUILD_ROOT}"
mkdir -p "${EXT_FULL}"
mkdir -p "${APP_LITE}"

# 1. 编译主程序 (SoftEtherUI)
echo "[2/5] 编译 iOS 主程序 (${APP_NAME} arm64)..."
xcrun -sdk iphoneos swiftc \
    -target arm64-apple-ios15.0 \
    -sdk "${IOS_SDK_PATH}" \
    -O \
    -parse-as-library \
    "SoftEtherUI/App.swift" \
    "SoftEtherUI/Views/MainView.swift" \
    "SoftEtherUI/Views/ServerConfigView.swift" \
    "SoftEtherUI/Views/LogConsoleView.swift" \
    "SoftEtherUI/Views/SettingsView.swift" \
    "SoftEtherUI/iOS/SoftEtherProtocolClient.swift" \
    "code/SoftEtherEngine.swift" \
    -o "${APP_FULL}/${APP_NAME}"

cp -f "${APP_FULL}/${APP_NAME}" "${APP_LITE}/${APP_NAME}"

# 2. 编译 NetworkExtension 插件 (PacketTunnel.appex)
echo "[3/5] 编译 iOS NetworkExtension 插件 (${EXT_NAME}.appex arm64)..."
xcrun -sdk iphoneos swiftc \
    -target arm64-apple-ios15.0 \
    -sdk "${IOS_SDK_PATH}" \
    -O \
    -application-extension \
    "SoftEtherUI/iOS/SoftEtherProtocolClient.swift" \
    "SoftEtherUI/iOS/PacketTunnelProvider.swift" \
    -Xlinker -e -Xlinker _NSExtensionMain \
    -o "${EXT_FULL}/${EXT_NAME}"

# 3. 生成 Info.plist 与 Entitlements
echo "[4/5] 生成 Info.plist 与权限描述..."

cat <<EOF > "${APP_FULL}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>SoftEther VPN</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.3</string>
    <key>CFBundleVersion</key>
    <string>2.3.0</string>
    <key>LSRequiresIPhoneOS</key>
    <true/>
    <key>MinimumOSVersion</key>
    <string>15.0</string>
    <key>UIDeviceFamily</key>
    <array>
        <integer>1</integer>
        <integer>2</integer>
    </array>
    <key>UILaunchScreen</key>
    <dict/>
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
    <key>UISupportedInterfaceOrientations~ipad</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationPortraitUpsideDown</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
</dict>
</plist>
EOF

cp -f "${APP_FULL}/Info.plist" "${APP_LITE}/Info.plist"
printf "APPL????" > "${APP_FULL}/PkgInfo"
printf "APPL????" > "${APP_LITE}/PkgInfo"

# 3.5 编译 iOS AppIcon 图标资源 (Assets.car + AppIcon*.png + CFBundleIcons)
if [ -d "${SCRIPT_DIR}/SoftEtherUI/iOS/Assets.xcassets" ]; then
    echo "    正在编译 iOS AppIcon 图标资源..."
    xcrun actool "${SCRIPT_DIR}/SoftEtherUI/iOS/Assets.xcassets" \
        --compile "${APP_FULL}" \
        --platform iphoneos \
        --minimum-deployment-target 15.0 \
        --app-icon AppIcon \
        --output-partial-info-plist "${BUILD_ROOT}/assetcatalog_info.plist"
    if [ -f "${BUILD_ROOT}/assetcatalog_info.plist" ]; then
        /usr/libexec/PlistBuddy -c "Merge ${BUILD_ROOT}/assetcatalog_info.plist" "${APP_FULL}/Info.plist"
    fi
    cp -f "${APP_FULL}/Info.plist" "${APP_LITE}/Info.plist"
    cp -f "${APP_FULL}/Assets.car" "${APP_LITE}/Assets.car" 2>/dev/null || true
    cp -f "${APP_FULL}"/AppIcon*.png "${APP_LITE}/" 2>/dev/null || true
fi

cat <<EOF > "${EXT_FULL}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>${EXT_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${EXT_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${EXT_BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${EXT_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>XPC!</string>
    <key>CFBundleShortVersionString</key>
    <string>2.3</string>
    <key>CFBundleVersion</key>
    <string>2.3.0</string>
    <key>MinimumOSVersion</key>
    <string>15.0</string>
    <key>UIDeviceFamily</key>
    <array>
        <integer>1</integer>
        <integer>2</integer>
    </array>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.networkextension.packet-tunnel</string>
        <key>NSExtensionPrincipalClass</key>
        <string>PacketTunnelProvider</string>
    </dict>
</dict>
</plist>
EOF

cat <<EOF > "${BUILD_ROOT}/entitlements_ne.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.networking.networkextension</key>
    <array>
        <string>packet-tunnel-provider</string>
    </array>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.${BUNDLE_ID}</string>
    </array>
</dict>
</plist>
EOF

# Ad-hoc 预签名（在本地 /tmp APFS 分区执行，避免 NAS/SMB 扩展属性导致 codesign 报错）
xattr -cr "${PAYLOAD_FULL}" "${PAYLOAD_LITE}" 2>/dev/null || true
codesign --force --sign - --entitlements "${BUILD_ROOT}/entitlements_ne.plist" "${EXT_FULL}"
codesign --force --sign - --entitlements "${BUILD_ROOT}/entitlements_ne.plist" "${APP_FULL}"
codesign --force --sign - "${APP_LITE}"

# 4. 打包生成两个 IPA 文件并拷回项目目录
echo "[5/5] 正在压缩生成 IPA 安装包..."
rm -f "${SCRIPT_DIR}/SoftEtherUI-iOS.ipa" "${SCRIPT_DIR}/SoftEtherUI-iOS-Lite.ipa"

(cd "${BUILD_ROOT}/full" && zip -qry "${BUILD_ROOT}/SoftEtherUI-iOS.ipa" Payload)
(cd "${BUILD_ROOT}/lite" && zip -qry "${BUILD_ROOT}/SoftEtherUI-iOS-Lite.ipa" Payload)

cp -f "${BUILD_ROOT}/SoftEtherUI-iOS.ipa" "${SCRIPT_DIR}/SoftEtherUI-iOS.ipa"
cp -f "${BUILD_ROOT}/SoftEtherUI-iOS-Lite.ipa" "${SCRIPT_DIR}/SoftEtherUI-iOS-Lite.ipa"

echo "============================================================"
echo " [SUCCESS] iOS IPA 打包完成！输出路径:"
echo "  1. ${SCRIPT_DIR}/SoftEtherUI-iOS.ipa      (完整 NetworkExtension 版)"
echo "  2. ${SCRIPT_DIR}/SoftEtherUI-iOS-Lite.ipa (免 VPN 权限单包版，兼容所有普通 .p12 证书)"
ls -lh "${SCRIPT_DIR}"/SoftEtherUI-iOS*.ipa
echo "============================================================"
