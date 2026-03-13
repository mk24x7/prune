import Foundation

// MARK: - Artifact Definition

/// Describes how to detect a project-level artifact type during scanning.
struct ArtifactDefinition {
    let category: ArtifactCategory
    /// Directory names to match (e.g. ["node_modules"])
    let targetDirNames: Set<String>
    /// If non-empty, at least one of these files must exist in the parent directory
    /// for the match to be valid (e.g. ["build.gradle", "build.gradle.kts"])
    let siblingFiles: [String]
}

// MARK: - System Artifact

/// A known system-level artifact at a fixed path.
struct SystemArtifactPath {
    let category: ArtifactCategory
    let url: URL
    /// If true, list subdirectories as individual entries instead of one big entry
    let expandSubdirectories: Bool
}

// MARK: - Registry

enum ArtifactRegistry {
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    /// All project-level artifact definitions, keyed by category
    static let projectDefinitions: [ArtifactDefinition] = [
        ArtifactDefinition(
            category: .nodeModules,
            targetDirNames: ["node_modules"],
            siblingFiles: []
        ),
        ArtifactDefinition(
            category: .swiftPM,
            targetDirNames: [".build"],
            siblingFiles: ["Package.swift"]
        ),
        ArtifactDefinition(
            category: .cocoapods,
            targetDirNames: ["Pods"],
            siblingFiles: ["Podfile"]
        ),
        ArtifactDefinition(
            category: .rust,
            targetDirNames: ["target"],
            siblingFiles: ["Cargo.toml"]
        ),
        ArtifactDefinition(
            category: .pythonVenv,
            targetDirNames: ["venv", ".venv"],
            siblingFiles: ["requirements.txt", "pyproject.toml", "setup.py", "setup.cfg", "Pipfile"]
        ),
        ArtifactDefinition(
            category: .pythonCache,
            targetDirNames: ["__pycache__"],
            siblingFiles: []
        ),
        ArtifactDefinition(
            category: .gradleBuild,
            targetDirNames: ["build"],
            siblingFiles: ["build.gradle", "build.gradle.kts"]
        ),
        ArtifactDefinition(
            category: .gradleCache,
            targetDirNames: [".gradle"],
            siblingFiles: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"]
        ),
    ]

    /// System-level artifacts at fixed paths
    static let systemArtifacts: [SystemArtifactPath] = [
        SystemArtifactPath(
            category: .xcodeDerivedData,
            url: home.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
            expandSubdirectories: true
        ),
        SystemArtifactPath(
            category: .xcodeArchives,
            url: home.appendingPathComponent("Library/Developer/Xcode/Archives"),
            expandSubdirectories: true
        ),
        SystemArtifactPath(
            category: .xcodeDeviceSupport,
            url: home.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport"),
            expandSubdirectories: true
        ),
        SystemArtifactPath(
            category: .xcodeCache,
            url: home.appendingPathComponent("Library/Caches/com.apple.dt.Xcode"),
            expandSubdirectories: false
        ),
        SystemArtifactPath(
            category: .gradleGlobalCache,
            url: home.appendingPathComponent(".gradle/caches"),
            expandSubdirectories: false
        ),
        SystemArtifactPath(
            category: .homebrewCache,
            url: home.appendingPathComponent("Library/Caches/Homebrew"),
            expandSubdirectories: false
        ),
    ]

    /// Get project definitions filtered by selected categories
    static func definitions(for categories: Set<ArtifactCategory>) -> [ArtifactDefinition] {
        projectDefinitions.filter { categories.contains($0.category) }
    }

    /// Get system artifacts filtered by selected categories
    static func systemArtifacts(for categories: Set<ArtifactCategory>) -> [SystemArtifactPath] {
        systemArtifacts.filter { categories.contains($0.category) }
    }

    /// All target directory names across given definitions (for fast lookup in scanner)
    static func allTargetNames(for definitions: [ArtifactDefinition]) -> Set<String> {
        var names = Set<String>()
        for def in definitions {
            names.formUnion(def.targetDirNames)
        }
        return names
    }

    /// Look up which definition matches a given directory name.
    /// Returns nil if no match. If sibling detection is required, checks parent for sibling files.
    static func matchDefinition(
        dirName: String,
        parentURL: URL,
        definitions: [ArtifactDefinition],
        fm: FileManager = .default
    ) -> ArtifactDefinition? {
        for def in definitions {
            guard def.targetDirNames.contains(dirName) else { continue }

            // If no sibling files required, it's a direct match
            if def.siblingFiles.isEmpty {
                return def
            }

            // Check if at least one sibling file exists in the parent
            for sibling in def.siblingFiles {
                let siblingURL = parentURL.appendingPathComponent(sibling)
                if fm.fileExists(atPath: siblingURL.path) {
                    return def
                }
            }
        }
        return nil
    }

    /// All valid directory names that the deleter is allowed to remove,
    /// across all categories.
    static func allowedDeletionNames(for categories: Set<ArtifactCategory>) -> Set<String> {
        var names = Set<String>()
        for def in definitions(for: categories) {
            names.formUnion(def.targetDirNames)
        }
        return names
    }

    /// All valid system-level URLs that the deleter is allowed to remove
    static func allowedSystemPaths(for categories: Set<ArtifactCategory>) -> Set<URL> {
        var urls = Set<URL>()
        for sys in systemArtifacts(for: categories) {
            urls.insert(sys.url)
            // If expanded, subdirectories are also allowed
            if sys.expandSubdirectories {
                if let contents = try? FileManager.default.contentsOfDirectory(
                    at: sys.url,
                    includingPropertiesForKeys: nil
                ) {
                    for item in contents {
                        urls.insert(item)
                    }
                }
            }
        }
        return urls
    }
}
