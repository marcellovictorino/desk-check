#!/bin/sh
# Replays commit subjects from this repository's real history through scripts/next-version.sh.
# Why: a wrong bump publishes a wrong release to Homebrew users, so each rule of the release policy is pinned.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
fail=0

# check <name> <current> <expected> <message>...  (messages are joined with the 0x1e separator)
check() {
  name="$1"; current="$2"; expected="$3"; shift 3
  actual="$(for m in "$@"; do printf '%s\036' "$m"; done | "$here/next-version.sh" "$current")"
  if [ "$actual" = "$expected" ]; then echo "ok   $name"; else echo "FAIL $name: expected '$expected', got '$actual'"; fail=1; fi
}

# Real subjects since v0.3.0 (the fix that PR #5 delivers, and its test commit)
check "fix and test since 0.3.0 is a patch" 0.3.0 0.3.1 \
  "fix(settings): remember a user-selected settings file" \
  "test(views): save labelled offscreen pictures"
# Real subjects between v0.2.0 and v0.3.0
check "feat among fixes is a minor" 0.2.0 0.3.0 \
  "chore(release): prepare Desk Check 0.3.0" \
  "feat(ui): Liquid Glass polish, Esc in Live returns to the main view, build records the real SDK" \
  "fix(sandbox-probe): match Foundation file errors" \
  "test(migration): distinguish copied settings"
check "test and chore only do not release" 0.3.0 "" \
  "test(views): save labelled offscreen pictures" \
  "chore(release): prepare Desk Check 0.3.0" \
  "docs: add the README with install, privacy, upgrade behaviour and credits"
check "no commits do not release" 0.3.0 ""
check "bang after type is a major" 0.3.0 1.0.0 \
  "fix: x" "feat(ui)!: drop the old settings file"
check "BREAKING CHANGE footer is a major" 0.3.0 1.0.0 \
  "$(printf 'refactor: change config layout\n\nBREAKING CHANGE: config moves')"
check "a squash merge subject with a PR number counts" 1.2.3 1.2.4 \
  "fix(settings): remember a user-selected settings file (#5)"
check "a fix body that mentions feat: does not raise the bump" 0.3.0 0.3.1 \
  "$(printf 'fix: x\n\nfeat: not a subject')"

# The whole script on this repository's real tags
if git -C "$here" rev-parse -q --verify refs/tags/v0.3.0 >/dev/null; then
  actual="$(cd "$here" && git log --format='%B%x1e' v0.3.0..2dfe437 2>/dev/null | "$here/next-version.sh" 0.3.0 || true)"
  if [ "$actual" = "0.3.1" ]; then echo "ok   real history v0.3.0..2dfe437"; else echo "FAIL real history: got '$actual'"; fail=1; fi
fi
exit "$fail"
