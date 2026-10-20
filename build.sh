#!/bin/bash
# Build Lidnight Limits.app (Apple Silicon, macOS 13+). With a Developer ID certificate and a notarytool
# keychain profile (NOTARY_PROFILE, default lidnight-notary) it also signs, notarizes and staples, then zips to dist/.
set -euo pipefail
cd "$(dirname "$0")"
V=$(cat VERSION)
APP="build/Lidnight Limits.app"
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" dist
swiftc -O -target arm64-apple-macos13 Sources/main.swift -o "$APP/Contents/MacOS/LidnightLimits"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Lidnight Limits</string>
<key>CFBundleDisplayName</key><string>Lidnight Limits</string>
<key>CFBundleIdentifier</key><string>app.lidnight.limits</string>
<key>CFBundleExecutable</key><string>LidnightLimits</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$V</string>
<key>CFBundleVersion</key><string>$V</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict></plist>
PL
SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -n 1)}"
ZIP="dist/LidnightLimits-$V.zip"
if [ -n "$SIGN_ID" ]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
  P="${NOTARY_PROFILE:-lidnight-notary}"
  if xcrun notarytool history --keychain-profile "$P" >/dev/null 2>&1; then
    ditto -c -k --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$P" --wait
    xcrun stapler staple "$APP"
  fi
else
  codesign --force --sign - "$APP"
fi
rm -f "$ZIP" && ditto -c -k --keepParent "$APP" "$ZIP"
spctl -a -vv "$APP" 2>&1 | tail -2 || true
shasum -a 256 "$ZIP"
