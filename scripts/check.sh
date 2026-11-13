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

# Swift Testing's macros are compiler plugins in the active toolchain's plugins folder. On the
# command line tools alone, an incremental build sometimes fails with "plugin for module
# 'TestingMacros' not found", so name that folder when it exists, and retry once on that error.
swift_test() {
    plugins="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing"
    set -- swift test
    if [ -d "$plugins" ]; then
        plugins="$(cd "$plugins" && pwd)"
        echo "Using the testing plugins folder $plugins"
        set -- "$@" -Xswiftc -plugin-path -Xswiftc "$plugins"
    fi
    log="$tmp/swift-test.log"
    { "$@" 2>&1; echo $? >"$log.status"; } | tee "$log"
    status="$(cat "$log.status")"
    [ "$status" -eq 0 ] && return 0
    grep -q "plugin for module 'TestingMacros' not found" "$log" || return "$status"
    echo
    echo "swift test could not find the TestingMacros plugin; retrying once."
    "$@"
}

step "swift-format lint" swift format lint --strict --recursive Sources Tests
# Homebrew's own style rules, the ones the tap applies to the formula at each release. A line over
# 118 characters here would make the tap reject the release, so catch it on the pull request.
# Needs Homebrew, which is on the macOS runners and on any Mac that installs Desk Check.
formula_style() {
    command -v brew >/dev/null 2>&1 || { echo "Homebrew is needed for brew style; see https://brew.sh" >&2; return 1; }
    HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 brew style Formula/desk-check.rb
}

step "formula style (brew style)" formula_style
step "swift test" swift_test
step "release policy (scripts/test-next-version.sh)" sh scripts/test-next-version.sh
step "build the app ($version)" scripts/build-app.sh "$version" "$tmp"
step "app permissions (Tests/verify-app.sh)" Tests/verify-app.sh "$app"
step "desk-check command (Tests/verify-wrapper.sh)" Tests/verify-wrapper.sh "$app" "$version"

echo
echo "All checks passed."
