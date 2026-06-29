import XCTest
@testable import Bugu

final class AgentProcessScannerTests: XCTestCase {

    // MARK: parseLine

    func testParseLineSplitsPidTtyCommand() {
        let parsed = AgentProcessScanner.parseLine("  1234 ttys001 node /usr/bin/claude --foo bar")
        XCTAssertEqual(parsed?.pid, 1234)
        XCTAssertEqual(parsed?.tty, "ttys001")
        XCTAssertEqual(parsed?.command, "node /usr/bin/claude --foo bar")
    }

    func testParseLineTreatsDoubleQuestionAsNoTTY() {
        let parsed = AgentProcessScanner.parseLine("987 ?? /Applications/Claude.app/Contents/MacOS/claude")
        XCTAssertEqual(parsed?.pid, 987)
        XCTAssertNil(parsed?.tty)
    }

    func testParseLineRejectsGarbage() {
        XCTAssertNil(AgentProcessScanner.parseLine("not a process line"))
        XCTAssertNil(AgentProcessScanner.parseLine(""))
    }

    // MARK: matchedAgentName

    func testMatchesKnownAgents() {
        XCTAssertEqual(AgentProcessScanner.matchedAgentName(command: "node /opt/homebrew/bin/claude"), "Claude Code")
        XCTAssertEqual(AgentProcessScanner.matchedAgentName(command: "/usr/local/bin/codex"), "Codex")
        XCTAssertEqual(AgentProcessScanner.matchedAgentName(command: "cursor-agent --resume"), "Cursor Agent")
    }

    func testWordBoundaryAvoidsSubstringFalsePositives() {
        // "amp" must not match inside an unrelated word.
        XCTAssertNil(AgentProcessScanner.matchedAgentName(command: "/usr/bin/example-tool run"))
        XCTAssertNil(AgentProcessScanner.matchedAgentName(command: "stamping-service"))
    }

    func testUnknownCommandHasNoMatch() {
        XCTAssertNil(AgentProcessScanner.matchedAgentName(command: "/usr/sbin/cron"))
    }

    // MARK: shouldIgnore

    func testIgnoresOwnAndHelperProcesses() {
        XCTAssertTrue(AgentProcessScanner.shouldIgnore(command: "/Applications/Bugu.app/Contents/MacOS/CodeBeacon"))
        XCTAssertTrue(AgentProcessScanner.shouldIgnore(command: "/Applications/Claude.app/Contents/Frameworks/helper"))
        XCTAssertTrue(AgentProcessScanner.shouldIgnore(command: "codex chronicle writer"))
    }

    func testIgnoresGooseMigrationToolButNotGooseAgent() {
        XCTAssertTrue(AgentProcessScanner.shouldIgnore(command: "goose up -dir ./migrations"))
        XCTAssertFalse(AgentProcessScanner.shouldIgnore(command: "/opt/homebrew/bin/goose session"))
    }

    func testDoesNotIgnoreRealAgent() {
        XCTAssertFalse(AgentProcessScanner.shouldIgnore(command: "node /opt/homebrew/bin/claude"))
    }
}
