import Foundation

/// Hook-based integration with coding-agent CLIs. A tiny bridge script is registered
/// as a hook in each CLI's config and forwards every event (with an explicit
/// `--event` name) to Bugu via a watched event file — giving instant, accurate
/// session state without `ps` polling. Modelled on the managed-block approach that
/// tools like Vibe Island use; adapter formats were derived from real installed
/// configs across the supported CLIs.
///
/// Guarantees: the bridge never blocks the agent (always exits 0); config edits are
/// idempotent, backed up first, and removed on uninstall.
enum HookIntegration {

    static let baseDir = NSHomeDirectory() + "/.bugu"
    static let binDir = baseDir + "/bin"
    static let bridgePath = binDir + "/bugu-bridge"
    static let eventsPath = baseDir + "/events.jsonl"

    /// How a given CLI stores its hooks.
    enum Engine {
        case jsonSettingsHooks    // merge into the `hooks` object of a settings.json
        case jsonStandaloneHooks  // a dedicated file whose root is { "hooks": { … } }
        case jsonCursorFlat       // { "hooks": { event: [ { command } ] }, version: 1 }
        case kiroAgent            // a self-contained Kiro agent JSON file we own
        case tomlEvent            // [[hooks]] with event = / command = / timeout =
        case tomlTyped            // [[hooks]] with name = / type = / command = / timeout =
    }

    struct CLI: Identifiable {
        let id: String
        let name: String
        let source: String
        let engine: Engine
        let configPath: String
        /// Native event names to register (canonicalised later by the watcher).
        let events: [String]

        var isAvailable: Bool {
            let fm = FileManager.default
            if fm.fileExists(atPath: configPath) { return true }
            let parent = (configPath as NSString).deletingLastPathComponent
            return fm.fileExists(atPath: parent)
        }
    }

    private static func home(_ p: String) -> String { NSHomeDirectory() + p }

    /// Claude-style event set (used by most settings.json / hooks.json CLIs).
    private static let claudeEvents = [
        "SessionStart", "UserPromptSubmit", "Notification",
        "PermissionRequest", "Stop", "StopFailure", "SubagentStop", "SessionEnd"
    ]

