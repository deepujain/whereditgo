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
                Picker("Corner", selection: $corner) {
                    ForEach(Corner.allCases) { Text($0.title).tag($0) }
                }
                Stepper(value: $pileSize, in: 3...10) {
                    LabeledContent("Prints in pile", value: "\(pileSize)")
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
