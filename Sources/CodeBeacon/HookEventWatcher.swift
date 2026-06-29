import Foundation

/// Tails the bridge's event file (~/.bugu/events.jsonl) and delivers each new hook
/// event. Uses a file-system dispatch source so events arrive the instant the bridge
/// appends them — no polling latency.
final class HookEventWatcher {

    struct Event: Sendable {
        let source: String       // which CLI (e.g. "claudecode")
        let hookEvent: String    // SessionStart / Stop / Notification / …
        let cwd: String?
        let sessionId: String?
        let tty: String?
    }

    private let path: String
    private let onEvent: @Sendable (Event) -> Void
    private var readHandle: FileHandle?
    private var source: DispatchSourceFileSystemObject?
    private var offset: UInt64 = 0

    init(path: String, onEvent: @escaping @Sendable (Event) -> Void) {
        self.path = path
        self.onEvent = onEvent
    }

    func start() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            fm.createFile(atPath: path, contents: nil)
        }
        guard let handle = FileHandle(forReadingAtPath: path) else { return }
        readHandle = handle
        // Start at end: ignore events from before Bugu launched.
        offset = (try? handle.seekToEnd()) ?? 0

        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename],
            queue: DispatchQueue.global(qos: .utility)
        )
        src.setEventHandler { [weak self] in self?.drain() }
        src.setCancelHandler { close(descriptor) }
        source = src
        src.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        try? readHandle?.close()
        readHandle = nil
    }

    private func drain() {
        guard let handle = readHandle else { return }
        let size = (try? handle.seekToEnd()) ?? 0
        if size < offset { offset = 0 }            // file truncated/rotated
        guard size > offset else { return }
        try? handle.seek(toOffset: offset)
        let data = handle.readDataToEndOfFile()
        offset = (try? handle.offset()) ?? size
        let text = String(decoding: data, as: UTF8.self)
        for line in text.split(separator: "\n") {
            if let event = parse(String(line)) {
                onEvent(event)
            }
        }
    }

    private func parse(_ line: String) -> Event? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let source = object["source"] as? String ?? "unknown"
        var tty = object["tty"] as? String
        if tty == "not a tty" || tty?.isEmpty == true { tty = nil }
        let payload = object["payload"] as? [String: Any]
        // The bridge records the event name explicitly via --event; fall back to the
        // payload's own field if absent.
        let hookEvent = (object["event"] as? String).flatMap { $0 == "unknown" ? nil : $0 }
            ?? (payload?["hook_event_name"] as? String)
            ?? (payload?["event"] as? String)
            ?? "Unknown"
        let cwd = payload?["cwd"] as? String
        let sessionId = (payload?["session_id"] as? String) ?? (payload?["sessionId"] as? String)
        return Event(source: source, hookEvent: hookEvent, cwd: cwd, sessionId: sessionId, tty: tty)
    }
}
