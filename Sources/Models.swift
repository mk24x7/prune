import Foundation

// MARK: - Artifact Category

enum ArtifactCategory: String, CaseIterable, Identifiable, Hashable {
    // Project-level (found by scanning)
    case nodeModules = "Node Modules"
    case swiftPM = "Swift PM"
    case cocoapods = "CocoaPods"
    case rust = "Rust"
    case pythonVenv = "Python Venv"
    case pythonCache = "Python Cache"
    case gradleBuild = "Gradle Build"
    case gradleCache = "Gradle Cache"

    // System-level (fixed paths)
    case xcodeDerivedData = "Xcode DerivedData"
    case xcodeArchives = "Xcode Archives"
    case xcodeDeviceSupport = "Xcode Device Support"
    case xcodeCache = "Xcode Cache"
    case gradleGlobalCache = "Gradle Global Cache"
    case homebrewCache = "Homebrew Cache"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .nodeModules: return "shippingbox"
        case .swiftPM: return "swift"
        case .cocoapods: return "leaf"
        case .rust: return "gearshape.2"
        case .pythonVenv: return "terminal"
        case .pythonCache: return "memorychip"
        case .gradleBuild: return "hammer"
        case .gradleCache: return "archivebox"
        case .xcodeDerivedData: return "xmark.bin"
        case .xcodeArchives: return "doc.zipper"
        case .xcodeDeviceSupport: return "iphone"
        case .xcodeCache: return "internaldrive"
        case .gradleGlobalCache: return "archivebox.fill"
        case .homebrewCache: return "mug"
        }
    }

    var isSystemLevel: Bool {
        switch self {
        case .xcodeDerivedData, .xcodeArchives, .xcodeDeviceSupport,
             .xcodeCache, .gradleGlobalCache, .homebrewCache:
            return true
        default:
            return false
        }
    }

    var reinstallHint: String {
        switch self {
        case .nodeModules: return "npm install"
        case .swiftPM: return "swift build"
        case .cocoapods: return "pod install"
        case .rust: return "cargo build"
        case .pythonVenv: return "python -m venv venv"
        case .pythonCache: return "auto-regenerated on next run"
        case .gradleBuild: return "./gradlew build"
        case .gradleCache: return "auto-regenerated on next build"
        case .xcodeDerivedData: return "Xcode rebuilds automatically"
        case .xcodeArchives: return "re-archive from Xcode"
        case .xcodeDeviceSupport: return "re-downloaded on device connect"
        case .xcodeCache: return "Xcode rebuilds cache automatically"
        case .gradleGlobalCache: return "re-downloaded on next build"
        case .homebrewCache: return "re-downloaded on next install"
        }
    }

    var shortDescription: String {
        switch self {
        case .nodeModules: return "JavaScript dependencies"
        case .swiftPM: return "Swift Package Manager build artifacts"
        case .cocoapods: return "CocoaPods dependencies"
        case .rust: return "Rust build artifacts"
        case .pythonVenv: return "Python virtual environments"
        case .pythonCache: return "Python bytecode cache"
        case .gradleBuild: return "Gradle/Android build outputs"
        case .gradleCache: return "Gradle project-level cache"
        case .xcodeDerivedData: return "Xcode build artifacts"
        case .xcodeArchives: return "Xcode archived builds"
        case .xcodeDeviceSupport: return "iOS device debug symbols"
        case .xcodeCache: return "Xcode caches"
        case .gradleGlobalCache: return "Global Gradle download cache"
        case .homebrewCache: return "Homebrew downloaded packages"
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
