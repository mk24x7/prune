import Foundation

// MARK: - Artifact Category

enum ArtifactCategory: String, CaseIterable, Identifiable, Hashable {
    // Project-level (found by scanning)
    case nodeModules = "Node Modules"
    case nextBuild = "Next.js Build"
    case nuxtBuild = "Nuxt Build"
    case svelteKit = "SvelteKit Build"
    case astroBuild = "Astro Build"
    case angularCache = "Angular Cache"
    case turboCache = "Turbo Cache"
    case viteCache = "Vite Cache"
    case parcelCache = "Parcel Cache"
    case swiftPM = "Swift PM"
    case cocoapods = "CocoaPods"
    case rust = "Rust"
    case pythonVenv = "Python Venv"
    case pythonCache = "Python Cache"
    case pytestCache = "Pytest Cache"
    case mypyCache = "Mypy Cache"
    case ruffCache = "Ruff Cache"
    case toxCache = "Tox Cache"
    case gradleBuild = "Gradle Build"
    case gradleCache = "Gradle Cache"

    // System-level (fixed paths)
    case xcodeDerivedData = "Xcode DerivedData"
    case xcodeArchives = "Xcode Archives"
    case xcodeDeviceSupport = "Xcode Device Support"
    case xcodeCache = "Xcode Cache"
    case gradleGlobalCache = "Gradle Global Cache"
    case homebrewCache = "Homebrew Cache"
    case npmCache = "npm Cache"
    case yarnCache = "Yarn Cache"
    case pnpmStore = "pnpm Store"
    case bunCache = "Bun Cache"
    case pipCache = "pip Cache"
    case cargoRegistry = "Cargo Registry Cache"
    case goModCache = "Go Module Cache"
    case puppeteerCache = "Puppeteer Cache"
    case playwrightCache = "Playwright Browsers"
    case electronCache = "Electron Cache"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .nodeModules: return "shippingbox"
        case .nextBuild: return "n.square"
        case .nuxtBuild: return "leaf.fill"
        case .svelteKit: return "flame"
        case .astroBuild: return "sparkles"
        case .angularCache: return "a.square"
        case .turboCache: return "bolt"
        case .viteCache: return "bolt.fill"
        case .parcelCache: return "shippingbox.fill"
        case .swiftPM: return "swift"
        case .cocoapods: return "leaf"
        case .rust: return "gearshape.2"
        case .pythonVenv: return "terminal"
        case .pythonCache: return "memorychip"
        case .pytestCache: return "checkmark.seal"
        case .mypyCache: return "checkmark.shield"
        case .ruffCache: return "wand.and.stars"
        case .toxCache: return "testtube.2"
        case .gradleBuild: return "hammer"
        case .gradleCache: return "archivebox"
        case .xcodeDerivedData: return "xmark.bin"
        case .xcodeArchives: return "doc.zipper"
        case .xcodeDeviceSupport: return "iphone"
        case .xcodeCache: return "internaldrive"
        case .gradleGlobalCache: return "archivebox.fill"
        case .homebrewCache: return "mug"
        case .npmCache: return "tray.full"
        case .yarnCache: return "circle.grid.cross"
        case .pnpmStore: return "cylinder.split.1x2"
        case .bunCache: return "hare"
        case .pipCache: return "tray"
        case .cargoRegistry: return "shippingbox.and.arrow.backward"
        case .goModCache: return "g.square"
        case .puppeteerCache: return "theatermasks"
        case .playwrightCache: return "play.rectangle"
        case .electronCache: return "atom"
        }
    }

    var isSystemLevel: Bool {
        switch self {
        case .xcodeDerivedData, .xcodeArchives, .xcodeDeviceSupport,
             .xcodeCache, .gradleGlobalCache, .homebrewCache,
             .npmCache, .yarnCache, .pnpmStore, .bunCache, .pipCache,
             .cargoRegistry, .goModCache, .puppeteerCache,
             .playwrightCache, .electronCache:
            return true
        default:
            return false
        }
    }

    var reinstallHint: String {
        switch self {
        case .nodeModules: return "npm install"
        case .nextBuild: return "next build"
        case .nuxtBuild: return "nuxt build"
        case .svelteKit: return "vite build"
        case .astroBuild: return "astro build"
        case .angularCache: return "ng build"
        case .turboCache: return "auto-regenerated on next turbo run"
        case .viteCache: return "auto-regenerated on next dev/build"
        case .parcelCache: return "auto-regenerated on next build"
        case .swiftPM: return "swift build"
        case .cocoapods: return "pod install"
        case .rust: return "cargo build"
        case .pythonVenv: return "python -m venv venv"
        case .pythonCache: return "auto-regenerated on next run"
        case .pytestCache: return "auto-regenerated on next test run"
        case .mypyCache: return "auto-regenerated on next mypy run"
        case .ruffCache: return "auto-regenerated on next ruff run"
        case .toxCache: return "auto-regenerated on next tox run"
        case .gradleBuild: return "./gradlew build"
        case .gradleCache: return "auto-regenerated on next build"
        case .xcodeDerivedData: return "Xcode rebuilds automatically"
        case .xcodeArchives: return "re-archive from Xcode"
        case .xcodeDeviceSupport: return "re-downloaded on device connect"
        case .xcodeCache: return "Xcode rebuilds cache automatically"
        case .gradleGlobalCache: return "re-downloaded on next build"
        case .homebrewCache: return "re-downloaded on next install"
        case .npmCache: return "re-downloaded on next npm install"
        case .yarnCache: return "re-downloaded on next yarn install"
        case .pnpmStore: return "re-downloaded on next pnpm install"
        case .bunCache: return "re-downloaded on next bun install"
        case .pipCache: return "re-downloaded on next pip install"
        case .cargoRegistry: return "re-downloaded on next cargo build"
        case .goModCache: return "re-downloaded on next go build"
        case .puppeteerCache: return "re-downloaded on next puppeteer run"
        case .playwrightCache: return "npx playwright install"
        case .electronCache: return "re-downloaded on next electron install"
        }
    }

    var shortDescription: String {
        switch self {
        case .nodeModules: return "JavaScript dependencies"
        case .nextBuild: return "Next.js build output"
        case .nuxtBuild: return "Nuxt build output"
        case .svelteKit: return "SvelteKit build output"
        case .astroBuild: return "Astro build cache"
        case .angularCache: return "Angular CLI cache"
        case .turboCache: return "Turborepo task cache"
        case .viteCache: return "Vite dependency cache"
        case .parcelCache: return "Parcel bundler cache"
        case .swiftPM: return "Swift Package Manager build artifacts"
        case .cocoapods: return "CocoaPods dependencies"
        case .rust: return "Rust build artifacts"
        case .pythonVenv: return "Python virtual environments"
        case .pythonCache: return "Python bytecode cache"
        case .pytestCache: return "pytest test result cache"
        case .mypyCache: return "mypy type-check cache"
        case .ruffCache: return "Ruff linter cache"
        case .toxCache: return "Tox virtualenv cache"
        case .gradleBuild: return "Gradle/Android build outputs"
        case .gradleCache: return "Gradle project-level cache"
        case .xcodeDerivedData: return "Xcode build artifacts"
        case .xcodeArchives: return "Xcode archived builds"
        case .xcodeDeviceSupport: return "iOS device debug symbols"
        case .xcodeCache: return "Xcode caches"
        case .gradleGlobalCache: return "Global Gradle download cache"
        case .homebrewCache: return "Homebrew downloaded packages"
        case .npmCache: return "Global npm package cache"
        case .yarnCache: return "Global Yarn package cache"
        case .pnpmStore: return "Global pnpm content-addressable store"
        case .bunCache: return "Global Bun install cache"
        case .pipCache: return "Global pip wheel cache"
        case .cargoRegistry: return "Cargo registry download cache"
        case .goModCache: return "Go module download cache"
        case .puppeteerCache: return "Puppeteer downloaded Chromium"
        case .playwrightCache: return "Playwright browser binaries"
        case .electronCache: return "Electron downloaded binaries"
        }
    }

    static var projectLevel: [ArtifactCategory] {
        allCases.filter { !$0.isSystemLevel }
    }

    static var systemLevel: [ArtifactCategory] {
        allCases.filter { $0.isSystemLevel }
    }
}

// MARK: - Artifact Entry

struct ArtifactEntry: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let projectName: String
    let sizeBytes: Int64
    let formattedSize: String
    let shortPath: String
    let age: String
    let lastModified: Date
    let category: ArtifactCategory

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    static func == (lhs: ArtifactEntry, rhs: ArtifactEntry) -> Bool {
        lhs.url == rhs.url
    }
}

// MARK: - Deletion

struct DeletionItem: Identifiable {
    let id = UUID()
    let entry: ArtifactEntry
    var status: DeletionStatus = .pending
    var error: String?
}

enum DeletionStatus {
    case pending, inProgress, done, failed
}

// MARK: - App State

enum AppPhase {
    case idle, scanning, results, deleting, summary
}

enum SortField: String, CaseIterable {
    case size = "Size"
    case name = "Name"
    case age = "Age"
    case path = "Path"
}
