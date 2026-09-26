# Contributing to Prune

Thanks for helping. Prune deletes files, so correctness and safety matter more than features. Please read this before opening a pull request.

## Requirements

- macOS 13 or later
- Xcode command line tools with Swift 5.9 or later
- Node.js 20.12 or later (for the CLI and the definitions validator)

## Build

```sh
swift build                 # debug build of the app and libraries
./build.sh                  # release build packaged as Prune.app
```

## Test

```sh
swift test                  # Swift unit tests
cd cli && npm ci && npm test  # CLI unit and end-to-end tests
node Definitions/validate.mjs # artifact definitions
```

All three must pass before a pull request is merged. CI runs the same commands.

## Screenshots

The app has a hidden snapshot mode that renders the UI offscreen and quits, so
the README screenshot can be regenerated without screen recording permission:

```sh
./build.sh
PRUNE_SNAPSHOT_DIR=/tmp/prune-shots dist/Prune.app/Contents/MacOS/Prune
cp /tmp/prune-shots/results.png assets/results.png
```

- `PRUNE_SNAPSHOT_DIR` turns the mode on and is where `landing.png` and
  `results.png` are written (2x, 2080x1360 px for the default 1040x680 pt window).
- `PRUNE_SNAPSHOT_ROOT` is the folder to scan (default `~/Demo`). Keep it a
  folder of throwaway demo projects so no real paths end up in the image.

Snapshot mode scans project artifact types only (no system caches), selects the
three largest results, forces the dark appearance, never deletes anything and
does not change the saved type selection. The glass sidebar and toolbar of the
real window do not render through offscreen capture, so the image shows the
sidebar and detail views side by side on solid backgrounds without the toolbar.

## Adding an artifact type

Every artifact type lives in one place, `Definitions/artifacts.json`, which both the app and the CLI load. `Definitions/artifacts.schema.json` documents every field; editors that understand JSON Schema will offer completion.

1. Add an entry to `types` in `Definitions/artifacts.json`, next to related types.
   - `kind: "project"` for directories found by scanning inside projects. Give `targets` (directory names) and `siblings` (marker files, at least one of which must exist next to the target; leave empty only when the target name is unambiguous).
   - `kind: "system"` for a fixed location under the home directory. Give `path` starting with `~/`, any `pathOverrides` environment variables the tool honours, and `expand: true` if each subfolder should be listed separately.
   - Set `regenerable: false` (which requires `defaultEnabled: false`) for anything that holds data a tool cannot recreate, and explain what is lost in `reinstallHint`.
2. Run `node Definitions/validate.mjs` and fix every reported problem.
3. Add a test fixture that covers the new type in both the Swift tests (`Tests/PruneCoreTests`) and the CLI tests (`cli/test`), including a negative case where the sibling marker is missing.
4. Regenerate the README tables with `node cli/scripts/readme-tables.js`.
5. Add a line under `## [Unreleased]` in `CHANGELOG.md`.

Only propose types that are safe to delete and are recreated automatically or by a single documented command. If you are unsure, open an "Artifact type request" issue first.

## Commit messages

- Imperative mood, capitalised, no trailing period: "Add Bun cache type", not "added bun cache".
- Subject line of 72 characters or fewer, blank line, then a body explaining why when it is not obvious.
- No emojis or decorative symbols anywhere: commits, code, comments or documentation.

## Pull requests

- Keep each pull request focused on one change.
- Fill in the pull request template checklist.
- Include tests for bug fixes and new behaviour. Changes to scanning, verification or deletion without tests will not be merged.
- Describe how you tested manually if the change affects the app UI.
- Be prepared to explain why a new artifact type can never contain user data.
