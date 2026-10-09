#if DEBUG
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Renders the main desk states to PNGs for visual review: `WheredItGo --snapshots <dir> <image>...`.
@MainActor
enum Snapshots {
    static func render(to folder: URL, images: [URL]) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let titles = ["Revenue", "Bug #482", "Launch plan", "Design review", "Team chat", "Trail map"]
        let apps = ["Numbers", "Xcode", "Notes", "Keynote", "Messages", "Maps"]
        let count = images.isEmpty ? SampleScreen.Kind.allCases.count : images.count
        let shots = (0..<count).map { index in
            let url = images.indices.contains(index) ? images[index] : URL(fileURLWithPath: "/sample-\(index).png")
            let shot = Shot(url: url, date: Date().addingTimeInterval(Double(-index) * 1500), app: apps[index % apps.count])
            shot.title = titles[index % titles.count]
            if images.indices.contains(index), let image = ShotImaging.thumbnail(url, maxPixel: 720) {
                shot.image = NSImage(cgImage: image.cgImage, size: .zero)
            } else {
                shot.image = SampleScreen.image(SampleScreen.Kind.allCases[index % SampleScreen.Kind.allCases.count])
            }
            return shot
        }
        let model = DeskModel()

        model.stage(shots: Array(shots.dropFirst()), printing: shots.first, develop: 0.45, expanded: false, hint: true)
        try write(scene(model, size: CGSize(width: Layout.pileSize.width, height: Layout.pileSize.height + Layout.stationSize.height)),
                  to: folder.appending(path: "1-printing.png"))

        model.stage(shots: shots, printing: nil, develop: 1, expanded: false, hint: false)
        try write(scene(model, size: Layout.pileSize), to: folder.appending(path: "2-pile.png"))

        model.stage(shots: shots, printing: nil, develop: 1, expanded: true, hint: false)
        try write(scene(model, size: CGSize(width: Layout.fanWidth(count: model.visibleShots.count), height: Layout.fanHeight)),
                  to: folder.appending(path: "3-fan.png"))
        try write(hitMap(model), to: folder.appending(path: "3-fan-hits.png"))

        model.stage(shots: Array(shots.prefix(4)), printing: nil, develop: 1, expanded: true, hint: false)
        for (index, shot) in model.visibleShots.enumerated() {
            model.hoveredShot = shot.id
            try write(hitMap(model), to: folder.appending(path: "3-fan4-lifted-\(index).png"))
        }
        model.hoveredShot = nil

        model.stage(shots: shots, printing: nil, develop: 1, expanded: false, hint: false)
        model.stageSweep(pointerInside: true, tossed: 0, swept: 0)
        try write(scene(model, size: Layout.pileSize), to: folder.appending(path: "6-sweep-button.png"))
        model.stageSweep(pointerInside: true, tossed: 2, swept: 0)
        try write(scene(model, size: Layout.pileSize), to: folder.appending(path: "7-sweeping.png"))
        model.stage(shots: [], printing: nil, develop: 1, expanded: false, hint: false)
        model.stageSweep(pointerInside: true, tossed: 0, swept: 6)
        try write(scene(model, size: Layout.pileSize), to: folder.appending(path: "8-undo.png"))

        let welcome = WelcomeView(model: model) {}.background(Color(nsColor: .windowBackgroundColor))
        try write(AnyView(welcome), to: folder.appending(path: "4-welcome.png"))

        try write(AnyView(SettingsView(model: model).background(Color(nsColor: .windowBackgroundColor))),
                  to: folder.appending(path: "5-settings.png"))
    }

    private static func scene(_ model: DeskModel, size: CGSize) -> AnyView {
        AnyView(
            DeskView(model: model)
                .frame(width: size.width, height: size.height)
                .background(LinearGradient(colors: [Color(red: 0.36, green: 0.42, blue: 0.62), Color(red: 0.82, green: 0.6, blue: 0.55)],
                                           startPoint: .top, endPoint: .bottom))
        )
    }

    /// The fan with a dot grid tinted by which card the pointer hit test picks.
    private static func hitMap(_ model: DeskModel) -> AnyView {
        let size = CGSize(width: Layout.fanWidth(count: model.visibleShots.count), height: Layout.fanHeight)
        let items = model.visibleShots
        let lifted = items.firstIndex { $0.id == model.hoveredShot }
        let colors: [Color] = [.red, .orange, .yellow, .green, .cyan, .purple, .pink, .brown, .mint, .indigo]
        let dots = Canvas { context, _ in
            for x in stride(from: CGFloat(3), to: size.width, by: 7) {
                for y in stride(from: CGFloat(3), to: size.height, by: 7) {
                    guard let index = Layout.fanCard(inward: size.width - x, up: size.height - y, count: items.count,
                                                     trailing: true, lifted: lifted) else { continue }
                    context.fill(Path(ellipseIn: CGRect(x: x - 2, y: y - 2, width: 4, height: 4)),
                                 with: .color(colors[index % colors.count]))
                }
            }
        }
        return AnyView(ZStack { scene(model, size: size); dots }.frame(width: size.width, height: size.height))
    }

    private static func write(_ view: AnyView, to url: URL) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}
