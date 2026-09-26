import XCTest
@testable import PruneCore

final class DeleterTests: XCTestCase {
    private var defs: Definitions!
    private let mib = 1_048_576

    override func setUpWithError() throws {
        defs = try Definitions.load()
    }

    private func entry(_ url: URL, _ typeId: String, size: Int64 = 1024) -> ArtifactEntry {
        ArtifactEntry(url: url, typeId: typeId, projectName: url.deletingLastPathComponent().lastPathComponent,
                      sizeBytes: size, lastModified: Date())
    }

    private func deleter(_ tree: TempTree, mode: DeleteMode, log: DeletionLog? = nil,
                         trash: Deleter.TrashFunction? = nil) -> Deleter {
        Deleter(mode: mode, scanRoot: tree.root, definitions: defs, log: log, env: [:], home: tree.root, trash: trash)
    }

    private func readLines(_ log: DeletionLog) throws -> [[String: Any]] {
        let text = try String(contentsOf: log.fileURL, encoding: .utf8)
        return try text.split(separator: "\n").map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
    }

    // MARK: - Permanent

    func testPermanentRemovesNormalTree() async throws {
        let tree = try TempTree([
            "app/package.json": .file("{}"),
            "app/node_modules/a/b/c/index.js": .file("x"),
            "app/node_modules/.bin/tool": .file("x"),
        ])
        let outcomes = await deleter(tree, mode: .permanent).delete([entry(tree.url("app/node_modules"), "node")])
        XCTAssertEqual(outcomes.map(\.status), [.deleted])
        XCTAssertEqual(FileKind.of(tree.url("app/node_modules")), .missing)
        XCTAssertEqual(FileKind.of(tree.url("app/package.json")), .regularFile, "siblings are untouched")
    }

    func testPermanentRemovesReadOnlyTree() async throws {
        try XCTSkipIf(isRunningAsRoot, "root ignores permission bits")
        let tree = try TempTree([
            "gomod/github.com/a/b@v1.0.0/go.mod": .file("module b"),
            "gomod/github.com/a/b@v1.0.0/sub/x.go": .file("package sub"),
        ])
        for relative in ["gomod/github.com/a/b@v1.0.0/go.mod", "gomod/github.com/a/b@v1.0.0/sub/x.go"] {
            tree.chmod(relative, 0o444)
        }
        for relative in ["gomod/github.com/a/b@v1.0.0/sub", "gomod/github.com/a/b@v1.0.0", "gomod/github.com/a", "gomod/github.com", "gomod"] {
            tree.chmod(relative, 0o555)
        }
        // Precondition: a plain removeItem really is refused, so the retry path is exercised.
        XCTAssertThrowsError(try FileManager.default.removeItem(at: tree.url("gomod/github.com/a/b@v1.0.0/sub")))
        let deleter = Deleter(mode: .permanent, scanRoot: tree.root, definitions: defs, log: nil,
                              env: ["GOMODCACHE": tree.path("gomod")], home: tree.root)
        let outcomes = await deleter.delete([entry(tree.url("gomod"), "go-mod-cache")])
        XCTAssertEqual(outcomes.map(\.status), [.deleted])
        XCTAssertEqual(FileKind.of(tree.url("gomod")), .missing)
    }

    func testMissingItemIsAlreadyGoneSuccess() async throws {
        let tree = try TempTree(["app/package.json": .file("{}")])
        for mode in [DeleteMode.permanent, .trash] {
            let outcomes = await deleter(tree, mode: mode, trash: { _ in XCTFail("must not be called"); return nil })
                .delete([entry(tree.url("app/node_modules"), "node")])
            XCTAssertEqual(outcomes.map(\.status), [.skipped(DeletionOutcome.alreadyGone)])
            XCTAssertTrue(outcomes[0].isSuccess)
        }
    }

    func testVerificationFailureLeavesItemInPlace() async throws {
        let tree = try TempTree(["elsewhere/real/x": .file("x"), "app/node_modules": .symlink("../elsewhere/real")])
        let outcomes = await deleter(tree, mode: .permanent).delete([entry(tree.url("app/node_modules"), "node")])
        guard case .failed(.verification) = outcomes[0].status else {
            return XCTFail("expected verification failure, got \(outcomes[0].status)")
        }
        XCTAssertEqual(FileKind.of(tree.url("app/node_modules")), .symlink)
        XCTAssertEqual(FileKind.of(tree.url("elsewhere/real/x")), .regularFile)
    }

