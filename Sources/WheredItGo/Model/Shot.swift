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

    /// The largest legible line of text in the screenshot, used as its handwritten caption.
    static func headline(_ url: URL) -> String? {
        guard let image = thumbnail(url, maxPixel: 1800)?.cgImage else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: image).perform([request])

        var best: (score: CGFloat, text: String)?
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first, candidate.confidence > 0.5 else { continue }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (3...40).contains(text.count), !text.contains("://"), !text.lowercased().hasPrefix("www.") else { continue }
            let letters = text.unicodeScalars.filter(CharacterSet.letters.contains).count
            guard Double(letters) / Double(text.count) > 0.6 else { continue }
            let score = observation.boundingBox.height * (text.count >= 5 ? 1 : 0.7)
            if score > (best?.score ?? 0) { best = (score, text) }
        }
        guard let text = best?.text else { return nil }
        return text.count > 24 ? text.prefix(22).trimmingCharacters(in: .whitespaces) + "…" : text
    }
}
