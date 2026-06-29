import Foundation
import AppKit

/// Launches or activates the terminal / editor session that hosts a running agent process.
///
/// macOS cannot jump from a PID to an exact terminal tab with 100% accuracy, so this
/// implementation degrades gracefully: it first tries to locate the tab by TTY, then by
/// window/tab title keywords, then simply activates the relevant application, and finally
/// falls back to opening Terminal.app.
enum AgentSessionLauncher {

    static func launchSession(pid: Int32, agentName: String, command: String?, projectPath: String? = nil) {
        // Ironclad rule: only ever bring forward an app that is *already running* and
        // genuinely hosts this agent. We never launch a terminal from scratch — doing
        // so was popping a blank Terminal/iTerm window whenever a session could not be
        // resolved (e.g. an agent hosted by a desktop app rather than a terminal).

        // 1. Most precise: the exact terminal tab/session owning this PID's TTY.
        //    Only queries Terminal/iTerm when they are already running.
        if focusByTTY(pid: pid) { return }

        // 2. The host terminal, read from the agent's own TERM_PROGRAM. Reliable for
        //    Warp / Ghostty / iTerm / Terminal / VS Code-family terminals.
        if let hostKind = hostTerminalKind(pid: pid) {
            // Warp / Ghostty expose no TTY→tab AppleScript API, so we match the tab by
            // the `bugu:<project>` title the hook bridge stamps onto it. Falls through
            // to a plain app activation when no tagged tab is found.
            if hostKind == .warp || hostKind == .ghostty,
               let base = projectBaseName(projectPath),
               focusTabByTitle(kind: hostKind, needle: "bugu:\(base)") { return }
            if activateIfRunning(hostKind) { return }
        }

        // 3. Catch-all: walk the agent's parent-process chain to the GUI application it
        //    descends from, and activate that. This brings up the right window whether
        //    the host is a desktop app (e.g. Claude's local agent → Claude.app) or a
        //    terminal whose env we could not read. It only ever activates an
        //    already-running ancestor, so it can never spawn a stray window.
        if activateHostGUIApp(pid: pid) { return }

        // No reliable, already-running host — do nothing rather than spawn a window.
    }

    /// Determines which terminal application hosts the agent by reading the
    /// `TERM_PROGRAM` environment variable from the agent process. Returns nil when
    /// the variable is absent (e.g. the process was launched by a GUI app rather
    /// than a terminal), in which case the caller falls back to other heuristics.
    private static func hostTerminalKind(pid: Int32) -> TerminalKind? {
        guard let term = termProgram(for: pid)?.lowercased() else { return nil }
        if term.contains("warp") { return .warp }
        if term.contains("iterm") { return .iterm }
        if term.contains("apple_terminal") { return .terminal }
        if term.contains("ghostty") { return .ghostty }
        if term.contains("vscode") || term.contains("cursor") { return .cursor }
        return nil
    }

    /// Reads the agent process's `TERM_PROGRAM` via `ps eww`, which appends the
    /// environment after the command for same-user processes.
    private static func termProgram(for pid: Int32) -> String? {
        guard let output = runProcessOutput(launchPath: "/bin/ps", arguments: ["eww", "-p", "\(pid)"]) else {
            return nil
        }
        guard let range = output.range(of: #"TERM_PROGRAM=[^\s]+"#, options: .regularExpression) else {
            return nil
        }
        let pair = output[range]
        return pair.split(separator: "=", maxSplits: 1).last.map(String.init)
    }

    // MARK: - Terminal kind detection

    private enum TerminalKind {
        case terminal, iterm, warp, ghostty, claudeCode, codex, cursor, generic

        var appName: String {
            switch self {
            case .terminal: return "Terminal"
            case .iterm: return "iTerm2"
            case .warp: return "Warp"
            case .ghostty: return "Ghostty"
            case .cursor: return "Cursor"
            default: return "Terminal"
            }
        }

        var bundleIdentifier: String {
            switch self {
            case .terminal: return "com.apple.Terminal"
            case .iterm: return "com.googlecode.iterm2"
            case .warp: return "dev.warp.Warp-Stable"
            case .ghostty: return "com.mitchellh.ghostty"
            case .cursor: return "com.todesktop.230313mzl4w4u92"
            default: return "com.apple.Terminal"
            }
        }

        init(command: String?, agentName: String) {
            let cmd = command?.lowercased() ?? ""
            let name = agentName.lowercased()

            if name.contains("claude") || cmd.contains("claude") {
                self = .claudeCode
            } else if name.contains("codex") || cmd.contains("codex") {
                self = .codex
            } else if name.contains("cursor") || cmd.contains("cursor") {
                self = .cursor
            } else if cmd.contains("warp") {
                self = .warp
            } else if cmd.contains("ghostty") {
                self = .ghostty
            } else if cmd.contains("iterm") {
                self = .iterm
            } else if cmd.contains("terminal.app") || cmd.contains("terminal") {
                self = .terminal
            } else {
                self = .generic
            }
        }
    }

    // MARK: - Activation strategies

    /// Resolves the PID's controlling TTY and focuses the matching tab/session.
    /// Tries Terminal first, then iTerm, since either may own the TTY regardless of
    /// which agent is running.
    ///
    /// IMPORTANT: we only talk to a terminal that is *already running*. Addressing an
    /// app with `tell application "X"` launches it even before any `if running` check,
    /// so without this guard, jumping to an agent in Warp would spuriously launch
    /// iTerm/Terminal just to ask them about the TTY.
    private static func focusByTTY(pid: Int32) -> Bool {
        guard let tty = tty(for: pid) else { return false }
        if isRunning(bundleID: TerminalKind.terminal.bundleIdentifier),
           runAppleScriptReturningBool(terminalTTYScript(tty: tty)) { return true }
        if isRunning(bundleID: TerminalKind.iterm.bundleIdentifier),
           runAppleScriptReturningBool(iTermTTYScript(tty: tty)) { return true }
        return false
    }

