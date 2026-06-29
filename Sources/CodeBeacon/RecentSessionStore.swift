import Foundation

/// A recent agent coding session, reconstructed from the on-disk transcripts that
/// Claude Code / Codex / Kimi Code each write, optionally matched to a live process.
///
/// This is how tools like Vibe Island show a rich, jump-able session list without
/// relying on `ps` alone: the conversation history, project, title and timestamps
/// all live in transcript files; a session is "active" when its working directory
/// matches a currently-running agent process.
struct RecentSession: Identifiable, Hashable, Sendable {
    let id: String
    let agent: String
    let projectPath: String
    let title: String
    let lastActivity: Date
    /// Set when the session is matched to a running agent process (i.e. it is live).
    var pid: Int32?
    var command: String?

    var isActive: Bool { pid != nil }

    var projectName: String {
        let name = (projectPath as NSString).lastPathComponent
        if !name.isEmpty { return name }
        return projectPath.isEmpty ? "—" : projectPath
    }
}

enum RecentSessionStore {

    /// Builds the recent-session list: reads transcripts, marks sessions that match a
    /// live agent process as active, and guarantees every running agent appears.
    /// `liveAgents` is the current `ps`-based scan from the watcher.
    static func load(liveAgents: [AgentProcess], limit: Int = 12) -> [RecentSession] {
        var disk: [RecentSession] = []
        disk.append(contentsOf: loadClaude())
        disk.append(contentsOf: loadCodex())
        disk.append(contentsOf: loadKimi())

        disk.sort { $0.lastActivity > $1.lastActivity }

        // Keep the most recent entry per (agent, project).
        var seen = Set<String>()
        var sessions: [RecentSession] = []
        for session in disk {
            let key = "\(session.agent)|\(session.projectPath)"
            if seen.insert(key).inserted {
                sessions.append(session)
            }
        }

        // Match live processes by their working directory.
        let liveByCwd = liveAgentsByCwd(liveAgents)
        var matchedCwds = Set<String>()
        sessions = sessions.map { session in
            var session = session
            if let match = liveByCwd[session.projectPath], match.name == session.agent {
                session.pid = match.pid
                session.command = match.command
                matchedCwds.insert(session.projectPath)
            }
            return session
        }

        // Make sure every running agent shows up and is jump-able, even if its
        // transcript could not be parsed or its cwd could not be resolved (covers
        // agents we have no transcript reader for, plus Warp/Kimi/Codex edge cases).
        let now = Date()
        let matchedPIDs = Set(sessions.compactMap(\.pid))
        for agent in liveAgents {
            if matchedPIDs.contains(agent.pid) { continue }
            let cwd = liveByCwd.first(where: { $0.value.pid == agent.pid })?.key
            if let cwd, matchedCwds.contains(cwd) { continue }
            if let cwd { matchedCwds.insert(cwd) }
            sessions.append(RecentSession(
                id: "live:\(agent.pid)",
                agent: agent.name,
                projectPath: cwd ?? "",
                title: cwd != nil ? "Running…" : "Running · \(agent.name)",
                lastActivity: now,
                pid: agent.pid,
                command: agent.command
            ))
        }

        // Active first, then most recent.
        sessions.sort { lhs, rhs in
            if lhs.isActive != rhs.isActive { return lhs.isActive }
            return lhs.lastActivity > rhs.lastActivity
        }

        return Array(sessions.prefix(limit))
    }

    // MARK: - Live process matching

    private static func liveAgentsByCwd(_ agents: [AgentProcess]) -> [String: AgentProcess] {
        var map: [String: AgentProcess] = [:]
        for agent in agents {
            if let cwd = workingDirectory(forPID: agent.pid) {
                map[cwd] = agent
            }
        }
        return map
    }

    /// Resolves a process's current working directory via `lsof`.
    private static func workingDirectory(forPID pid: Int32) -> String? {
        guard let output = runOutput("/usr/sbin/lsof", ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"]) else {
            return nil
        }
        for line in output.split(separator: "\n") where line.hasPrefix("n") {
            return String(line.dropFirst())
        }
        return nil
    }

    // MARK: - Claude Code

