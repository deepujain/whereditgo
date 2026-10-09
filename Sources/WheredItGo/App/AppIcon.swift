import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Renders the app icon artwork into an `.iconset` folder for `iconutil`.
@MainActor
enum AppIconRenderer {
    static func writeIconset(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let renderer = ImageRenderer(content: AppIconArtwork())
        renderer.scale = 1
        guard let master = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
        let sizes: [(String, Int)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]
        for (name, pixels) in sizes {
            guard let image = resize(master, to: pixels),
                  let destination = CGImageDestinationCreateWithURL(folder.appending(path: "\(name).png") as CFURL,
                                                                    UTType.png.identifier as CFString, 1, nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
    }

    private static func resize(_ image: CGImage, to pixels: Int) -> CGImage? {
        guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        return context.makeImage()
    }
}

struct AppIconArtwork: View {
    private let shape = RoundedRectangle(cornerRadius: 186, style: .continuous)

    var body: some View {
        ZStack {
            shape
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.84, blue: 0.64), Color(red: 0.98, green: 0.62, blue: 0.66),
                                              Color(red: 0.66, green: 0.58, blue: 0.98)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay {
                    ZStack {
                        IconPrint()
                            .rotationEffect(.degrees(8))
                            .offset(x: 34, y: 210)
                        CameraView()
                            .scaleEffect(3.2)
                            .offset(y: -96)
                    }
                    .frame(width: 824, height: 824)
                    .clipShape(shape)
                }
                .overlay(shape.strokeBorder(.white.opacity(0.35), lineWidth: 3))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.28), radius: 22, y: 12)
        }
        .frame(width: 1024, height: 1024)
    }
}

private struct IconPrint: View {
    var body: some View {
        VStack(spacing: 0) {
            SamplePhoto()
                .scaleEffect(2.6)
                .frame(width: 300, height: 250)
                .clipped()
            Text(verbatim: "?")
                .font(.custom("Noteworthy-Bold", size: 96))
                .foregroundStyle(Color(red: 0.16, green: 0.19, blue: 0.36))
                .frame(height: 110)
        }
        .padding([.top, .horizontal], 22)
        .frame(width: 344, height: 400, alignment: .top)
        .background(Paper())
        .shadow(color: .black.opacity(0.25), radius: 18, y: 10)
    }
}
