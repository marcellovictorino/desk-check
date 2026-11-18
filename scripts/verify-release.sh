#!/bin/sh
# Checks a published release the way a person would after it: the release on GitHub, then the
# Homebrew tap's formula. The release workflow runs it after publishing, so each release checks itself.
#
# Usage:
#   scripts/verify-release.sh release <version> <commit>   the release is published, latest, at <commit>, with notes
#   scripts/verify-release.sh tap <version>                waits for the tap's formula to point at this
#                                                          version's archive, then compares its checksum
#   scripts/verify-release.sh formula <formula.rb> <version> <archive.tar.gz>
#                                                          the comparison the tap check makes, on local files
#
# Reads GitHub with gh (set GH_TOKEN in CI). REPO and TAP_REPO name the projects;
# TAP_WAIT_SECONDS (default 1200) is how long the tap check waits for the tap's update run.
set -eu
REPO="${REPO:-marcellovictorino/desk-check}"
TAP_REPO="${TAP_REPO:-marcellovictorino/homebrew-tap}"
TAP_WAIT_SECONDS="${TAP_WAIT_SECONDS:-1200}"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok   $*"; }

archive_url() { echo "https://github.com/$REPO/archive/refs/tags/v$1.tar.gz"; }

check_release() { # version commit
    version="$1"; commit="$2"; tag="v$version"
    fields="$(gh api "repos/$REPO/releases/tags/$tag" \
        --jq '[.draft, .prerelease, ((.body // "") | length)] | @tsv')" \
        || fail "no release $tag in $REPO"
    draft="$(echo "$fields" | cut -f1)"; prerelease="$(echo "$fields" | cut -f2)"; notes="$(echo "$fields" | cut -f3)"
    [ "$draft" = false ] || fail "$tag is still a draft"
    [ "$prerelease" = false ] || fail "$tag is marked as a prerelease"
    [ "$notes" -gt 0 ] || fail "$tag has no release notes"
    ok "$tag is published with notes ($notes characters)"

    latest="$(gh api "repos/$REPO/releases/latest" --jq .tag_name)"
    [ "$latest" = "$tag" ] || fail "the latest release is $latest, not $tag"
    ok "$tag is the latest release"

    tagged="$(gh api "repos/$REPO/commits/$tag" --jq .sha)"
    [ "$tagged" = "$commit" ] || fail "$tag points at $tagged, not $commit"
    ok "$tag points at $commit"
}

check_formula() { # formula version archive
    formula="$1"; version="$2"; archive="$3"
    want="$(archive_url "$version")"
    url="$(sed -n 's/^  url "\(.*\)"$/\1/p' "$formula")"
    sha="$(sed -n 's/^  sha256 "\([0-9a-f]*\)"$/\1/p' "$formula")"
    [ "$url" = "$want" ] || fail "the formula downloads '$url', not $want"
    ok "the formula downloads $want"
    actual="$(shasum -a 256 "$archive" | cut -d' ' -f1)"
    [ "$sha" = "$actual" ] || fail "the formula's sha256 is '$sha', but the archive's is $actual"
    ok "the formula's sha256 matches the archive ($actual)"
}

check_tap() { # version
    version="$1"; want="$(archive_url "$version")"
    work="$(mktemp -d)"
    trap 'rm -rf "$work"' EXIT
    formula="$work/desk-check.rb"
    waited=0
    while :; do
        gh api "repos/$TAP_REPO/contents/Formula/desk-check.rb" -H 'Accept: application/vnd.github.raw' >"$formula" \
            || fail "could not read Formula/desk-check.rb from $TAP_REPO"
        grep -q "^  url \"$want\"$" "$formula" && break
        [ "$waited" -lt "$TAP_WAIT_SECONDS" ] \
            || fail "after ${waited}s the tap's formula still downloads $(sed -n 's/^  url "\(.*\)"$/\1/p' "$formula"), not $want"
        echo "The tap's formula does not point at v$version yet; checking again in 30s (${waited}s so far)."
        sleep 30
        waited=$((waited + 30))
    done
    curl -fsSL -o "$work/archive.tar.gz" "$want" || fail "could not download $want"
    check_formula "$formula" "$version" "$work/archive.tar.gz"
}

case "${1:-}" in
    release) [ $# -eq 3 ] || fail "usage: $0 release <version> <commit>"; check_release "$2" "$3" ;;
    tap) [ $# -eq 2 ] || fail "usage: $0 tap <version>"; check_tap "$2" ;;
    formula) [ $# -eq 4 ] || fail "usage: $0 formula <formula.rb> <version> <archive.tar.gz>"; check_formula "$2" "$3" "$4" ;;
    *) fail "usage: $0 release|tap|formula ..." ;;
esac
