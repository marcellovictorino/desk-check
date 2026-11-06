#!/bin/sh
# Builds a small probe, signs it with Desk Check's own entitlements file and runs it, so the
# sandbox rules are tested by the kernel rather than read from a file.
#
# Usage: Tests/sandbox-probe.sh [entitlements file]   (default: Resources/DeskCheck.entitlements)
#
# The probe creates ~/.config/desk-check/ if it is missing, as the app does, and macOS keeps a
# container folder for it at ~/Library/Containers/io.github.marcellovictorino.desk-check.sandbox-probe.
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
entitlements="${1:-$root/Resources/DeskCheck.entitlements}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
id=io.github.marcellovictorino.desk-check.sandbox-probe

# A sandboxed command line program needs a bundle identifier in an embedded Info.plist,
# or macOS stops it at launch.
cat > "$work/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>$id</string></dict></plist>
PLIST
swiftc -O -o "$work/SandboxProbe" \
  "$root/Tests/SandboxProbe/main.swift" "$root"/Sources/DeskCheckCore/*.swift \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$work/Info.plist"
codesign --force --sign - --identifier "$id" --entitlements "$entitlements" "$work/SandboxProbe" 2>/dev/null

# Port 9 on this Mac has no listener: without a sandbox the connection is refused by the
# network stack (ECONNREFUSED); with it, macOS refuses it first (EPERM). Nothing leaves the Mac.
"$work/SandboxProbe" 9
