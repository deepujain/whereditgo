import AppKit
import ImageIO
import Observation
import Vision

@MainActor
@Observable
final class Shot: Identifiable {
    let id = UUID()
    var url: URL
    let date: Date
    let app: String?
    var title: String
    var image: NSImage?
    /// Every line of text Vision found, top to bottom.
    var text: String?
    let tilt: Double
    let nudge: CGSize

    init(url: URL, date: Date, app: String?) {
        self.url = url
        self.date = date
        self.app = app
        title = app?.lowercased() ?? String(localized: "screenshot")
        tilt = .random(in: -7...7)
        nudge = CGSize(width: .random(in: -6...6), height: .random(in: -4...4))
    }

    var time: String { date.formatted(date: .omitted, time: .shortened).lowercased() }

    var subtitle: String {
        guard let app = app?.lowercased(), app != title else { return time }
        return "\(app) · \(time)"
    }

    var accessibilityLabel: String {
        String(localized: "Screenshot: \(title), \(subtitle)")
    }

    /// The first few lines of recognized text, so VoiceOver can say what’s in the picture.
    var accessibilityText: String? {
        guard let text, !text.isEmpty else { return nil }
        let preview = text.split(separator: "\n").prefix(4).joined(separator: ". ")
        return preview.count > 160 ? String(preview.prefix(160)) + "…" : preview
    }

    var timeOfDay: TimeOfDay { TimeOfDay(date) }
}

enum TimeOfDay: Int, CaseIterable, Comparable {
    case morning, afternoon, evening

    init(_ date: Date) {
        let hour = Calendar.current.component(.hour, from: date)
        self = hour < 12 ? .morning : hour < 17 ? .afternoon : .evening
    }

    var title: String {
        switch self {
        case .morning: String(localized: "Morning")
        case .afternoon: String(localized: "Afternoon")
        case .evening: String(localized: "Evening")
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension Shot {

    var menuThumbnail: NSImage? {
        guard let image else { return nil }
        let size = NSSize(width: 28, height: 20)
        return NSImage(size: size, flipped: false) { rect in
            let source = image.size
            let scale = max(rect.width / source.width, rect.height / source.height)
            let drawn = NSSize(width: source.width * scale, height: source.height * scale)
            let origin = NSPoint(x: (rect.width - drawn.width) / 2, y: (rect.height - drawn.height) / 2)
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).addClip()
            image.draw(in: NSRect(origin: origin, size: drawn))
            return true
        }
    }
}

struct SendableImage: @unchecked Sendable {
    let cgImage: CGImage
}

enum ShotImaging {
    static func thumbnail(_ url: URL, maxPixel: Int) -> SendableImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return SendableImage(cgImage: image)
    }

    struct Reading: Sendable {
        /// The largest legible line, used as the handwritten caption.
        var headline: String?
        var text: String
    }

    static func read(_ url: URL) -> Reading? {
        guard let image = thumbnail(url, maxPixel: 1800)?.cgImage else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: image).perform([request])
        let observations = request.results ?? []

        let lines = observations
            .sorted { $0.boundingBox.minY > $1.boundingBox.minY }
            .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var best: (score: CGFloat, text: String)?
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first, candidate.confidence > 0.5 else { continue }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (3...40).contains(text.count), !text.contains("://"), !text.lowercased().hasPrefix("www.") else { continue }
            let letters = text.unicodeScalars.filter(CharacterSet.letters.contains).count
            guard Double(letters) / Double(text.count) > 0.6 else { continue }
            let score = observation.boundingBox.height * (text.count >= 5 ? 1 : 0.7)
            if score > (best?.score ?? 0) { best = (score, text) }
        }
        let headline = best.map { $0.text.count > 24 ? $0.text.prefix(22).trimmingCharacters(in: .whitespaces) + "…" : $0.text }
        return Reading(headline: headline, text: lines.joined(separator: "\n"))
    }
}