    /// Whether an app with the given bundle id is currently running. Uses
    /// NSRunningApplication so it never launches the app just to check.
    private static func isRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Activates the app for `kind` only if it is already running. Never launches it.
    private static func activateIfRunning(_ kind: TerminalKind) -> Bool {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: kind.bundleIdentifier)
        guard let app = apps.first else { return false }
        return app.activate(options: [.activateAllWindows])
    }

    /// The trailing path component of a project path (e.g. "/a/b/bugu" → "bugu"),
    /// which the bridge uses as the `bugu:<name>` terminal-title tag.
    private static func projectBaseName(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        let base = (path as NSString).lastPathComponent
        return base.isEmpty ? nil : base
    }

    /// Focuses the Warp/Ghostty tab whose title contains `needle`. These terminals
    /// don't script their tabs, but each tab's title is exposed to macOS, so we drive
    /// the app's own "Window" menu (which lists every tab/window by title) via System
    /// Events, then fall back to AXRaise on a matching window. Only ever touches an
    /// already-running app.
    private static func focusTabByTitle(kind: TerminalKind, needle: String) -> Bool {
        guard isRunning(bundleID: kind.bundleIdentifier) else { return false }
        let escaped = needle.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "System Events"
            set procs to (processes whose bundle identifier is "\(kind.bundleIdentifier)")
            if procs is {} then return false
            set proc to item 1 of procs
            set frontmost of proc to true
            -- Preferred: the Window menu lists open tabs/windows by their titles.
            try
                set winMenu to menu 1 of menu bar item "Window" of menu bar 1 of proc
                repeat with mi in menu items of winMenu
                    try
                        if name of mi contains "\(escaped)" then
                            click mi
                            return true
                        end if
                    end try
                end repeat
            end try
            -- Fallback: raise the window whose title matches.
            try
                repeat with w in windows of proc
                    if title of w contains "\(escaped)" then
                        perform action "AXRaise" of w
                        return true
                    end if
                end repeat
            end try
        end tell
        return false
        """
        return runAppleScriptReturningBool(script)
    }

    /// Walks the agent's parent-process chain and activates the first ancestor that is
    /// a regular GUI application (e.g. a CLI agent → Claude.app / Cursor / a terminal).
    /// Never launches anything; only activates an already-running ancestor.
    private static func activateHostGUIApp(pid: Int32) -> Bool {
        var current = pid
        for _ in 0..<16 {
            if let app = NSRunningApplication(processIdentifier: current),
               app.activationPolicy == .regular {
                return app.activate(options: [.activateAllWindows])
            }
            guard let parent = parentPID(of: current), parent > 1, parent != current else {
                break
            }
            current = parent
        }
        return false
    }

    /// Returns the parent PID of a process, or nil if unavailable.
    private static func parentPID(of pid: Int32) -> Int32? {
        guard let output = runProcessOutput(launchPath: "/bin/ps", arguments: ["-o", "ppid=", "-p", "\(pid)"]) else {
            return nil
        }
        return Int32(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - AppleScript builders

    private static func terminalTTYScript(tty: String) -> String {
        let fullTTY = tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
        return """
        tell application "Terminal"
            if not running then return false
            set targetTTY to "\(fullTTY)"
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        if (tty of t) is equal to targetTTY then
                            set selected of t to true
                            set frontmost of w to true
                            activate
                            return true
                        end if
                    end try
                end repeat
            end repeat
            return false
        end tell
        """
    }

    private static func iTermTTYScript(tty: String) -> String {
        // iTerm reports a session's tty as the full "/dev/ttysNNN" path, so compare
        // against the full path — the previous code stripped "/dev/" and never matched.
        let fullTTY = tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
        return """
        tell application "iTerm2"
            if not running then return false
            set targetTTY to "\(fullTTY)"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        try
                            if (tty of s as string) is equal to targetTTY then
                                select s
                                select t
                                set frontmost of w to true
                                activate
                                return true
                            end if
                        end try
                    end repeat
                end repeat
            end repeat
            return false
        end tell
        """
    }

    // MARK: - Process helpers

    /// Returns the TTY name (e.g. "ttys001") for a PID, or nil if unavailable.
    private static func tty(for pid: Int32) -> String? {
        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-o", "tty=", "-p", "\(pid)"]
        task.standardError = FileHandle.nullDevice

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let raw = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let raw = raw, !raw.isEmpty else { return nil }
            // ps prints "?" or "??" for a process with no controlling terminal.
            guard !raw.allSatisfy({ $0 == "?" }) else { return nil }

            // ps returns values like "ttys001" or occasionally just "s001".
            if raw.hasPrefix("tty") {
                return raw
            }
            return "tty\(raw)"
        } catch {
            return nil
        }
    }

    /// Runs a process and returns its stdout as a string, or nil on failure.
    private static func runProcessOutput(launchPath: String, arguments: [String]) -> String? {
        let task = Process()
        task.launchPath = launchPath
        task.arguments = arguments
        task.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    /// Executes an AppleScript and interprets its result as a boolean.
    private static func runAppleScriptReturningBool(_ source: String) -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-"]

        let input = source.data(using: .utf8) ?? Data()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        task.standardInput = inputPipe
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        do {
            try task.run()
            inputPipe.fileHandleForWriting.write(input)
            inputPipe.fileHandleForWriting.closeFile()
            task.waitUntilExit()

            guard task.terminationStatus == 0 else { return false }

            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return output == "true"
        } catch {
            return false
        }
    }
}