    // MARK: - Trash

    func testTrashModeRecordsDestination() async throws {
        let tree = try TempTree(["app/package.json": .file("{}"), "app/node_modules/x/index.js": .file("x"), "FakeTrash/.keep": .file("")])
        let trashDir = tree.url("FakeTrash")
        let log = DeletionLog(directory: tree.url("logs"), version: "test")
        let fakeTrash: Deleter.TrashFunction = { url in
            let destination = trashDir.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
        let outcomes = await deleter(tree, mode: .trash, log: log, trash: fakeTrash)
            .delete([entry(tree.url("app/node_modules"), "node")])
        guard case .trashed(let destination) = outcomes[0].status else {
            return XCTFail("expected trashed, got \(outcomes[0].status)")
        }
        XCTAssertEqual(destination.path, trashDir.appendingPathComponent("node_modules").path)
        XCTAssertEqual(FileKind.of(tree.url("app/node_modules")), .missing)
        XCTAssertEqual(FileKind.of(tree.url("FakeTrash/node_modules/x/index.js")), .regularFile)

        let lines = try readLines(log)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0]["result"] as? String, "trashed")
        XCTAssertEqual(lines[0]["trashedTo"] as? String, trashDir.appendingPathComponent("node_modules").path)
        XCTAssertEqual(lines[0]["mode"] as? String, "trash")
    }

    func testTrashUnsupportedLeavesDirectoryInPlace() async throws {
        let tree = try TempTree(["app/package.json": .file("{}"), "app/node_modules/x/index.js": .file("x")])
        let unsupported: Deleter.TrashFunction = { _ in
            throw NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError,
                          userInfo: [NSLocalizedDescriptionKey: "The volume does not support the Trash."])
        }
        let outcomes = await deleter(tree, mode: .trash, trash: unsupported)
            .delete([entry(tree.url("app/node_modules"), "node")])
        XCTAssertTrue(outcomes[0].isTrashUnsupported)
        XCTAssertFalse(outcomes[0].isSuccess)
        XCTAssertEqual(FileKind.of(tree.url("app/node_modules/x/index.js")), .regularFile)
    }

    func testTrashENOENTIsAlreadyGone() async throws {
        let tree = try TempTree(["app/package.json": .file("{}"), "app/node_modules/x": .file("x")])
        let vanished: Deleter.TrashFunction = { _ in
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
        }
        let outcomes = await deleter(tree, mode: .trash, trash: vanished)
            .delete([entry(tree.url("app/node_modules"), "node")])
        XCTAssertEqual(outcomes.map(\.status), [.skipped(DeletionOutcome.alreadyGone)])
    }

    // MARK: - Log

    func testLogHasOneLinePerItemPlusRunLine() async throws {
        let tree = try TempTree([
            "a/package.json": .file("{}"), "a/node_modules/x": .file("x"),
            "b/Cargo.toml": .file("[package]\nname=\"b\"\n"), "b/target/x": .file("x"),
            "c/src/x": .file("x"),
        ])
        let log = DeletionLog(directory: tree.url("logs"), version: "9.9.9")
        let entries = [
            entry(tree.url("a/node_modules"), "node", size: 100),
            entry(tree.url("b/target"), "rust", size: 200),
            entry(tree.url("c/src"), "node", size: 300),
        ]
        let outcomes = await deleter(tree, mode: .permanent, log: log).delete(entries)
        let ok = outcomes.filter(\.isSuccess).count
        log.recordRun(scanRoot: tree.root, selected: entries.count, ok: ok, failed: entries.count - ok,
                      estimatedBytes: 600, measuredFreedBytes: 0)

        let lines = try readLines(log)
        XCTAssertEqual(lines.count, entries.count + 1)
        let items = lines.filter { $0["event"] == nil }
        XCTAssertEqual(items.count, 3)
        for item in items {
            XCTAssertEqual(item["tool"] as? String, "app")
            XCTAssertEqual(item["version"] as? String, "9.9.9")
            XCTAssertEqual(item["mode"] as? String, "permanent")
            XCTAssertNotNil(item["ts"] as? String)
            XCTAssertNotNil(item["path"] as? String)
            XCTAssertNotNil(item["estimatedBytes"] as? Int)
        }
        XCTAssertEqual(items.map { $0["result"] as? String }, ["deleted", "deleted", "failed"])
        XCTAssertNotNil(items[2]["error"] as? String)
        XCTAssertEqual(items[1]["typeId"] as? String, "rust")

        let run = try XCTUnwrap(lines.last)
        XCTAssertEqual(run["event"] as? String, "run")
        XCTAssertEqual(run["selected"] as? Int, 3)
        XCTAssertEqual(run["ok"] as? Int, 2)
        XCTAssertEqual(run["failed"] as? Int, 1)
        XCTAssertEqual(run["estimatedBytes"] as? Int, 600)
        XCTAssertEqual(run["measuredFreedBytes"] as? Int, 0)
        XCTAssertEqual(run["scanRoot"] as? String, tree.root.path)
    }

    func testLogDirectoryOverrideAndRotation() throws {
        let tree = try TempTree(["logs/deletions.jsonl": .bytes(Int(DeletionLog.rotateBytes))])
        XCTAssertEqual(DeletionLog.defaultDirectory(env: ["PRUNE_LOG_DIR": tree.path("logs")], home: tree.root).path,
                       tree.path("logs"))
        XCTAssertEqual(DeletionLog.defaultDirectory(env: [:], home: tree.root).path,
                       tree.path("Library/Logs/Prune"))

        let log = DeletionLog(version: "t", env: ["PRUNE_LOG_DIR": tree.path("logs")], home: tree.root)
        log.recordRun(scanRoot: tree.root, selected: 0, ok: 0, failed: 0, estimatedBytes: 0, measuredFreedBytes: 0)
        let files = try FileManager.default.contentsOfDirectory(atPath: tree.path("logs")).sorted()
        XCTAssertEqual(files.count, 2, "\(files)")
        XCTAssertTrue(files.contains("deletions.jsonl"))
        XCTAssertTrue(files.contains { $0.hasPrefix("deletions-") && $0.hasSuffix(".jsonl") })
        XCTAssertEqual(try readLines(log).count, 1)
    }

    // MARK: - Disk space

    func testMeasuredFreedSpaceForPermanentDeletion() async throws {
        var spec: [String: TreeNode] = ["app/package.json": .file("{}")]
        for i in 0..<20 { spec["app/node_modules/blob\(i).bin"] = .bytes(mib) }
        let tree = try TempTree(spec)
        let url = tree.url("app/node_modules")
        let before = DiskSpace.snapshot(for: [url])
        XCTAssertEqual(before.available.count, 1)
        let outcomes = await deleter(tree, mode: .permanent).delete([entry(url, "node", size: Int64(20 * mib))])
        XCTAssertEqual(outcomes.map(\.status), [.deleted])
        let after = DiskSpace.snapshot(matching: before)
        let freed = DiskSpace.freedBytes(before: before, after: after)
        XCTAssertGreaterThanOrEqual(freed, 0)
        XCTAssertGreaterThanOrEqual(freed, Int64(10 * mib), "expected at least 10 MiB back, measured \(freed)")
    }

    func testFreedBytesClampsNegativeDeltas() {
        let before = DiskSpace.Snapshot(available: ["/a": 100, "/b": 500])
        let after = DiskSpace.Snapshot(available: ["/a": 300, "/b": 400])
        XCTAssertEqual(DiskSpace.freedBytes(before: before, after: after), 200)
    }

    // MARK: - Real Trash (opt-in)

    func testRealTrashIntegration() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PRUNE_TEST_REAL_TRASH"] == "1",
                          "set PRUNE_TEST_REAL_TRASH=1 to move a fixture into the real Trash")
        let tree = try TempTree(["app/package.json": .file("{}"), "app/node_modules/x/index.js": .file("x")])
        let outcomes = await deleter(tree, mode: .trash).delete([entry(tree.url("app/node_modules"), "node")])
        guard case .trashed(let destination) = outcomes[0].status else {
            return XCTFail("expected trashed, got \(outcomes[0].status)")
        }
        XCTAssertEqual(FileKind.of(tree.url("app/node_modules")), .missing)
        XCTAssertEqual(FileKind.of(destination), .directory)
        try? FileManager.default.removeItem(at: destination)
    }
}
