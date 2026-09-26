#!/bin/bash
# Prepare a release: set the version everywhere, roll the changelog, commit
# and create an annotated tag. Nothing is pushed.
#
# Usage: scripts/bump-version.sh X.Y.Z
#
# Updates:
#   VERSION                     X.Y.Z
#   Info.plist                  CFBundleShortVersionString = X.Y.Z,
#                               CFBundleVersion = commit count of the release commit
#   cli/package.json (+ lock)   version X.Y.Z (npm version --no-git-tag-version)
#   CHANGELOG.md                "## [Unreleased]" content moves under
#                               "## [X.Y.Z] - YYYY-MM-DD", compare links updated
# Then commits "Release vX.Y.Z" and tags vX.Y.Z (annotated).
set -euo pipefail

usage() {
    echo "usage: $0 X.Y.Z" >&2
    exit 2
}

[ "$#" -eq 1 ] || usage
NEW_VERSION="${1#v}"
if ! [[ "$NEW_VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "error: '$1' is not a semantic version of the form X.Y.Z" >&2
    usage
fi
TAG="v$NEW_VERSION"

cd "$(git rev-parse --show-toplevel)"

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "error: working tree has uncommitted changes; commit or stash them first" >&2
    exit 1
fi
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    echo "error: tag $TAG already exists" >&2
    exit 1
fi
if ! grep -q '^## \[Unreleased\]' CHANGELOG.md; then
    echo "error: CHANGELOG.md has no '## [Unreleased]' heading" >&2
    exit 1
fi
if grep -q "^## \[$NEW_VERSION\]" CHANGELOG.md; then
    echo "error: CHANGELOG.md already has a section for $NEW_VERSION" >&2
    exit 1
fi
unreleased_body="$(awk '
    /^## \[Unreleased\]/ { in_block = 1; next }
    in_block && /^## \[/ { exit }
    in_block && /^\[[^]]+\]: / { exit }
    in_block { print }
' CHANGELOG.md | tr -d '[:space:]')"
if [ -z "$unreleased_body" ]; then
    echo "error: the Unreleased section of CHANGELOG.md is empty" >&2
    exit 1
fi

RELEASE_DATE="$(date +%Y-%m-%d)"
# The release commit created below is HEAD + 1, which is also what
# `git rev-list --count HEAD` returns when build.sh runs on the tag.
BUILD_NUMBER="$(( $(git rev-list --count HEAD) + 1 ))"

echo "Bumping to $NEW_VERSION (build $BUILD_NUMBER, $RELEASE_DATE)"

printf '%s\n' "$NEW_VERSION" > VERSION

# Edit the two values in place rather than with PlistBuddy Set, which
# re-serialises the whole file (sorted keys, tabs) and produces a noisy diff.
# PlistBuddy then reads the values back to prove the edit landed.
NEW_VERSION="$NEW_VERSION" BUILD_NUMBER="$BUILD_NUMBER" perl -0777 -i -pe '
    s{(<key>CFBundleShortVersionString</key>\s*<string>)[^<]*(</string>)}{$1$ENV{NEW_VERSION}$2}
        or die "Info.plist: CFBundleShortVersionString not found\n";
    s{(<key>CFBundleVersion</key>\s*<string>)[^<]*(</string>)}{$1$ENV{BUILD_NUMBER}$2}
        or die "Info.plist: CFBundleVersion not found\n";
' Info.plist
plutil -lint Info.plist >/dev/null
if [ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)" != "$NEW_VERSION" ] ||
    [ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Info.plist)" != "$BUILD_NUMBER" ]; then
    echo "error: failed to update Info.plist" >&2
    exit 1
fi

(cd cli && npm version "$NEW_VERSION" --no-git-tag-version --allow-same-version >/dev/null)

NEW_VERSION="$NEW_VERSION" RELEASE_DATE="$RELEASE_DATE" perl -0777 -i -pe '
    my ($v, $d) = ($ENV{NEW_VERSION}, $ENV{RELEASE_DATE});
    s/^## \[Unreleased\][ \t]*\n/## [Unreleased]\n\n## [$v] - $d\n/m
        or die "CHANGELOG.md: no Unreleased heading\n";
    s{^\[Unreleased\]:[ \t]*(\S+)/compare/(\S+?)\.\.\.HEAD[ \t]*$}{[Unreleased]: $1/compare/v$v...HEAD\n[$v]: $1/compare/$2...v$v}m
        or die "CHANGELOG.md: no [Unreleased] compare link\n";
' CHANGELOG.md

scripts/check-versions.sh "$TAG"

git add VERSION Info.plist CHANGELOG.md cli/package.json
if [ -f cli/package-lock.json ]; then
    git add cli/package-lock.json
fi
git commit -m "Release $TAG"
git tag -a "$TAG" -m "Prune $TAG"

echo ""
echo "Created commit and tag $TAG. Review with:"
echo "  git show --stat HEAD"
echo "Then publish with:"
echo "  git push origin HEAD && git push origin $TAG"
