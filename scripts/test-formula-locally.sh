#!/bin/sh
# Installs (or upgrades) Desk Undo from the committed code through a local test tap,
# exactly as `brew install marcellovictorino/tap/desk-undo` would, without publishing anything.
#
# Usage: scripts/test-formula-locally.sh <version>     e.g. 0.1.0, then 0.1.1 to test an upgrade
# Clean up afterwards with: brew uninstall desk-undo-local/test/desk-undo && brew untap desk-undo-local/test
set -eu
version="${1:?version}"
root="$(cd "$(dirname "$0")/.." && pwd)"
tap=desk-undo-local/test
work="${TMPDIR:-/tmp}/desk-undo-formula-test"
mkdir -p "$work"

tarball="$work/desk-undo-$version.tar.gz"
git -C "$root" archive --format=tar.gz --prefix="desk-undo-$version/" -o "$tarball" HEAD
sha="$(shasum -a 256 "$tarball" | cut -d' ' -f1)"

brew tap-info --installed 2>/dev/null | grep -q "^$tap:" || brew tap-new --no-git "$tap" >/dev/null
formula="$(brew --repository "$tap")/Formula/desk-undo.rb"
sed -e "s|^  url .*|  url \"file://$tarball\"\\
  sha256 \"$sha\"|" -e '/^  head /d' "$root/Formula/desk-undo.rb" > "$formula"

if brew list --formula "$tap/desk-undo" >/dev/null 2>&1; then
  brew upgrade --verbose "$tap/desk-undo"
else
  brew install --verbose "$tap/desk-undo"
fi
brew test "$tap/desk-undo"
