#!/bin/sh
# Reads Desk Check's permissions back from a built DeskCheck.app and fails when the
# privacy promises in the README do not hold: menu bar only, camera on request,
# App Sandbox with no network access, read/write ~/.config/desk-check/, and read-only ~/.config/desk-undo/.
#
# Usage: Tests/verify-app.sh <path to DeskCheck.app>
set -eu
app="${1:?path to DeskCheck.app}"
plist="$app/Contents/Info.plist"
ents="$(mktemp)"
trap 'rm -f "$ents"' EXIT
codesign -d --entitlements - --xml "$app" > "$ents" 2>/dev/null

# plutil reads dots as a path, so entitlement keys have their dots escaped.
ent() { plutil -extract "$(printf '%s' "$1" | sed 's/\./\\./g')$2" raw "$ents" 2>/dev/null; }
info() { plutil -extract "$1" raw "$plist"; }
is() { [ "$1" = "$2" ]; }

fail=0
check() { # description, command...
  desc="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "ok   $desc"; else echo "FAIL $desc"; fail=1; fi
}

exception=com.apple.security.temporary-exception.files.home-relative-path.read-write
legacy=com.apple.security.temporary-exception.files.home-relative-path.read-only
expected_keys="com.apple.security.app-sandbox com.apple.security.device.camera com.apple.security.files.bookmarks.app-scope com.apple.security.files.user-selected.read-write $legacy $exception"
actual_keys="$(plutil -convert json -o - "$ents" | /usr/bin/python3 -I -c 'import json,sys; print(" ".join(sorted(json.load(sys.stdin))))')"

check "signature is valid" codesign --verify --strict "$app"
check "signed ad hoc, no developer account" sh -c "codesign -dv \"\$1\" 2>&1 | grep -q 'Signature=adhoc'" _ "$app"
check "no Dock icon (LSUIElement)" is "$(info LSUIElement || true)" true
check "camera usage text present" info NSCameraUsageDescription
check "App Sandbox on" is "$(ent com.apple.security.app-sandbox '' || true)" true
check "camera entitlement on" is "$(ent com.apple.security.device.camera '' || true)" true
check "no network client entitlement" is "$(ent com.apple.security.network.client '' || echo absent)" absent
check "no network server entitlement" is "$(ent com.apple.security.network.server '' || echo absent)" absent
check "one folder exception, /.config/desk-check/" is "$(ent $exception '' || true)|$(ent $exception .0 || true)" "1|/.config/desk-check/"
check "read-only access to the old folder, /.config/desk-undo/" is "$(ent $legacy '' || true)|$(ent $legacy .0 || true)" "1|/.config/desk-undo/"
# Intent: choosing a settings file grants only user-selected access, remembered with an app-scoped bookmark.
check "user-selected file read/write access" is "$(ent com.apple.security.files.user-selected.read-write '' || true)" true
check "app-scoped bookmarks" is "$(ent com.apple.security.files.bookmarks.app-scope '' || true)" true
check "no other entitlements" is "$actual_keys" "$expected_keys"

exit $fail
