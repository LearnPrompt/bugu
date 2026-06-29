import XCTest
@testable import Bugu

final class RecentSessionStoreTests: XCTestCase {

    func testFirstCaptureExtractsCwd() {
        let head = #"{"type":"session_meta","payload":{"cwd":"/Users/me/proj","id":"x"}}"#
        let cwd = RecentSessionStore.firstCapture(in: head, pattern: #""cwd"\s*:\s*"([^"]+)""#)
        XCTAssertEqual(cwd, "/Users/me/proj")
    }

    func testFirstCaptureReturnsNilWhenAbsent() {
        XCTAssertNil(RecentSessionStore.firstCapture(in: #"{"foo":"bar"}"#, pattern: #""cwd"\s*:\s*"([^"]+)""#))
    }

    func testClipCollapsesAndTruncates() {
        XCTAssertEqual(RecentSessionStore.clip("  hello \n world  "), "hello   world")
        let long = String(repeating: "a", count: 100)
        let clipped = RecentSessionStore.clip(long, max: 10)
        XCTAssertEqual(clipped.count, 11) // 10 chars + ellipsis
        XCTAssertTrue(clipped.hasSuffix("…"))
    }

    func testProjectNameFallsBackForEmptyPath() {
        let empty = RecentSession(id: "x", agent: "Codex", projectPath: "", title: "t", lastActivity: .now)
        XCTAssertEqual(empty.projectName, "—")
        let named = RecentSession(id: "y", agent: "Codex", projectPath: "/a/b/myproj", title: "t", lastActivity: .now)
        XCTAssertEqual(named.projectName, "myproj")
    }

    func testIsActiveTracksPid() {
        var s = RecentSession(id: "x", agent: "Codex", projectPath: "/a", title: "t", lastActivity: .now)
        XCTAssertFalse(s.isActive)
        s.pid = 42
        XCTAssertTrue(s.isActive)
    }
}
