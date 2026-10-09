import AppKit

/// Small sound effects: a few that ship with macOS, plus a shutter and print motor synthesized on first use.
@MainActor
enum Sounds {
    private static let systemSounds = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds"

    private static let swishes: [NSSound] = (1...4).compactMap {
        NSSound(contentsOfFile: "\(systemSounds)/ink/InkSoundStroke\($0).aif", byReference: true)
    }
    private static let poofSound = NSSound(contentsOfFile: "\(systemSounds)/dock/poof item off dock.aif", byReference: true)
    private static let shutterSound = Synth.shutter()
    private static let motorSound = Synth.motor()

    private static var enabled: Bool { UserDefaults.standard.bool(forKey: Prefs.playSounds) }

    static func shutter() {
        play(shutterSound, volume: 0.55)
    }

    /// The whir of the rollers pushing a print out of the slot.
    static func motor() {
        play(motorSound, volume: 0.32)
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
    static let duration = 0.9

    static func shutter() -> NSSound? {
        var noise = Noise()
        return clip(seconds: 0.2) { t in
            var s = noise.next() * exp(-t / 0.003) * 0.7
            let thunk = t - 0.03
            if thunk > 0 {
                s += sin(2 * .pi * 92 * thunk) * exp(-thunk / 0.035) * 0.8
                s += noise.next() * exp(-thunk / 0.005) * 0.45
            }
            let reset = t - 0.1
            if reset > 0 { s += noise.next() * exp(-reset / 0.004) * 0.3 }
            return s
        }
    }

    static func motor() -> NSSound? {
        var noise = Noise()
        var phase = 0.0, low = 0.0
        let length = duration
        return clip(seconds: length) { t in
            let envelope = min(1, t / 0.05) * min(1, max(0, length - t) / 0.12)
            let frequency = 118 + 10 * sin(2 * .pi * 3 * t)
            phase += frequency / Self.rate
            let saw = 2 * (phase - floor(phase)) - 1
            low += 0.12 * ((saw + noise.next() * 0.5) - low)
            let rollerTick = (t * 26).truncatingRemainder(dividingBy: 1) < 0.06 ? noise.next() * 0.18 : 0
            return (low * 0.9 + sin(2 * .pi * frequency * 2 * t) * 0.12 + rollerTick) * envelope
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
