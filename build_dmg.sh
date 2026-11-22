#!/bin/bash
# build_dmg.sh
# 生成 SoftEtherUI 标准 macOS DMG 安装包 (拖拽式)
set -euo pipefail

APP_NAME="SoftEtherUI"
APP_BUNDLE="${APP_NAME}.app"
VERSION="1.0.0"
DMG_NAME="SoftEtherUI-v${VERSION}.dmg"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGING_DIR="$(mktemp -d /tmp/softether_dmg_XXXXXX)"
DMG_STAGING="$(mktemp -d /tmp/softether_dmg_staging_XXXXXX)"
MOUNT_DIR=""

# Ensure cleanup on exit: remove temp dirs and detach any mounted DMG volume
cleanup() {
    if [ -n "${MOUNT_DIR}" ] && [ -d "${MOUNT_DIR}" ]; then
        hdiutil detach "${MOUNT_DIR}" -force 2>/dev/null || true
    fi
    rm -rf "${STAGING_DIR}" "${DMG_STAGING}"
}
trap cleanup EXIT

echo "============================================================"
echo " Building ${DMG_NAME} (macOS DMG Installer)"
echo "============================================================"

# 0. 预检
if [ ! -d "${PROJECT_DIR}/${APP_BUNDLE}" ]; then
    echo "[Error] 未找到 ${APP_BUNDLE}，请先执行 build_ui.sh 编译 App。"
    exit 1
fi

if ! command -v hdiutil &> /dev/null; then
    echo "[Error] 未检测到 hdiutil。"
    exit 1
fi

echo "[1/5] 准备 DMG 暂存目录..."

# 1. 创建拖拽式 DMG 布局
# 标准布局：左侧 App + 右侧 Applications 文件夹快捷方式
mkdir -p "${DMG_STAGING}"
cp -R "${PROJECT_DIR}/${APP_BUNDLE}" "${DMG_STAGING}/"
# 规范化权限 (目录 755, 可执行/动态库 755, 资源 644)
find "${DMG_STAGING}/${APP_BUNDLE}" -type d -exec chmod 755 {} +
find "${DMG_STAGING}/${APP_BUNDLE}" -type f -exec chmod 644 {} +
chmod 755 "${DMG_STAGING}/${APP_BUNDLE}/Contents/MacOS"/* 2>/dev/null || true
ln -s /Applications "${DMG_STAGING}/Applications"

# 嵌入 DMG 卷标图标
if [ -f "${PROJECT_DIR}/AppIcon.icns" ]; then
    cp -f "${PROJECT_DIR}/AppIcon.icns" "${DMG_STAGING}/.VolumeIcon.icns"
fi

# 2. 创建自定义体积 (留出空间给图标布局)
SIZE=$(du -sk "${DMG_STAGING}" | awk '{print $1}')
SIZE=$((SIZE + 20480))  # +20MB 余量

echo "[2/5] 创建空 DMG 镜像 (${SIZE}KB)..."
hdiutil create -srcfolder "${DMG_STAGING}" -volname "SoftEtherUI" \
    -fs HFS+ -size ${SIZE}k -format UDRW -o "${STAGING_DIR}/temp.dmg" \
    >/dev/null 2>&1

# 3. 挂载并设置图标布局
echo "[3/5] 设置 DMG 图标布局..."
# 动态获取真实挂载点，避免同名宗卷冲突导致路径错误
ATTACH_OUTPUT=$(hdiutil attach "${STAGING_DIR}/temp.dmg" -readwrite -noverify -noautoopen 2>&1)
MOUNT_DIR=$(echo "${ATTACH_OUTPUT}" | grep -o '/Volumes/.*' | head -1)
if [ -z "${MOUNT_DIR}" ]; then
    echo "[Error] 无法获取 DMG 挂载点"
    exit 1
fi
echo "  - 挂载至: ${MOUNT_DIR}"
VOLUME_NAME=$(basename "${MOUNT_DIR}")
SetFile -a C "${MOUNT_DIR}" 2>/dev/null || true

# AppleScript 设置窗口大小和图标位置
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "${VOLUME_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 720, 440}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set position of item "${APP_BUNDLE}" of container window to {120, 120}
        set position of item "Applications" of container window to {400, 120}
        close
        open
    end tell
end tell
APPLESCRIPT

# 等待 Finder 完成布局
sleep 2

# 卸载 (转换前必须卸载)
hdiutil detach "${MOUNT_DIR}" -force >/dev/null 2>&1 || true
MOUNT_DIR=""  # 清空以防 trap 重复卸载

# 4. 转换为压缩只读 DMG (-ov 覆盖旧文件)
echo "[4/5] 压缩并转换为只读 DMG..."
hdiutil convert "${STAGING_DIR}/temp.dmg" -format UDZO -imagekey zlib-level=9 -ov \
    -o "${PROJECT_DIR}/${DMG_NAME}"

# 5. 清理由 trap EXIT 自动完成
echo "[5/5] 清理临时文件..."

echo "============================================================"
echo " [Success] DMG 安装包生成完成！"
echo " 文件: ${PROJECT_DIR}/${DMG_NAME}"
echo "============================================================"
echo ""
echo "安装方式: 双击 ${DMG_NAME} -> 拖拽 SoftEtherUI 到 Applications 文件夹"
