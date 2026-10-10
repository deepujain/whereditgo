import SwiftUI

/// The menu bar panel: today’s prints as a contact sheet, quick switches, and the way to everything else.
struct MenuContent: View {
    let model: DeskModel
    let showWelcome: () -> Void
    let showAbout: () -> Void

    @AppStorage(Prefs.showPile) private var showPile = true
    @AppStorage(Prefs.playSounds) private var playSounds = true
    @AppStorage(Prefs.tidyDesktop) private var tidyDesktop = false
    @AppStorage(Prefs.copyToClipboard) private var copyToClipboard = false
    private let instantState = State(initialValue: !ScreenshotFolder.showsFloatingThumbnail)

    private var instant: Bool {
        get { instantState.wrappedValue }
        nonmutating set { instantState.wrappedValue = newValue }
    }

    /// Room for two time-of-day rows of prints, or two rows under one heading; more scrolls.
    private static let sheetHeight: CGFloat = 212

    private var today: [Shot] {
        model.shots.filter { Calendar.current.isDateInToday($0.date) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            // A fixed height: the menu bar window keeps the size it first opened at, so content that grows gets cropped.
            Group {
                if !model.folderReadable {
                    accessNeeded
                } else if today.isEmpty {
                    emptyState
                } else {
                    ScrollView { contactSheet }
                        .scrollIndicators(.automatic)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.sheetHeight)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 12)

            switches
                .padding(.horizontal, 12)
                .padding(.top, 12)

            Divider().padding(.top, 12)
            footer
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .frame(width: 344)
        .onAppear { instant = !ScreenshotFolder.showsFloatingThumbnail }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            CameraView()
                .scaleEffect(0.26, anchor: .topLeading)
                .frame(width: CameraView.size.width * 0.26, height: CameraView.size.height * 0.26, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "Where’d It Go?")
                    .font(.system(.headline, design: .rounded))
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
        }
    }

    private var summary: String {
        guard let latest = today.first else { return String(localized: "Ready when you are") }
        return String(localized: "\(today.count) prints today · last at \(latest.time)")
    }

    // MARK: Prints

