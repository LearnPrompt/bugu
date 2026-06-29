import AppKit
import AVFoundation
import Foundation

/// Selects which set of sounds the engine should play.
enum BuguSoundProfile: String, CaseIterable, Identifiable {
    case system
    case bugu
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .bugu: return "Bugu Pack"
        case .custom: return "Custom"
        }
    }
}

/// Plays status cues using either macOS system sounds or the bundled Bugu MP3 pack.
@MainActor
final class BuguSoundEngine {

    /// The set of status cues Bugu can announce with sound.
    enum Cue {
        case accepted
        case running
        case completed
        case interrupted
        case permissionNeeded
    }

    private(set) var currentProfile: BuguSoundProfile = .system

    /// User-chosen macOS system sound name per cue, used by the `.custom` profile.
    /// Falls back to the default mapping for any cue the user has not customised.
    private var customSoundNames: [Cue: String] = [:]

    /// Holds the currently playing Bugu Pack MP3 player so the sound is not
    /// deallocated before it finishes.
    private var currentPlayer: AVAudioPlayer?

    /// Changes the active sound pack. The next `play(_:volume:)` will use the new pack.
    func setProfile(_ profile: BuguSoundProfile) {
        currentProfile = profile
    }

    /// Sets the macOS system sound used for a cue under the `.custom` profile.
    func setCustomSoundName(_ name: String, for cue: Cue) {
        customSoundNames[cue] = name
    }

    /// Plays the cue for the current profile at the requested volume.
    /// Volume is clamped to the same 0.2...1.0 range the UI enforces.
    func play(_ cue: Cue, volume: Float) {
        let clampedVolume = min(max(volume, 0.2), 1.0)

        switch currentProfile {
        case .system:
            playSystemSound(cue, volume: clampedVolume)
        case .bugu:
            playBuguSound(cue, volume: clampedVolume)
        case .custom:
            playCustomSound(cue, volume: clampedVolume)
        }
    }

    // MARK: - Custom pack

    private func playCustomSound(_ cue: Cue, volume: Float) {
        let name = customSoundNames[cue] ?? defaultSystemSoundName(for: cue)
        guard let sound = NSSound(named: NSSound.Name(name)) else {
            playSystemSound(cue, volume: volume)
            return
        }
        sound.volume = volume
        sound.play()
    }

    // MARK: - System pack

    private func playSystemSound(_ cue: Cue, volume: Float) {
        guard let sound = NSSound(named: systemSoundName(for: cue)) else {
            return
        }
        sound.volume = volume
        sound.play()
    }

    private func systemSoundName(for cue: Cue) -> NSSound.Name {
        NSSound.Name(defaultSystemSoundName(for: cue))
    }

    /// The default macOS system sound name for each cue. Shared by the System
    /// profile and used as the fallback for any un-customised cue in Custom.
    func defaultSystemSoundName(for cue: Cue) -> String {
        switch cue {
        case .accepted:         return "Funk"
        case .running:          return "Hero"
        case .completed:        return "Blow"
        case .interrupted:      return "Basso"
        case .permissionNeeded: return "Ping"
        }
    }

    // MARK: - Bugu pack

    private func playBuguSound(_ cue: Cue, volume: Float) {
        let fileName = buguFileName(for: cue)

        // Look in the main bundle's Resources/Sounds/bugu-pack directory.
        // The build script copies the sound pack here; if it is missing, we
        // gracefully fall back to the equivalent system sound.
        let url = Bundle.main.url(
            forResource: fileName,
            withExtension: "mp3",
            subdirectory: "Sounds/bugu-pack"
        )

        guard let soundURL = url else {
            playSystemSound(cue, volume: volume)
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: soundURL)
            player.volume = volume
            player.prepareToPlay()
            player.play()
            currentPlayer = player
        } catch {
            playSystemSound(cue, volume: volume)
        }
    }

    private func buguFileName(for cue: Cue) -> String {
        switch cue {
        case .accepted:         return "start"
        case .running:          return "continue"
        case .completed:        return "success"
        case .interrupted:      return "end"
        case .permissionNeeded: return "need"
        }
    }
}
