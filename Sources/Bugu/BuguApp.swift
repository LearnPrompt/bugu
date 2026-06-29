import AppKit
import ApplicationServices
import IOKit.pwr_mgt
import SwiftUI

@main
struct BuguApp: App {
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

        if CommandLine.arguments.contains("--list-sessions") {
            let sessions = RecentSessionStore.load(liveAgents: AgentProcessScanner.scan())
            for session in sessions {
                let live = session.isActive ? "LIVE pid \(session.pid ?? 0)" : "history"
                print("[\(live)]\t\(session.agent)\t\(session.projectName)\t\(session.title)")
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

        Window("Bugu · Agents", id: "main") {
            BeaconWindowView(model: model)
        }
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

private struct BeaconMenuView: View {
    @ObservedObject var model: BeaconModel
    @Environment(\.openWindow) private var openWindow

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

            if let update = model.availableUpdate {
                Button {
                    model.openUpdatePage()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.white)
                        Text("Update available: v\(update.version)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)
                        Spacer(minLength: 4)
                        Text("Download ›")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open the latest release page to download v\(update.version)")
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

            HStack {
                Text("Sound pack")
                Spacer()
                Picker("", selection: $model.soundProfile) {
                    ForEach(BuguSoundProfile.allCases) { profile in
                        Text(profile.displayName).tag(profile)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            }

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

            if !model.recentSessions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Recent sessions")
                            .font(.caption.bold())
                        Spacer()
                        Text("each task shows its state · click to jump")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.currentSessions) { session in
                        SessionRow(
                            session: session,
                            relativeTime: model.relativeTime(session.lastActivity),
                            symbol: model.sessionSymbol(session),
                            color: model.sessionColor(session)
                        )
                    }
                    if model.currentSessions.isEmpty {
                        Text("No active sessions.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    // Fold away older/expired sessions so the menu stays short.
                    if !model.olderSessions.isEmpty {
                        DisclosureGroup("Older (\(model.olderSessions.count))") {
                            ForEach(model.olderSessions) { session in
                                SessionRow(
                                    session: session,
                                    relativeTime: model.relativeTime(session.lastActivity),
                                    symbol: model.sessionSymbol(session),
                                    color: model.sessionColor(session)
                                )
                            }
                        }
                        .font(.caption2)
                    }
                }
            }

            #if DEBUG
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
            #endif

            Divider()

            Button("Manage agents…") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }

            Button("Check for updates") {
                model.checkForUpdates(announce: true)
            }

            Button("Quit Bugu") {
                model.shutdown()
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(16)
        .onAppear { model.refreshSessions(immediate: true) }
    }
}

/// A single recent-session row: live status dot, project + title, agent and time.
/// Tapping a live session jumps to its terminal; historical rows are not jump-able.
private struct SessionRow: View {
    let session: RecentSession
    let relativeTime: String
    let symbol: String
    let color: Color

    var body: some View {
        Button {
            guard let pid = session.pid else { return }
            AgentSessionLauncher.launchSession(
                pid: pid,
                agentName: session.agent,
                command: session.command,
                projectPath: session.projectPath
            )
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.caption2)
                    .foregroundStyle(color)
                    .frame(width: 12)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.projectName)
                        .font(.caption)
                        .lineLimit(1)
                    Text(session.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(session.agent)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(relativeTime)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!session.isActive)
        .help(session.isActive ? "Jump to \(session.agent) in \(session.projectName)" : "Historical session")
    }
}

/// The Agents window has a single, focused job: pick which coding agents Bugu hooks
/// into. Everything that mirrors live state (awake, volume, sound pack, sessions) lives
/// in the menu-bar popover and is deliberately *not* duplicated here.
private struct BeaconWindowView: View {
    @ObservedObject var model: BeaconModel

    private var detectedCount: Int {
        HookIntegration.supportedCLIs.filter(\.isAvailable).count
    }
    private var enabledCount: Int {
        HookIntegration.supportedCLIs.filter { model.integrationStatus[$0.id] == true }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 34))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Agents")
                        .font(.largeTitle.bold())
                    Text("Pick which coding agents Bugu hooks into for instant, accurate start / done / permission events. Enabling an agent edits its CLI config — backed up first and fully reversible.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(enabledCount) enabled · \(detectedCount) detected · \(HookIntegration.supportedCLIs.count) supported")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)

            Divider()

            if !model.accessibilityTrusted {
                HStack(spacing: 10) {
                    Image(systemName: "hand.raised.circle.fill")
                        .foregroundStyle(.orange)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Enable Accessibility for precise tab jumps")
                            .font(.callout.weight(.medium))
                        Text("Jumping to the exact Warp/Ghostty tab uses System Events. Without it, Bugu just activates the app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button("Grant…") { model.requestAccessibilityPermission() }
                }
                .padding(12)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(HookIntegration.supportedCLIs) { cli in
                        AgentToggleRow(cli: cli, model: model)
                        if cli.id != HookIntegration.supportedCLIs.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }

            Divider()

            HStack {
                Button("Enable all detected") { model.enableAllDetectedIntegrations() }
                    .disabled(detectedCount == 0 || enabledCount == detectedCount)
                Spacer()
                Button("Disable all") { model.disableAllIntegrations() }
                    .disabled(enabledCount == 0)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 440, idealWidth: 480, minHeight: 460, idealHeight: 620)
        .onAppear {
            model.refreshIntegrationStatus()
            model.refreshAccessibilityStatus()
        }
    }
}

/// One agent row: name, whether its CLI is installed on this Mac, and the on/off
/// switch that installs or removes Bugu's hook.
private struct AgentToggleRow: View {
    let cli: HookIntegration.CLI
    @ObservedObject var model: BeaconModel

    var body: some View {
        Toggle(isOn: Binding(
            get: { model.integrationStatus[cli.id] ?? false },
            set: { model.setIntegration(cli, enabled: $0) }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(cli.name)
                    .font(.body)
                Text(cli.isAvailable ? "Detected on this Mac" : "Not installed")
                    .font(.caption)
                    .foregroundStyle(cli.isAvailable ? .green : .secondary)
            }
        }
        .toggleStyle(.switch)
        .disabled(!cli.isAvailable)
        .padding(.vertical, 8)
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
    @Published var soundProfile: BuguSoundProfile = .system {
        didSet {
            soundEngine.setProfile(soundProfile)
            UserDefaults.standard.set(soundProfile.rawValue, forKey: Self.soundProfileKey)
        }
    }
    /// Per-cue macOS system sound names for the Custom profile, keyed by cue key.
    /// Persisted to UserDefaults and pushed into the sound engine on change.
    @Published var customSoundNames: [String: String] = [:] {
        didSet {
            UserDefaults.standard.set(customSoundNames, forKey: Self.customSoundsKey)
            applyCustomSounds()
        }
    }
    @Published private(set) var taskState: TaskState = .idle
    @Published private(set) var lastEventMessage: String?
    @Published private(set) var activeAgents: [AgentProcess] = []
    /// Recent coding sessions read from on-disk transcripts, with live ones flagged.
    @Published private(set) var recentSessions: [RecentSession] = []
    /// Drives the menu bar icon's gentle pulse while a task is running.
    @Published private(set) var pulseOn = false

    private var powerAssertionIDs: [IOPMAssertionID] = []
    /// True when the agent watcher (not the user) turned keep-awake on, so it can
    /// be released automatically once all watched agents finish.
    private var autoAwakeEngaged = false
    private var heartbeatTimer: Timer?
    private var agentScanTimer: Timer?
    private var pulseTimer: Timer?
    private var knownAgentPIDs = Set<Int32>()
    private var announcedAgentPIDs = Set<Int32>()
    private var watchedAgentStartTimes: [Int32: Date] = [:]
    /// Consecutive scans an announced agent has been missing, for liveness debounce.
    private var agentMissCounts: [Int32: Int] = [:]
    private var simulatedAgentProcess: Process?
    private let soundEngine = BuguSoundEngine()
    private var hookWatcher: HookEventWatcher?
    /// Debounce handle for `refreshSessions()`.
    private var sessionRefreshTask: Task<Void, Never>?
    /// Per-session phase from hooks, keyed by session identity, so concurrent agents
    /// are tracked independently and the menu-bar state is their aggregate.
    private var hookSessions: [String: (phase: SessionPhase, at: Date)] = [:]
    /// Latest hook phase per project dir, used to badge each row in the session list
    /// with its own state (so an "interrupted" chirp points to a specific task).
    private var hookPhaseByProject: [String: (phase: SessionPhase, at: Date)] = [:]
    /// When the last hook event arrived. While recent, the `ps` poller defers to hooks
    /// for state and sounds so the two paths don't double-fire.
    private var lastHookEventAt: Date = .distantPast
    private var hooksRecentlyActive: Bool { Date().timeIntervalSince(lastHookEventAt) < 15 }
    /// Per-CLI hook install status, surfaced in the Integrations UI.
    @Published var integrationStatus: [String: Bool] = [:]

    /// One selectable status cue, used to build the Custom sound pickers.
    struct CueOption: Identifiable {
        let cue: BuguSoundEngine.Cue
        let key: String
        let label: String
        var id: String { key }
    }

    static let cueOptions: [CueOption] = [
        CueOption(cue: .accepted, key: "accepted", label: "Accept"),
        CueOption(cue: .running, key: "running", label: "Running"),
        CueOption(cue: .completed, key: "completed", label: "Done"),
        CueOption(cue: .interrupted, key: "interrupted", label: "Interrupted"),
        CueOption(cue: .permissionNeeded, key: "permission", label: "Permission")
    ]

    static let defaultCustomNames: [String: String] = [
        "accepted": "Funk",
        "running": "Hero",
        "completed": "Blow",
        "interrupted": "Basso",
        "permission": "Ping"
    ]

    /// Available macOS alert sounds, discovered from the system Sounds directory.
    static let systemSoundNames: [String] = {
        let dir = "/System/Library/Sounds"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        let names = files
            .filter { $0.hasSuffix(".aiff") }
            .map { String($0.dropLast(5)) }
        return names.sorted()
    }()

    init() {
        alertVolume = Self.loadAlertVolume()
        soundProfile = Self.loadSoundProfile()
        customSoundNames = Self.loadCustomSoundNames()
        soundEngine.setProfile(soundProfile)
        applyCustomSounds()

        // Hook integration: deploy the bridge, start watching for events, and read
        // which CLIs currently have Bugu hooks installed.
        HookIntegration.deployBridge()
        refreshIntegrationStatus()
        startHookWatcher()

        // Watch coding agents by default (persisted): a beacon that starts off isn't
        // much of a beacon. The user can still turn it off and that choice sticks.
        autoWatchEnabled = Self.loadAutoWatch()
        if autoWatchEnabled { startAgentWatcher() }

        // Quietly check GitHub for a newer release on launch.
        checkForUpdates()
    }

    // MARK: - Update check (notify only; never auto-installs)

    /// The newest release found on GitHub when it is newer than this build, else nil.
    @Published var availableUpdate: UpdateChecker.Release?

    /// The running build's version string from Info.plist.
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Asks GitHub for the latest release and flags it if newer. `announce` surfaces a
    /// result message even when up to date (used by the manual "Check for updates").
    func checkForUpdates(announce: Bool = false) {
        Task { [weak self] in
            let latest = await UpdateChecker.fetchLatest()
            guard let self else { return }
            guard let latest else {
                if announce { self.lastEventMessage = "Update check failed (offline?)." }
                return
            }
            if UpdateChecker.isNewer(latest.version, than: self.currentVersion) {
                self.availableUpdate = latest
                self.lastEventMessage = "Update available: v\(latest.version)."
            } else {
                self.availableUpdate = nil
                if announce { self.lastEventMessage = "Bugu is up to date (v\(self.currentVersion))." }
            }
        }
    }

    /// Opens the release page for the available update in the browser.
    func openUpdatePage() {
        let link = availableUpdate?.url ?? UpdateChecker.releasesPageURL
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }

    private func startHookWatcher() {
        let watcher = HookEventWatcher(path: HookIntegration.eventsPath) { [weak self] event in
            Task { @MainActor in self?.applyHookEvent(event) }
        }
        watcher.start()
        hookWatcher = watcher
    }

    /// Drives state + sounds instantly from a CLI hook event (no polling latency).
    ///
    /// Each agent session is tracked independently in `hookSessions`, so when several
    /// agents run at once one session finishing doesn't reset the others. Sounds fire
    /// on a single session's transition; the menu-bar state is the *aggregate* across
    /// all live sessions (any waiting → permission, else any running → running, else the
    /// most recent terminal result).
    private func applyHookEvent(_ event: HookEventWatcher.Event) {
        guard let action = HookActionMapping.action(for: event.hookEvent) else { return }
        // Only react to CLIs the user has enabled. A stale hook left behind by a
        // since-disabled CLI must not keep driving Bugu (nil = unknown source → allow).
        if integrationStatus[event.source] == false { return }
        lastHookEventAt = Date()

        let key = hookSessionKey(event)
        let previous = hookSessions[key]?.phase
        let phase = SessionPhase(action)
        if phase == .ended {
            hookSessions.removeValue(forKey: key)
        } else {
            hookSessions[key] = (phase: phase, at: Date())
        }
        // Mirror the phase onto the project dir so the session list can badge this
        // exact task with its own state.
        if let cwd = event.cwd, !cwd.isEmpty {
            if phase == .ended {
                hookPhaseByProject.removeValue(forKey: cwd)
            } else {
                hookPhaseByProject[cwd] = (phase: phase, at: Date())
            }
        }

        // Per-session sound on a meaningful transition (deduped against the prior phase).
        switch action {
        case .started:
            if !keepAwakeEnabled {
                keepAwakeEnabled = true
                autoAwakeEngaged = true
                startPowerAssertions()
            }
            // Chirp only for a genuinely new or restarted session, not every turn.
            if previous == nil || previous == .done || previous == .failed {
                playCue(.accepted)
            }
            lastEventMessage = "\(event.source): session started."
        case .working:
            break // ongoing work is silent
        case .done:
            if previous != .done { playCue(.completed) }
            lastEventMessage = "\(event.source): turn complete."
        case .failed:
            if previous != .failed { playCue(.interrupted) }
            lastEventMessage = "\(event.source): turn failed."
        case .permission:
            if previous != .permission { playCue(.permissionNeeded) }
            lastEventMessage = "\(event.source): needs your input."
        case .ended:
            lastEventMessage = "\(event.source): session ended."
        }

        recomputeAggregateState()
        refreshSessions()
    }

    /// Stable identity for a hook session: prefer the session id, then cwd, then tty.
    private func hookSessionKey(_ event: HookEventWatcher.Event) -> String {
        if let sid = event.sessionId, !sid.isEmpty { return "\(event.source)|sid:\(sid)" }
        if let cwd = event.cwd, !cwd.isEmpty { return "\(event.source)|cwd:\(cwd)" }
        if let tty = event.tty, !tty.isEmpty { return "\(event.source)|tty:\(tty)" }
        return "\(event.source)|single"
    }

    /// Collapses all tracked hook sessions into the single menu-bar task state.
    private func recomputeAggregateState() {
        // Forget sessions we haven't heard from in a while so a missing SessionEnd
        // can't pin Bugu to "running" forever.
        let staleCutoff = Date().addingTimeInterval(-30 * 60)
        hookSessions = hookSessions.filter { $0.value.at > staleCutoff }
        hookPhaseByProject = hookPhaseByProject.filter { $0.value.at > staleCutoff }

        let phases = hookSessions.values
        if phases.contains(where: { $0.phase == .permission }) {
            taskState = .permissionNeeded(at: Date())
            startPulse()
        } else if phases.contains(where: { $0.phase == .running }) {
            if case .running = taskState {} else { taskState = .running(startedAt: Date()) }
            startPulse()
        } else if let latest = phases.max(by: { $0.at < $1.at }) {
            stopPulse()
            taskState = latest.phase == .failed
                ? .interrupted(finishedAt: latest.at)
                : .completed(finishedAt: latest.at)
            releaseAutoAwakeIfNeeded()
        } else {
            stopPulse()
            taskState = .idle
            releaseAutoAwakeIfNeeded()
        }
    }

    func refreshIntegrationStatus() {
        var status: [String: Bool] = [:]
        for cli in HookIntegration.supportedCLIs {
            status[cli.id] = HookIntegration.isInstalled(cli)
        }
        integrationStatus = status
    }

    /// Installs or removes Bugu hooks for a CLI (writes its config; backed up first).
    func setIntegration(_ cli: HookIntegration.CLI, enabled: Bool) {
        if enabled {
            HookIntegration.install(cli)
        } else {
            HookIntegration.uninstall(cli)
        }
        refreshIntegrationStatus()
    }

    /// Installs hooks for every CLI actually present on this Mac, in one click.
    func enableAllDetectedIntegrations() {
        for cli in HookIntegration.supportedCLIs where cli.isAvailable {
            HookIntegration.install(cli)
        }
        refreshIntegrationStatus()
    }

    /// Removes Bugu hooks from every CLI we previously installed into.
    func disableAllIntegrations() {
        for cli in HookIntegration.supportedCLIs where integrationStatus[cli.id] == true {
            HookIntegration.uninstall(cli)
        }
        refreshIntegrationStatus()
    }

    // MARK: - Accessibility permission (needed for precise tab jumps)

    /// Whether Bugu is trusted for Accessibility, which System Events needs to focus a
    /// specific Warp/Ghostty tab. Without it, jumps fall back to merely activating the app.
    @Published var accessibilityTrusted: Bool = AXIsProcessTrusted()

    func refreshAccessibilityStatus() {
        accessibilityTrusted = AXIsProcessTrusted()
    }

    /// Triggers the macOS permission prompt and opens the Accessibility settings pane
    /// so the user can grant Bugu in one step.
    func requestAccessibilityPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        refreshAccessibilityStatus()
    }

    /// SwiftUI binding for a single cue's custom sound selection.
    func customSoundBinding(for key: String) -> Binding<String> {
        Binding(
            get: { self.customSoundNames[key] ?? Self.defaultCustomNames[key] ?? "Funk" },
            set: { self.customSoundNames[key] = $0 }
        )
    }

    private func applyCustomSounds() {
        for option in Self.cueOptions {
            let name = customSoundNames[option.key] ?? Self.defaultCustomNames[option.key] ?? "Funk"
            soundEngine.setCustomSoundName(name, for: option.cue)
        }
    }

    /// Elapsed-time label for a watched agent, e.g. "3m 12s", or nil if unknown.
    func runtimeLabel(for pid: Int32) -> String? {
        guard let startedAt = watchedAgentStartTimes[pid] else { return nil }
        return Self.durationFormatter.string(from: Date().timeIntervalSince(startedAt))
    }

    /// Display label for one active-agent row, including runtime when available.
    func agentRowLabel(for agent: AgentProcess) -> String {
        var label = "\(agent.name) · pid \(agent.pid)"
        if let runtime = runtimeLabel(for: agent.pid) {
            label += " · \(runtime)"
        }
        return label
    }

    /// Short "time ago" label for a session's last activity.
    func relativeTime(_ date: Date) -> String {
        Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    /// Live or recently-active sessions, shown expanded.
    var currentSessions: [RecentSession] { recentSessions.filter(\.isCurrent) }
    /// Older/expired sessions, folded behind a disclosure to keep the menu short.
    var olderSessions: [RecentSession] { recentSessions.filter { !$0.isCurrent } }

    /// Per-row status icon, reusing the menu bar's five-state vocabulary so each task
    /// carries the same brand language as the global state.
    func sessionSymbol(_ s: RecentSession) -> String {
        switch s.displayPhase {
        case .running: return "bird.fill"
        case .permission: return "hand.raised.fill"
        case .done, .ended: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .none: return s.isActive ? "bird.fill" : "circle.fill"
        }
    }

    /// Per-row status colour matching `sessionSymbol`.
    func sessionColor(_ s: RecentSession) -> Color {
        switch s.displayPhase {
        case .running: return .blue
        case .permission: return .orange
        case .done, .ended: return .green
        case .failed: return .red
        case .none: return s.isActive ? .blue : Color.secondary.opacity(0.4)
        }
    }

    /// Reloads the recent-session list off the main thread (transcript reads + lsof).
    /// Debounced: rapid callers (e.g. a burst of hook events) collapse into a single
    /// reload so we don't hammer the disk and `lsof` on every PostToolUse.
    func refreshSessions(immediate: Bool = false) {
        sessionRefreshTask?.cancel()
        sessionRefreshTask = Task { [weak self] in
            if !immediate {
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
            guard !Task.isCancelled, let self else { return }
            let live = self.activeAgents
            var sessions = await Task.detached(priority: .utility) {
                RecentSessionStore.load(liveAgents: live)
            }.value
            guard !Task.isCancelled else { return }
            // Overlay each session's own latest hook state (matched by project dir).
            let phases = self.hookPhaseByProject
            sessions = sessions.map { session in
                var session = session
                if !session.projectPath.isEmpty, let entry = phases[session.projectPath] {
                    session.displayPhase = entry.phase
                }
                return session
            }
            self.recentSessions = sessions
        }
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
            return pulseOn ? "bird.fill" : "bird"
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

    private static let autoWatchKey = "autoWatchEnabled"
    /// Whether to watch agents on launch. Defaults to ON the first time so the beacon
    /// is useful out of the box; afterwards it honours the user's saved choice.
    private static func loadAutoWatch() -> Bool {
        if UserDefaults.standard.object(forKey: autoWatchKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: autoWatchKey)
    }

    private static let alertVolumeKey = "alertVolume"
    private static let soundProfileKey = "soundProfile"
    private static let customSoundsKey = "customSoundNames"

    private static func loadCustomSoundNames() -> [String: String] {
        let stored = UserDefaults.standard.dictionary(forKey: customSoundsKey) as? [String: String]
        var names = defaultCustomNames
        if let stored {
            for (key, value) in stored where systemSoundNames.contains(value) {
                names[key] = value
            }
        }
        return names
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter
    }()

    private static func loadAlertVolume() -> Double {
        if UserDefaults.standard.object(forKey: alertVolumeKey) == nil {
            return 0.65
        }
        return clampAlertVolume(UserDefaults.standard.double(forKey: alertVolumeKey))
    }

    private static func loadSoundProfile() -> BuguSoundProfile {
        guard let raw = UserDefaults.standard.string(forKey: soundProfileKey),
              let profile = BuguSoundProfile(rawValue: raw) else {
            return .system
        }
        return profile
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
        UserDefaults.standard.set(enabled, forKey: Self.autoWatchKey)
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
        startPulse()
    }

    func playRunning() {
        taskState = .running(startedAt: Date())
        lastEventMessage = "Running: task heartbeat cue."
        playCue(.running)
        scheduleHeartbeat()
        startPulse()
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
        stopPulse()
        stopAgentWatcher()
        taskState = .idle
        lastEventMessage = "Stopped watching. Bugu is idle."
    }

    func markCompleted() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        stopPulse()
        taskState = .completed(finishedAt: Date())
        lastEventMessage = "Done: task completed."
        playCue(.completed)
    }

    func markInterrupted() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        stopPulse()
        taskState = .interrupted(finishedAt: Date())
        lastEventMessage = "Interrupted: task stopped unexpectedly."
        playCue(.interrupted)
    }

    func playPermissionNeeded() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        stopPulse()
        taskState = .permissionNeeded(at: Date())
        lastEventMessage = "Permission needed: waiting for user approval."
        playCue(.permissionNeeded)
    }

    func playHeartbeat() {
        guard case .running = taskState else {
            // No task is running, so there is nothing to announce. Tear down the stray
            // timer instead of beeping — previously this branch still played a sound,
            // which made Bugu chirp even when idle.
            heartbeatTimer?.invalidate()
            heartbeatTimer = nil
            lastEventMessage = "Heartbeat skipped because no task is running."
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
        pulseTimer?.invalidate()
        pulseTimer = nil
        hookWatcher?.stop()
        hookWatcher = nil
        if simulatedAgentProcess?.isRunning == true {
            simulatedAgentProcess?.terminate()
        }
        stopPowerAssertions()
    }

    private func startAgentWatcher() {
        autoWatchEnabled = true
        // Establish the baseline off the main thread, then schedule periodic scans.
        Task.detached(priority: .utility) {
            let snapshot = AgentProcessScanner.scan()
            await MainActor.run { [weak self] in self?.applyBaseline(snapshot) }
        }

        agentScanTimer?.invalidate()
        agentScanTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scanAgents() }
        }
    }

    /// Records the initial set of running agents without announcing any of them, so a
    /// watcher started mid-task doesn't immediately chirp.
    private func applyBaseline(_ snapshot: [AgentProcess]) {
        activeAgents = snapshot
        knownAgentPIDs = Set(snapshot.map(\.pid))
        announcedAgentPIDs.removeAll()
        // Treat agents already running at baseline as started "now" so the menu can
        // show an approximate runtime instead of nothing.
        let now = Date()
        for agent in snapshot {
            watchedAgentStartTimes[agent.pid] = now
        }
        lastEventMessage = "Watching coding agents. Baseline: \(snapshot.count) active."
        refreshSessions(immediate: true)
    }

    private func stopAgentWatcher() {
        agentScanTimer?.invalidate()
        agentScanTimer = nil
        activeAgents = []
        knownAgentPIDs.removeAll()
        announcedAgentPIDs.removeAll()
        watchedAgentStartTimes.removeAll()
        agentMissCounts.removeAll()
        autoWatchEnabled = false
        lastEventMessage = "Agent watcher stopped."
    }

    /// Kicks off a process scan on a background thread; results are applied on main.
    /// `ps -axo` over every process is too heavy to run on the UI thread every 2s.
    private func scanAgents() {
        Task.detached(priority: .utility) {
            let snapshot = AgentProcessScanner.scan()
            await MainActor.run { [weak self] in self?.applyScan(snapshot) }
        }
    }

    private func applyScan(_ snapshot: [AgentProcess]) {
        let currentPIDs = Set(snapshot.map(\.pid))
        // Genuinely new = appeared this scan and not already tracked (a pid that
        // flickered out for a sample and came back is not "new").
        let newPIDs = currentPIDs.subtracting(knownAgentPIDs).subtracting(announcedAgentPIDs)

        // Liveness debounce: an announced agent must be missing from two consecutive
        // scans before we treat it as ended, so a single dropped `ps` sample can't
        // fire a false completion/interruption cue.
        var endedAnnouncedPIDs = Set<Int32>()
        for pid in announcedAgentPIDs {
            if currentPIDs.contains(pid) {
                agentMissCounts[pid] = 0
            } else {
                let misses = (agentMissCounts[pid] ?? 0) + 1
                agentMissCounts[pid] = misses
                if misses >= 2 { endedAnnouncedPIDs.insert(pid) }
            }
        }
        let newAgents = snapshot.filter { newPIDs.contains($0.pid) }

        activeAgents = snapshot

        if !newAgents.isEmpty {
            // Only treat this as a *new session* (and play the start cue) when no agents
            // were being tracked before. Agents constantly spawn short-lived child
            // processes that also match our signatures; without this guard every one of
            // them re-triggered the "accepted" sound on each 3s scan.
            let wasIdle = announcedAgentPIDs.isEmpty
            announcedAgentPIDs.formUnion(newAgents.map(\.pid))
            let now = Date()
            for agent in newAgents {
                watchedAgentStartTimes[agent.pid] = now
            }
            if wasIdle && !hooksRecentlyActive {
                handleAgentStarted(newAgents)
            } else if !wasIdle {
                let names = newAgents.map(\.name).joined(separator: ", ")
                lastEventMessage = "Additional agent detected: \(names)."
            }
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
                agentMissCounts.removeValue(forKey: pid)
            }
            announcedAgentPIDs.subtract(endedAnnouncedPIDs)
            if announcedAgentPIDs.isEmpty {
                if hooksRecentlyActive {
                    // Hooks own state/sound right now; just fall idle quietly.
                    taskState = .idle
                } else if shortLivedCount > 0 {
                    handleWatchedAgentsInterrupted(count: endedAnnouncedPIDs.count)
                } else {
                    handleWatchedAgentsCompleted(count: endedAnnouncedPIDs.count)
                }
            } else {
                lastEventMessage = "\(endedAnnouncedPIDs.count) watched agent process ended; \(announcedAgentPIDs.count) still running."
            }
        }

        knownAgentPIDs = currentPIDs

        // Refresh the session list the moment the live set changes, so green dots and
        // new sessions appear promptly instead of only when the menu is next opened.
        if !newPIDs.isEmpty || !endedAnnouncedPIDs.isEmpty {
            refreshSessions()
        }
    }

    private func handleAgentStarted(_ agents: [AgentProcess]) {
        if !keepAwakeEnabled {
            // The watcher (not the user) is enabling keep-awake, so remember to
            // release it automatically when all watched agents finish.
            keepAwakeEnabled = true
            autoAwakeEngaged = true
            startPowerAssertions()
        }
        taskState = .running(startedAt: Date())
        let names = agents.map(\.name).joined(separator: ", ")
        lastEventMessage = "Detected agent start: \(names). Heartbeat every \(heartbeatLabel)."
        playCue(.accepted)
        scheduleHeartbeat()
        startPulse()
    }

    private func handleWatchedAgentsCompleted(count: Int) {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        stopPulse()
        let released = releaseAutoAwakeIfNeeded()
        taskState = .completed(finishedAt: Date())
        lastEventMessage = "\(count) watched agent process ended."
            + (released ? " Keep-awake released automatically." : "")
        playCue(.completed)
    }

    private func handleWatchedAgentsInterrupted(count: Int) {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        stopPulse()
        let released = releaseAutoAwakeIfNeeded()
        taskState = .interrupted(finishedAt: Date())
        lastEventMessage = "\(count) watched agent process stopped too quickly."
            + (released ? " Keep-awake released automatically." : "")
        playCue(.interrupted)
    }

    /// Releases keep-awake only if the watcher engaged it (never overrides a manual
    /// keep-awake the user turned on themselves). Returns whether it released.
    @discardableResult
    private func releaseAutoAwakeIfNeeded() -> Bool {
        guard autoAwakeEngaged else { return false }
        autoAwakeEngaged = false
        stopPowerAssertions()
        return true
    }

    // MARK: - Menu bar pulse

    private func startPulse() {
        guard pulseTimer == nil else { return }
        pulseOn = true
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pulseOn.toggle()
            }
        }
    }

    private func stopPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        pulseOn = false
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

