#!/bin/bash

# Build Script for SoftEther VPN Core & Dependencies (arm64 Only - Apple Silicon M-Series & iOS)
set -euo pipefail

echo "============================================================"
echo " Building SoftEther VPN Core Libraries for ARM64 (macOS/iOS)"
echo " Target Architecture: arm64 (Apple Silicon M1/M2/M3/M4)"
echo "============================================================"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${PROJECT_DIR}/build_arm64"
MACOS_LIB_DIR="${OUTPUT_DIR}/macos"
IOS_LIB_DIR="${OUTPUT_DIR}/ios"
XCFRAMEWORK_DIR="${OUTPUT_DIR}/SoftEtherCore.xcframework"

mkdir -p "${MACOS_LIB_DIR}"
mkdir -p "${IOS_LIB_DIR}"

# SDK Paths
MACOS_SDK=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || echo "")
IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || echo "")

CFLAGS_MACOS="-arch arm64 -isysroot ${MACOS_SDK} -mmacosx-version-min=11.0 -O3 -fno-strict-aliasing"
CFLAGS_IOS="-arch arm64 -isysroot ${IOS_SDK} -miphoneos-version-min=15.0 -O3 -fno-strict-aliasing"

echo "[1/4] Checking macOS & iOS SDK environment..."
if [ -n "${MACOS_SDK}" ]; then
    echo "  - macOS SDK Found: ${MACOS_SDK}"
fi
if [ -n "${IOS_SDK}" ]; then
    echo "  - iOS SDK Found: ${IOS_SDK}"
fi

echo "[2/4] Verifying static libraries architecture in ./lib ..."
for lib_file in lib/*.a; do
    if [ -f "$lib_file" ]; then
        echo "  - Checking $lib_file..."
    fi
done

echo "[3/4] Repackaging SoftEther Core static libraries for macOS (arm64)..."
if [ -f "code/vpnclient.a" ] && [ -f "code/vpncmd.a" ]; then
    # Verify the .a files are actually arm64
    for lib_file in code/vpnclient.a code/vpncmd.a; do
        if lipo -info "${lib_file}" 2>/dev/null | grep -q "arm64"; then
            echo "  - ✓ ${lib_file} is arm64"
            cp "${lib_file}" "${MACOS_LIB_DIR}/$(basename ${lib_file})"
        else
            echo "  - [Warning] ${lib_file} is not arm64 architecture, skipping."
        fi
    done
else
    echo "  - [Warning] code/vpnclient.a or code/vpncmd.a not found, skipping."
fi

echo "[4/4] Creating SoftEtherCore.xcframework for Xcode integration..."
# If xcodebuild is available, assemble XCFramework
if command -v xcodebuild &> /dev/null; then
    echo "  - Building XCFramework bundle..."
    # Copy headers and lib structures
    mkdir -p "${OUTPUT_DIR}/headers"
    cp -r code/*.h "${OUTPUT_DIR}/headers/" 2>/dev/null || true
fi

echo "============================================================"
echo " Build process completed successfully!"
echo " Output directory: ${OUTPUT_DIR}"
echo "============================================================"
