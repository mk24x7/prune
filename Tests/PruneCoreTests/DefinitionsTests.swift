import XCTest
@testable import PruneCore
import PruneDefinitions

final class DefinitionsTests: XCTestCase {
    private func bundledData() throws -> Data {
        try Data(contentsOf: DefinitionsBundle.artifactsURL)
    }

    private func mutatedData(_ mutate: (inout [String: Any]) -> Void) throws -> Data {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: bundledData()) as? [String: Any])
        mutate(&root)
        return try JSONSerialization.data(withJSONObject: root)
    }

    private func mutateType(id: String, _ change: @escaping (inout [String: Any]) -> Void) throws -> Data {
        try mutatedData { root in
            var types = root["types"] as! [[String: Any]]
            let index = types.firstIndex { $0["id"] as? String == id }!
            change(&types[index])
            root["types"] = types
        }
    }

    private func assertInvalid(_ data: Data, containing fragment: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try Definitions.decode(data), file: file, line: line) { error in
            guard case DefinitionsError.invalid(let problems) = error else {
                return XCTFail("expected .invalid, got \(error)", file: file, line: line)
            }
            XCTAssertTrue(problems.contains { $0.contains(fragment) },
                          "no problem mentions \"\(fragment)\": \(problems)", file: file, line: line)
        }
    }

    func testBundledJSONLoadsAndValidates() throws {
        let defs = try Definitions.load()
        XCTAssertEqual(defs.version, 1)
        XCTAssertEqual(defs.types.count, 47, "type count is pinned so accidental deletions are caught")
        XCTAssertEqual(Set(defs.types.map(\.id)).count, defs.types.count)
        XCTAssertEqual(defs.projectTypes.count + defs.systemTypes.count + defs.filesTypes.count, 47)
        XCTAssertEqual(defs.colors.count, 12)
        XCTAssertEqual(defs.scan.maxDepth, 10)
    }

    func testViteRemoved() throws {
        let defs = try Definitions.load()
        XCTAssertNil(defs.type(id: "vite"))
        XCTAssertFalse(defs.projectTypes.contains { ($0.targets ?? []).contains(".vite") })
    }

    func testNonRegenerableTypesAreOffByDefault() throws {
        let defs = try Definitions.load()
        for id in ["xcode-archives", "android-avd", "ios-device-backups"] {
            let type = try XCTUnwrap(defs.type(id: id), id)
            XCTAssertFalse(type.defaultEnabled, id)
            XCTAssertFalse(type.regenerable, id)
            XCTAssertFalse(defs.defaultEnabledIds.contains(id), id)
        }
        for type in defs.types where !type.regenerable {
            XCTAssertFalse(type.defaultEnabled, type.id)
        }
    }

    func testProjectTypesHaveTargetsAndSystemPathsAreHomeRelative() throws {
        let defs = try Definitions.load()
        for type in defs.projectTypes {
            XCTAssertFalse((type.targets ?? []).isEmpty, type.id)
        }
        for type in defs.systemTypes {
            let path = try XCTUnwrap(type.path, type.id)
            XCTAssertTrue(path.hasPrefix("~/"), type.id)
        }
        XCTAssertEqual(defs.filesTypes.map(\.id), ["downloads-installers"])
    }

    func testUnknownKeyIsRejected() throws {
        assertInvalid(try mutateType(id: "node") { $0["colour"] = "green" }, containing: "unknown key \"colour\"")
        assertInvalid(try mutatedData { $0["extra"] = 1 }, containing: "unknown key \"extra\"")
        assertInvalid(try mutatedData { root in
            var scan = root["scan"] as! [String: Any]
            scan["depth"] = 3
            root["scan"] = scan
        }, containing: "unknown key \"depth\"")
    }

    func testEachBrokenRuleProducesSpecificMessage() throws {
        assertInvalid(try mutateType(id: "next") { $0["id"] = "node" }, containing: "duplicate id")
        assertInvalid(try mutateType(id: "node") { $0["color"] = "magenta" }, containing: "not in the colors palette")
        assertInvalid(try mutateType(id: "xcode-archives") { $0["defaultEnabled"] = true },
                      containing: "defaultEnabled must be false")
        assertInvalid(try mutateType(id: "node") { $0["path"] = "~/x" }, containing: "must not have \"path\"")
        assertInvalid(try mutateType(id: "node") { $0.removeValue(forKey: "siblings") }, containing: "requires \"siblings\"")
        assertInvalid(try mutateType(id: "node") { $0["targets"] = [String]() }, containing: "non-empty targets")
        assertInvalid(try mutateType(id: "npm-cache") { $0["targets"] = ["x"] }, containing: "must not have \"targets\"")
        assertInvalid(try mutateType(id: "npm-cache") { $0["path"] = "/tmp/npm" }, containing: "must start with ~/")
        assertInvalid(try mutateType(id: "npm-cache") { $0.removeValue(forKey: "expand") }, containing: "requires \"expand\"")
        assertInvalid(try mutateType(id: "downloads-installers") { $0["expand"] = true }, containing: "must not have \"expand\"")
        assertInvalid(try mutateType(id: "node") { $0["nameFrom"] = "derivedData" }, containing: "not valid for kind")
    }

    func testResolvedSystemURLHonoursOverridesInOrder() throws {
        let defs = try Definitions.load()
        let go = try XCTUnwrap(defs.type(id: "go-mod-cache"))
        let home = URL(fileURLWithPath: "/tmp/fakehome", isDirectory: true)

        XCTAssertEqual(
            defs.resolvedSystemURL(for: go, env: ["GOMODCACHE": "/opt/gomod", "GOPATH": "/opt/gopath"], home: home)?.path,
            "/opt/gomod")
        XCTAssertEqual(
            defs.resolvedSystemURL(for: go, env: ["GOMODCACHE": "", "GOPATH": "/opt/gopath"], home: home)?.path,
            "/opt/gopath/pkg/mod")
        XCTAssertEqual(defs.resolvedSystemURL(for: go, env: [:], home: home)?.path, "/tmp/fakehome/go/pkg/mod")

        let node = try XCTUnwrap(defs.type(id: "node"))
        XCTAssertNil(defs.resolvedSystemURL(for: node, env: [:], home: home))
        let downloads = try XCTUnwrap(defs.type(id: "downloads-installers"))
        XCTAssertEqual(defs.resolvedSystemURL(for: downloads, env: [:], home: home)?.path, "/tmp/fakehome/Downloads")
    }
}
