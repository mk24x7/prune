import XCTest
@testable import PruneCore

final class ScannerTests: XCTestCase {
    private var defs: Definitions!

    override func setUpWithError() throws {
        defs = try Definitions.load()
    }

    // MARK: - Fixture A (project scan)

    /// Fake home that doubles as the scan root.
    private func makeFixtureA() throws -> TempTree {
        var spec: [String: TreeNode] = [
            "app1/package.json": .file(#"{"name":"app-one"}"#),
            "app1/node_modules/left-pad/index.js": .file("x"),
            "app1/.next/cache/data": .file("x"),
            "rusty/Cargo.toml": .file("[package]\nname = \"rusty\"\n"),
            "rusty/target/debug/rusty": .file("x"),
            // Bug 3: target/ without a Cargo.toml sibling must be recursed into.
            "notrust/target/inner/Cargo.toml": .file("[package]\nname = \"inner\"\n"),
            "notrust/target/inner/target/debug/inner": .file("x"),
            "py/requirements.txt": .file("requests\n"),
            "py/venv/bin/python": .file("x"),
            "py/pkg/__pycache__/mod.cpython-312.pyc": .file("x"),
            "gradleproj/build.gradle": .file("apply plugin: 'java'\n"),
            "gradleproj/build/classes/A.class": .file("x"),
            "gradleproj/.gradle/8.0/file": .file("x"),
            "gradleproj/src/build/notes.txt": .file("no build.gradle next to this build dir"),
            "linkdir": .symlink("app1"),
            ".hidden/package.json": .file(#"{"name":"hidden"}"#),
            ".hidden/node_modules/x/index.js": .file("x"),
            "Library/x/node_modules/y/index.js": .file("x"),
            "work/Library/node_modules/z/index.js": .file("x"),
            "work/Wallpapers/node_modules/w/index.js": .file("x"),
            "Thing.app/Contents/node_modules/q/index.js": .file("x"),
            "Tool.XcodeProj/node_modules/q/index.js": .file("x"),
            "caches/node_modules/c/index.js": .file("x"),
        ]
        // node_modules at depth 12: eleven directories then node_modules.
        spec["deep/d2/d3/d4/d5/d6/d7/d8/d9/d10/d11/node_modules/pkg/index.js"] = .file("x")
        return try TempTree(spec)
    }

    private func scan(_ tree: TempTree, includeHidden: Bool = false, maxDepth: Int? = nil,
                      extraSkip: Set<URL> = []) -> ScanResult {
        var rules = defs.scan
        if let maxDepth {
            rules = ScanRules(maxDepth: maxDepth, skipUnderHome: rules.skipUnderHome,
                              skipAnywhere: rules.skipAnywhere, skipPackageExtensions: rules.skipPackageExtensions)
        }
        return Scanner().scan(
            root: tree.root, types: defs.projectTypes, rules: rules, includeHidden: includeHidden,
            home: tree.root, extraSkipPaths: extraSkip, onProgress: { _ in }, onFound: { _, _, _ in })
    }

    private func pairs(_ result: ScanResult, _ tree: TempTree) -> Set<String> {
        Set(result.found.map { tree.relative($0.url) + " " + $0.typeId })
    }

    private let expectedA: Set<String> = [
        "app1/node_modules node",
        "app1/.next next",
        "rusty/target rust",
        "notrust/target/inner/target rust",
        "py/venv pythonvenv",
        "py/pkg/__pycache__ pycache",
        "gradleproj/build gradle",
        "gradleproj/.gradle gradlecache",
        "work/Library/node_modules node",
        "caches/node_modules node",
    ]

    func testFixtureAExactMatches() throws {
        let tree = try makeFixtureA()
        let result = scan(tree)
        XCTAssertEqual(pairs(result, tree), expectedA)
        XCTAssertEqual(result.deniedCount, 0)
        XCTAssertGreaterThan(result.scannedCount, 10)
    }

    func testSymlinksAndPackageContentsAreNeverReported() throws {
        let tree = try makeFixtureA()
        let found = pairs(scan(tree, includeHidden: true, maxDepth: 20), tree)
        XCTAssertFalse(found.contains { $0.hasPrefix("linkdir") })
        XCTAssertFalse(found.contains { $0.hasPrefix("Thing.app") })
        XCTAssertFalse(found.contains { $0.hasPrefix("Tool.XcodeProj") }, "package suffix match is case-insensitive")
        XCTAssertFalse(found.contains { $0.hasPrefix("Library/") }, "skipUnderHome applies directly under home")
        XCTAssertFalse(found.contains { $0.hasPrefix("work/Wallpapers") }, "skipAnywhere applies at any depth")
    }

    func testHiddenToggle() throws {
        let tree = try makeFixtureA()
        XCTAssertFalse(pairs(scan(tree), tree).contains(".hidden/node_modules node"))
        XCTAssertEqual(pairs(scan(tree, includeHidden: true), tree), expectedA.union([".hidden/node_modules node"]))
    }

    func testDepthLimit() throws {
        let tree = try makeFixtureA()
        let deep = "deep/d2/d3/d4/d5/d6/d7/d8/d9/d10/d11/node_modules node"
        XCTAssertFalse(pairs(scan(tree), tree).contains(deep), "default maxDepth is 10")
        XCTAssertFalse(pairs(scan(tree, maxDepth: 11), tree).contains(deep))
        XCTAssertTrue(pairs(scan(tree, maxDepth: 12), tree).contains(deep), "depth maxDepth is inclusive")
        // Fixture A has no artifact directly under the root (depth 1).
        XCTAssertTrue(pairs(scan(tree, maxDepth: 1), tree).isEmpty)
        // A direct child of the root is depth 1, so maxDepth 1 still finds it.
        let shallow = try TempTree(["node_modules/x": .file("x"), "app/node_modules/x": .file("x")])
        XCTAssertEqual(pairs(scan(shallow, maxDepth: 1), shallow), ["node_modules node"])
        XCTAssertEqual(pairs(scan(shallow, maxDepth: 2), shallow), ["node_modules node", "app/node_modules node"])
    }

    func testExtraSkipPathsAreNeverEntered() throws {
        let tree = try makeFixtureA()
        let found = pairs(scan(tree, extraSkip: [tree.url("caches")]), tree)
        XCTAssertEqual(found, expectedA.subtracting(["caches/node_modules node"]))
    }

    func testOnlySelectedTypesAreMatched() throws {
        let tree = try makeFixtureA()
        let rust = defs.projectTypes.filter { $0.id == "rust" }
        let result = Scanner().scan(
            root: tree.root, types: rust, rules: defs.scan, includeHidden: false, home: tree.root,
            extraSkipPaths: [], onProgress: { _ in }, onFound: { _, _, _ in })
        XCTAssertEqual(pairs(result, tree), ["rusty/target rust", "notrust/target/inner/target rust"])
    }

    func testOnFoundReportsRunningCount() throws {
        let tree = try makeFixtureA()
        var counts: [Int] = []
        let result = Scanner().scan(
            root: tree.root, types: defs.projectTypes, rules: defs.scan, includeHidden: false,
            home: tree.root, extraSkipPaths: [], onProgress: { _ in },
            onFound: { _, _, count in counts.append(count) })
        XCTAssertEqual(counts, Array(1...result.found.count))
    }

    func testUnreadableDirectoryIsCountedAsDenied() throws {
        try XCTSkipIf(isRunningAsRoot, "root can read chmod 000 directories")
        let tree = try makeFixtureA()
        try tree.add(["locked/secret/node_modules/x": .file("x")])
        tree.chmod("locked", 0o000)
        let result = scan(tree)
        XCTAssertEqual(result.deniedCount, 1)
        XCTAssertEqual(result.deniedDirectories.map { tree.relative($0) }, ["locked"])
        XCTAssertEqual(pairs(result, tree), expectedA)
    }

    func testCancellationReturnsPromptly() async throws {
        var spec: [String: TreeNode] = [:]
        for a in 0..<50 {
            for b in 0..<100 {
                spec["p\(a)/q\(b)"] = .dir
            }
        }
        let tree = try TempTree(spec)
        let root = tree.root
        let rules = defs.scan
        let types = defs.projectTypes
        let start = Date()
        let task = Task.detached {
            Scanner().scan(root: root, types: types, rules: rules, includeHidden: false, home: root,
                           extraSkipPaths: [], onProgress: { _ in }, onFound: { _, _, _ in })
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        task.cancel()
        let result = await task.value
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 0.5, "scan of a 5000-directory tree must stop within 500 ms of starting")
        XCTAssertLessThanOrEqual(result.scannedCount, 5051)
    }

    // MARK: - Fixture B (system and files kinds)

    private func makeFixtureB() throws -> TempTree {
        try TempTree([
            "Library/Developer/Xcode/DerivedData/Foo-abc/Build/x": .file("x"),
            "Library/Developer/Xcode/DerivedData/Bar-def/Build/x": .file("x"),
            "Library/Developer/Xcode/DerivedData/.hidden-ghi/x": .file("x"),
            "Library/Developer/Xcode/DerivedData/info.plist": .file("not a directory"),
            "Library/Developer/Xcode/DerivedData/linked": .symlink("Foo-abc"),
            "go/pkg/mod/github.com/a/b@v1/go.mod": .file("module b"),
            "custommod/cache/download/x": .file("x"),
            "gp/pkg/mod/cache/x": .file("x"),
            "Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw": .bytes(4096),
            "Downloads/Tool.dmg": .file("x"),
            "Downloads/Other.PKG": .file("x"),
            "Downloads/archive.zip": .file("x"),
            "Downloads/folder.dmg/inside": .file("x"),
            "Downloads/link.dmg": .symlink("Tool.dmg"),
        ])
    }

    private func system(_ ids: [String], _ tree: TempTree, env: [String: String] = [:]) -> Set<String> {
        let types = ids.compactMap { defs.type(id: $0) }
        return Set(Scanner().checkSystemArtifacts(types: types, definitions: defs, env: env, home: tree.root)
            .map { tree.relative($0.url) + " " + $0.typeId })
    }

    func testExpandListsAllSubdirectoriesIncludingHidden() throws {
        let tree = try makeFixtureB()
        XCTAssertEqual(system(["xcode-derived"], tree), [
            "Library/Developer/Xcode/DerivedData/Foo-abc xcode-derived",
            "Library/Developer/Xcode/DerivedData/Bar-def xcode-derived",
            "Library/Developer/Xcode/DerivedData/.hidden-ghi xcode-derived",
        ])
    }

    func testGoModCacheResolution() throws {
        let tree = try makeFixtureB()
        XCTAssertEqual(system(["go-mod-cache"], tree), ["go/pkg/mod go-mod-cache"])
        XCTAssertEqual(system(["go-mod-cache"], tree, env: ["GOMODCACHE": tree.path("custommod")]),
                       ["custommod go-mod-cache"])
        XCTAssertEqual(system(["go-mod-cache"], tree, env: ["GOPATH": tree.path("gp")]),
                       ["gp/pkg/mod go-mod-cache"])
        XCTAssertEqual(system(["go-mod-cache"], tree, env: ["GOMODCACHE": tree.path("nope")]), [])
    }

    func testMissingPathsYieldNothing() throws {
        let tree = try makeFixtureB()
        XCTAssertEqual(system(["npm-cache", "xcode-archives", "homebrew-cache"], tree), [])
    }

    func testFileArtifactMustBeARegularFile() throws {
        let tree = try makeFixtureB()
        XCTAssertEqual(system(["docker-disk-image"], tree),
                       ["Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw docker-disk-image"])
        let dirTree = try TempTree(["Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw/x": .file("x")])
        XCTAssertEqual(system(["docker-disk-image"], dirTree), [])
    }

    func testFilesKindMatchesExtensionsCaseInsensitively() throws {
        let tree = try makeFixtureB()
        XCTAssertEqual(system(["downloads-installers"], tree), [
            "Downloads/Tool.dmg downloads-installers",
            "Downloads/Other.PKG downloads-installers",
        ])
    }
}
