#!/bin/bash

# build_deps_arm64.sh
# 专门为 Apple Silicon (M系列 CPU / arm64) 重新编译 OpenSSL 及 SoftEther 依赖库
set -e

echo "============================================================"
echo " SoftEther VPN Dependency Builder for Apple Silicon (arm64)"
echo "============================================================"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${PROJECT_DIR}/lib"
BUILD_DIR="${PROJECT_DIR}/build_deps_tmp"

mkdir -p "${LIB_DIR}"
mkdir -p "${BUILD_DIR}"

# 1. 检查 Apple Silicon arm64 编译环境
ARCH=$(uname -m)
echo "[Status] Current build host architecture: ${ARCH}"

# 优先尝试检测 Homebrew 安装的 Apple Silicon OpenSSL / ncurses / editline 静态库
BREW_PREFIX=$(brew --prefix 2>/dev/null || echo "/opt/homebrew")

if [ -d "${BREW_PREFIX}/opt/openssl@3/lib" ]; then
    echo "[Found] Detected Homebrew arm64 OpenSSL@3 at ${BREW_PREFIX}/opt/openssl@3"
    cp "${BREW_PREFIX}/opt/openssl@3/lib/libssl.a" "${LIB_DIR}/" 2>/dev/null || true
    cp "${BREW_PREFIX}/opt/openssl@3/lib/libcrypto.a" "${LIB_DIR}/" 2>/dev/null || true
fi

# 2. 从源码重新编译 OpenSSL 为 arm64 (如果本地未检测到 arm64 版本的 libcrypto.a)
IS_ARM64_CRYPTO=false
if [ -f "${LIB_DIR}/libcrypto.a" ]; then
    if lipo -info "${LIB_DIR}/libcrypto.a" 2>/dev/null | grep -q "arm64"; then
        IS_ARM64_CRYPTO=true
        echo "[Verified] ${LIB_DIR}/libcrypto.a is ARM64."
    fi
fi

if [ "$IS_ARM64_CRYPTO" = false ]; then
    echo "[Build] Downloading & Compiling OpenSSL for darwin64-arm64-cc..."
    cd "${BUILD_DIR}"
    OPENSSL_VER="3.1.4"
    if [ ! -f "openssl-${OPENSSL_VER}.tar.gz" ]; then
        curl -LO "https://www.openssl.org/source/openssl-${OPENSSL_VER}.tar.gz"
    fi
    tar -zxf "openssl-${OPENSSL_VER}.tar.gz"
    cd "openssl-${OPENSSL_VER}"
    
    ./Configure darwin64-arm64-cc no-shared no-async --prefix="${BUILD_DIR}/openssl_out"
    make -j$(sysctl -n hw.ncpu)
    make install_sw
    
    cp "${BUILD_DIR}/openssl_out/lib/libssl.a" "${LIB_DIR}/"
    cp "${BUILD_DIR}/openssl_out/lib/libcrypto.a" "${LIB_DIR}/"
    echo "[Success] Built arm64 OpenSSL successfully!"
fi

echo "============================================================"
echo " ARM64 dependencies ready in ${LIB_DIR}"
echo "============================================================"
