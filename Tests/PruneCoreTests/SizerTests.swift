import XCTest
@testable import PruneCore

final class SizerTests: XCTestCase {
    private var defs: Definitions!
    private let mib = 1_048_576

    override func setUpWithError() throws {
        defs = try Definitions.load()
    }

    private func type(_ id: String) throws -> ArtifactType {
        try XCTUnwrap(defs.type(id: id), id)
    }

    // MARK: - Sizes

    func testDiskSizeCountsAllFiles() async throws {
        let tree = try TempTree([
            "art/a.bin": .bytes(mib / 2),
            "art/b.bin": .bytes(mib / 2),
            "art/sub/c.bin": .bytes(mib / 2),
            "art/sub/deeper/d.bin": .bytes(mib / 2),
        ])
        let size = await Sizer.diskSize(at: tree.url("art"))
        let bytes = try XCTUnwrap(size)
        XCTAssertGreaterThanOrEqual(bytes, Int64(2 * mib))
    }

    func testUnreadableSubdirectoryStillSized() async throws {
        try XCTSkipIf(isRunningAsRoot, "root can read chmod 000 directories")
        let tree = try TempTree([
            "art/readable.bin": .bytes(mib),
            "art/locked/hidden.bin": .bytes(mib),
        ])
        tree.chmod("art/locked", 0o000)
        let size = await Sizer.diskSize(at: tree.url("art"))
        let bytes = try XCTUnwrap(size, "du exits non-zero here but its total must still be used")
        XCTAssertGreaterThanOrEqual(bytes, Int64(mib))
    }

    func testCancelledSizingIsUnknown() async throws {
        let tree = try TempTree(["art/a.bin": .bytes(1024)])
        let url = tree.url("art")
        let task = Task { () -> Int64? in
            withUnsafeCurrentTask { $0?.cancel() }
            return await Sizer.diskSize(at: url)
        }
        let size = await task.value
        XCTAssertNil(size)
    }

    func testFileEntriesUseAttributes() async throws {
        let tree = try TempTree(["Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw": .bytes(mib)])
        let entry = await Sizer.buildEntry(
            for: tree.url("Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"),
            type: try type("docker-disk-image"))
        XCTAssertFalse(entry.sizeUnknown)
        XCTAssertGreaterThanOrEqual(entry.sizeBytes, Int64(mib))
        XCTAssertEqual(entry.projectName, "Docker.raw")
    }

    func testSparseFileUsesAllocatedSize() throws {
        let tree = try TempTree(["Docker.raw": .bytes(4096)])
        let handle = try FileHandle(forWritingTo: tree.url("Docker.raw"))
        try handle.truncate(atOffset: UInt64(1 << 30))   // 1 GiB apparent, a few KiB allocated
        try handle.close()
        let size = try XCTUnwrap(Sizer.fileSize(at: tree.url("Docker.raw")))
        XCTAssertLessThan(size, Int64(mib), "apparent size must not be reported for sparse files")
        XCTAssertGreaterThanOrEqual(size, 4096)
    }

