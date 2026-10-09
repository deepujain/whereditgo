import SwiftUI

/// A little instant camera, drawn in a 180 × 126 pt design space.
struct CameraView: View {
    var flash: Double = 0
    /// Direction the lens looks, up to length 1, with y pointing up.
    var gaze: CGSize = .zero

    private let cream = LinearGradient(
        colors: [Color(red: 0.99, green: 0.97, blue: 0.93), Color(red: 0.94, green: 0.90, blue: 0.83), Color(red: 0.86, green: 0.80, blue: 0.70)],
        startPoint: .top, endPoint: .bottom
    )
    private let stripe: [Color] = [
        Color(red: 0.91, green: 0.28, blue: 0.23), Color(red: 0.95, green: 0.60, blue: 0.17),
        Color(red: 0.96, green: 0.81, blue: 0.23), Color(red: 0.27, green: 0.68, blue: 0.35),
        Color(red: 0.18, green: 0.50, blue: 0.88),
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.95, green: 0.42, blue: 0.35), Color(red: 0.78, green: 0.22, blue: 0.17)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 22, height: 10)
                .offset(x: 140, y: 2)

            body(shape: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .frame(width: 180, height: 116)
                .offset(y: 8)

            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(white: 0.11))
                .overlay(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.4, green: 0.48, blue: 0.65).opacity(0.7))
                        .frame(width: 8, height: 5).offset(x: 3, y: 3)
                }
                .frame(width: 24, height: 16)
                .offset(x: 16, y: 20)

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: [.white, Color(red: 0.85, green: 0.88, blue: 0.92)], startPoint: .top, endPoint: .bottom))
                .overlay {
                    VStack(spacing: 5) {
                        ForEach(0..<3, id: \.self) { _ in Rectangle().fill(Color(red: 0.5, green: 0.58, blue: 0.66).opacity(0.3)).frame(height: 0.75) }
                    }
                    .padding(.horizontal, 5)
                }
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
                .frame(width: 44, height: 22)
                .offset(x: 122, y: 18)

            HStack(spacing: 0) {
                ForEach(stripe.indices, id: \.self) { stripe[$0].frame(width: 5) }
            }
            .frame(height: 46)
            .offset(x: 18, y: 46)

            lens.frame(width: 80, height: 80).offset(x: 50, y: 26)

            Capsule()
                .fill(Color(red: 0.17, green: 0.15, blue: 0.13))
                .overlay(alignment: .top) { Capsule().fill(.black.opacity(0.6)).frame(height: 2) }
                .frame(width: 140, height: 6)
                .offset(x: 20, y: 114)

            Text(verbatim: "WHERE’D IT GO?")
                .font(.system(size: 5, weight: .heavy, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(Color(red: 0.72, green: 0.66, blue: 0.56))
                .fixedSize()
                .frame(width: 52, alignment: .center)
                .offset(x: 118, y: 98)

            Circle()
                .fill(RadialGradient(colors: [.white, Color(red: 1, green: 0.98, blue: 0.9).opacity(0.7), .white.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: 60))
                .frame(width: 120, height: 120)
                .offset(x: 84, y: -31)
                .opacity(flash)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        }
        .frame(width: 180, height: 126, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private func body(shape: some InsettableShape) -> some View {
        shape.fill(cream)
            .overlay(alignment: .top) {
                shape.fill(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .frame(height: 40)
                    .mask(alignment: .top) { Rectangle().frame(height: 26) }
            }
            .overlay(shape.strokeBorder(.black.opacity(0.12), lineWidth: 0.75))
            .shadow(color: Color(red: 0.25, green: 0.12, blue: 0).opacity(0.35), radius: 14, y: 10)
    }

    private var lens: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(white: 0.3), Color(white: 0.14), Color(white: 0.05)],
                                         center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: 44))
            Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1)
            Circle().fill(Color(white: 0.08)).overlay(Circle().strokeBorder(Color(white: 0.24), lineWidth: 1.5)).padding(9)
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0.43, green: 0.5, blue: 0.84), Color(red: 0.16, green: 0.18, blue: 0.42),
                                                  Color(red: 0.05, green: 0.05, blue: 0.13), .black],
                                         center: UnitPoint(x: 0.38, y: 0.34), startRadius: 0, endRadius: 30))
                    .padding(17)
                Circle().fill(Color(red: 0.02, green: 0.03, blue: 0.06)).frame(width: 14, height: 14)
                    .offset(x: gaze.width * 3, y: -gaze.height * 3)
            }
            .offset(x: gaze.width * 3, y: -gaze.height * 3)
            .clipShape(Circle().inset(by: 10))
            Ellipse().fill(.white.opacity(0.55)).frame(width: 13, height: 8).rotationEffect(.degrees(-30))
                .offset(x: -9 - gaze.width * 1.5, y: -10 + gaze.height * 1.5)
            Circle().fill(.white.opacity(0.3)).frame(width: 4, height: 4)
                .offset(x: 9 - gaze.width, y: 9 + gaze.height)
        }
    }
}
