import Foundation
import PruneDefinitions

// MARK: - Model (mirrors Definitions/artifacts.json and artifacts.schema.json)

public struct Definitions: Codable, Sendable, Equatable {
    public let version: Int
    public let scan: ScanRules
    public let colors: [String]
    public let types: [ArtifactType]

    public init(version: Int, scan: ScanRules, colors: [String], types: [ArtifactType]) {
        self.version = version
        self.scan = scan
        self.colors = colors
        self.types = types
    }
}

public struct ScanRules: Codable, Sendable, Equatable {
    public let maxDepth: Int
    public let skipUnderHome: [String]
    public let skipAnywhere: [String]
    public let skipPackageExtensions: [String]

    public init(maxDepth: Int, skipUnderHome: [String], skipAnywhere: [String], skipPackageExtensions: [String]) {
        self.maxDepth = maxDepth
        self.skipUnderHome = skipUnderHome
        self.skipAnywhere = skipAnywhere
        self.skipPackageExtensions = skipPackageExtensions
    }
}

public enum ArtifactKind: String, Codable, Sendable, Equatable {
    case project, system, files
}

public enum NameStrategy: String, Codable, Sendable, Equatable {
    case packageJson, cargoToml, packageSwift, gradleSettings, derivedData, dirname, parentDirname
}

public struct PathOverride: Codable, Sendable, Equatable, Hashable {
    public let env: String
    public let append: String?

    public init(env: String, append: String? = nil) {
        self.env = env
        self.append = append
    }
}

public struct ArtifactType: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let kind: ArtifactKind
    public let displayName: String
    public let description: String
    public let nameFrom: NameStrategy
    public let defaultEnabled: Bool
    public let regenerable: Bool
    public let reinstallHint: String
    public let color: String
    public let icon: String
    public let targets: [String]?
    public let siblings: [String]?
    public let path: String?
    public let pathOverrides: [PathOverride]?
    public let expand: Bool?
    public let readOnlyTree: Bool?
    public let isFile: Bool?
    public let extensions: [String]?

    public init(
        id: String, kind: ArtifactKind, displayName: String, description: String,
        nameFrom: NameStrategy, defaultEnabled: Bool, regenerable: Bool,
        reinstallHint: String, color: String, icon: String,
        targets: [String]? = nil, siblings: [String]? = nil, path: String? = nil,
        pathOverrides: [PathOverride]? = nil, expand: Bool? = nil,
        readOnlyTree: Bool? = nil, isFile: Bool? = nil, extensions: [String]? = nil
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.description = description
        self.nameFrom = nameFrom
        self.defaultEnabled = defaultEnabled
        self.regenerable = regenerable
        self.reinstallHint = reinstallHint
        self.color = color
        self.icon = icon
        self.targets = targets
        self.siblings = siblings
        self.path = path
        self.pathOverrides = pathOverrides
        self.expand = expand
        self.readOnlyTree = readOnlyTree
        self.isFile = isFile
        self.extensions = extensions
    }

    /// True when the artifact is a single regular file rather than a directory
    /// (system types with `isFile`, and every entry of a `files` type).
    public var entriesAreFiles: Bool {
        kind == .files || isFile == true
    }
}

// MARK: - Errors

public enum DefinitionsError: Error, LocalizedError, Equatable {
    case unreadable(String)
    case malformed(String)
    case invalid([String])

    public var errorDescription: String? {
        switch self {
        case .unreadable(let detail):
            return "Could not read artifacts.json: \(detail)"
        case .malformed(let detail):
            return "artifacts.json could not be decoded: \(detail)"
        case .invalid(let problems):
            return "artifacts.json is invalid:\n" + problems.map { "- " + $0 }.joined(separator: "\n")
        }
    }
}

// MARK: - Loading and validation

extension Definitions {
    static let topLevelKeys: Set<String> = ["version", "scan", "colors", "types"]
    static let scanKeys: Set<String> = ["maxDepth", "skipUnderHome", "skipAnywhere", "skipPackageExtensions"]
    static let pathOverrideKeys: Set<String> = ["env", "append"]
    static let commonTypeKeys: Set<String> = [
        "id", "kind", "displayName", "description", "nameFrom",
        "defaultEnabled", "regenerable", "reinstallHint", "color", "icon",
    ]
    static let kindKeys: [ArtifactKind: (required: Set<String>, optional: Set<String>)] = [
        .project: (["targets", "siblings"], []),
        .system: (["path", "expand", "pathOverrides", "readOnlyTree"], ["isFile"]),
        .files: (["path", "extensions"], ["pathOverrides"]),
    ]
    static let allowedNameFrom: [ArtifactKind: Set<NameStrategy>] = [
        .project: [.packageJson, .cargoToml, .packageSwift, .gradleSettings, .parentDirname],
        .system: [.derivedData, .dirname],
        .files: [.dirname],
    ]

