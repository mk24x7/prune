# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Shared artifact definitions in `Definitions/artifacts.json`, with a JSON Schema, used by both the macOS app and the CLI so the two can no longer drift apart.
- Verifier that re-checks every selected path immediately before removal: no symlinks, basename must be one of the type's own targets, path must stay under the scan root, required sibling files must still exist, and system paths must match the resolved location.
- Deletion log at `~/Library/Logs/Prune/deletions.jsonl`, one line per trashed or deleted item plus one line per run.
- Freed space is measured from each volume's available capacity before and after cleanup, alongside the estimated total.
- Minimum age filter (app picker and CLI `--min-age <days>`) so recently modified artifacts can be excluded.
- CLI flags: `--categories`, `--all`, `--list-categories`, `--dry-run`, `--include-hidden`, `--yes`, `--json`, `--permanent`, `--min-age`, `--min-size`, `--max-depth`, `--no-color`, `--log-dir`, `--version`. Unknown flags are rejected with exit code 2.
- Twelve new artifact types: Android System Images, Android Virtual Devices, Gradle Wrapper Distributions, Simulator Caches, iOS Device Backups, Docker Disk Image, Downloaded Installers, Go Build Cache, SwiftPM Cache, pnpm Cache, node-gyp Cache and Cypress Cache. Types that hold user data are off by default and marked as not regenerable.
- Project hygiene files: LICENSE, CONTRIBUTING, SECURITY, issue and pull request templates, Dependabot configuration.

### Changed

- Cleanup moves items to the Trash by default; permanent deletion is an explicit opt-in.
- Xcode Archives are now off by default and marked as not regenerable, because archives hold the dSYMs needed to symbolicate crash logs from shipped builds.
- System cache locations honour their tools' environment variable overrides (for example `GOMODCACHE`, `CARGO_HOME`, `GRADLE_USER_HOME`, `npm_config_cache`).
- Bundle identifier changed from `com.prune.app` to `com.mk24x7.prune`.
- CLI entry point renamed from `node-cleanup.js` to `prune.js`; `chalk` and `ora` dependencies removed; Node.js 20.12 or later is required.
- Default maximum scan depth raised to 10 and configurable.
- `cli/package-lock.json` is now committed so CI installs are reproducible.

### Fixed

- Scanner now keeps descending into a directory whose name matches a target but whose sibling check fails, so nested targets (for example a real Rust `target` inside an unrelated `target` folder) are found.
- Scan cancellation uses structured task cancellation and terminates in-flight `du` processes instead of polling a flag.
- Sizes that could not be measured are shown as unknown and excluded from totals instead of being reported as zero.
- Package bundles (`.app`, `.xcodeproj`, `.framework` and similar) are skipped by extension; the previous skip option had no effect on shallow directory listings.
- The read-only Go module cache can be deleted permanently.
- System cache paths are excluded from the project scan so nothing is found twice.

### Removed

- Vite Cache artifact type. Its cache lives inside `node_modules`, which the scanner never descends into, so it could never be found.

## [3.1.0] - 2026-05-27

### Added

- 22 new regenerable artifact types covering JavaScript framework build outputs, Python tool caches, Gradle, Xcode and global package manager caches.

## [3.0.0] - 2026-03-13

### Added

- Multi-artifact cleanup support: Prune now finds and removes build artifacts and caches for several ecosystems, not only `node_modules`.

## [2.0.0] - 2026-03-13

### Added

- Initial release: a native macOS app and a Node.js CLI for finding and deleting `node_modules` directories.

Note: the `v2.0.0` tag points to a commit from before the repository history was rewritten, so it is not an ancestor of `main`.

[Unreleased]: https://github.com/mk24x7/prune/compare/v3.1.0...HEAD
[3.1.0]: https://github.com/mk24x7/prune/compare/v3.0.0...v3.1.0
[3.0.0]: https://github.com/mk24x7/prune/compare/v2.0.0...v3.0.0
[2.0.0]: https://github.com/mk24x7/prune/releases/tag/v2.0.0