    func testBuildEntryForDirectory() async throws {
        let tree = try TempTree([
            "web/package.json": .file(#"{"name":"web-app"}"#),
            "web/node_modules/x/index.js": .bytes(64 * 1024),
        ])
        let entry = await Sizer.buildEntry(for: tree.url("web/node_modules"), type: try type("node"))
        XCTAssertEqual(entry.typeId, "node")
        XCTAssertEqual(entry.projectName, "web-app")
        XCTAssertFalse(entry.sizeUnknown)
        XCTAssertGreaterThanOrEqual(entry.sizeBytes, 64 * 1024)
        XCTAssertEqual(entry.countedBytes, entry.sizeBytes)
    }

    func testUnknownSizeIsExcludedFromTotals() {
        let entry = ArtifactEntry(url: URL(fileURLWithPath: "/tmp/x"), typeId: "node", projectName: "x",
                                  sizeBytes: 0, sizeUnknown: true, lastModified: Date())
        XCTAssertEqual(entry.formattedSize, "?")
        XCTAssertEqual(entry.countedBytes, 0)
    }

    // MARK: - nameFrom strategies

    private func name(_ typeId: String, artifact: String, files: [String: TreeNode]) throws -> String {
        var spec = files
        spec[artifact + "/placeholder"] = .file("x")
        let tree = try TempTree(spec)
        return Sizer.projectName(for: tree.url(artifact), type: try type(typeId))
    }

    func testPackageJsonName() throws {
        XCTAssertEqual(try name("node", artifact: "proj/node_modules",
                                files: ["proj/package.json": .file(#"{"name": "@scope/web"}"#)]), "@scope/web")
        XCTAssertEqual(try name("node", artifact: "proj/node_modules",
                                files: ["proj/package.json": .file("{ not json")]), "proj")
        XCTAssertEqual(try name("node", artifact: "proj/node_modules",
                                files: ["proj/package.json": .file(#"{"name": 42}"#)]), "proj")
        XCTAssertEqual(try name("node", artifact: "proj/node_modules", files: [:]), "proj")
    }

    func testCargoTomlName() throws {
        let good = "[workspace]\nname = \"not-this\"\n\n[package]\nversion = \"0.1.0\"\nname = \"crab\"\n"
        XCTAssertEqual(try name("rust", artifact: "r/target", files: ["r/Cargo.toml": .file(good)]), "crab")
        XCTAssertEqual(try name("rust", artifact: "r/target",
                                files: ["r/Cargo.toml": .file("[workspace]\nmembers = [\"a\"]\n")]), "r")
        XCTAssertEqual(try name("rust", artifact: "r/target",
                                files: ["r/Cargo.toml": .file("[package]\nname = crab\n")]), "r")
    }

    func testPackageSwiftName() throws {
        let good = "// swift-tools-version: 5.9\nlet package = Package(\n    name: \"Tool\",\n    targets: [.target(name: \"Other\")]\n)\n"
        XCTAssertEqual(try name("swiftpm", artifact: "s/.build", files: ["s/Package.swift": .file(good)]), "Tool")
        XCTAssertEqual(try name("swiftpm", artifact: "s/.build",
                                files: ["s/Package.swift": .file("let package = Package(targets: [])")]), "s")
    }

    func testGradleSettingsName() throws {
        XCTAssertEqual(try name("gradle", artifact: "g/build",
                                files: ["g/settings.gradle": .file("rootProject.name = 'droid'\n")]), "droid")
        XCTAssertEqual(try name("gradle", artifact: "g/build",
                                files: ["g/settings.gradle.kts": .file("rootProject.name = \"kts-app\"\n")]), "kts-app")
        XCTAssertEqual(try name("gradle", artifact: "g/build",
                                files: ["g/settings.gradle": .file("include ':app'\n")]), "g")
    }

    func testDerivedDataDirnameAndParentDirname() throws {
        XCTAssertEqual(try name("xcode-derived", artifact: "DD/My-App-abcdef123", files: [:]), "My-App")
        XCTAssertEqual(try name("xcode-derived", artifact: "DD/NoHash", files: [:]), "NoHash")
        XCTAssertEqual(try name("xcode-device-support", artifact: "DS/iPhone15,2 17.0", files: [:]), "iPhone15,2 17.0")
        XCTAssertEqual(try name("pycache", artifact: "pkg/__pycache__", files: [:]), "pkg")
    }

    // MARK: - lastModified

    func testLastModifiedReflectsTouchedChild() throws {
        let tree = try TempTree(["art/old.txt": .file("x"), "art/child.txt": .file("y")])
        let old = Date(timeIntervalSinceNow: -90 * 86400)
        let recent = Date(timeIntervalSinceNow: -2 * 86400)
        try tree.touch("art/old.txt", date: old)
        try tree.touch("art/child.txt", date: old)
        try tree.touch("art", date: old)
        XCTAssertEqual(Sizer.lastModified(of: tree.url("art"), isFile: false).timeIntervalSince1970,
                       old.timeIntervalSince1970, accuracy: 1)
        try tree.touch("art/child.txt", date: recent)
        try tree.touch("art", date: old)
        let modified = Sizer.lastModified(of: tree.url("art"), isFile: false)
        XCTAssertEqual(modified.timeIntervalSince1970, recent.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(Sizer.lastModified(of: tree.url("art/old.txt"), isFile: true).timeIntervalSince1970,
                       old.timeIntervalSince1970, accuracy: 1)
    }
}
