#!/bin/sh
# Checks the desk-check command (scripts/desk-check.sh) against built apps, installed the way the formula does.
# Intent: `desk-check --version` prints the version the app was built as, and `desk-check` after an upgrade
# quits the copy still running from the older install instead of leaving both in the menu bar.
#
# Usage: Tests/verify-wrapper.sh <DeskCheck.app> <version it was built as> [<older DeskCheck.app>]
# With an older app this launches both apps and quits every other DeskCheck.app you are running, the
# installed one included; start it again afterwards with `desk-check`.
set -eu
app="$(cd "${1:?path to DeskCheck.app}" && pwd -P)"
version="${2:?version the app was built as}"
old="${3:-}"
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
cmd="$tmp/desk-check"
sed "s|@APP@|$app|g" "$root/scripts/desk-check.sh" > "$cmd"
chmod +x "$cmd"

fail=0
check() { # description, command...
  desc="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "ok   $desc"; else echo "FAIL $desc"; fail=1; fi
}
running() { ps -axo comm= | grep -cxF "$1/Contents/MacOS/DeskCheck" || true; }

before="$(running "$app")"
check "--version prints $version" [ "$("$cmd" --version)" = "$version" ]
check "--version opens nothing" [ "$(running "$app")" = "$before" ]

if [ -n "$old" ]; then
  old="$(cd "$old" && pwd -P)"
  # An older copy that ignores SIGTERM stands in for one that will not quit: desk-check must not open a second copy.
  # A copy of sleep inside a DeskCheck.app path runs with the exact name and path of an old Desk Check.
  stubborn="$tmp/stubborn/DeskCheck.app/Contents/MacOS/DeskCheck"
  mkdir -p "$(dirname "$stubborn")"
  cp /bin/sleep "$stubborn"
  codesign --force --sign - "$stubborn" 2>/dev/null # a moved system binary is killed unless signed again
  sh -c 'trap "" TERM; exec "$1" 600' _ "$stubborn" &
  stubborn_pid=$!
  i=0; while [ "$(running "$tmp/stubborn/DeskCheck.app")" = 0 ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  check "desk-check fails when an older copy will not quit" sh -c '! "$1" 2>/dev/null' _ "$cmd"
  check "desk-check did not open a second copy" [ "$(running "$app")" = 0 ]
  check "the copy that would not quit is still running" [ "$(running "$tmp/stubborn/DeskCheck.app")" = 1 ]
  kill -9 "$stubborn_pid" 2>/dev/null || true; wait "$stubborn_pid" 2>/dev/null || true
  open "$old"
  i=0; while [ "$(running "$old")" = 0 ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  check "older copy started" [ "$(running "$old")" = 1 ]
  "$cmd"
  i=0; while [ "$(running "$app")" = 0 ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  check "desk-check quit the older copy" [ "$(running "$old")" = 0 ]
  check "desk-check opened this copy" [ "$(running "$app")" = 1 ]
  "$cmd"
  sleep 1
  check "running desk-check again keeps this copy" [ "$(running "$app")" = 1 ]
  pid="$(ps -axo pid=,comm= | grep -F "$app/Contents/MacOS/DeskCheck" | awk '{print $1}')"
  [ -z "$pid" ] || kill $pid
fi

exit $fail