    /// The full roster Bugu can install hooks for, with formats verified against
    /// real installed configs. (OpenCode / Hermes / Pi Agent are detected by the
    /// poller but have no verified hook format yet, so they are omitted here.)
    static let supportedCLIs: [CLI] = [
        CLI(id: "claudecode", name: "Claude Code", source: "claudecode", engine: .jsonSettingsHooks,
            configPath: home("/.claude/settings.json"), events: claudeEvents),
        CLI(id: "codex", name: "Codex", source: "codex", engine: .jsonStandaloneHooks,
            configPath: home("/.codex/hooks.json"),
            events: ["SessionStart", "UserPromptSubmit", "PermissionRequest", "Stop"]),
        CLI(id: "gemini", name: "Gemini CLI", source: "gemini", engine: .jsonSettingsHooks,
            configPath: home("/.gemini/settings.json"),
            events: ["SessionStart", "AfterAgent", "Notification", "SessionEnd"]),
        CLI(id: "cursor", name: "Cursor Agent", source: "cursor", engine: .jsonCursorFlat,
            configPath: home("/.cursor/hooks.json"),
            events: ["beforeSubmitPrompt", "afterAgentResponse", "stop"]),
        CLI(id: "trae", name: "Trae", source: "trae", engine: .jsonStandaloneHooks,
            configPath: home("/.trae/hooks.json"),
            events: ["SessionStart", "UserPromptSubmit", "Notification", "Stop"]),
        CLI(id: "droid", name: "Droid", source: "droid", engine: .jsonSettingsHooks,
            configPath: home("/.factory/settings.json"),
            events: ["SessionStart", "UserPromptSubmit", "Notification", "Stop", "SessionEnd"]),
        CLI(id: "qoder", name: "Qoder", source: "qoder", engine: .jsonSettingsHooks,
            configPath: home("/.qoder/settings.json"), events: claudeEvents),
        CLI(id: "qwen", name: "Qwen", source: "qwen", engine: .jsonSettingsHooks,
            configPath: home("/.qwen/settings.json"), events: claudeEvents),
        CLI(id: "kimi", name: "Kimi", source: "kimi", engine: .tomlEvent,
            configPath: home("/.kimi/config.toml"),
            events: ["SessionStart", "UserPromptSubmit", "Notification", "PermissionRequest", "Stop", "SessionEnd"]),
        CLI(id: "kimicode", name: "Kimi Code", source: "kimicode", engine: .tomlEvent,
            configPath: home("/.kimi-code/config.toml"),
            events: ["SessionStart", "UserPromptSubmit", "Notification", "PermissionRequest", "Stop", "SessionEnd"]),
        CLI(id: "mistralvibe", name: "Mistral Vibe", source: "mistralvibe", engine: .tomlTyped,
            configPath: home("/.vibe/hooks.toml"),
            events: ["post_agent_turn", "after_tool"]),
        CLI(id: "codebuddy", name: "CodeBuddy", source: "codebuddy", engine: .jsonSettingsHooks,
            configPath: home("/.codebuddy/settings.json"), events: claudeEvents),
        CLI(id: "workbuddy", name: "WorkBuddy", source: "workbuddy", engine: .jsonSettingsHooks,
            configPath: home("/.workbuddy/settings.json"), events: claudeEvents),
        CLI(id: "kiro", name: "Kiro CLI", source: "kiro", engine: .kiroAgent,
            configPath: home("/.kiro/agents/bugu.json"),
            events: ["agentSpawn", "userPromptSubmit", "stop"])
    ]

    private static let blockStart = "# --- bugu hooks START (managed, do not edit) ---"
    private static let blockEnd = "# --- bugu hooks END ---"

    private static func command(for cli: CLI, event: String) -> String {
        "\(bridgePath) --source \(cli.source) --event \(event)"
    }

    // MARK: - Bridge deployment

