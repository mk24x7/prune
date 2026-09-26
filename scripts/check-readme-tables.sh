#!/bin/bash
# Verify that the artifact tables in README.md (between the markers
# <!-- artifact-tables:start --> and <!-- artifact-tables:end -->) match the
# output of `node cli/scripts/readme-tables.js`.
#
# Until the README carries the markers (or the generator exists) this prints
# a GitHub Actions warning and exits 0 instead of failing.
set -euo pipefail

cd "$(dirname "$0")/.."

START='<!-- artifact-tables:start -->'
END='<!-- artifact-tables:end -->'
GENERATOR='cli/scripts/readme-tables.js'

warn() {
    if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
        echo "::warning file=README.md::$1"
    else
        echo "warning: $1" >&2
    fi
}

if ! grep -qF "$START" README.md || ! grep -qF "$END" README.md; then
    warn "README.md has no artifact-tables markers; table sync check skipped"
    exit 0
fi
if [ ! -f "$GENERATOR" ]; then
    warn "$GENERATOR does not exist; table sync check skipped"
    exit 0
fi

# Strip leading and trailing blank lines so surrounding spacing is not significant.
trim() {
    awk 'NF { found = 1 } found' | awk '{ lines[NR] = $0 } END {
        last = NR
        while (last > 0 && lines[last] ~ /^[[:space:]]*$/) last--
        for (i = 1; i <= last; i++) print lines[i]
    }'
}

expected="$(node "$GENERATOR" | trim)"
actual="$(awk -v start="$START" -v end="$END" '
    index($0, end) { inside = 0 }
    inside { print }
    index($0, start) { inside = 1 }
' README.md | trim)"

if [ "$expected" != "$actual" ]; then
    echo "error: README.md artifact tables are out of date." >&2
    echo "Regenerate with: node $GENERATOR and paste the output between the markers." >&2
    diff <(printf '%s\n' "$actual") <(printf '%s\n' "$expected") || true
    exit 1
fi
echo "README.md artifact tables are in sync."
