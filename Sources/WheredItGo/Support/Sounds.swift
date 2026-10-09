import AppKit

/// Small sound effects built from sounds that ship with macOS, so they feel at home.
@MainActor
enum Sounds {
    private static let systemSounds = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds"

    private static let swishes: [NSSound] = (1...4).compactMap {
        NSSound(contentsOfFile: "\(systemSounds)/ink/InkSoundStroke\($0).aif", byReference: true)
    }
    private static let poofSound = NSSound(contentsOfFile: "\(systemSounds)/dock/poof item off dock.aif", byReference: true)

    private static var enabled: Bool { UserDefaults.standard.bool(forKey: Prefs.playSounds) }

    static func landing() {
        guard enabled else { return }
        play(NSSound(named: "Pop"), volume: 0.25)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    /// A paper flick for each print swept off the pile.
    static func swish(_ index: Int) {
        guard !swishes.isEmpty else { return }
        play(swishes[index % swishes.count], volume: 0.5)
    }

    static func poof() {
        guard enabled else { return }
        play(poofSound ?? NSSound(named: "Blow"), volume: 0.45)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    private static func play(_ sound: NSSound?, volume: Float) {
        guard enabled, let sound = sound?.copy() as? NSSound else { return }
        sound.volume = volume
        sound.play()
    }
}
