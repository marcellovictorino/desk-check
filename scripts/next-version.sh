#!/bin/sh
# Prints the next Desk Check version, or nothing when no commit calls for a release.
#
# Usage: scripts/next-version.sh                  commits since the latest v* tag in this repository
#        scripts/next-version.sh <current-version>  commit messages from stdin, each ended by an ASCII 0x1e byte
#
# Conventional commits decide the bump: a "!" after the type or a BREAKING CHANGE footer is major,
# feat is minor, fix is patch. Anything else (chore, docs, test, refactor, perf) does not release.
set -eu

if [ "$#" -eq 0 ]; then
  tag="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"
  [ -n "$tag" ] || { echo "next-version: no v* tag to count from" >&2; exit 1; }
  git log --format='%B%x1e' "$tag..HEAD" | "$0" "${tag#v}"
  exit 0
fi

current="$1"
IFS=. read -r major minor patch <<EOF2
$current
EOF2

level="$(awk 'BEGIN { RS = "\036"; level = 0 }
{
  sub(/^[\n ]+/, "")
  n = split($0, lines, "\n")
  subject = lines[1]
  if (subject ~ /^[A-Za-z]+(\([^)]*\))?!:/) level = 3
  for (i = 2; i <= n; i++) if (lines[i] ~ /^BREAKING[ -]CHANGE:/) level = 3
  if (subject ~ /^feat(\([^)]*\))?:/ && level < 2) level = 2
  if (subject ~ /^fix(\([^)]*\))?:/ && level < 1) level = 1
}
END { print level }')"

case "$level" in
  3) echo "$((major + 1)).0.0" ;;
  2) echo "$major.$((minor + 1)).0" ;;
  1) echo "$major.$minor.$((patch + 1))" ;;
esac
