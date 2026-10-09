import SwiftUI

enum Prefs {
    static let tidyDesktop = "tidyDesktop"
    static let copyToClipboard = "copyToClipboard"
    static let smartCaptions = "smartCaptions"
    static let playSounds = "playSounds"
    static let pileSize = "pileSize"
    static let corner = "corner"
    static let showPile = "showPile"
    static let hasOnboarded = "hasOnboarded"

    static func register() {
        UserDefaults.standard.register(defaults: [
            smartCaptions: true,
            playSounds: true,
            pileSize: 6,
            corner: Corner.bottomTrailing.rawValue,
            showPile: true,
        ])
    }
}

enum Corner: String, CaseIterable, Identifiable {
    case bottomTrailing
    case bottomLeading

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .bottomTrailing: "Bottom Right"
        case .bottomLeading: "Bottom Left"
        }
    }

    var isTrailing: Bool { self == .bottomTrailing }
    var alignment: Alignment { isTrailing ? .bottomTrailing : .bottomLeading }
    var horizontal: HorizontalAlignment { isTrailing ? .trailing : .leading }
    var edge: Edge.Set { isTrailing ? .trailing : .leading }
}

enum Layout {
    static let cardWidth: CGFloat = 132
    static let cardHeight: CGFloat = 158
    static let cardInset: CGFloat = 8
    static let photoHeight: CGFloat = 104
    static var captionHeight: CGFloat { cardHeight - cardInset - photoHeight }

    static let edgeInset: CGFloat = 24
    static let badgeHeight: CGFloat = 26
    static let pileSize = CGSize(width: 220, height: 252)

    static let fanStep: CGFloat = 96
    static let fanHeight: CGFloat = 300
    static let fanLift: CGFloat = 22
    static let fanHoverScale: CGFloat = 1.06
    static var pileBottomInset: CGFloat { badgeHeight + 14 }

    static func fanWidth(count: Int) -> CGFloat {
        cardWidth + CGFloat(max(0, count - 1)) * fanStep + edgeInset * 2 + 40
    }

    /// Clockwise rotation, in degrees, of a fanned card.
    static func fanAngle(index: Int, trailing: Bool) -> Double {
        (trailing ? 1 : -1) * (2.5 - Double(index) * 2.2)
    }

    /// Index of the topmost fanned card under a point measured inward from the pile's
    /// screen edge and up from the bottom of the panel.
    static func fanCard(inward: CGFloat, up: CGFloat, count: Int, trailing: Bool, lifted: Int?) -> Int? {
        func contains(_ index: Int) -> Bool {
            let anchorInward = edgeInset + CGFloat(index) * fanStep + cardWidth / 2
            let anchorUp = pileBottomInset + CGFloat(index) * 4
            let theta = fanAngle(index: index, trailing: trailing) * .pi / 180
            let dx = (inward - anchorInward) * (trailing ? -1 : 1), dy = anchorUp - up
            let x = dx * cos(theta) + dy * sin(theta)
            let y = -dx * sin(theta) + dy * cos(theta)
            let isLifted = index == lifted
            let halfWidth = cardWidth / 2 * (isLifted ? fanHoverScale : 1)
            let top = cardHeight * (isLifted ? fanHoverScale : 1) + (isLifted ? fanLift : 0)
            return abs(x) <= halfWidth && y <= 0 && y >= -top
        }
        if let lifted, lifted < count, contains(lifted) { return lifted }
        return (0..<count).first(where: contains)
    }

    static let stationSize = CGSize(width: 180, height: 296)
    static let slotY: CGFloat = 124

    static let screenMargin: CGFloat = 10
}
