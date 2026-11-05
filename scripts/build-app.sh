#!/bin/sh
# Builds DeskUndo.app with Apple's command line tools (Xcode is not needed) and signs it
# ad hoc for this Mac, with the sandbox entitlements in Resources/DeskUndo.entitlements.
#
# Usage: scripts/build-app.sh <version> <output-dir>
# Homebrew's formula runs this same script during `brew install`.
set -eu

version="${1:?version}"
out="${2:?output dir}"
root="$(cd "$(dirname "$0")/.." && pwd)"

# /usr/bin/xcrun, not a wrapper on PATH: Homebrew's wrapper drops DEVELOPER_DIR when asked for a path.
echo "toolchain: $(/usr/bin/xcrun --find swift)"
# --disable-sandbox: SwiftPM's own build sandbox cannot nest inside Homebrew's.
swift build --package-path "$root" -c release --arch arm64 --disable-sandbox
bin="$(swift build --package-path "$root" -c release --arch arm64 --show-bin-path)"

app="$out/DeskUndo.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin/DeskUndo" "$app/Contents/MacOS/DeskUndo"
sed "s/@VERSION@/$version/g" "$root/Resources/Info.plist" > "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist"

codesign --force --sign - --entitlements "$root/Resources/DeskUndo.entitlements" "$app"
codesign --verify --strict "$app"
echo "built $app"
