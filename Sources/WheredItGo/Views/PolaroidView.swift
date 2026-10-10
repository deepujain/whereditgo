import SwiftUI

struct PolaroidView: View {
    let shot: Shot
    var develop: Double = 1
    var lifted = false
    /// Pointer position across the card (0...1) for a holographic glint, or nil for none.
    var sheen: Double?
    var shadowed = true

    private let ink = Color(red: 0.16, green: 0.19, blue: 0.36)

    var body: some View {
        VStack(spacing: 0) {
            photo
                .frame(width: Layout.cardWidth - Layout.cardInset * 2, height: Layout.photoHeight)
                .overlay {
                    if let sheen {
                        Holo(position: sheen).allowsHitTesting(false)
                    }
                }
                .clipped()
                .overlay(Rectangle().strokeBorder(.black.opacity(0.14), lineWidth: 0.5))
            VStack(spacing: 0) {
                Text(shot.title)
                    .font(.custom("Noteworthy-Bold", size: 15))
                    .foregroundStyle(ink)
                Text(shot.subtitle)
                    .font(.custom("Noteworthy-Light", size: 10))
                    .foregroundStyle(ink.opacity(0.6))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .frame(height: Layout.captionHeight)
            .opacity(min(1, max(0, (develop - 0.5) / 0.4)))
        }
        .padding([.top, .horizontal], Layout.cardInset)
        .frame(width: Layout.cardWidth, height: Layout.cardHeight, alignment: .top)
        .background(Paper())
        .clipShape(RoundedRectangle(cornerRadius: 2.5, style: .continuous))
        .shadow(color: .black.opacity(shadowed ? 0.2 : 0), radius: 1, y: 1)
        .shadow(color: Color(red: 0.2, green: 0.1, blue: 0).opacity(shadowed ? (lifted ? 0.34 : 0.24) : 0), radius: lifted ? 16 : 7, y: lifted ? 12 : 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shot.accessibilityLabel)
        .accessibilityValue(shot.accessibilityText ?? "")
        .accessibilityAddTraits(.isImage)
    }

    @ViewBuilder private var photo: some View {
        let fog = 1 - develop
        ZStack {
            if let image = shot.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                SamplePhoto()
            }
        }
        // Undeveloped, the picture is already there under a milky haze, pale and soft, and clears.
        .blur(radius: fog * 1.5, opaque: true)
        .saturation(0.2 + 0.8 * develop)
        .contrast(1 - 0.35 * fog)
        .overlay {
            RadialGradient(colors: [Color(red: 0.9, green: 0.9, blue: 0.88), Color(red: 0.76, green: 0.79, blue: 0.82)],
                           center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: 110)
                .opacity(fog * 0.55)
        }
        .overlay {
            LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0)], startPoint: .topLeading, endPoint: UnitPoint(x: 0.45, y: 0.55))
        }
    }
}

/// A soft rainbow glint that slides across the card with the pointer, like a foil trading card.
private struct Holo: View {
    let position: Double

    var body: some View {
        let center = position * 1.4 - 0.2
        func stop(_ color: Color, _ offset: Double) -> Gradient.Stop {
            .init(color: color, location: min(1, max(0, center + offset)))
        }
        return LinearGradient(stops: [
            stop(.clear, -0.34),
            stop(Color(hue: 0.52, saturation: 0.5, brightness: 1).opacity(0.18), -0.16),
            stop(Color(hue: 0.14, saturation: 0.35, brightness: 1).opacity(0.3), -0.04),
            stop(.white.opacity(0.34), 0),
            stop(Color(hue: 0.88, saturation: 0.45, brightness: 1).opacity(0.22), 0.1),
            stop(Color(hue: 0.68, saturation: 0.5, brightness: 1).opacity(0.14), 0.2),
            stop(.clear, 0.34),
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
        .blendMode(.plusLighter)
    }
}

/// Stand-in artwork for places where there is no real screenshot, like the welcome window.
struct SamplePhoto: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.99, green: 0.78, blue: 0.55), Color(red: 0.93, green: 0.53, blue: 0.6), Color(red: 0.5, green: 0.47, blue: 0.86)],
                           startPoint: .top, endPoint: .bottom)
            Circle().fill(Color(red: 1, green: 0.93, blue: 0.75)).frame(width: 34, height: 34).offset(y: 6)
            Rectangle().fill(Color(red: 0.32, green: 0.3, blue: 0.55).opacity(0.85)).frame(height: 30).offset(y: 40)
        }
    }
}

/// Faintly textured instant-film paper.
struct Paper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.995), Color(red: 0.95, green: 0.94, blue: 0.91)], startPoint: .top, endPoint: .bottom)
            Image(nsImage: PaperGrain.tile)
                .resizable(resizingMode: .tile)
                .opacity(0.5)
        }
    }
}

@MainActor
enum PaperGrain {
    static let tile: NSImage = {
        let size = 64
        var generator = SystemRandomNumberGenerator()
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            for _ in 0..<420 {
                let x = CGFloat.random(in: 0..<CGFloat(size), using: &generator)
                let y = CGFloat.random(in: 0..<CGFloat(size), using: &generator)
                NSColor(white: .random(in: 0.35...0.7), alpha: .random(in: 0.04...0.12)).setFill()
                NSRect(x: x, y: y, width: 0.8, height: 0.8).fill()
            }
            return true
        }
        return image
    }()
}
