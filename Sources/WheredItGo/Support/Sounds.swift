import AppKit

/// Small sound effects: a few that ship with macOS, plus a shutter and print motor synthesized on first use.
@MainActor
enum Sounds {
    private static let systemSounds = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds"

    private static let swishes: [NSSound] = (1...4).compactMap {
        NSSound(contentsOfFile: "\(systemSounds)/ink/InkSoundStroke\($0).aif", byReference: true)
    }
    private static let poofSound = NSSound(contentsOfFile: "\(systemSounds)/dock/poof item off dock.aif", byReference: true)
    private static let shutterSound = NSSound(contentsOfFile: "\(systemSounds)/system/Shutter.aif", byReference: true)
    private static let feedSound = Synth.paperFeed(length: DeskModel.feedDuration)

    private static var enabled: Bool { UserDefaults.standard.bool(forKey: Prefs.playSounds) }

    /// Only for pictures the app takes itself; macOS already plays a shutter for screenshots.
    static func shutter() {
        play(shutterSound, volume: 0.5)
    }

    /// A soft hush of paper sliding through the rollers.
    static func motor() {
        play(feedSound, volume: 0.22)
    }

    static func landing() {
        guard enabled else { return }
        play(NSSound(named: "Pop"), volume: 0.25)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    static func copied() {
        play(NSSound(named: "Tink"), volume: 0.2)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
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

/// Builds short mono WAV clips from a sample function.
private enum Synth {
    /// Band-limited noise with a slow swell: no tone, so it reads as paper rather than a buzzer.
    static func paperFeed(length: Double) -> NSSound? {
        var noise = Noise()
        var low = 0.0, lower = 0.0
        return clip(seconds: length) { t in
            let envelope = min(1, t / 0.25) * min(1, max(0, length - t) / 0.35)
            let white = noise.next()
            low += 0.18 * (white - low)
            lower += 0.03 * (low - lower)
            let band = low - lower
            let texture = 0.85 + 0.15 * sin(2 * .pi * 7 * t)
            return band * texture * envelope * 1.6
        }
    }

    static let rate = 44_100.0

    private static func clip(seconds: Double, _ sample: (Double) -> Double) -> NSSound? {
        let count = Int(seconds * rate)
        var data = Data(capacity: 44 + count * 2)
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + count * 2))
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(rate)); append(UInt32(rate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(UInt32(count * 2))
        for index in 0..<count {
            let value = max(-1, min(1, sample(Double(index) / rate)))
            append(Int16(value * 32_000))
        }
        return NSSound(data: data)
    }

    private struct Noise {
        private var state: UInt32 = 0x9E37_79B9
        mutating func next() -> Double {
            state = state &* 1_664_525 &+ 1_013_904_223
            return Double(state) / Double(UInt32.max) * 2 - 1
        }
    }
}
