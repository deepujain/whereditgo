import AppKit
import SwiftUI

/// A photographed instant camera, laid out in a 180 × 136 pt design space.
struct CameraView: View {
    var flash: Double = 0
    /// Direction the lens looks, up to length 1, with y pointing up.
    var gaze: CGSize = .zero

    nonisolated static let size = CGSize(width: 180, height: 136)
    nonisolated static let lensCenter = CGPoint(x: 90, y: 60)
    /// Vertical centre of the print slot.
    nonisolated static let slotCenter: CGFloat = 117
    private static let glassRadius: CGFloat = 12
    private static let flashCenter = CGPoint(x: 150, y: 25)

    private static let photo: NSImage? = {
        if let url = Bundle.main.url(forResource: "Camera", withExtension: "png") { return NSImage(contentsOf: url) }
        #if DEBUG
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return NSImage(contentsOf: source.appending(path: "Resources/Camera.png"))
        #else
        return nil
        #endif
    }()

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let photo = Self.photo {
                Image(nsImage: photo)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: Self.size.width, height: Self.size.height)
                    .shadow(color: Color(red: 0.25, green: 0.12, blue: 0).opacity(0.35), radius: 12, y: 8)
            }

            glass
                .frame(width: Self.glassRadius * 2, height: Self.glassRadius * 2)
                .offset(x: Self.lensCenter.x - Self.glassRadius, y: Self.lensCenter.y - Self.glassRadius)

            Circle()
                .fill(RadialGradient(colors: [.white, Color(red: 1, green: 0.98, blue: 0.9).opacity(0.7), .white.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: 60))
                .frame(width: 120, height: 120)
                .offset(x: Self.flashCenter.x - 60, y: Self.flashCenter.y - 60)
                .opacity(flash)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    /// Shifts a pupil and a glint inside the real lens glass so the camera seems to look around.
    private var glass: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [.black.opacity(0.75), .black.opacity(0)], center: .center, startRadius: 0, endRadius: 7))
                .frame(width: 14, height: 14)
                .offset(x: gaze.width * 4, y: -gaze.height * 4)
            Ellipse()
                .fill(.white.opacity(0.55))
                .frame(width: 6, height: 3.5)
                .rotationEffect(.degrees(-30))
                .blur(radius: 0.4)
                .offset(x: -4 - gaze.width * 2, y: -4 + gaze.height * 2)
        }
        .clipShape(Circle())
        .allowsHitTesting(false)
    }
}
