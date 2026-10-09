import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let model: DeskModel

    @AppStorage(Prefs.corner) private var corner = Corner.bottomTrailing
    @AppStorage(Prefs.pileSize) private var pileSize = 6
    @AppStorage(Prefs.showPile) private var showPile = true
    @AppStorage(Prefs.playSounds) private var playSounds = true
    @AppStorage(Prefs.smartCaptions) private var smartCaptions = true
    @AppStorage(Prefs.copyToClipboard) private var copyToClipboard = false
    @AppStorage(Prefs.tidyDesktop) private var tidyDesktop = false
    private let thumbnailState = State(initialValue: ScreenshotFolder.showsFloatingThumbnail)
    private let loginState = State(initialValue: SMAppService.mainApp.status == .enabled)

    private var floatingThumbnail: Bool {
        get { thumbnailState.wrappedValue }
        nonmutating set { thumbnailState.wrappedValue = newValue }
    }

    private var launchAtLogin: Bool {
        get { loginState.wrappedValue }
        nonmutating set { loginState.wrappedValue = newValue }
    }

    var body: some View {
        Form {
            Section("Pile") {
                HStack(alignment: .center, spacing: 18) {
                    CornerPicker(corner: $corner, count: pileSize)
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Where prints land")
                                .font(.headline)
                            Text("Click a corner of the screen.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Picker("Corner", selection: $corner) {
                            ForEach(Corner.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                }
                .padding(.vertical, 4)
                Stepper(value: $pileSize, in: 3...10) {
                    LabeledContent("Prints in pile") {
                        HStack(spacing: 10) {
                            MiniStack(count: pileSize)
                            Text("\(pileSize)")
                                .monospacedDigit()
                                .contentTransition(.numericText(value: Double(pileSize)))
                        }
                    }
                }
                Toggle("Keep pile on screen", isOn: $showPile)
                Text("When off, the pile tucks itself away a few seconds after each print.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Play a soft sound when a print lands", isOn: $playSounds)
            }

            Section("Screenshots") {
                LabeledContent("Watching") {
                    HStack {
                        Text(model.folderURL.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .foregroundStyle(.secondary)
                            .truncationMode(.middle)
                        Button("Change…") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app"))
                        }
                        Button("Refresh") { model.refreshFolder() }
                    }
                }
                if !model.folderReadable {
                    Label("Allow access to this folder in System Settings › Privacy & Security › Files and Folders.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                Toggle("Handwrite captions from the screenshot’s text", isOn: $smartCaptions)
                Toggle("Copy each new screenshot to the clipboard", isOn: $copyToClipboard)
                Toggle("Keep my Desktop tidy", isOn: $tidyDesktop)
                Text("Files new screenshots under Pictures › Where’d It Go, one folder per day.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Speed") {
                Toggle("Show the macOS floating thumbnail", isOn: Binding(
                    get: { floatingThumbnail },
                    set: { show in
                        ScreenshotFolder.setShowsFloatingThumbnail(show)
                        floatingThumbnail = show
                    }
                ))
                Text("While the thumbnail is showing, macOS waits about five seconds before saving, so prints arrive late. Turn it off for instant prints.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Open at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            NSSound.beep()
                        }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                ))
            } footer: {
                VStack(spacing: 2) {
                    Text("Where’d It Go? \(Bundle.main.shortVersion) · Screenshots, fresh off the press.")
                    HStack(spacing: 4) {
                        Text("Made by 1xAI ·")
                        Link(AppLinks.websiteLabel, destination: AppLinks.website)
                    }
                }
                .font(.caption).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            NSApp.activate()
            floatingThumbnail = ScreenshotFolder.showsFloatingThumbnail
        }
    }
}

extension Bundle {
    var shortVersion: String { object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
}

/// A little Mac screen; click either bottom corner to send the pile there.
struct CornerPicker: View {
    @Binding var corner: Corner
    let count: Int
    private let hoverState = State<Corner?>(initialValue: nil)

    private var hovered: Corner? {
        get { hoverState.wrappedValue }
        nonmutating set { hoverState.wrappedValue = newValue }
    }

    private let screen = CGSize(width: 176, height: 110)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.42, blue: 0.68), Color(red: 0.86, green: 0.6, blue: 0.56)],
                                     startPoint: .top, endPoint: .bottom))
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    Image(systemName: "apple.logo").font(.system(size: 6))
                    Capsule().frame(width: 14, height: 2.5)
                    Capsule().frame(width: 10, height: 2.5)
                    Spacer()
                    Image(systemName: "photo.stack").font(.system(size: 6, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 7)
                .frame(height: 10)
                .background(.white.opacity(0.18))
                Spacer()
                Capsule()
                    .fill(.white.opacity(0.28))
                    .frame(width: 66, height: 9)
                    .padding(.bottom, 4)
            }

            ForEach(Corner.allCases) { option in
                let selected = option == corner
                Button {
                    withAnimation(.spring(duration: 0.45, bounce: 0.35)) { corner = option }
                } label: {
                    ZStack(alignment: option.alignment) {
                        Color.clear
                        if selected {
                            MiniStack(count: min(count, 4), scale: 0.9)
                                .transition(.scale(scale: 0.3, anchor: option.isTrailing ? .bottomTrailing : .bottomLeading)
                                    .combined(with: .opacity))
                        } else {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(.white.opacity(hovered == option ? 0.9 : 0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                                .frame(width: 22, height: 26)
                        }
                    }
                    .padding(9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: screen.width / 2, height: screen.height - 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: option.alignment)
                .onHover { hovered = $0 ? option : nil }
                .accessibilityLabel(Text(option.title))
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .frame(width: screen.width, height: screen.height)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .padding(5)
        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
    }
}

/// A tiny stack of prints, one card per print in the pile.
private struct MiniStack: View {
    let count: Int
    var scale: CGFloat = 1

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Color(white: 0.98))
                    .overlay(alignment: .top) {
                        LinearGradient(colors: [Color(red: 0.99, green: 0.74, blue: 0.55), Color(red: 0.55, green: 0.5, blue: 0.86)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 12)
                            .padding([.top, .horizontal], 2)
                    }
                    .frame(width: 16, height: 19)
                    .shadow(color: .black.opacity(0.2), radius: 0.8, y: 0.5)
                    .rotationEffect(.degrees(Double(index - count / 2) * 7))
                    .offset(x: CGFloat(index) * 1.2, y: CGFloat(-index) * 0.8)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .scaleEffect(scale)
        .frame(width: 30, height: 26)
        .animation(.spring(duration: 0.35, bounce: 0.4), value: count)
        .accessibilityHidden(true)
    }
}
