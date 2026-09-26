#!/bin/bash
# Fail if any tracked (or untracked but not ignored) text file contains a
# non-ASCII byte. Uses perl because BSD grep has no -P.
set -euo pipefail

cd "$(dirname "$0")/.."

status=0
while IFS= read -r -d '' file; do
    [ -f "$file" ] || continue
    case "$file" in
        cli/package-lock.json) continue ;;
    esac
    if ! perl -ne '
        if (/[^\x00-\x7F]/) {
            chomp;
            my $col = $-[0] + 1;
            print "$ARGV:$.:$col: non-ASCII byte\n";
            $bad = 1;
        }
        END { exit($bad ? 1 : 0) }
    ' "$file"; then
        status=1
    fi
done < <(git ls-files -z --cached --others --exclude-standard -- \
    '*.swift' '*.js' '*.mjs' '*.json' '*.md' '*.sh' '*.yml' '*.yaml' \
    '*.plist' '*.rb' '*.txt')

if [ "$status" -ne 0 ]; then
    echo "error: non-ASCII bytes found (see above)" >&2
    exit 1
fi
echo "All checked text files are pure ASCII."
