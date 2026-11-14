#!/bin/bash
# build_xcframework.sh
# 此脚本用于将 SoftEther C 核心跨平台编译为 .xcframework 供 NetworkExtension 使用。

set -e

PROJECT_ROOT=$(pwd)
SRC_DIR="$PROJECT_ROOT/softether_src"
BUILD_DIR="$PROJECT_ROOT/build_apple"
OUTPUT_DIR="$PROJECT_ROOT/XCFrameworks"

mkdir -p "$BUILD_DIR"
mkdir -p "$OUTPUT_DIR"

echo "=== 准备编译 iOS 平台 (ARM64) ==="
mkdir -p "$BUILD_DIR/ios"
cd "$BUILD_DIR/ios"
cmake "$SRC_DIR" \
    -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_ARCHITECTURES="arm64" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF
cmake --build . --config Release --target cedar
cmake --build . --config Release --target mayaqua
cd "$PROJECT_ROOT"

echo "=== 准备编译 macOS 平台 (Universal: ARM64 + x86_64) ==="
mkdir -p "$BUILD_DIR/macos"
cd "$BUILD_DIR/macos"
cmake "$SRC_DIR" \
    -G Xcode \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF
cmake --build . --config Release --target cedar
cmake --build . --config Release --target mayaqua
cd "$PROJECT_ROOT"

echo "=== 生成 libcedar.xcframework ==="
rm -rf "$OUTPUT_DIR/libcedar.xcframework"
xcodebuild -create-xcframework \
    -library "$BUILD_DIR/ios/Release-iphoneos/libcedar.a" \
    -library "$BUILD_DIR/macos/Release/libcedar.a" \
    -output "$OUTPUT_DIR/libcedar.xcframework"

echo "=== 生成 libmayaqua.xcframework ==="
rm -rf "$OUTPUT_DIR/libmayaqua.xcframework"
xcodebuild -create-xcframework \
    -library "$BUILD_DIR/ios/Release-iphoneos/libmayaqua.a" \
    -library "$BUILD_DIR/macos/Release/libmayaqua.a" \
    -output "$OUTPUT_DIR/libmayaqua.xcframework"

echo "=== XCFrameworks 生成完成 ==="
ls -l "$OUTPUT_DIR"
