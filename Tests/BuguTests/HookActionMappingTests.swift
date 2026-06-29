import XCTest
@testable import Bugu

final class HookActionMappingTests: XCTestCase {

    func testSessionLifecycleMapping() {
        XCTAssertEqual(HookActionMapping.action(for: "SessionStart"), .started)
        XCTAssertEqual(HookActionMapping.action(for: "agentSpawn"), .started)
        XCTAssertEqual(HookActionMapping.action(for: "SessionEnd"), .ended)
    }

    func testCaseInsensitivity() {
        XCTAssertEqual(HookActionMapping.action(for: "sessionstart"), .started)
        XCTAssertEqual(HookActionMapping.action(for: "STOP"), .done)
    }

    func testDoneEventsAcrossClis() {
        for name in ["Stop", "afterAgent", "afterAgentResponse", "post_agent_turn"] {
            XCTAssertEqual(HookActionMapping.action(for: name), .done, "\(name) should map to .done")
        }
    }

    func testWorkingEventsAreSilent() {
        for name in ["UserPromptSubmit", "beforeSubmitPrompt", "PreToolUse", "PostToolUse", "afterFileEdit"] {
            XCTAssertEqual(HookActionMapping.action(for: name), .working, "\(name) should map to .working")
        }
    }

    func testSingleToolFailureIsNotATaskFailure() {
        // A failed tool call must not fire the interrupted cue — only a Stop-with-failure does.
        XCTAssertEqual(HookActionMapping.action(for: "PostToolUseFailure"), .working)
        XCTAssertEqual(HookActionMapping.action(for: "StopFailure"), .failed)
    }

    func testPermissionEvents() {
        XCTAssertEqual(HookActionMapping.action(for: "Notification"), .permission)
        XCTAssertEqual(HookActionMapping.action(for: "PermissionRequest"), .permission)
    }

    func testUnknownEventMapsToNil() {
        XCTAssertNil(HookActionMapping.action(for: "SomethingElse"))
        XCTAssertNil(HookActionMapping.action(for: ""))
    }

    func testSessionPhaseFromAction() {
        XCTAssertEqual(SessionPhase(.started), .running)
        XCTAssertEqual(SessionPhase(.working), .running)
        XCTAssertEqual(SessionPhase(.permission), .permission)
        XCTAssertEqual(SessionPhase(.done), .done)
        XCTAssertEqual(SessionPhase(.failed), .failed)
        XCTAssertEqual(SessionPhase(.ended), .ended)
    }
}