    /// Load, decode and validate the bundled (or given) artifacts.json.
    public static func load(from url: URL = DefinitionsBundle.artifactsURL) throws -> Definitions {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DefinitionsError.unreadable("\(url.path): \(error.localizedDescription)")
        }
        return try decode(data)
    }

    /// Decode and validate raw JSON bytes.
    public static func decode(_ data: Data) throws -> Definitions {
        let definitions: Definitions
        do {
            definitions = try JSONDecoder().decode(Definitions.self, from: data)
        } catch {
            throw DefinitionsError.malformed(String(describing: error))
        }
        try definitions.validate(rawJSON: data)
        return definitions
    }

    /// Enforce the rules that Codable alone cannot. When `rawJSON` is given the
    /// key sets are also checked, because Codable silently ignores unknown keys.
    public func validate(rawJSON: Data? = nil) throws {
        var problems: [String] = []

        if version != 1 { problems.append("version must be 1, found \(version)") }
        if scan.maxDepth < 1 || scan.maxDepth > 64 { problems.append("scan.maxDepth must be between 1 and 64") }
        for ext in scan.skipPackageExtensions where !Self.isExtension(ext) {
            problems.append("scan.skipPackageExtensions: \"\(ext)\" must look like .ext")
        }
        if colors.isEmpty { problems.append("colors must not be empty") }
        if Set(colors).count != colors.count { problems.append("colors contains duplicates") }
        if types.isEmpty { problems.append("types must not be empty") }

        let palette = Set(colors)
        var seen: [String: Int] = [:]
        for (index, type) in types.enumerated() {
            let at = "types[\(index)] (\(type.id))"
            if let first = seen[type.id] {
                problems.append("\(at): duplicate id, first used at types[\(first)]")
            } else {
                seen[type.id] = index
            }
            if type.id.isEmpty || type.id.range(of: "^[a-z0-9-]+$", options: .regularExpression) == nil {
                problems.append("\(at): id must match ^[a-z0-9-]+$")
            }
            for (field, value) in [("displayName", type.displayName), ("description", type.description),
                                   ("reinstallHint", type.reinstallHint), ("icon", type.icon)] where value.isEmpty {
                problems.append("\(at): \(field) must not be empty")
            }
            if !palette.contains(type.color) {
                problems.append("\(at): color \"\(type.color)\" is not in the colors palette")
            }
            if !type.regenerable && type.defaultEnabled {
                problems.append("\(at): regenerable is false so defaultEnabled must be false")
            }
            if let allowed = Self.allowedNameFrom[type.kind], !allowed.contains(type.nameFrom) {
                problems.append("\(at): nameFrom \"\(type.nameFrom.rawValue)\" is not valid for kind \"\(type.kind.rawValue)\"")
            }
            problems.append(contentsOf: Self.kindProblems(type, at: at))
        }

        if let rawJSON {
            problems.append(contentsOf: Self.unknownKeyProblems(rawJSON))
        }

        if !problems.isEmpty { throw DefinitionsError.invalid(problems) }
    }

    private static func kindProblems(_ type: ArtifactType, at: String) -> [String] {
        var problems: [String] = []
        let present: [String: Bool] = [
            "targets": type.targets != nil, "siblings": type.siblings != nil,
            "path": type.path != nil, "pathOverrides": type.pathOverrides != nil,
            "expand": type.expand != nil, "readOnlyTree": type.readOnlyTree != nil,
            "isFile": type.isFile != nil, "extensions": type.extensions != nil,
        ]
        let spec = kindKeys[type.kind]!
        for key in spec.required.sorted() where present[key] != true {
            problems.append("\(at): kind \(type.kind.rawValue) requires \"\(key)\"")
        }
        for (key, isPresent) in present.sorted(by: { $0.key < $1.key })
        where isPresent && !spec.required.contains(key) && !spec.optional.contains(key) {
            problems.append("\(at): kind \(type.kind.rawValue) must not have \"\(key)\"")
        }

        switch type.kind {
        case .project:
            if let targets = type.targets, targets.isEmpty {
                problems.append("\(at): project type needs non-empty targets")
            }
            for name in (type.targets ?? []) + (type.siblings ?? []) where !isPlainName(name) {
                problems.append("\(at): invalid file name \"\(name)\"")
            }
        case .system, .files:
            if let path = type.path {
                if !path.hasPrefix("~/") { problems.append("\(at): path must start with ~/") }
                if path == "~/" || path.hasSuffix("/") { problems.append("\(at): path must not end with /") }
                if path.split(separator: "/").contains("..") { problems.append("\(at): path must not contain .. segments") }
            }
            for override in type.pathOverrides ?? [] {
                if override.env.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) == nil {
                    problems.append("\(at): pathOverrides env \"\(override.env)\" is not a valid variable name")
                }
                if let append = override.append {
                    if append.isEmpty || append.hasPrefix("/") || append.hasPrefix("~") || append.hasSuffix("/")
                        || append.split(separator: "/").contains("..") {
                        problems.append("\(at): pathOverrides append \"\(append)\" must be a relative path")
                    }
                }
            }
            if type.isFile == true && type.expand == true {
                problems.append("\(at): a file cannot be expanded")
            }
            if let extensions = type.extensions {
                if extensions.isEmpty { problems.append("\(at): extensions must not be empty") }
                for ext in extensions where !isExtension(ext) {
                    problems.append("\(at): extension \"\(ext)\" must look like .ext")
                }
            }
        }
        return problems
    }

    private static func unknownKeyProblems(_ data: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ["top level must be a JSON object"]
        }
        var problems: [String] = []
        func check(_ object: [String: Any], allowed: Set<String>, at: String) {
            for key in Set(object.keys).subtracting(allowed).sorted() {
                problems.append("\(at): unknown key \"\(key)\"")
            }
        }
        check(root, allowed: topLevelKeys, at: "$")
        if let scan = root["scan"] as? [String: Any] {
            check(scan, allowed: scanKeys, at: "scan")
        }
        for (index, element) in ((root["types"] as? [Any]) ?? []).enumerated() {
            guard let object = element as? [String: Any] else {
                problems.append("types[\(index)]: must be an object")
                continue
            }
            let at = "types[\(index)] (\(object["id"] as? String ?? "?"))"
            var allowed = commonTypeKeys
            if let kindRaw = object["kind"] as? String, let kind = ArtifactKind(rawValue: kindRaw),
               let spec = kindKeys[kind] {
                allowed.formUnion(spec.required)
                allowed.formUnion(spec.optional)
            }
            check(object, allowed: allowed, at: at)
            for (oIndex, override) in ((object["pathOverrides"] as? [Any]) ?? []).enumerated() {
                if let override = override as? [String: Any] {
                    check(override, allowed: pathOverrideKeys, at: "\(at).pathOverrides[\(oIndex)]")
                }
            }
        }
        return problems
    }

    private static func isPlainName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/")
    }

    private static func isExtension(_ ext: String) -> Bool {
        ext.range(of: "^\\.[A-Za-z0-9]+$", options: .regularExpression) != nil
    }
}