/// Made-up app windows, so README images never contain anyone's real screen.
struct SampleScreen: View {
    enum Kind: CaseIterable { case chart, code, notes, slide, chat, map }
    let kind: Kind

    @MainActor
    static func image(_ kind: Kind) -> NSImage? {
        let renderer = ImageRenderer(content: SampleScreen(kind: kind).frame(width: 360, height: 225))
        renderer.scale = 2
        return renderer.nsImage
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: wallpaper, startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 0) {
                HStack(spacing: 5) {
                    ForEach([Color.red, .orange, .green], id: \.self) { Circle().fill($0.opacity(0.85)).frame(width: 7, height: 7) }
                    Spacer()
                }
                .padding(.horizontal, 9)
                .frame(height: 18)
                .background(dark ? Color(white: 0.2) : Color(white: 0.93))
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(dark ? Color(white: 0.12) : .white)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
            .padding(.horizontal, 26)
            .padding(.vertical, 20)
        }
    }

    private var dark: Bool { kind == .code }

    private var wallpaper: [Color] {
        switch kind {
        case .chart: [Color(red: 0.55, green: 0.75, blue: 0.95), Color(red: 0.35, green: 0.45, blue: 0.85)]
        case .code: [Color(red: 0.25, green: 0.2, blue: 0.45), Color(red: 0.1, green: 0.1, blue: 0.2)]
        case .notes: [Color(red: 0.98, green: 0.85, blue: 0.55), Color(red: 0.95, green: 0.6, blue: 0.45)]
        case .slide: [Color(red: 0.95, green: 0.6, blue: 0.7), Color(red: 0.6, green: 0.45, blue: 0.85)]
        case .chat: [Color(red: 0.6, green: 0.9, blue: 0.8), Color(red: 0.3, green: 0.65, blue: 0.75)]
        case .map: [Color(red: 0.75, green: 0.9, blue: 0.6), Color(red: 0.4, green: 0.7, blue: 0.5)]
        }
    }

    private func bar(_ width: CGFloat, _ color: Color = Color(white: 0.82), height: CGFloat = 6) -> some View {
        RoundedRectangle(cornerRadius: height / 2).fill(color).frame(width: width, height: height)
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .chart:
            VStack(alignment: .leading, spacing: 8) {
                bar(90, Color(white: 0.3), height: 8)
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(Array([0.35, 0.55, 0.45, 0.75, 0.6, 0.9, 0.8].enumerated()), id: \.offset) { _, value in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .bottom, endPoint: .top))
                            .frame(width: 22, height: 120 * value)
                    }
                }
            }
            .padding(14)
        case .code:
            VStack(alignment: .leading, spacing: 7) {
                ForEach(0..<9, id: \.self) { line in
                    HStack(spacing: 6) {
                        bar(CGFloat(10 + (line * 13) % 30), .purple.opacity(0.8))
                        bar(CGFloat(40 + (line * 37) % 120), line == 4 ? .red.opacity(0.8) : .cyan.opacity(0.7))
                        bar(CGFloat(20 + (line * 23) % 50), .orange.opacity(0.7))
                    }
                    .padding(.leading, CGFloat(line % 3) * 12)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .notes:
            VStack(alignment: .leading, spacing: 9) {
                bar(120, Color(white: 0.25), height: 9)
                ForEach(0..<6, id: \.self) { line in
                    HStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 2).strokeBorder(.orange, lineWidth: 1.5).frame(width: 9, height: 9)
                        bar(CGFloat(110 + (line * 41) % 120))
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .slide:
            VStack(spacing: 10) {
                bar(150, Color(white: 0.25), height: 12)
                bar(110)
                HStack(spacing: 10) {
                    ForEach([Color.pink, .purple, .orange], id: \.self) { RoundedRectangle(cornerRadius: 6).fill($0.opacity(0.7)).frame(width: 64, height: 50) }
                }
            }
        case .chat:
            VStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { index in
                    HStack {
                        if index.isMultiple(of: 2) { Spacer() }
                        Capsule().fill(index.isMultiple(of: 2) ? Color.blue : Color(white: 0.88))
                            .frame(width: CGFloat(90 + (index * 47) % 100), height: 18)
                        if !index.isMultiple(of: 2) { Spacer() }
                    }
                }
            }
            .padding(14)
        case .map:
            ZStack {
                Color(red: 0.9, green: 0.94, blue: 0.86)
                Path { path in
                    path.move(to: CGPoint(x: 20, y: 160))
                    path.addCurve(to: CGPoint(x: 290, y: 30), control1: CGPoint(x: 120, y: 40), control2: CGPoint(x: 190, y: 190))
                }
                .stroke(.blue, style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [1, 9]))
                Image(systemName: "mappin.circle.fill").font(.system(size: 26)).foregroundStyle(.red).offset(x: 130, y: -55)
            }
        }
    }
}
#endif
