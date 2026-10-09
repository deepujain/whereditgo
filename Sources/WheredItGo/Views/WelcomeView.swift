import SwiftUI

struct WelcomeView: View {
    let model: DeskModel
    let onDone: () -> Void

    private let baselineState = State(initialValue: 0)
    private let thumbnailState = State(initialValue: ScreenshotFolder.showsFloatingThumbnail)
    private let sampleState = State(initialValue: Shot(url: URL(fileURLWithPath: "/"), date: .now, app: nil))
    private let printedState = State(initialValue: false)

    private var baseline: Int {
        get { baselineState.wrappedValue }
        nonmutating set { baselineState.wrappedValue = newValue }
    }

    private var floatingThumbnail: Bool {
        get { thumbnailState.wrappedValue }
        nonmutating set { thumbnailState.wrappedValue = newValue }
    }

    private var sample: Shot { sampleState.wrappedValue }

    private var printed: Bool {
        get { printedState.wrappedValue }
        nonmutating set { printedState.wrappedValue = newValue }
    }

    var body: some View {
        VStack(spacing: 22) {
            hero
            VStack(spacing: 8) {
                Text("Where’d It Go?")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Every screenshot gets printed into a little pile in the corner of your screen. Grab it while it’s fresh and drop it anywhere.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 16) {
                step(symbol: "folder.fill", tint: .blue,
                     title: "Watching \(model.folderURL.lastPathComponent)",
                     detail: "Where macOS saves your screenshots. You can change it in the Screenshot app.")
                step(symbol: "bolt.fill", tint: .orange,
                     title: "Instant prints",
                     detail: floatingThumbnail
                         ? "The macOS floating thumbnail holds screenshots back for about five seconds."
                         : "The macOS floating thumbnail is off, so prints arrive right away.") {
                    if floatingThumbnail {
                        Button("Turn Off") {
                            ScreenshotFolder.setShowsFloatingThumbnail(false)
                            floatingThumbnail = false
                        }
                    } else {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3)
                    }
                }
                step(symbol: "camera.viewfinder", tint: .pink,
                     title: "Try it now",
                     detail: printed ? "Look at the corner of your screen." : "Press ⇧⌘4 and drag across anything.") {
                    if printed {
                        Label("Printed!", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.headline)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .padding(18)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button(action: onDone) {
                Text("Start Printing").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 36)
        .padding(.top, 28)
        .padding(.bottom, 28)
        .frame(width: 540)
        .onAppear {
            baseline = model.arrivals
            sample.title = String(localized: "where’d it go?")
        }
        .onChange(of: model.arrivals) { _, count in
            withAnimation(.spring(duration: 0.4, bounce: 0.4)) { printed = count > baseline }
        }
    }

    private var hero: some View {
        ZStack(alignment: .top) {
            CameraView()
            PolaroidView(shot: sample)
                .feedingFromSlot(0.8)
                .rotationEffect(.degrees(2), anchor: .top)
                .padding(.top, CameraView.slotCenter)
        }
        .frame(width: 200, height: 262, alignment: .top)
        .padding(.top, 6)
    }

    private func step(symbol: String, tint: Color, title: String, detail: String,
                      @ViewBuilder accessory: () -> some View = { EmptyView() }) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            accessory()
        }
    }
}
