#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/dist/MouseVoiceBridge.app"
mkdir -p "$APP/Contents/MacOS" "$PWD/.module-cache"
xcrun swiftc -module-cache-path "$PWD/.module-cache" -O -framework Cocoa -framework ApplicationServices main.swift -o "$APP/Contents/MacOS/MouseVoiceBridge"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MouseVoiceBridge</string>
<key>CFBundleIdentifier</key><string>local.ocean.mousevoicebridge</string>
<key>CFBundleName</key><string>MouseVoiceBridge</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>LSUIElement</key><false/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
printf 'Built: %s\n' "$APP"
