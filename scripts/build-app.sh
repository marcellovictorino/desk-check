#!/bin/sh
# Builds DeskCheck.app with Apple's command line tools (Xcode is not needed) and signs it
# ad hoc for this Mac, with the sandbox entitlements in Resources/DeskCheck.entitlements.
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
# The platform_version flags make the binary record the SDK it was built with. SwiftPM's default build system
# writes sdk 14.0 whatever SDK is installed, and macOS 26 then draws the old grey buttons instead of Liquid Glass.
sdk="$(/usr/bin/xcrun --sdk macosx --show-sdk-version)"
set -- -c release --arch arm64 -Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$sdk"
swift build --package-path "$root" "$@" --disable-sandbox
bin="$(swift build --package-path "$root" "$@" --show-bin-path)"

app="$out/DeskCheck.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin/DeskCheck" "$app/Contents/MacOS/DeskCheck"
sed "s/@VERSION@/$version/g" "$root/Resources/Info.plist" > "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist"

codesign --force --sign - --entitlements "$root/Resources/DeskCheck.entitlements" "$app"
codesign --verify --strict "$app"
echo "built $app"
