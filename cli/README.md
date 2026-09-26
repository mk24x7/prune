# prune-cli

Command-line version of [Prune](https://github.com/mk24x7/prune): find and
safely remove regenerable developer artifacts on macOS (`node_modules`, Rust
`target`, Python virtualenvs, Xcode DerivedData, Homebrew, npm, pnpm, Gradle
and other caches). Items go to the Trash by default, every deletion is
re-verified and logged, and a dry run never prompts.

The full list of artifact types, screenshots and the macOS app are in the
[main README](https://github.com/mk24x7/prune#readme). The CLI and the app read
the same definitions file, so they always agree on what is safe to remove.

## Install

```sh
npm install -g @mk24x7/prune
# or run once
npx @mk24x7/prune --dry-run
```

Requires macOS and Node.js 20.17+, 22.13+ or 23.5+.

## Usage

```
prune [path] [options]
```

| Option | Meaning |
| --- | --- |
| `path` | Directory to scan for project artifacts (default: home) |
| `--categories <list>` | Comma-separated type ids, e.g. `node,rust,xcode-derived` |
| `--all` | Every type, including ones that are not regenerable (warns) |
| `--list-categories` | Show all type ids and exit |
| `--dry-run` | List only; never prompts, never deletes |
| `--include-hidden` | Also descend into hidden directories |
| `--max-depth <n>` | Maximum directory depth below `path` |
| `--min-age <days>` | Only items not modified in the last `<days>` days |
| `--min-size <n[KB\|MB\|GB]>` | Only items at least this large |
| `--permanent` | Delete permanently instead of moving to the Trash |
| `-y`, `--yes` | Select everything found and skip prompts (needs `--categories` or `--all`; alias `--non-interactive`) |
| `--json` | One JSON document on stdout, human output on stderr; implies `--dry-run` unless `--yes` |
| `--no-color` | Disable colors (`NO_COLOR` is honoured too) |
| `--log-dir <path>` | Deletion log directory (default `~/Library/Logs/Prune`, or `$PRUNE_LOG_DIR`) |
| `-h`, `--help` / `-V`, `--version` | Help and version |

Exit codes: `0` success, `1` runtime error, `2` usage error, `3` some items
could not be removed.

## Examples

```sh
prune                                   # choose categories and items interactively
prune ~/code --categories node,rust     # one folder, two types
prune --all --dry-run                   # preview everything
prune --categories node --min-age 90 -y # trash node_modules untouched for 90 days
prune --all --json > report.json        # machine-readable preview
```

If a volume has no Trash, `--yes` runs report those items and exit with code 3;
rerun with `--permanent` to delete them. Interactive runs ask first.

## License

MIT
