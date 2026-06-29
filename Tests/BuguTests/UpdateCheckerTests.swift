import XCTest
@testable import Bugu

final class UpdateCheckerTests: XCTestCase {

    func testNormalizeStripsLeadingV() {
        XCTAssertEqual(UpdateChecker.normalize("v0.2.2"), "0.2.2")
        XCTAssertEqual(UpdateChecker.normalize("V1.0.0"), "1.0.0")
        XCTAssertEqual(UpdateChecker.normalize("0.3.0"), "0.3.0")
        XCTAssertEqual(UpdateChecker.normalize("  v2.1.0 "), "2.1.0")
    }

    func testIsNewerBasic() {
        XCTAssertTrue(UpdateChecker.isNewer("0.2.3", than: "0.2.2"))
        XCTAssertTrue(UpdateChecker.isNewer("0.3.0", than: "0.2.9"))
        XCTAssertTrue(UpdateChecker.isNewer("1.0.0", than: "0.9.9"))
        XCTAssertFalse(UpdateChecker.isNewer("0.2.2", than: "0.2.2"))
        XCTAssertFalse(UpdateChecker.isNewer("0.2.1", than: "0.2.2"))
    }

    func testNumericNotLexicographic() {
        // "0.2.10" must be newer than "0.2.9" (10 > 9, not string compare).
        XCTAssertTrue(UpdateChecker.isNewer("0.2.10", than: "0.2.9"))
    }

    func testPreReleaseSuffixIgnored() {
        // A dev build of the same version is not "behind" the released one.
        XCTAssertFalse(UpdateChecker.isNewer("0.2.2", than: "0.2.2-dev"))
        XCTAssertTrue(UpdateChecker.isNewer("0.2.3", than: "0.2.2-dev"))
    }

    func testDifferingComponentCounts() {
        XCTAssertTrue(UpdateChecker.isNewer("0.2.1", than: "0.2"))
        XCTAssertFalse(UpdateChecker.isNewer("0.2", than: "0.2.0"))
    }
}
