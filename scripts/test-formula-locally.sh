#!/bin/sh
# Installs (or upgrades) Desk Check from the committed code through a local test tap,
# exactly as `brew install marcellovictorino/tap/desk-check` would, without publishing anything.
#
# Usage: scripts/test-formula-locally.sh <version>     e.g. 0.1.0, then 0.1.1 to test an upgrade
# Clean up afterwards with: brew uninstall desk-check-local/test/desk-check && brew untap desk-check-local/test
set -eu
version="${1:?version}"
root="$(cd "$(dirname "$0")/.." && pwd)"
tap=desk-check-local/test
work="${TMPDIR:-/tmp}/desk-check-formula-test"
mkdir -p "$work"

tarball="$work/desk-check-$version.tar.gz"
git -C "$root" archive --format=tar.gz --prefix="desk-check-$version/" -o "$tarball" HEAD
sha="$(shasum -a 256 "$tarball" | cut -d' ' -f1)"

brew tap-info --installed 2>/dev/null | grep -q "^$tap:" || brew tap-new --no-git "$tap" >/dev/null
formula="$(brew --repository "$tap")/Formula/desk-check.rb"
sed -e "s|^  url .*|  url \"file://$tarball\"\\
  sha256 \"$sha\"|" -e '/^  sha256 /d' -e '/^  head /d' "$root/Formula/desk-check.rb" > "$formula"

if brew list --formula "$tap/desk-check" >/dev/null 2>&1; then
  brew upgrade --verbose "$tap/desk-check"
else
  brew install --verbose "$tap/desk-check"
fi
brew test "$tap/desk-check"
