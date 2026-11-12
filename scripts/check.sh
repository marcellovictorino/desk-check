#!/bin/sh
# The one gate for Desk Check: lint, unit tests, release-policy tests, a real app build, and the
# permission and command checks on that build. People run it before a pull request and CI runs
# the same file, so a pass here means a pass there.
#
# Usage: scripts/check.sh      (from any folder; needs macOS with Xcode or its command line tools)
# It leaves nothing behind: the app is built into a temporary folder that is removed on exit.
# It does not run Tests/sandbox-probe.sh, which needs a signed-in Mac and the real home folder.
set -eu
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
trap 'exit 130' INT TERM

version=0.0.0-ci
app="$tmp/DeskCheck.app"

step() { # name, command...
    name="$1"; shift
    echo
    echo "==> $name"
    if ! "$@"; then
        echo "FAILED: $name" >&2
        exit 1
    fi
}

step "swift-format lint" swift format lint --strict --recursive Sources Tests
step "swift test" swift test
step "release policy (scripts/test-next-version.sh)" sh scripts/test-next-version.sh
step "build the app ($version)" scripts/build-app.sh "$version" "$tmp"
step "app permissions (Tests/verify-app.sh)" Tests/verify-app.sh "$app"
step "desk-check command (Tests/verify-wrapper.sh)" Tests/verify-wrapper.sh "$app" "$version"

echo
echo "All checks passed."