    @discardableResult
    static func deployBridge() -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: binDir, withIntermediateDirectories: true)
        do {
            try bridgeScript.write(toFile: bridgePath, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bridgePath)
            return true
        } catch {
            return false
        }
    }

    /// The bridge: records source + event + tty + payload to the event file, and
    /// tags the terminal with the project name so Warp/Ghostty jumps can match it.
    private static let bridgeScript = """
    #!/bin/sh
    # Bugu hook bridge — forwards a coding-agent hook event to the Bugu app.
    # Safe by design: never blocks the agent, always exits 0.
    DIR="$HOME/.bugu"
    mkdir -p "$DIR" 2>/dev/null
    SRC="unknown"
    EV="unknown"
    while [ $# -gt 0 ]; do
      case "$1" in
        --source) SRC="$2"; shift 2 ;;
        --event) EV="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    PAYLOAD=$(cat 2>/dev/null | tr -d '\\n\\r')
    case "$PAYLOAD" in
      \\{*) : ;;
      *) PAYLOAD="null" ;;
    esac
    TTYV=$(tty 2>/dev/null || echo "")
    # Keep the event log bounded — trim to the last 200 lines once it grows past ~512KB.
    LOG="$DIR/events.jsonl"
    if [ -f "$LOG" ]; then
      SIZE=$(wc -c < "$LOG" 2>/dev/null || echo 0)
      if [ "$SIZE" -gt 524288 ]; then
        tail -n 200 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG" 2>/dev/null
      fi
    fi
    printf '{"ts":%s,"source":"%s","event":"%s","tty":"%s","payload":%s}\\n' \\
      "$(date +%s)" "$SRC" "$EV" "$TTYV" "$PAYLOAD" >> "$LOG" 2>/dev/null
    # Tag the terminal tab with the project name for Warp/Ghostty jump matching.
    if [ -n "$TTYV" ] && [ "$TTYV" != "not a tty" ]; then
      CWD=$(printf '%s' "$PAYLOAD" | sed -n 's/.*"cwd":"\\([^"]*\\)".*/\\1/p')
      BASE=$(basename "$CWD" 2>/dev/null)
      if [ -n "$BASE" ]; then
        printf '\\033]0;bugu:%s\\007' "$BASE" > "$TTYV" 2>/dev/null || true
      fi
    fi
    exit 0
    """

    // MARK: - Status / install / uninstall

    static func isInstalled(_ cli: CLI) -> Bool {
        guard let text = try? String(contentsOfFile: cli.configPath, encoding: .utf8) else {
            return false
        }
        return text.contains("bugu-bridge")
    }

    @discardableResult
    static func install(_ cli: CLI) -> Bool {
        deployBridge()
        switch cli.engine {
        case .jsonSettingsHooks: return installJSONHooks(cli, standalone: false)
        case .jsonStandaloneHooks: return installJSONHooks(cli, standalone: true)
        case .jsonCursorFlat: return installCursorFlat(cli)
        case .kiroAgent: return installKiroAgent(cli)
        case .tomlEvent: return installTOML(cli, typed: false)
        case .tomlTyped: return installTOML(cli, typed: true)
        }
    }

    @discardableResult
    static func uninstall(_ cli: CLI) -> Bool {
        switch cli.engine {
        case .jsonSettingsHooks: return uninstallJSONHooks(cli)
        case .jsonStandaloneHooks: return uninstallJSONHooks(cli)
        case .jsonCursorFlat: return uninstallJSONHooks(cli)
        case .kiroAgent: return uninstallKiroAgent(cli)
        case .tomlEvent, .tomlTyped: return uninstallTOML(cli)
        }
    }

    private static func backup(_ path: String) {
        guard FileManager.default.fileExists(atPath: path) else { return }
        let backupPath = path + ".bugu-backup"
        if !FileManager.default.fileExists(atPath: backupPath) {
            try? FileManager.default.copyItem(atPath: path, toPath: backupPath)
        }
    }

    private static func loadJSON(_ path: String) -> [String: Any] {
        guard let data = FileManager.default.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    /// Loads a JSON object, distinguishing "file absent" (safe to start fresh) from
    /// "file present but unparseable" (e.g. JSONC with comments). In the latter case
    /// `safe` is false so callers abort rather than overwrite the user's whole config
    /// with just our hooks.
    private static func loadJSONForEdit(_ path: String) -> (object: [String: Any], safe: Bool) {
        guard FileManager.default.fileExists(atPath: path) else { return ([:], true) }
        guard let data = FileManager.default.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ([:], false)
        }
        return (obj, true)
    }

    private static func writeJSON(_ object: [String: Any], to path: String) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return false
        }
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }

    private static func isBugu(_ command: Any?) -> Bool {
        (command as? String)?.contains("bugu-bridge") == true
    }

    // MARK: - Nested JSON hooks (Claude / Codex / Trae / Gemini / Qwen / …)

    private static func installJSONHooks(_ cli: CLI, standalone: Bool) -> Bool {
        let (loaded, safe) = loadJSONForEdit(cli.configPath)
        guard safe else { return false }   // never clobber an unparseable config
        backup(cli.configPath)
        var root = loaded
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in cli.events {
            var groups = (hooks[event] as? [[String: Any]] ?? []).filter { group in
                let inner = group["hooks"] as? [[String: Any]] ?? []
                return !inner.contains { isBugu($0["command"]) }
            }
            groups.append(["hooks": [["type": "command", "command": command(for: cli, event: event), "timeout": 5]]])
            hooks[event] = groups
        }
        root["hooks"] = hooks
        return writeJSON(root, to: cli.configPath)
    }

    private static func uninstallJSONHooks(_ cli: CLI) -> Bool {
        let (loaded, safe) = loadJSONForEdit(cli.configPath)
        guard safe else { return false }   // leave an unparseable config untouched
        var root = loaded
        guard var hooks = root["hooks"] as? [String: Any] else { return true }
        for (event, value) in hooks {
            guard var groups = value as? [[String: Any]] else { continue }
            // Cursor-flat entries are { command }; nested are { hooks: [ { command } ] }.
            groups.removeAll { group in
                if isBugu(group["command"]) { return true }
                let inner = group["hooks"] as? [[String: Any]] ?? []
                return inner.contains { isBugu($0["command"]) }
            }
            if groups.isEmpty { hooks[event] = nil } else { hooks[event] = groups }
        }
        root["hooks"] = hooks
        return writeJSON(root, to: cli.configPath)
    }

    // MARK: - Cursor flat JSON

    private static func installCursorFlat(_ cli: CLI) -> Bool {
        let (loaded, safe) = loadJSONForEdit(cli.configPath)
        guard safe else { return false }
        backup(cli.configPath)
        var root = loaded
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in cli.events {
            var entries = (hooks[event] as? [[String: Any]] ?? []).filter { !isBugu($0["command"]) }
            entries.append(["command": command(for: cli, event: event)])
            hooks[event] = entries
        }
        root["hooks"] = hooks
        if root["version"] == nil { root["version"] = 1 }
        return writeJSON(root, to: cli.configPath)
    }

    // MARK: - Kiro agent file (Bugu owns this file)

    private static func installKiroAgent(_ cli: CLI) -> Bool {
        var hooks: [String: Any] = [:]
        for event in cli.events {
            hooks[event] = [["command": command(for: cli, event: event)]]
        }
        let agent: [String: Any] = [
            "name": "bugu",
            "description": "Bugu monitoring agent",
            "tools": ["*"],
            "includeMcpJson": true,
            "hooks": hooks
        ]
        return writeJSON(agent, to: cli.configPath)
    }

    private static func uninstallKiroAgent(_ cli: CLI) -> Bool {
        try? FileManager.default.removeItem(atPath: cli.configPath)
        return true
    }

    // MARK: - TOML adapters

    private static func installTOML(_ cli: CLI, typed: Bool) -> Bool {
        backup(cli.configPath)
        var text = (try? String(contentsOfFile: cli.configPath, encoding: .utf8)) ?? ""
        text = strippedManagedBlock(from: text)

        var block = "\n\(blockStart)\n"
        for event in cli.events {
            block += "[[hooks]]\n"
            if typed {
                block += "name = \"bugu-\(event)\"\ntype = \"\(event)\"\n"
            } else {
                block += "event = \"\(event)\"\n"
            }
            block += "command = \"\(command(for: cli, event: event))\"\ntimeout = 5\n\n"
        }
        block += "\(blockEnd)\n"
        text += block
        let dir = (cli.configPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return (try? text.write(toFile: cli.configPath, atomically: true, encoding: .utf8)) != nil
    }

    private static func uninstallTOML(_ cli: CLI) -> Bool {
        guard let text = try? String(contentsOfFile: cli.configPath, encoding: .utf8) else { return true }
        let cleaned = strippedManagedBlock(from: text)
        return (try? cleaned.write(toFile: cli.configPath, atomically: true, encoding: .utf8)) != nil
    }

    private static func strippedManagedBlock(from text: String) -> String {
        guard let startRange = text.range(of: blockStart),
              let endRange = text.range(of: blockEnd) else {
            return text
        }
        var lower = startRange.lowerBound
        if lower > text.startIndex {
            let before = text.index(before: lower)
            if text[before] == "\n" { lower = before }
        }
        var result = text
        result.removeSubrange(lower..<endRange.upperBound)
        return result
    }
}
