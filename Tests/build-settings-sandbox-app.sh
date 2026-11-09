#!/bin/sh
# Intent: test the actual Settings controls and bookmarks with a disposable sandbox identity.
# Usage: sh Tests/build-settings-sandbox-app.sh <new-output-folder>
# This creates only a new test app; it never signs or replaces an installed app.
set -eu
out="${1:?new output folder}"
if [ -e "$out" ]; then echo "Choose a new output folder" >&2; exit 1; fi
mkdir -p "$out"
root="$(cd "$(dirname "$0")/.." && pwd)"
id="io.deskcheck.settings-test-$(uuidgen | tr '[:upper:]' '[:lower:]')"
app="$out/SettingsSandbox.app"
mkdir -p "$app/Contents/MacOS" "$out/modules"
xcrun swiftc -parse-as-library -emit-library -static -emit-module -module-name DeskCheckCore \
  -emit-module-path "$out/modules/DeskCheckCore.swiftmodule" \
  "$root"/Sources/DeskCheckCore/*.swift -o "$out/modules/libDeskCheckCore.a"
set --
for source in "$root"/Sources/DeskCheck/*.swift; do
  case "$source" in */DeskCheckApp.swift) ;; *) set -- "$@" "$source" ;; esac
done
xcrun swiftc -parse-as-library -I "$out/modules" -L "$out/modules" -lDeskCheckCore \
  "$@" "$root/Tests/SettingsSandboxApp.swift" -o "$app/Contents/MacOS/SettingsSandbox"
cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$id</string>
<key>CFBundleExecutable</key><string>SettingsSandbox</string>
<key>CFBundleName</key><string>Settings sandbox test</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSCameraUsageDescription</key><string>Camera checks are not used by this isolated settings test.</string>
</dict></plist>
EOF
codesign --sign - --entitlements "$root/Resources/DeskCheck.entitlements" "$app"
codesign --verify --strict "$app"
printf 'Test app: %s\nDisposable identity: %s\n' "$app" "$id"