// MARK: - Queries

extension Definitions {
    public var projectTypes: [ArtifactType] { types.filter { $0.kind == .project } }
    public var systemTypes: [ArtifactType] { types.filter { $0.kind == .system } }
    public var filesTypes: [ArtifactType] { types.filter { $0.kind == .files } }
    public var defaultEnabledIds: Set<String> { Set(types.filter(\.defaultEnabled).map(\.id)) }

    public func type(id: String) -> ArtifactType? {
        types.first { $0.id == id }
    }

    /// Resolve the on-disk location of a system or files type. The first
    /// override whose environment variable is set and non-empty wins (with
    /// `append` joined on when present); otherwise `~/` is expanded against
    /// `home`. Returns nil for project types.
    public func resolvedSystemURL(
        for type: ArtifactType,
        env: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL? {
        guard let path = type.path else { return nil }
        for override in type.pathOverrides ?? [] {
            guard let value = env[override.env], !value.isEmpty else { continue }
            var url = URL(fileURLWithPath: (value as NSString).expandingTildeInPath, isDirectory: true)
            if let append = override.append {
                url.appendPathComponent(append)
            }
            return url.standardizedFileURL
        }
        guard path.hasPrefix("~/") else { return nil }
        return home.appendingPathComponent(String(path.dropFirst(2))).standardizedFileURL
    }
}
