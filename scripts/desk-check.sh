#!/bin/sh
# The `desk-check` command. Homebrew's formula installs it with @APP@ replaced by the installed DeskCheck.app.
#
#   desk-check            quits a Desk Check left running by an older install, then opens this one
#   desk-check --version  prints this install's version and opens nothing
set -eu
app="@APP@"

if [ "${1:-}" = "--version" ]; then
  exec /usr/bin/plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist"
fi

# After `brew upgrade` the old build keeps running from its removed folder, and `open` would start the new
# one beside it. Quit only this user's processes named exactly DeskCheck that run a DeskCheck.app other than this one.
current="$(cd "$app" && pwd -P)/Contents/MacOS/DeskCheck"
for pid in $(pgrep -x -U "$(id -u)" DeskCheck || true); do
  path="$(ps -o comm= -p "$pid" || true)"
  case "$path" in "$current" | "") continue ;; */DeskCheck.app/Contents/MacOS/DeskCheck) ;; *) continue ;; esac
  kill "$pid" 2>/dev/null || true
  # Wait up to five seconds, so the new copy does not start while the old one still holds the menu bar.
  i=0
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  if kill -0 "$pid" 2>/dev/null; then
    echo "desk-check: the Desk Check at $path (process $pid) did not quit, so a second copy was not opened. Quit it and run desk-check again." >&2
    exit 1
  fi
done
exec open "$app"
