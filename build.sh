#!/usr/bin/env bash
# OpenWrt SoftEther VPN Client & LuCI Package Builder
# Supports cross-compiling for X86_64, ARM64 (aarch64), and ARM32 (cortex-a7)
# Using official OpenWrt SDK containers or local SDK.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${SCRIPT_DIR}/bin"
PACKAGE_DIR="${SCRIPT_DIR}/package"

VERSION="23.05.3"
TARGET_ARCH="${1:-all}"

echo "============================================================"
echo " SoftEther OpenWrt Client & LuCI IPK Builder"
echo " Target Architecture: ${TARGET_ARCH}"
echo "============================================================"

build_arch() {
    local arch="$1"
    local docker_image="$2"
    local output_dir="${BIN_DIR}/${arch}"

    echo ""
    echo ">>> Building for architecture: ${arch} [${docker_image}] ..."
    mkdir -p "${output_dir}"

    if command -v docker >/dev/null 2>&1; then
        echo "Using Docker container: ${docker_image}"
        docker run --rm \
            -v "${PACKAGE_DIR}:/builder/package/custom:ro" \
            -v "${output_dir}:/builder/bin/packages:rw" \
            "${docker_image}" \
            bash -c "
                set -e
                echo 'Updating feeds...'
                ./scripts/feeds update -a >/dev/null 2>&1 || true
                ./scripts/feeds install -a >/dev/null 2>&1 || true

                echo 'Configuring SoftEther packages...'
                make defconfig >/dev/null 2>&1
                echo 'CONFIG_PACKAGE_softether-client=m' >> .config
                echo 'CONFIG_PACKAGE_luci-app-softether-client=m' >> .config
                make defconfig >/dev/null 2>&1

                echo 'Compiling softether-client...'
                make package/custom/softether-client/compile V=s -j\$(nproc)

                echo 'Compiling luci-app-softether-client...'
                make package/custom/luci-app-softether-client/compile V=s

                echo 'Collecting IPK artifacts...'
                find bin/ -name '*softether*.ipk' -exec cp {} /builder/bin/packages/ \;
                echo 'Done for ${arch}!'
            "
    else
        echo "Docker is not installed or not running."
        echo "If you have a local OpenWrt SDK, run:"
        echo "  cp -r ${PACKAGE_DIR}/* /path/to/sdk/package/"
        echo "  make package/softether-client/compile V=s"
        echo "  make package/luci-app-softether-client/compile V=s"
        return 1
    fi
}

mkdir -p "${BIN_DIR}"

case "${TARGET_ARCH}" in
    x86_64|amd64)
        build_arch "x86_64" "openwrt/sdk:x86-64-v${VERSION}"
        ;;
    arm64|aarch64)
        build_arch "aarch64" "openwrt/sdk:armsr-armv8-v${VERSION}"
        ;;
    arm|armv7|cortex-a7)
        build_arch "arm_cortex-a7" "openwrt/sdk:armsr-armv7-v${VERSION}"
        ;;
    all)
        echo "Building all architectures..."
        build_arch "x86_64" "openwrt/sdk:x86-64-v${VERSION}"
        build_arch "aarch64" "openwrt/sdk:armsr-armv8-v${VERSION}"
        build_arch "arm_cortex-a7" "openwrt/sdk:armsr-armv7-v${VERSION}"
        ;;
    *)
        echo "Unknown architecture: ${TARGET_ARCH}"
        echo "Supported options: x86_64, aarch64, arm_cortex-a7, all"
        exit 1
        ;;
esac

echo ""
echo "============================================================"
echo " Build Completed!"
echo " IPK packages generated in: ${BIN_DIR}"
echo "============================================================"
ls -lh "${BIN_DIR}"/*/*.ipk 2>/dev/null || true