    private static func loadClaude() -> [RecentSession] {
        let base = home("/.claude/projects")
        guard let dirs = try? FileManager.default.contentsOfDirectory(atPath: base) else { return [] }

        var sessions: [RecentSession] = []
        for dir in dirs {
            let dirPath = "\(base)/\(dir)"
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: dirPath) else { continue }
            for file in files where file.hasSuffix(".jsonl") {
                let path = "\(dirPath)/\(file)"
                guard let mtime = modificationDate(path), mtime > cutoff else { continue }
                let parsed = parseClaude(path: path)
                sessions.append(RecentSession(
                    id: "claude:\(file)",
                    agent: "Claude Code",
                    projectPath: parsed.cwd ?? "",
                    title: parsed.title ?? "Claude session",
                    lastActivity: mtime
                ))
            }
        }
        return sessions
    }

    private static func parseClaude(path: String) -> (cwd: String?, title: String?) {
        guard let text = tail(ofPath: path) else { return (nil, nil) }
        let lines = text.split(separator: "\n").map(String.init)

        var cwd: String?
        var title: String?
        // Walk from the end to find the most recent human-readable message and a cwd.
        for line in lines.reversed() {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            if cwd == nil, let value = object["cwd"] as? String, !value.isEmpty {
                cwd = value
            }
            if title == nil, let preview = messagePreview(object) {
                title = preview
            }
            if cwd != nil && title != nil { break }
        }
        return (cwd, title)
    }

    /// Extracts a short preview from a Claude transcript line, if it is a user or
    /// assistant text message.
    private static func messagePreview(_ object: [String: Any]) -> String? {
        guard let type = object["type"] as? String, type == "user" || type == "assistant" else {
            return nil
        }
        guard let message = object["message"] as? [String: Any] else { return nil }

        if let content = message["content"] as? String {
            return clip(content)
        }
        if let blocks = message["content"] as? [[String: Any]] {
            for block in blocks where (block["type"] as? String) == "text" {
                if let text = block["text"] as? String {
                    return clip(text)
                }
            }
        }
        return nil
    }

    // MARK: - Codex

    private static func loadCodex() -> [RecentSession] {
        let indexPath = home("/.codex/session_index.jsonl")
        guard let text = try? String(contentsOfFile: indexPath, encoding: .utf8) else { return [] }

        struct Entry { let id: String; let title: String; let updatedAt: Date }
        var entries: [Entry] = []
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let updatedAt = (object["updated_at"] as? String).flatMap(parseISODate),
                  updatedAt > cutoff else {
                continue
            }
            let id = object["id"] as? String ?? UUID().uuidString
            let title = (object["thread_name"] as? String).map { clip($0) } ?? "Codex session"
            entries.append(Entry(id: id, title: title, updatedAt: updatedAt))
        }
        entries.sort { $0.updatedAt > $1.updatedAt }
        let recent = Array(entries.prefix(12))

        // Resolve each recent session's working directory from its rollout
        // session_meta, so Codex rows show their project and can match a live process.
        let cwds = codexCwds(forIDs: Set(recent.map(\.id)))

        return recent.map { entry in
            RecentSession(
                id: "codex:\(entry.id)",
                agent: "Codex",
                projectPath: cwds[entry.id] ?? "",
                title: entry.title,
                lastActivity: entry.updatedAt
            )
        }
    }

    /// Maps the given Codex session ids to their working directory by scanning the
    /// rollout files (filename ends with the session UUID) and reading session_meta.
    private static func codexCwds(forIDs ids: Set<String>) -> [String: String] {
        guard !ids.isEmpty else { return [:] }
        let base = URL(fileURLWithPath: home("/.codex/sessions"))
        guard let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else {
            return [:]
        }
        var result: [String: String] = [:]
        for case let fileURL as URL in enumerator {
            let name = fileURL.lastPathComponent
            guard name.hasPrefix("rollout-"), name.hasSuffix(".jsonl") else { continue }
            let stem = name.dropFirst("rollout-".count).dropLast(".jsonl".count)
            guard stem.count >= 36 else { continue }
            let id = String(stem.suffix(36))
            guard ids.contains(id), result[id] == nil else { continue }
            if let cwd = codexCwd(path: fileURL.path) {
                result[id] = cwd
            }
            if result.count == ids.count { break }
        }
        return result
    }

    /// Reads `cwd` from a Codex rollout file's session_meta. That first line embeds
    /// large fields (base_instructions, dynamic_tools) and can exceed any fixed read
    /// size, so rather than parse the whole JSON we scan the head for the `"cwd"`
    /// value, which sits near the start of the payload.
    private static func codexCwd(path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 8_192)
        // Lossy decode so a multibyte character split at the read boundary can't fail.
        let text = String(decoding: data, as: UTF8.self)
        return firstCapture(in: text, pattern: #""cwd"\s*:\s*"([^"]+)""#)
    }

    /// Returns the first capture group of `pattern` in `text`, or nil.
    static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captureRange])
    }

    // MARK: - Kimi Code

    private static func loadKimi() -> [RecentSession] {
        let indexPath = home("/.kimi-code/session_index.jsonl")
        guard let text = try? String(contentsOfFile: indexPath, encoding: .utf8) else { return [] }

        var sessions: [RecentSession] = []
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let workDir = object["workDir"] as? String,
                  let sessionDir = object["sessionDir"] as? String else {
                continue
            }
            let statePath = "\(sessionDir)/state.json"
            let state = (try? Data(contentsOf: URL(fileURLWithPath: statePath)))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let updatedAt = (state?["updatedAt"] as? String).flatMap(parseISODate)
                ?? modificationDate(statePath)
                ?? .distantPast
            guard updatedAt > cutoff else { continue }
            let title = (state?["title"] as? String).map { clip($0) }
                ?? (workDir as NSString).lastPathComponent
            sessions.append(RecentSession(
                id: "kimi:\(object["sessionId"] as? String ?? sessionDir)",
                agent: "Kimi Code",
                projectPath: workDir,
                title: title,
                lastActivity: updatedAt
            ))
        }
        return sessions
    }

    // MARK: - Helpers

    /// Only surface sessions touched within the last two weeks.
    private static let cutoff = Date().addingTimeInterval(-14 * 24 * 3600)

    private static func home(_ suffix: String) -> String {
        NSHomeDirectory() + suffix
    }

    private static func modificationDate(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    /// Reads up to the last `maxBytes` of a file. Transcripts can be large, and only
    /// the tail is needed for a recent-message preview (cwd appears on every line).
    private static func tail(ofPath path: String, maxBytes: Int = 262_144) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: start)
        let data = handle.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }

    static func clip(_ text: String, max: Int = 64) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.count <= max { return collapsed }
        return String(collapsed.prefix(max)) + "…"
    }

    private static func parseISODate(_ string: String) -> Date? {
        isoFormatter.date(from: string) ?? isoFormatterNoFraction.date(from: string)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatterNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func runOutput(_ launchPath: String, _ arguments: [String]) -> String? {
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
}
