#!/bin/bash

APP_NAME="SoftEtherUI"
APP_BUNDLE="${APP_NAME}.app"
APP_EXECUTABLE_DIR="${APP_BUNDLE}/Contents/MacOS"

# Create App Bundle structure
mkdir -p "${APP_EXECUTABLE_DIR}"

# Compile Swift code
swiftc SoftEtherUI.swift -o "${APP_EXECUTABLE_DIR}/${APP_NAME}"

if [ $? -ne 0 ]; then
    echo "Failed to compile Swift UI."
    exit 1
fi

# Copy core files into the app bundle
echo "Copying core components into the app bundle..."
cp vpnclient "${APP_EXECUTABLE_DIR}/"
cp vpncmd "${APP_EXECUTABLE_DIR}/"
cp hamcore.se2 "${APP_EXECUTABLE_DIR}/"

# Create Info.plist
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
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.13</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "Built ${APP_BUNDLE} successfully!"
