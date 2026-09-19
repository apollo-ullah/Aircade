#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="$PWD/build/Aircade.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Aircade "$APP/Contents/MacOS/Aircade"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Aircade</string>
<key>CFBundleIdentifier</key><string>com.aircade.motionlab</string>
<key>CFBundleName</key><string>Aircade</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSCameraUsageDescription</key><string>Aircade tracks your controller hand locally to move the saber sideways and vertically. Camera frames are not saved or uploaded.</string>
<key>NSMotionUsageDescription</key><string>Aircade uses AirPods motion to control your saber and test handheld tracking. Motion logs stay on this Mac.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
printf 'Built %s\n' "$APP"
