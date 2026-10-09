import SwiftUI

/// The About window: the camera prints its own credits. Click the camera to take another.
struct AboutView: View {
    let model: DeskModel
    private let animated: Bool

    private let feedState: State<Double>
    private let flopState = State(initialValue: 0.0)
    private let flashState = State(initialValue: 0.0)
    private let developStartState: State<Date>
    private let frameState: State<Int>
    private let busyState = State(initialValue: false)
    private let cardState = State(initialValue: Self.creditsCard(title: "made by 1xAI"))

    private var feed: Double { get { feedState.wrappedValue } nonmutating set { feedState.wrappedValue = newValue } }
    private var flop: Double { get { flopState.wrappedValue } nonmutating set { flopState.wrappedValue = newValue } }
    private var flash: Double { get { flashState.wrappedValue } nonmutating set { flashState.wrappedValue = newValue } }
    private var developStart: Date { get { developStartState.wrappedValue } nonmutating set { developStartState.wrappedValue = newValue } }
    private var frame: Int { get { frameState.wrappedValue } nonmutating set { frameState.wrappedValue = newValue } }
    private var busy: Bool { get { busyState.wrappedValue } nonmutating set { busyState.wrappedValue = newValue } }
    private var card: Shot { get { cardState.wrappedValue } nonmutating set { cardState.wrappedValue = newValue } }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Pass `animated: false` to show the credits print already out and developed.
    init(model: DeskModel, animated: Bool = true) {
        self.model = model
        self.animated = animated
        feedState = State(initialValue: animated ? 0 : 1)
        developStartState = State(initialValue: animated ? .distantFuture : .distantPast)
        frameState = State(initialValue: animated ? 0 : 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            stage
                .frame(height: 330, alignment: .top)
                .padding(.top, 34)

            VStack(spacing: 6) {
                Text(verbatim: "Where’d It Go?")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Version \(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("Every screenshot, fresh off the press.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            HStack(spacing: 10) {
                Text("Made by")
                    .foregroundStyle(.secondary)
                Text(verbatim: "1xAI")
                    .font(.system(.body, design: .rounded).weight(.heavy))
            }
            .padding(.top, 18)

            Link(destination: AppLinks.website) {
                Label("Visit the website", systemImage: "safari")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(.top, 10)

            Text(verbatim: Bundle.main.copyright)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 14)
                .padding(.bottom, 22)
        }
        .frame(width: 340)
        .background(alignment: .top) {
            LinearGradient(colors: [Color(red: 1, green: 0.84, blue: 0.64).opacity(0.55),
                                    Color(red: 0.98, green: 0.62, blue: 0.66).opacity(0.3), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 380)
                .ignoresSafeArea()
        }
        .onAppear {
            if animated { takePicture(after: .milliseconds(450)) }
        }
    }

    private var stage: some View {
        ZStack(alignment: .top) {
            Button {
                takePicture()
            } label: {
                CameraView(flash: flash)
            }
            .buttonStyle(.plain)
            .help(Text("Take another"))
            .accessibilityLabel(Text("Take another picture"))

            TimelineView(.animation(paused: feed < 1 && developStart == .distantFuture)) { context in
                PolaroidView(shot: card, develop: min(1, max(0, context.date.timeIntervalSince(developStart) / 2.2)))
            }
            .feedingFromSlot(reduceMotion ? 1 : feed, flop: flop)
            .rotationEffect(.degrees(frame.isMultiple(of: 2) ? -2 : 2.5), anchor: .top)
            .padding(.top, CameraView.slotCenter)
            .allowsHitTesting(false)
        }
    }

    private func takePicture(after delay: Duration = .zero) {
        guard !busy else { return }
        busy = true
        Task {
            try? await Task.sleep(for: delay)
            if feed > 0 {
                withAnimation(.easeIn(duration: 0.25)) { feed = 0 }
                try? await Task.sleep(for: .milliseconds(260))
            }
            card = nextPrint()
            frame += 1
            Sounds.shutter()
            withAnimation(.easeOut(duration: 0.05)) { flash = 1 }
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(.easeOut(duration: 0.5)) { flash = 0 }
            developStart = Date().addingTimeInterval(0.3)
            Sounds.motor()
            withAnimation(.timingCurve(0.3, 0.1, 0.45, 1, duration: DeskModel.feedDuration)) { feed = 1 }
            try? await Task.sleep(for: .seconds(DeskModel.feedDuration))
            withAnimation(.easeIn(duration: 0.08)) { flop = -10 }
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.spring(duration: 0.5, bounce: 0.55)) { flop = 0 }
            busy = false
        }
    }

    /// The first print carries the credits; after that the camera reprints your recent screenshots.
    private func nextPrint() -> Shot {
        let recent = model.shots.prefix(6)
        guard frame > 0 else { return Self.creditsCard(title: "made by 1xAI") }
        guard !recent.isEmpty else { return Self.creditsCard(title: String(localized: "say cheese!")) }
        let source = recent[recent.startIndex + (frame - 1) % recent.count]
        let shot = Shot(url: source.url, date: source.date, app: source.app)
        shot.title = source.title
        shot.image = source.image
        return shot
    }

    private static func creditsCard(title: String) -> Shot {
        let shot = Shot(url: URL(fileURLWithPath: "/"), date: .now, app: "v\(Bundle.main.shortVersion)")
        shot.title = title
        return shot
    }
}

extension Bundle {
    var buildNumber: String { object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }
    var copyright: String { object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "© 2026 1xAI" }
}
