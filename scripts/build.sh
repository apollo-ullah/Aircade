#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="$PWD/build/Aircade.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Music"
cp .build/release/Aircade "$APP/Contents/MacOS/Aircade"
cp "audio-library/music/Local Forecast.mp3" "$APP/Contents/Resources/Music/Local Forecast.mp3"
cp audio-library/CREDITS.md "$APP/Contents/Resources/AudioCredits.md"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Aircade</string>
<key>CFBundleIdentifier</key><string>com.aircade.motionlab</string>
<key>CFBundleName</key><string>Aircade</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.5.0</string>
<key>CFBundleVersion</key><string>5</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
<key>NSHighResolutionCapable</key><true/>
<key>NSCameraUsageDescription</key><string>Aircade scans badge QR codes for player sign-in and tracks your controller hand locally. Camera frames are not saved or uploaded.</string>
<key>NSMotionUsageDescription</key><string>Aircade uses AirPods motion to control your saber and test handheld tracking. Motion logs stay on this Mac.</string>
<key>NSLocalNetworkUsageDescription</key><string>Aircade connects to your iPhone on the local network so it can control solo games or either player in a duel.</string>
<key>NSBonjourServices</key><array><string>_aircade._tcp</string></array>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
printf 'Built %s\n' "$APP"
