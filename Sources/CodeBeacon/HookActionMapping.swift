import Foundation

/// The canonical action a hook event maps to, normalised across every CLI's own
/// event-name vocabulary (Claude's SessionStart/Stop, Cursor's
/// afterAgentResponse/stop, Mistral's post_agent_turn, Kiro's agentSpawn, …).
enum HookAction: Equatable {
    case started, working, done, failed, permission, ended
}

/// Maps a raw hook event name to a `HookAction`. Pure and side-effect free so it can
/// be unit-tested independently of the app's state machine.
enum HookActionMapping {
    static func action(for eventName: String) -> HookAction? {
        switch eventName.lowercased() {
        case "sessionstart", "agentspawn":
            return .started
        case "userpromptsubmit", "beforesubmitprompt", "pretooluse", "posttooluse",
             "before_tool", "after_tool", "afteragentthought", "afterfileedit",
             "aftershellexecution", "aftermcpexecution",
             // A single failed tool call is not a failed *task*: treat it as ongoing
             // work (no sound) rather than firing the interrupted cue every time a
             // grep returns non-zero.
             "posttoolusefailure":
            return .working
        case "stop", "afteragent", "afteragentresponse", "post_agent_turn":
            return .done
        case "stopfailure":
            return .failed
        case "notification", "permissionrequest":
            return .permission
        case "sessionend":
            return .ended
        default:
            return nil
        }
    }
}