    private var contactSheet: some View {
        let recent = Array(today.prefix(8))
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(TimeOfDay.allCases.reversed(), id: \.self) { part in
                let shots = recent.filter { $0.timeOfDay == part }
                if !shots.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(part.title.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 4)
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(74), spacing: 6), count: 4), alignment: .leading, spacing: 8) {
                            ForEach(Array(shots.enumerated()), id: \.element.id) { index, shot in
                                MiniPrint(shot: shot, model: model, tilt: index.isMultiple(of: 2) ? -1.6 : 1.4, close: closeMenu)
                            }
                        }
                    }
                }
            }
            if today.count > recent.count {
                Button {
                    model.openFolder()
                    closeMenu()
                } label: {
                    Label("\(today.count - recent.count) more in the folder", systemImage: "arrow.forward.circle")
                        .font(.caption)
                }
                .buttonStyle(.link)
                .padding(.leading, 4)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessNeeded: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Allow access to \(model.folderURL.lastPathComponent)")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
            Text("Where’d It Go? prints the screenshots macOS saves there.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Allow Access…") {
                closeMenu()
                if FolderAccess.isSandboxed {
                    model.grantAccess()
                } else {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!)
                }
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("Nothing printed yet today")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
            HStack(spacing: 8) {
                Shortcut(keys: "⇧⌘3", title: "Whole screen")
                Shortcut(keys: "⇧⌘4", title: "A selection")
                Shortcut(keys: "⇧⌘5", title: "More options")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Switches

    private var switches: some View {
        HStack(spacing: 0) {
            QuickSwitch(symbol: "pin.fill", title: "On Screen", isOn: $showPile,
                        help: "Keep the pile in the corner, or let it tuck away after each print.")
            QuickSwitch(symbol: "bolt.fill", title: "Instant", isOn: Binding(
                get: { instant },
                set: { on in
                    guard ScreenshotFolder.canChangeFloatingThumbnail else {
                        closeMenu()
                        return ScreenshotFolder.openScreenshotOptions()
                    }
                    ScreenshotFolder.setShowsFloatingThumbnail(!on)
                    instant = on
                }
            ), help: ScreenshotFolder.canChangeFloatingThumbnail
                ? "Turns off the macOS floating thumbnail, which holds each screenshot back for about five seconds."
                : "Prints arrive instantly when the macOS floating thumbnail is off. Opens Screenshot, where Options has Show Floating Thumbnail.")
            QuickSwitch(symbol: "doc.on.clipboard.fill", title: "Auto Copy", isOn: $copyToClipboard,
                        help: "Copy every new screenshot to the clipboard.")
            QuickSwitch(symbol: "tray.full.fill", title: "Tidy", isOn: $tidyDesktop,
                        help: "File new screenshots under Pictures › Where’d It Go, one folder per day.")
            QuickSwitch(symbol: playSounds ? "speaker.wave.2.fill" : "speaker.slash.fill", title: "Sounds", isOn: $playSounds,
                        help: "Shutter, motor, and landing sounds.")
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 2) {
            FooterButton(symbol: "folder", title: "Open Folder") {
                model.openFolder()
                closeMenu()
            }
            .keyboardShortcut("o")
            FooterButton(symbol: "wind", title: "Sweep Pile") {
                model.clearPile()
                closeMenu()
            }
            .keyboardShortcut(.delete)
            .disabled(!model.canSweep)

            Spacer()

            FooterButton(symbol: "sparkles", title: "Welcome Tour") {
                closeMenu()
                showWelcome()
            }
            FooterButton(symbol: "info.circle", title: "About Where’d It Go?") {
                closeMenu()
                showAbout()
            }
            SettingsLink {
                FooterIcon(symbol: "gearshape")
            }
            .buttonStyle(FooterButtonStyle())
            .keyboardShortcut(",")
            .help(Text("Settings"))
            .simultaneousGesture(TapGesture().onEnded { closeMenu() })
            FooterButton(symbol: "power", title: "Quit Where’d It Go?") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    private func closeMenu() {
        NSApp.keyWindow?.close()
    }
}

/// A tiny print on the contact sheet. Click to open, drag it anywhere, right-click for more.
private struct MiniPrint: View {
    let shot: Shot
    let model: DeskModel
    let tilt: Double
    let close: () -> Void
    private let hoverState = State(initialValue: false)

    private var hovering: Bool {
        get { hoverState.wrappedValue }
        nonmutating set { hoverState.wrappedValue = newValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let image = shot.image {
                    Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                } else {
                    SamplePhoto()
                }
            }
            .frame(width: 64, height: 48)
            .clipped()
            Text(shot.title)
                .font(.custom("Noteworthy-Bold", size: 9))
                .foregroundStyle(Color(red: 0.16, green: 0.19, blue: 0.36))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 64, height: 16)
        }
        .padding([.top, .horizontal], 5)
        .background(Paper())
        .clipShape(RoundedRectangle(cornerRadius: 1.5, style: .continuous))
        .shadow(color: .black.opacity(hovering ? 0.28 : 0.16), radius: hovering ? 6 : 2, y: hovering ? 4 : 1)
        .rotationEffect(.degrees(hovering ? 0 : tilt))
        .scaleEffect(hovering ? 1.08 : 1)
        .zIndex(hovering ? 1 : 0)
        .animation(.spring(duration: 0.28, bounce: 0.4), value: hovering)
        .onHover { hovering = $0 }
        .onTapGesture {
            model.open(shot)
            close()
        }
        .onDrag { model.dragProvider(for: shot) }
        .contextMenu {
            Button("Open") { model.open(shot) }
            Button("Copy") { model.copy(shot) }
            Button("Copy Text") { model.copyText(shot) }
                .disabled(shot.text?.isEmpty ?? true)
            Button("Show in Finder") { model.reveal(shot) }
        }
        .help(Text("\(shot.title) · \(shot.time)"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shot.accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }
}

private struct Shortcut: View {
    let keys: String
    let title: LocalizedStringKey

    var body: some View {
        VStack(spacing: 4) {
            Text(verbatim: keys)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 0, y: 1)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A round Control Center–style switch.
private struct QuickSwitch: View {
    let symbol: String
    let title: LocalizedStringKey
    @Binding var isOn: Bool
    let help: LocalizedStringKey

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.3, bounce: 0.4)) { isOn.toggle() }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isOn ? Color.white : Color.primary.opacity(0.75))
                    .frame(width: 34, height: 34)
                    .background(isOn ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.quaternary), in: Circle())
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(help))
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(isOn ? "On" : "Off"))
    }
}

private struct FooterIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .frame(width: 30, height: 26)
            .contentShape(Rectangle())
    }
}

private struct FooterButton: View {
    let symbol: String
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) { FooterIcon(symbol: symbol) }
            .buttonStyle(FooterButtonStyle())
            .help(Text(title))
            .accessibilityLabel(Text(title))
    }
}

private struct FooterButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Hovering { hovering in
            configuration.label
                .foregroundStyle(.secondary)
                .opacity(isEnabled ? 1 : 0.4)
                .background(.primary.opacity(configuration.isPressed ? 0.14 : hovering && isEnabled ? 0.07 : 0),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}

private struct Hovering<Content: View>: View {
    @ViewBuilder let content: (Bool) -> Content
    private let hoverState = State(initialValue: false)

    var body: some View {
        content(hoverState.wrappedValue)
            .onHover { hoverState.wrappedValue = $0 }
    }
}
