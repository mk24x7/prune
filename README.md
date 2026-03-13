<p align="center">
  <img src="assets/icon.png" width="128" height="128" alt="Prune logo">
</p>

<h1 align="center">Prune</h1>

<p align="center">
  <strong>Reclaim disk space by cleaning up developer build artifacts</strong>
</p>

<p align="center">
  <a href="https://github.com/mk24x7/prune/releases/latest"><img src="https://img.shields.io/github/v/release/mk24x7/prune?style=flat-square&color=brightgreen" alt="Latest Release"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-blue?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/swift-5.9-orange?style=flat-square" alt="Swift">
  <img src="https://img.shields.io/github/repo-size/mk24x7/prune?style=flat-square" alt="Repo Size">
  <a href="https://github.com/mk24x7/prune/blob/main/LICENSE"><img src="https://img.shields.io/github/license/mk24x7/prune?style=flat-square" alt="License"></a>
</p>

---

A native macOS app that scans your filesystem for developer build artifacts and caches, shows how much space each one occupies, and lets you selectively delete them. Built with SwiftUI -- no Electron, no web runtime. The entire app is under 2 MB.

## Supported Artifact Types

### Project-level (found by scanning)

| Category | What it finds | How it detects |
|----------|--------------|----------------|
| **Node Modules** | `node_modules` directories | Direct name match |
| **Swift PM** | `.build` directories | Requires `Package.swift` sibling |
| **CocoaPods** | `Pods` directories | Requires `Podfile` sibling |
| **Rust** | `target` directories | Requires `Cargo.toml` sibling |
| **Python Venv** | `venv`, `.venv` directories | Requires Python project file sibling |
| **Python Cache** | `__pycache__` directories | Direct name match |
| **Gradle Build** | `build` directories | Requires `build.gradle` / `build.gradle.kts` sibling |
| **Gradle Cache** | `.gradle` directories | Requires Gradle project file sibling |

### System-level (fixed locations)

| Category | Path |
|----------|------|
| **Xcode DerivedData** | `~/Library/Developer/Xcode/DerivedData` |
| **Xcode Archives** | `~/Library/Developer/Xcode/Archives` |
| **Xcode Device Support** | `~/Library/Developer/Xcode/iOS DeviceSupport` |
| **Xcode Cache** | `~/Library/Caches/com.apple.dt.Xcode` |
| **Gradle Global Cache** | `~/.gradle/caches` |
| **Homebrew Cache** | `~/Library/Caches/Homebrew` |

## Screenshots

> *Coming soon*

## Download

Grab the latest release from the [Releases page](https://github.com/mk24x7/prune/releases/latest):

| Asset | Description |
|-------|-------------|
| **Prune.dmg** | Disk image -- mount, drag to Applications |
| **Prune-app.zip** | Zipped app bundle -- unzip and run |

### First launch

The app is ad-hoc signed (no Apple Developer certificate). On first launch, macOS will block it:

1. Open **System Settings** > **Privacy & Security**
2. Scroll down and click **Open Anyway** next to the Prune message
3. Subsequent launches will work normally

## Features

- Scan any directory (defaults to home directory)
- Select which artifact types to scan for from the landing screen
- Smart scanning -- skips `.Trash`, `Library`, `.git`, IDE caches, and other unproductive paths
- Sibling-file detection to avoid false positives (e.g. only matches `target/` when `Cargo.toml` exists)
- System-level cache scanning at known macOS paths (Xcode, Gradle, Homebrew)
- Shows project name, category, size, full path, and last modified age
- Color-coded size badges (red > 500 MB, orange > 100 MB, green otherwise)
- Filter results by category
- Sort by size, name, age, or path
- Select all / deselect all with one click
- Confirmation dialog before deletion
- Per-item progress and status during deletion
- Summary with total space freed and per-category breakdown

## Build from source

Requires Swift 5.9+ and macOS 13+.

```bash
git clone https://github.com/mk24x7/prune.git
cd prune

# Build and assemble .app bundle
./build.sh

# Optional: create DMG
./dmg.sh
```

The built `Prune.app` will be in the project root.

## CLI

A Node.js command-line version is included in the `cli/` directory for terminal users:

```bash
cd cli
npm install

# Interactive mode (prompts for category selection)
node node-cleanup.js

# Scan specific categories
node node-cleanup.js --categories node,rust,xcode-derived

# Scan all categories
node node-cleanup.js --all

# Scan a specific directory
node node-cleanup.js ~/projects --categories node,swiftpm

# Preview without deleting
node node-cleanup.js --all --dry-run

# List available categories
node node-cleanup.js --list-categories
```

Requires Node.js 18+. Features interactive category selection, checkboxes, colored output, and spinner animations.

## How it works

1. **Scan** -- Iterative depth-first search (max depth 8) using `FileManager.contentsOfDirectory`. Skips known unproductive directories. Uses sibling-file detection for ambiguous directory names (e.g. `build/` is only matched when `build.gradle` exists alongside it). System-level caches are checked at known absolute paths.
2. **Size** -- Shells out to `du -sk` for fast, accurate size calculation. Reads project manifests (`package.json`, `Cargo.toml`, `Package.swift`, `settings.gradle`) for project names.
3. **Delete** -- Uses `FileManager.removeItem` for deletion. Safety guards verify each path against allowed directory names and known system paths before deletion. Reports per-item success/failure.

## Project structure

```
prune/
  Package.swift              # Swift Package Manager config
  Sources/                   # SwiftUI app (13 files)
    PruneApp.swift           # App entry point
    AppState.swift           # Observable state machine
    ArtifactDefinitions.swift# Artifact type registry and detection rules
    Scanner.swift            # Actor-based filesystem scanner
    Sizer.swift              # Size calculation + project name extraction
    Deleter.swift            # Directory deletion with safety guards
    Models.swift             # Data types, enums, ArtifactCategory
    ContentView.swift        # Phase-based view routing
    LandingView.swift        # Category selection + scan trigger
    ScanningView.swift       # Scan progress display
    ResultsView.swift        # Results list with category filter
    DeletingView.swift       # Deletion progress
    SummaryView.swift        # Completion summary with breakdown
  cli/                       # Node.js CLI tool
    node-cleanup.js          # CLI entry point
    lib/                     # Scanner, sizer, deleter, UI, constants
  build.sh                   # Build + assemble .app bundle
  dmg.sh                     # Create DMG installer
  Info.plist                 # App metadata
  AppIcon.icns               # App icon
```

## License

MIT
