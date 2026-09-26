import XCTest
@testable import PruneCore

final class FormatterTests: XCTestCase {
    private typealias F = PruneCore.Formatter

    func testFormatSizeUnits() {
        XCTAssertEqual(F.formatSize(0), "0.0 KB")
        XCTAssertEqual(F.formatSize(1024), "1.0 KB")
        XCTAssertEqual(F.formatSize(1_048_576), "1.0 MB")
        XCTAssertEqual(F.formatSize(1_572_864), "1.5 MB")
        XCTAssertEqual(F.formatSize(1_073_741_824), "1.0 GB")
        XCTAssertEqual(F.formatSize(5 * 1_073_741_824), "5.0 GB")
    }

    func testShortenPathReplacesHomePrefix() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(F.shortenPath(home + "/code/app"), "~/code/app")
        XCTAssertEqual(F.shortenPath("/usr/local/bin"), "/usr/local/bin")
    }

    func testFormatAge() {
        let day: TimeInterval = 86400
        XCTAssertEqual(F.formatAge(Date()), "today")
        XCTAssertEqual(F.formatAge(Date(timeIntervalSinceNow: -1 * day - 60)), "1 day ago")
        XCTAssertEqual(F.formatAge(Date(timeIntervalSinceNow: -3 * day - 60)), "3 days ago")
        XCTAssertEqual(F.formatAge(Date(timeIntervalSinceNow: -14 * day - 60)), "2 weeks ago")
        XCTAssertEqual(F.formatAge(Date(timeIntervalSinceNow: -61 * day)), "2 months ago")
        XCTAssertEqual(F.formatAge(Date(timeIntervalSinceNow: -400 * day)), "1 year ago")
    }

    func testSizeSeverityThresholds() {
        let mib: Int64 = 1_048_576
        XCTAssertEqual(F.sizeSeverity(10 * mib), .small)
        XCTAssertEqual(F.sizeSeverity(100 * mib), .small)
        XCTAssertEqual(F.sizeSeverity(100 * mib + 1), .medium)
        XCTAssertEqual(F.sizeSeverity(500 * mib), .medium)
        XCTAssertEqual(F.sizeSeverity(500 * mib + 1), .large)
    }
}
