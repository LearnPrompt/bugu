import AppKit
import IOKit.pwr_mgt
import SwiftUI

@main
struct CodeBeaconApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = BeaconModel()

    init() {
        if CommandLine.arguments.contains("--scan-agents") {
            let agents = AgentProcessScanner.scan()
            for agent in agents {
                print("\(agent.pid)\t\(agent.name)\t\(agent.command)")
            }
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra("Bugu", systemImage: model.menuIconName) {
            BeaconMenuView(model: model)
                .frame(width: 320)
        }
        .menuBarExtraStyle(.window)

        Window("Bugu", id: "main") {
            BeaconWindowView(model: model)
                .frame(width: 560, height: 440)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

private struct BeaconMenuView: View {
    @ObservedObject var model: BeaconModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: model.menuIconName)
                    .font(.title2)
                    .foregroundStyle(model.statusColor)
                VStack(alignment: .leading) {
                    Text("布谷 · \(model.statusTitle)")
                        .font(.headline)
                    Text(model.statusSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            Toggle("Keep Mac awake", isOn: $model.keepAwakeEnabled)
                .onChange(of: model.keepAwakeEnabled) { _, enabled in
                    model.setKeepAwake(enabled)
                }

            Toggle("Watch coding agents", isOn: $model.autoWatchEnabled)
                .onChange(of: model.autoWatchEnabled) { _, enabled in
                    model.setAutoWatch(enabled)
                }

            HStack {
                Text("Heartbeat")
                Spacer()
                Picker("", selection: $model.heartbeatSeconds) {
                    Text("10s").tag(10)
                    Text("30s").tag(30)
                    Text("1m").tag(60)
                    Text("5m").tag(300)
                    Text("10m").tag(600)
                    Text("30m").tag(1800)
                }
                .pickerStyle(.menu)
                .frame(width: 92)
            }

            HStack {
                Text("Alert volume")
                Spacer()
                Text(model.alertVolumePercent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $model.alertVolume, in: 0.2...1.0, step: 0.05)

            Divider()

            HStack {
                Text("Status sounds")
                    .font(.caption.bold())
                Spacer()
            }

            HStack {
                Button("Accept") {
                    model.playAccepted()
                }
                Button("Running") {
                    model.playRunning()
                }
                Button("Done") {
                    model.markCompleted()
                }
            }

            HStack {
                Button("Interrupted") {
                    model.markInterrupted()
                }
                Button("Permission") {
                    model.playPermissionNeeded()
                }
            }

            if let message = model.lastEventMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !model.activeAgents.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Active agents")
                        .font(.caption.bold())
                    ForEach(model.activeAgents.prefix(4)) { agent in
                        Text("\(agent.name) · pid \(agent.pid)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Divider()

            DisclosureGroup("Debug") {
                VStack(alignment: .leading, spacing: 8) {
                    Button("Sim Agent") {
                        model.startSimulatedAgent()
                    }
                    Button("Sim Interrupt") {
                        model.startSimulatedInterruptedAgent()
                    }
                    Button("Reset watcher") {
                        model.stopWatching()
                    }
                    Text("Starts a short fake Codex process to test automatic detection.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Button("Quit Bugu") {
                model.shutdown()
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(16)
    }
}

private struct BeaconWindowView: View {
    @ObservedObject var model: BeaconModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: model.menuIconName)
                    .font(.system(size: 42))
                    .foregroundStyle(model.statusColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bugu / 布谷")
                        .font(.largeTitle.bold())
                    Text("A sound beacon for long-running Mac coding tasks.")
                        .foregroundStyle(.secondary)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                GridRow {
                    Text("Awake assertion")
                    Text(model.keepAwakeEnabled ? "Active" : "Off")
                        .foregroundStyle(model.keepAwakeEnabled ? .green : .secondary)
                }
                GridRow {
                    Text("Agent watcher")
                    Text(model.autoWatchEnabled ? "Watching" : "Off")
                        .foregroundStyle(model.autoWatchEnabled ? .blue : .secondary)
                }
                GridRow {
                    Text("Active agents")
                    Text(model.activeAgentSummary)
                        .foregroundStyle(model.activeAgents.isEmpty ? .secondary : .primary)
                }
                GridRow {
                    Text("Task state")
                    Text(model.statusTitle)
                        .foregroundStyle(model.statusColor)
                }
                GridRow {
                    Text("Heartbeat interval")
                    Text(model.heartbeatLabel)
                }
                GridRow {
                    Text("Alert volume")
                    Text(model.alertVolumePercent)
                }
                GridRow {
                    Text("Sound profile")
                    Text("Five short system cues")
                }
                GridRow {
                    Text("Last event")
                    Text(model.lastEventMessage ?? "No event yet")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.body)

            HStack {
                Toggle("Keep Mac awake", isOn: $model.keepAwakeEnabled)
                    .onChange(of: model.keepAwakeEnabled) { _, enabled in
                        model.setKeepAwake(enabled)
                    }
                Toggle("Watch agents", isOn: $model.autoWatchEnabled)
                    .onChange(of: model.autoWatchEnabled) { _, enabled in
                        model.setAutoWatch(enabled)
                    }
            }

            HStack {
                Text("Alert volume")
                Slider(value: $model.alertVolume, in: 0.2...1.0, step: 0.05)
                Text(model.alertVolumePercent)
                    .frame(width: 44, alignment: .trailing)
                    .monospacedDigit()
            }

            HStack {
                Button("Accept") { model.playAccepted() }
                Button("Running") { model.playRunning() }
                Button("Done") { model.markCompleted() }
                Button("Interrupted") { model.markInterrupted() }
                Button("Permission") { model.playPermissionNeeded() }
            }

            DisclosureGroup("Debug") {
                HStack {
                    Button("Sim agent") { model.startSimulatedAgent() }
                    Button("Sim interrupt") { model.startSimulatedInterruptedAgent() }
                    Button("Reset watcher") { model.stopWatching() }
                }
            }

            Text("MVP scope: this uses macOS IOKit power assertions and short sound feedback. Closed-lid force-awake support should stay behind an explicit experimental toggle because it can affect heat and battery safety.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(24)
    }
}

@MainActor
final class BeaconModel: ObservableObject {
    enum TaskState {
        case idle
        case running(startedAt: Date)
        case completed(finishedAt: Date)
        case interrupted(finishedAt: Date)
        case permissionNeeded(at: Date)
    }

    @Published var keepAwakeEnabled = false
    @Published var autoWatchEnabled = false
    @Published var alertVolume: Double {
        didSet {
            UserDefaults.standard.set(Self.clampAlertVolume(alertVolume), forKey: Self.alertVolumeKey)
        }
    }
    @Published var heartbeatSeconds = 30 {
        didSet {
            if case .running = taskState {
                scheduleHeartbeat()
            }
        }
    }
    @Published private(set) var taskState: TaskState = .idle
    @Published private(set) var lastEventMessage: String?
    @Published private(set) var activeAgents: [AgentProcess] = []

    private var powerAssertionIDs: [IOPMAssertionID] = []
    private var heartbeatTimer: Timer?
    private var agentScanTimer: Timer?
    private var knownAgentPIDs = Set<Int32>()
    private var announcedAgentPIDs = Set<Int32>()
    private var watchedAgentStartTimes: [Int32: Date] = [:]
    private var simulatedAgentProcess: Process?
    private let soundEngine = BuguSoundEngine()

    init() {
        alertVolume = Self.loadAlertVolume()
    }

    var statusTitle: String {
        switch taskState {
        case .idle:
            return "Idle"
        case .running:
            return "Coding in progress"
        case .completed:
            return "Task complete"
        case .interrupted:
            return "Task interrupted"
        case .permissionNeeded:
            return "Permission needed"
        }
    }

    var statusSubtitle: String {
        switch taskState {
        case .idle:
            return keepAwakeEnabled ? "Awake mode is active" : "No task is being watched"
        case .running(let startedAt):
            return "Started \(Self.relativeFormatter.localizedString(for: startedAt, relativeTo: Date()))"
        case .completed(let finishedAt):
            return "Finished \(Self.relativeFormatter.localizedString(for: finishedAt, relativeTo: Date()))"
        case .interrupted(let finishedAt):
            return "Interrupted \(Self.relativeFormatter.localizedString(for: finishedAt, relativeTo: Date()))"
        case .permissionNeeded(let at):
            return "Waiting since \(Self.relativeFormatter.localizedString(for: at, relativeTo: Date()))"
        }
    }

    var menuIconName: String {
        switch taskState {
        case .idle:
            return keepAwakeEnabled ? "bird.fill" : "bird"
        case .running:
            return "bird.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .interrupted:
            return "exclamationmark.triangle.fill"
        case .permissionNeeded:
            return "hand.raised.fill"
        }
    }

    var statusColor: Color {
        switch taskState {
        case .idle:
            return keepAwakeEnabled ? .orange : .secondary
        case .running:
            return .blue
        case .completed:
            return .green
        case .interrupted:
            return .red
        case .permissionNeeded:
            return .orange
        }
    }

    var heartbeatLabel: String {
        if heartbeatSeconds < 60 {
            return "\(heartbeatSeconds)s"
        }
        return "\(heartbeatSeconds / 60)m"
    }

    var alertVolumePercent: String {
        "\(Int((clampedAlertVolume * 100).rounded()))%"
    }

    private var clampedAlertVolume: Double {
        Self.clampAlertVolume(alertVolume)
    }

    private var alertVolumeFloat: Float {
        Float(clampedAlertVolume)
    }

    var activeAgentSummary: String {
        if activeAgents.isEmpty {
            return autoWatchEnabled ? "None yet" : "Not watching"
        }
        let names = activeAgents.prefix(3).map(\.name).joined(separator: ", ")
        if activeAgents.count > 3 {
            return "\(names) +\(activeAgents.count - 3)"
        }
        return names
    }

    private static let alertVolumeKey = "alertVolume"

    private static func loadAlertVolume() -> Double {
        if UserDefaults.standard.object(forKey: alertVolumeKey) == nil {
            return 0.65
        }
        return clampAlertVolume(UserDefaults.standard.double(forKey: alertVolumeKey))
    }

    private static func clampAlertVolume(_ value: Double) -> Double {
        min(max(value, 0.2), 1.0)
    }

    private func playCue(_ cue: BuguSoundEngine.Cue) {
        soundEngine.play(cue, volume: alertVolumeFloat)
    }

    func setKeepAwake(_ enabled: Bool) {
        enabled ? startPowerAssertions() : stopPowerAssertions()
    }

    func setAutoWatch(_ enabled: Bool) {
        enabled ? startAgentWatcher() : stopWatching()
    }

    func playAccepted() {
        if !keepAwakeEnabled {
            keepAwakeEnabled = true
            startPowerAssertions()
        }
        taskState = .running(startedAt: Date())
        lastEventMessage = "Accepted: task is now being watched. Heartbeat every \(heartbeatLabel)."
        playCue(.accepted)
        scheduleHeartbeat()
    }

    func playRunning() {
        taskState = .running(startedAt: Date())
        lastEventMessage = "Running: task heartbeat cue."
        playCue(.running)
        scheduleHeartbeat()
    }

    func startSimulatedAgent() {
        startSimulatedAgent(duration: 8, label: "simulated Codex agent")
    }

    func startSimulatedInterruptedAgent() {
        startSimulatedAgent(duration: 1, label: "simulated interrupted Codex agent")
    }

    private func startSimulatedAgent(duration: Int, label: String) {
        if !autoWatchEnabled {
            autoWatchEnabled = true
            startAgentWatcher()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "exec -a codex-agent-sim sleep \(duration)"]

        do {
            try process.run()
            simulatedAgentProcess = process
            lastEventMessage = "Started \(label) for watcher validation."
            scanAgents()
        } catch {
            lastEventMessage = "Could not start simulated agent: \(error.localizedDescription)"
            playCue(.interrupted)
        }
    }

    func stopWatching() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        stopAgentWatcher()
        taskState = .idle
        lastEventMessage = "Stopped watching. Bugu is idle."
    }

    func markCompleted() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        taskState = .completed(finishedAt: Date())
        lastEventMessage = "Done: task completed."
        playCue(.completed)
    }

    func markInterrupted() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        taskState = .interrupted(finishedAt: Date())
        lastEventMessage = "Interrupted: task stopped unexpectedly."
        playCue(.interrupted)
    }

    func playPermissionNeeded() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        taskState = .permissionNeeded(at: Date())
        lastEventMessage = "Permission needed: waiting for user approval."
        playCue(.permissionNeeded)
    }

    func playHeartbeat() {
        guard case .running = taskState else {
            lastEventMessage = "Heartbeat skipped because no task is running."
            playCue(.running)
            return
        }
        lastEventMessage = "Heartbeat: coding task is still running."
        playCue(.running)
    }

    func shutdown() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        agentScanTimer?.invalidate()
        agentScanTimer = nil
        if simulatedAgentProcess?.isRunning == true {
            simulatedAgentProcess?.terminate()
        }
        stopPowerAssertions()
    }

    private func startAgentWatcher() {
        autoWatchEnabled = true
        let snapshot = AgentProcessScanner.scan()
        activeAgents = snapshot
        knownAgentPIDs = Set(snapshot.map(\.pid))
        announcedAgentPIDs.removeAll()
        lastEventMessage = "Watching coding agents. Baseline: \(snapshot.count) active."

        agentScanTimer?.invalidate()
        agentScanTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scanAgents()
            }
        }
    }

    private func stopAgentWatcher() {
        agentScanTimer?.invalidate()
        agentScanTimer = nil
        activeAgents = []
        knownAgentPIDs.removeAll()
        announcedAgentPIDs.removeAll()
        watchedAgentStartTimes.removeAll()
        autoWatchEnabled = false
        lastEventMessage = "Agent watcher stopped."
    }

    private func scanAgents() {
        let snapshot = AgentProcessScanner.scan()
        let currentPIDs = Set(snapshot.map(\.pid))
        let newPIDs = currentPIDs.subtracting(knownAgentPIDs)
        let endedAnnouncedPIDs = announcedAgentPIDs.subtracting(currentPIDs)
        let newAgents = snapshot.filter { newPIDs.contains($0.pid) }

        activeAgents = snapshot

        if !newAgents.isEmpty {
            announcedAgentPIDs.formUnion(newAgents.map(\.pid))
            let now = Date()
            for agent in newAgents {
                watchedAgentStartTimes[agent.pid] = now
            }
            handleAgentStarted(newAgents)
        }

        if !endedAnnouncedPIDs.isEmpty {
            let now = Date()
            let shortLivedCount = endedAnnouncedPIDs.filter { pid in
                guard let startedAt = watchedAgentStartTimes[pid] else {
                    return false
                }
                return now.timeIntervalSince(startedAt) < 5
            }.count
            for pid in endedAnnouncedPIDs {
                watchedAgentStartTimes.removeValue(forKey: pid)
            }
            announcedAgentPIDs.subtract(endedAnnouncedPIDs)
            if announcedAgentPIDs.isEmpty {
                if shortLivedCount > 0 {
                    handleWatchedAgentsInterrupted(count: endedAnnouncedPIDs.count)
                } else {
                    handleWatchedAgentsCompleted(count: endedAnnouncedPIDs.count)
                }
            } else {
                lastEventMessage = "\(endedAnnouncedPIDs.count) watched agent process ended; \(announcedAgentPIDs.count) still running."
            }
        }

        knownAgentPIDs = currentPIDs
    }

    private func handleAgentStarted(_ agents: [AgentProcess]) {
        if !keepAwakeEnabled {
            keepAwakeEnabled = true
            startPowerAssertions()
        }
        taskState = .running(startedAt: Date())
        let names = agents.map(\.name).joined(separator: ", ")
        lastEventMessage = "Detected agent start: \(names). Heartbeat every \(heartbeatLabel)."
        playCue(.accepted)
        scheduleHeartbeat()
    }

    private func handleWatchedAgentsCompleted(count: Int) {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        taskState = .completed(finishedAt: Date())
        lastEventMessage = "\(count) watched agent process ended."
        playCue(.completed)
    }

    private func handleWatchedAgentsInterrupted(count: Int) {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        taskState = .interrupted(finishedAt: Date())
        lastEventMessage = "\(count) watched agent process stopped too quickly."
        playCue(.interrupted)
    }

    private func startPowerAssertions() {
        if !powerAssertionIDs.isEmpty {
            return
        }

        let reason = "Bugu is watching a long-running coding task" as CFString
        let requestedTypes: [CFString] = [
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString
        ]
        var createdAssertions: [IOPMAssertionID] = []

        for assertionType in requestedTypes {
            var assertionID = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                assertionType,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &assertionID
            )

            if result == kIOReturnSuccess {
                createdAssertions.append(assertionID)
            } else {
                createdAssertions.forEach { IOPMAssertionRelease($0) }
                powerAssertionIDs.removeAll()
                keepAwakeEnabled = false
                lastEventMessage = "Could not start power assertion: IOKit error \(result)."
                playCue(.interrupted)
                return
            }
        }

        powerAssertionIDs = createdAssertions
        lastEventMessage = "Awake assertions started with IOKit power management."
    }

    private func stopPowerAssertions() {
        powerAssertionIDs.forEach { IOPMAssertionRelease($0) }
        powerAssertionIDs.removeAll()
        keepAwakeEnabled = false
        lastEventMessage = "Awake assertion stopped."
    }

    private func scheduleHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(heartbeatSeconds), repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.playHeartbeat()
            }
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

struct AgentProcess: Identifiable, Hashable {
    let pid: Int32
    let name: String
    let command: String

    var id: Int32 { pid }
}

private enum AgentProcessScanner {
    private struct Signature {
        let name: String
        let patterns: [String]
    }

    private static let signatures: [Signature] = [
        Signature(name: "Codex", patterns: ["codex-agent-sim", #"(^|[/\s])codex($|\s)"#]),
        Signature(name: "Claude Code", patterns: [#"(^|[/\s])claude($|\s)"#]),
        Signature(name: "OpenCode", patterns: [#"(^|[/\s])opencode($|\s)"#]),
        Signature(name: "Aider", patterns: [#"(^|[/\s])aider($|\s)"#]),
        Signature(name: "Goose", patterns: [#"(^|[/\s])goose($|\s)"#]),
        Signature(name: "Gemini CLI", patterns: [#"(^|[/\s])gemini($|\s)"#]),
        Signature(name: "Amp", patterns: [#"(^|[/\s])amp($|\s)"#]),
        Signature(name: "Qwen Code", patterns: [#"(^|[/\s])qwen($|\s)"#, #"(^|[/\s])qwen-code($|\s)"#]),
        Signature(name: "Crush", patterns: [#"(^|[/\s])crush($|\s)"#]),
        Signature(name: "Devin", patterns: [#"(^|[/\s])devin($|\s)"#]),
        Signature(name: "Cursor Agent", patterns: ["cursor-agent"]),
        Signature(name: "OpenHands", patterns: ["openhands"])
    ]

    static func scan() -> [AgentProcess] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,command="]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else {
            return []
        }

        return output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap(parseLine)
            .filter { !shouldIgnore(command: $0.command) }
            .compactMap { process in
                guard let name = matchedAgentName(command: process.command) else {
                    return nil
                }
                return AgentProcess(pid: process.pid, name: name, command: process.command)
            }
            .sorted { $0.pid < $1.pid }
    }

    private static func parseLine(_ line: Substring) -> (pid: Int32, command: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let firstSpace = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
            return nil
        }

        let pidText = trimmed[..<firstSpace]
        let command = trimmed[firstSpace...].trimmingCharacters(in: .whitespaces)
        guard let pid = Int32(pidText), !command.isEmpty else {
            return nil
        }
        return (pid, command)
    }

    private static func shouldIgnore(command: String) -> Bool {
        let lower = command.lowercased()
        let ignoredFragments = [
            "codebeacon",
            "/applications/codex.app/",
            "/applications/claude.app/",
            "codex computer use.app",
            "browser_crashpad_handler",
            "chrome_crashpad_handler",
            "extension-host",
            "node_repl",
            "codex_chronicle",
            "codex app-server",
            "rg -i",
            "ps -axo"
        ]
        return ignoredFragments.contains { lower.contains($0) }
    }

    private static func matchedAgentName(command: String) -> String? {
        let lower = command.lowercased()
        for signature in signatures {
            if signature.patterns.contains(where: { pattern in
                if pattern.contains("(") || pattern.contains("[") || pattern.contains("\\") {
                    return lower.range(of: pattern, options: .regularExpression) != nil
                }
                return lower.contains(pattern)
            }) {
                return signature.name
            }
        }
        return nil
    }
}

private final class BuguSoundEngine {
    enum Cue {
        case accepted
        case running
        case completed
        case interrupted
        case permissionNeeded
    }

    func play(_ cue: Cue, volume: Float) {
        let clampedVolume = min(max(volume, 0.2), 1.0)
        guard let sound = NSSound(named: soundName(for: cue)) else {
            return
        }
        sound.volume = clampedVolume
        sound.play()
    }

    private func soundName(for cue: Cue) -> NSSound.Name {
        switch cue {
        case .accepted:
            return NSSound.Name("Funk")
        case .running:
            return NSSound.Name("Hero")
        case .completed:
            return NSSound.Name("Blow")
        case .interrupted:
            return NSSound.Name("Basso")
        case .permissionNeeded:
            return NSSound.Name("Ping")
        }
    }
}