struct AgentProcess: Identifiable, Hashable, Sendable {
    let pid: Int32
    let name: String
    let command: String
    /// Controlling terminal (e.g. "ttys001"), or nil for processes without one.
    /// Used to collapse an agent's child processes that share the same tab.
    let tty: String?

    var id: Int32 { pid }
}

enum AgentProcessScanner {
    struct Signature {
        let name: String
        let patterns: [String]
    }

    // Full agent roster, modelled on the set competitors like Vibe Island support.
    // Order matters: the first matching signature wins, so more specific patterns
    // (path fragments, hyphenated names) come before bare-word fallbacks. Short or
    // common names use word-boundary regexes to limit false positives; the dedup,
    // cwd-matching and ignore list further suppress noise.
    private static let signatures: [Signature] = [
        Signature(name: "Codex", patterns: ["codex-agent-sim", #"(^|[/\s])codex($|\s)"#]),
        Signature(name: "Claude Code", patterns: [#"(^|[/\s])claude($|\s)"#]),
        // `.kimi-code/` is the install/config dir; the bare "kimi-code" substring is
        // intentionally omitted because it false-matches project paths like
        // "bugu-kimi-code-demo". The word-boundary `kimi` still catches the binary.
        Signature(name: "Kimi Code", patterns: [".kimi-code/", #"(^|[/\s])kimi($|\s)"#]),
        Signature(name: "OpenCode", patterns: [".opencode/", #"(^|[/\s])opencode($|\s)"#]),
        Signature(name: "Gemini CLI", patterns: [#"(^|[/\s])gemini($|\s)"#]),
        Signature(name: "Cursor Agent", patterns: ["cursor-agent"]),
        Signature(name: "Qwen Code", patterns: ["qwen-code", #"(^|[/\s])qwen($|\s)"#]),
        Signature(name: "Trae", patterns: ["trae-agent", #"(^|[/\s])trae($|\s)"#]),
        Signature(name: "Droid", patterns: ["factory-droid", #"(^|[/\s])droid($|\s)"#]),
        Signature(name: "Qoder", patterns: [#"(^|[/\s])qoder($|\s)"#]),
        Signature(name: "Mistral Vibe", patterns: ["mistral-vibe", "mistral_vibe"]),
        Signature(name: "CodeBuddy", patterns: [".codebuddy/", "codebuddy"]),
        Signature(name: "WorkBuddy", patterns: ["workbuddy"]),
        Signature(name: "Hermes", patterns: ["hermes-agent", "hermes-cli", #"(^|[/\s])hermes($|\s)"#]),
        Signature(name: "Pi Agent", patterns: ["pi-agent"]),
        Signature(name: "Kiro CLI", patterns: ["kiro-cli", #"(^|[/\s])kiro($|\s)"#]),
        Signature(name: "Aider", patterns: [#"(^|[/\s])aider($|\s)"#]),
        Signature(name: "Goose", patterns: [#"(^|[/\s])goose($|\s)"#]),
        Signature(name: "Amp", patterns: [#"(^|[/\s])amp($|\s)"#]),
        Signature(name: "Crush", patterns: [#"(^|[/\s])crush($|\s)"#]),
        Signature(name: "Devin", patterns: [#"(^|[/\s])devin($|\s)"#]),
        Signature(name: "OpenHands", patterns: ["openhands"])
    ]

    static func scan() -> [AgentProcess] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,tty=,command="]
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

        // Exclude our own process so Bugu never counts itself as an agent — e.g. the
        // dev binary lives under a path containing "kimi-code", which would otherwise
        // match the Kimi signature.
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let matched = output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap(parseLine)
            .filter { $0.pid != selfPID && !shouldIgnore(command: $0.command) }
            .compactMap { entry -> AgentProcess? in
                guard let name = matchedAgentName(command: entry.command) else {
                    return nil
                }
                return AgentProcess(pid: entry.pid, name: name, command: entry.command, tty: entry.tty)
            }
            .sorted { $0.pid < $1.pid }

        // Collapse one logical session to a single entry: an agent spawns many
        // child processes that share its controlling terminal, and listing each
        // one separately both clutters the UI and (before this) re-fired sounds.
        // Group by (tty, name) and keep the lowest-PID representative. Processes
        // without a tty are kept individually since we cannot prove they belong
        // to the same session.
        var representatives: [String: AgentProcess] = [:]
        for agent in matched {
            let key: String
            if let tty = agent.tty {
                key = "tty:\(tty)|\(agent.name)"
            } else {
                key = "pid:\(agent.pid)"
            }
            if representatives[key] == nil {
                representatives[key] = agent
            }
        }

        return representatives.values.sorted { $0.pid < $1.pid }
    }

    static func parseLine(_ line: Substring) -> (pid: Int32, tty: String?, command: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Columns: PID TTY COMMAND (COMMAND may itself contain spaces).
        let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count == 3, let pid = Int32(parts[0]) else {
            return nil
        }

        let rawTTY = String(parts[1])
        // ps prints "??" for processes without a controlling terminal.
        let tty: String? = (rawTTY == "??" || rawTTY.isEmpty) ? nil : rawTTY
        let command = String(parts[2]).trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty else {
            return nil
        }
        return (pid, tty, command)
    }

    static func shouldIgnore(command: String) -> Bool {
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
            // Codex / Claude internal background machinery, not user-launched tasks.
            // This mirrors the built-in filter list competitors (e.g. Vibe Island)
            // ship: memory writers, consolidation, guardian/auto-review, chronicle,
            // and the Claude-Mem background plugin all run as headless agent
            // processes that should never count as a live coding session.
            "chronicle",
            "screen_recording",
            "x-openai-memgen",
            "codex remote ssh",
            "memory writer",
            "memory consolidation",
            "memgen",
            "autoreview",
            "auto-review",
            "guardian",
            "claude-mem",
            "claudemem",
            "rg -i",
            "ps -axo",
            // Name collisions with bare-word agent signatures: the Goose DB migration
            // tool's subcommands (vs Block's Goose agent) look nothing like an agent
            // session, so filter them out explicitly.
            "goose up", "goose down", "goose create", "goose status", "goose -dir",
            "goose redo", "goose validate", "goose migrate"
        ]
        return ignoredFragments.contains { lower.contains($0) }
    }

    static func matchedAgentName(command: String) -> String? {
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
