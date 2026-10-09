import SwiftUI

/// The part of a print that has left the camera slot, drawn as a flexible sheet: it leaves the slot
/// pointing toward the viewer, droops more the further it hangs out, and falls flat when released.
struct CurlingPrint: View, Animatable {
    /// The undeveloped print, `Layout.cardWidth` × `Layout.cardHeight`.
    let sheet: NSImage
    /// 0 while the print is inside the camera, 1 once it is fully out.
    var progress: Double
    /// 0 while the rollers hold the print, 1 once it lies flat. Springs may overshoot.
    var relax: Double

    nonisolated var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(progress, relax) }
        set { progress = newValue.first; relax = newValue.second }
    }

    var body: some View {
        let length = Layout.cardHeight * min(1, max(0, progress))
        let slices = Self.slices(length: length, relax: relax)
        ZStack(alignment: .top) {
            ForEach(slices.indices, id: \.self) { index in
                let slice = slices[index]
                Image(nsImage: sheet)
                    .resizable()
                    .frame(width: Layout.cardWidth, height: Layout.cardHeight)
                    .offset(y: -(Layout.cardHeight - length + slice.start))
                    .frame(width: Layout.cardWidth, height: slice.length, alignment: .top)
                    .clipped()
                    .brightness(slice.shade)
                    .scaleEffect(x: slice.scale, y: slice.height / slice.length, anchor: .top)
                    .offset(y: slice.top)
            }
        }
        .frame(width: Layout.cardWidth, height: Layout.cardHeight, alignment: .top)
        .compositingGroup()
        .shadow(color: Color(red: 0.2, green: 0.1, blue: 0).opacity(0.25), radius: 6, y: 4)
    }

    // MARK: Geometry

    private struct Slice {
        var start: CGFloat
        var length: CGFloat
        var top: CGFloat
        var height: CGFloat
        var scale: CGFloat
        var shade: Double
    }

    /// Angle from straight down, in radians, at which paper leaves the slot.
    private static let exitAngle = 1.2
    private static let viewerDistance: CGFloat = 520
    private static let sliceLength: CGFloat = 3

    private static func slices(length: CGFloat, relax: Double) -> [Slice] {
        guard length > 0.5 else { return [] }
        let count = max(1, Int((length / sliceLength).rounded(.up)))
        let step = length / CGFloat(count)
        var y: CGFloat = 0, z: CGFloat = 0
        var result: [Slice] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            let start = CGFloat(index) * step
            let theta = angle(at: start + step / 2, length: length) * (1 - relax)
            let near = viewerDistance / (viewerDistance - z)
            let top = y * near
            y += cos(theta) * step
            z += sin(theta) * step
            let far = viewerDistance / (viewerDistance - z)
            let slotShadow = -0.28 * exp(-start / 7) * (1 - min(1, max(0, relax)))
            result.append(Slice(start: start, length: step, top: top, height: max(0.01, y * far - top + 0.6),
                                scale: (near + far) / 2, shade: slotShadow + 0.07 * sin(theta)))
        }
        return result
    }

    /// Stiff paper held at the slot sags like a cantilever under its own weight:
    /// the bend at each point grows with the cube of how much paper hangs beyond it.
    private static func angle(at s: CGFloat, length: CGFloat) -> CGFloat {
        let full = Layout.cardHeight
        let sag = 3 * (exitAngle + 0.12) / (full * full * full)
        let hanging = pow(length, 3) - pow(length - s, 3)
        return max(-0.12, exitAngle - sag * hanging / 3)
    }
}

@MainActor
enum PrintSheet {
    /// A still image of the print before it develops, for drawing it as it curls out of the slot.
    static func render(_ shot: Shot) -> NSImage? {
        let renderer = ImageRenderer(content: PolaroidView(shot: shot, develop: 0, shadowed: false))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.nsImage
    }
}
