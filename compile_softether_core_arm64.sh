#!/bin/bash

# compile_softether_core_arm64.sh
# 支持本地/Win 提前下载源码离线编译，亦支持浅克隆
set -e

echo "============================================================"
echo " Building SoftEther VPN Core C-Source for Apple Silicon ARM64"
echo "============================================================"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${PROJECT_DIR}/softether_src"
BUILD_DIR="${SRC_DIR}/build"

# 1. 检查 CMake
if ! command -v cmake &> /dev/null; then
    echo "[Error] 未检测到 cmake 命令。请在 Mac 上执行 'brew install cmake'。"
    exit 1
fi

# 2. 检查本地源码完整性 (支持 Win 侧提前下载)
echo "[1/3] 检查源码完整性..."

if [ -f "${SRC_DIR}/src/libhamcore/CMakeLists.txt" ]; then
    echo "  - [识别] 本地/Win侧已提供完整 SoftEther 源码目录！跳过网络下载，直接进行离线编译。"
else
    echo "  - [未找到离线源码] 尝试浅克隆极速拉取源码与全部子模块..."

    # Fix #14: Save original global git config values before temporarily modifying them
    _OLD_POSTBUF=$(git config --global --get http.postBuffer 2>/dev/null || echo "")
    _OLD_LOWSPEED_LIMIT=$(git config --global --get http.lowSpeedLimit 2>/dev/null || echo "")
    _OLD_LOWSPEED_TIME=$(git config --global --get http.lowSpeedTime 2>/dev/null || echo "")

    git config --global http.postBuffer 524288000 2>/dev/null || true
    git config --global http.lowSpeedLimit 0 2>/dev/null || true
    git config --global http.lowSpeedTime 999999 2>/dev/null || true

    rm -rf "${SRC_DIR}"
    if ! git clone --depth 1 --recursive --shallow-submodules https://ghproxy.net/https://github.com/SoftEtherVPN/SoftEtherVPN.git "${SRC_DIR}"; then
        echo "  - 镜像拉取超时，尝试直连浅克隆..."
        git clone --depth 1 --recursive --shallow-submodules https://github.com/SoftEtherVPN/SoftEtherVPN.git "${SRC_DIR}"
    fi

    # Fix #14: Restore original global git config values
    if [ -n "$_OLD_POSTBUF" ]; then git config --global http.postBuffer "$_OLD_POSTBUF" 2>/dev/null; else git config --global --unset http.postBuffer 2>/dev/null || true; fi
    if [ -n "$_OLD_LOWSPEED_LIMIT" ]; then git config --global http.lowSpeedLimit "$_OLD_LOWSPEED_LIMIT" 2>/dev/null; else git config --global --unset http.lowSpeedLimit 2>/dev/null || true; fi
    if [ -n "$_OLD_LOWSPEED_TIME" ]; then git config --global http.lowSpeedTime "$_OLD_LOWSPEED_TIME" 2>/dev/null; else git config --global --unset http.lowSpeedTime 2>/dev/null || true; fi
fi

# 2.1 自动应用 macOS utun 核心网络与防丢包补丁
if [ -f "${PROJECT_DIR}/patches/macos_utun.patch" ]; then
    if ! grep -q "UTUN_GARP_INTERVAL" "${SRC_DIR}/src/Cedar/VLanUnix.h" 2>/dev/null; then
        echo "  - [补丁] 正在应用 macOS utun 核心网络驱动优化补丁..."
        git -C "${SRC_DIR}" apply --ignore-whitespace "${PROJECT_DIR}/patches/macos_utun.patch" 2>/dev/null || true
    else
        echo "  - [补丁] 源码已包含 macOS utun 优化，无需重复应用。"
    fi
fi

# 3. 配置 CMake 针对 Apple Silicon arm64 构建
echo "[2/3] 配置 CMake 针对 macOS arm64 进行构建..."
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

cmake .. \
    -DCMAKE_OSX_ARCHITECTURES="arm64" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="-arch arm64 -O3"

# 4. 多核并行编译
echo "[3/3] 开始编译 arm64 核心二进制..."
NCPU=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
make -j${NCPU}

echo "============================================================"
echo " [Success] arm64 核心编译成功！"
echo " 正在更新本地可执行文件..."
echo "============================================================"

cd "${PROJECT_DIR}"

# 拷贝二进制
if [ -f "${BUILD_DIR}/vpnclient" ]; then
    cp "${BUILD_DIR}/vpnclient" "${PROJECT_DIR}/vpnclient"
    echo "  - 已更新 vpnclient (arm64)"
fi

if [ -f "${BUILD_DIR}/vpncmd" ]; then
    cp "${BUILD_DIR}/vpncmd" "${PROJECT_DIR}/vpncmd"
    echo "  - 已更新 vpncmd (arm64)"
fi

# 拷贝动态库 (关键! 缺少这些 dylib 会导致 vpnclient/vpncmd 无法启动)
for dylib in libcedar.dylib libmayaqua.dylib; do
    if [ -f "${BUILD_DIR}/${dylib}" ]; then
        cp "${BUILD_DIR}/${dylib}" "${PROJECT_DIR}/${dylib}"
        echo "  - 已更新 ${dylib} (arm64)"
    fi
done

# 修复 rpath: 将 @rpath 引用改为 @executable_path/ 以便就地加载
echo "  - 修复动态库加载路径 (install_name_tool)..."
for bin in vpnclient vpncmd; do
    if [ -f "${PROJECT_DIR}/${bin}" ]; then
        install_name_tool -change @rpath/libcedar.dylib @executable_path/libcedar.dylib "${PROJECT_DIR}/${bin}" 2>/dev/null || true
        install_name_tool -change @rpath/libmayaqua.dylib @executable_path/libmayaqua.dylib "${PROJECT_DIR}/${bin}" 2>/dev/null || true
        echo "    ✓ ${bin} rpath 已修复"
    fi
done

# 修复 dylib 的 install_name (id) 确保自引用一致
for dylib in libcedar.dylib libmayaqua.dylib; do
    if [ -f "${PROJECT_DIR}/${dylib}" ]; then
        install_name_tool -id "@executable_path/${dylib}" "${PROJECT_DIR}/${dylib}" 2>/dev/null || true
        # libcedar 依赖 libmayaqua，也需要修复交叉引用
        install_name_tool -change @rpath/libmayaqua.dylib @executable_path/libmayaqua.dylib "${PROJECT_DIR}/${dylib}" 2>/dev/null || true
        install_name_tool -change @rpath/libcedar.dylib @executable_path/libcedar.dylib "${PROJECT_DIR}/${dylib}" 2>/dev/null || true
    fi
done

echo "------------------------------------------------------------"
echo "验证架构 (Architectural Verification):"
file "${PROJECT_DIR}/vpnclient" 2>/dev/null || true
echo "动态库依赖:"
otool -L "${PROJECT_DIR}/vpnclient" 2>/dev/null || true
echo "============================================================"
