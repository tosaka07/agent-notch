import AppKit
import AVFoundation
import Defaults

/// Plays sounds for session events based on user settings.
@MainActor
enum SoundPlayer {
    private static var player: AVAudioPlayer?

    static func play(_ event: SoundEvent) {
        guard Defaults[.soundEnabled] else { return }

        let choice: SoundChoice = switch event {
        case .sessionCompleted: Defaults[.soundCompleted]
        case .subagentCompleted: Defaults[.soundSubagentCompleted]
        case .permissionWaiting: Defaults[.soundPermission]
        case .error: Defaults[.soundError]
        }

        play(choice)
    }

    static func play(_ choice: SoundChoice) {
        switch choice.kind {
        case .none:
            return
        case .system:
            if let sound = NSSound(named: choice.name) {
                sound.play()
            }
        case .custom:
            let url = URL(fileURLWithPath: choice.name)
            guard FileManager.default.fileExists(atPath: choice.name) else { return }
            player = try? AVAudioPlayer(contentsOf: url)
            player?.play()
        }
    }

    /// Preview a sound (used in settings picker).
    static func preview(_ choice: SoundChoice) {
        play(choice)
    }
}
