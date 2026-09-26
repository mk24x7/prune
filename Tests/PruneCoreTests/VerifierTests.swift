import XCTest
@testable import PruneCore

final class VerifierTests: XCTestCase {
    private var defs: Definitions!

    override func setUpWithError() throws {
        defs = try Definitions.load()
    }

    private func entry(_ url: URL, _ typeId: String) -> ArtifactEntry {
        ArtifactEntry(url: url, typeId: typeId, projectName: "x", sizeBytes: 0, lastModified: Date())
    }

    private func verify(_ url: URL, _ typeId: String, root: URL, home: URL, env: [String: String] = [:]) throws {
        let type = try XCTUnwrap(defs.type(id: typeId))
        try Verifier.verify(entry: entry(url, typeId), type: type, scanRoot: root, definitions: defs,
                            env: env, home: home)
    }

    private func assertRejected(_ url: URL, _ typeId: String, root: URL, home: URL, env: [String: String] = [:],
                                _ fragment: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try verify(url, typeId, root: root, home: home, env: env), file: file, line: line) { error in
            guard case DeletionFailure.verification(let reason) = error else {
                return XCTFail("expected verification failure, got \(error)", file: file, line: line)
            }
            XCTAssertTrue(reason.contains(fragment), "\"\(reason)\" should mention \"\(fragment)\"", file: file, line: line)
        }
    }

    func testProjectArtifactPasses() throws {
        let tree = try TempTree([
            "code/app/package.json": .file("{}"),
            "code/app/node_modules/x/index.js": .file("x"),
            "code/web/next.config.js": .file(""),
            "code/web/.next/cache": .dir,
        ])
        XCTAssertNoThrow(try verify(tree.url("code/app/node_modules"), "node", root: tree.url("code"), home: tree.root))
        XCTAssertNoThrow(try verify(tree.url("code/web/.next"), "next", root: tree.url("code"), home: tree.root))
    }

    func testRejectsOutsideScanRoot() throws {
        let tree = try TempTree(["a/app/node_modules/x": .file("x"), "b/placeholder": .file("")])
        assertRejected(tree.url("a/app/node_modules"), "node", root: tree.url("b"), home: tree.root, "outside")
        // A sibling folder whose name merely starts with the root's name is still outside.
        let prefixTree = try TempTree(["code/x": .file(""), "code2/app/node_modules/x": .file("x")])
        assertRejected(prefixTree.url("code2/app/node_modules"), "node", root: prefixTree.url("code"),
                       home: prefixTree.root, "outside")
    }

    func testRejectsSymlink() throws {
        let tree = try TempTree([
            "real/stuff/x": .file("x"),
            "app/package.json": .file("{}"),
            "app/node_modules": .symlink("../real/stuff"),
        ])
        assertRejected(tree.url("app/node_modules"), "node", root: tree.root, home: tree.root, "symbolic link")
    }

    func testRejectsMissingSibling() throws {
        let tree = try TempTree(["web/.next/cache/x": .file("x"), "crate/target/debug/x": .file("x")])
        assertRejected(tree.url("web/.next"), "next", root: tree.root, home: tree.root, "any more")
        assertRejected(tree.url("crate/target"), "rust", root: tree.root, home: tree.root, "Cargo.toml")
    }

    func testRejectsWrongBasename() throws {
        let tree = try TempTree(["app/package.json": .file("{}"), "app/src/index.js": .file("x")])
        assertRejected(tree.url("app/src"), "node", root: tree.root, home: tree.root, "folder name")
    }

    func testRejectsFileWhereDirectoryExpected() throws {
        let tree = try TempTree(["app/node_modules": .file("not a dir")])
        assertRejected(tree.url("app/node_modules"), "node", root: tree.root, home: tree.root, "expected a directory")
    }

    func testSystemPathRules() throws {
        let tree = try TempTree([
            ".npm/_cacache/x": .file("x"),
            ".npm2/x": .file("x"),
            "Library/Developer/Xcode/DerivedData/Foo-abc/Build/x": .file("x"),
            "gomod/cache/x": .file("x"),
        ])
        let home = tree.root
        XCTAssertNoThrow(try verify(tree.url(".npm"), "npm-cache", root: home, home: home))
        assertRejected(tree.url(".npm2"), "npm-cache", root: home, home: home, "location")
        assertRejected(tree.url(".npm/_cacache"), "npm-cache", root: home, home: home, "location")

        let dd = "Library/Developer/Xcode/DerivedData"
        XCTAssertNoThrow(try verify(tree.url(dd + "/Foo-abc"), "xcode-derived", root: home, home: home))
        XCTAssertNoThrow(try verify(tree.url(dd), "xcode-derived", root: home, home: home))
        assertRejected(tree.url(dd + "/Foo-abc/Build"), "xcode-derived", root: home, home: home, "location")

        XCTAssertNoThrow(try verify(tree.url("gomod"), "go-mod-cache", root: home, home: home,
                                    env: ["GOMODCACHE": tree.path("gomod")]))
        assertRejected(tree.url("gomod"), "go-mod-cache", root: home, home: home, "location")
    }

    func testRejectsHomeAndShallowPaths() throws {
        let tree = try TempTree(["Library/Developer/Xcode/DerivedData/x": .file("x")])
        // Pretend DerivedData's parent chain resolves such that home itself is the candidate.
        assertRejected(tree.root, "xcode-derived", root: tree.root, home: tree.root, "home")
        assertRejected(URL(fileURLWithPath: "/"), "xcode-derived", root: tree.root, home: tree.root, "root")
        assertRejected(URL(fileURLWithPath: "/tmp/node_modules"), "node", root: URL(fileURLWithPath: "/tmp"),
                       home: tree.root, "root")
    }

    func testFileAndFilesKinds() throws {
        let raw = "Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"
        let tree = try TempTree([
            raw: .bytes(16),
            "Downloads/Tool.DMG": .file("x"),
            "Downloads/notes.zip": .file("x"),
            "Downloads/sub/Nested.dmg": .file("x"),
            "Downloads/Folder.pkg/x": .file("x"),
        ])
        let home = tree.root
        XCTAssertNoThrow(try verify(tree.url(raw), "docker-disk-image", root: home, home: home))
        XCTAssertNoThrow(try verify(tree.url("Downloads/Tool.DMG"), "downloads-installers", root: home, home: home))
        assertRejected(tree.url("Downloads/notes.zip"), "downloads-installers", root: home, home: home, "extension")
        assertRejected(tree.url("Downloads/sub/Nested.dmg"), "downloads-installers", root: home, home: home, "directly inside")
        assertRejected(tree.url("Downloads/Folder.pkg"), "downloads-installers", root: home, home: home, "expected a file")

        let dirTree = try TempTree([raw + "/inner": .file("x")])
        assertRejected(dirTree.url(raw), "docker-disk-image", root: dirTree.root, home: dirTree.root, "expected a file")
    }

    func testRejectsTypeMismatch() throws {
        let tree = try TempTree(["app/node_modules/x": .file("x")])
        let type = try XCTUnwrap(defs.type(id: "rust"))
        XCTAssertThrowsError(try Verifier.verify(entry: entry(tree.url("app/node_modules"), "node"), type: type,
                                                 scanRoot: tree.root, definitions: defs, env: [:], home: tree.root))
    }
}
