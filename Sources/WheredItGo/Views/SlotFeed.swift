import SwiftUI

/// A print feeding out of the camera slot. Above the slot line it stays hidden; the part that is out
/// bends toward the viewer over the slot's lip, with the lip's shadow and a curl at the leading edge,
/// and lies flat once the print is all the way out.
struct SlotFeed: ViewModifier {
    /// 0 while the print is inside the camera, 1 once it is fully out.
    var progress: Double
    /// Extra bend in degrees, for the slap as the print falls flat.
    var flop: Double = 0

    private static let maxBend = 64.0

    func body(content: Content) -> some View {
        let out = min(1, max(0, progress))
        let emerging = out < 1
        let curl = pow(1 - out, 0.65)
        let bend = curl * Self.maxBend + flop
        content
            .brightness(-0.16 * curl)
            .overlay(alignment: .bottom) {
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.45), location: 0.55),
                    .init(color: .black.opacity(0.22), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                .frame(height: 16)
                .opacity(curl)
                .allowsHitTesting(false)
            }
            .offset(y: (out - 1) * Layout.cardHeight)
            .frame(width: Layout.cardWidth, height: Layout.cardHeight, alignment: .top)
            .mask(alignment: .top) {
                Rectangle()
                    .frame(width: Layout.cardWidth * 2, height: Layout.cardHeight * (emerging ? 1 : 3))
                    .offset(y: emerging ? 0 : -Layout.cardHeight)
            }
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.black.opacity(0.5), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 9)
                    LinearGradient(colors: [.white.opacity(0), .white.opacity(0.35), .white.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 5)
                        .blendMode(.plusLighter)
                }
                .frame(width: Layout.cardWidth)
                .opacity(emerging ? min(1, out * 10) : 0)
                .allowsHitTesting(false)
            }
            .rotation3DEffect(.degrees(bend), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.55)
    }
}

extension View {
    func feedingFromSlot(_ progress: Double, flop: Double = 0) -> some View {
        modifier(SlotFeed(progress: progress, flop: flop))
    }
}
