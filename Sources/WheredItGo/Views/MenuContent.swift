import SwiftUI

struct MenuContent: View {
    let model: DeskModel
    let showWelcome: () -> Void
    let showAbout: () -> Void
    @AppStorage(Prefs.showPile) private var showPile = true

    var body: some View {
        if model.shots.isEmpty {
            Text("No prints yet today")
        } else {
            let recent = Array(model.shots.prefix(8))
            ForEach(TimeOfDay.allCases.reversed(), id: \.self) { part in
                let shots = recent.filter { $0.timeOfDay == part }
                if !shots.isEmpty {
                    Section(part.title) {
                        ForEach(shots) { shot in
                            Button {
                                model.open(shot)
                            } label: {
                                if let thumbnail = shot.menuThumbnail {
                                    Image(nsImage: thumbnail)
                                }
                                Text("\(shot.title) — \(shot.time)")
                            }
                        }
                    }
                }
            }
        }

        Divider()
        Toggle("Keep Pile on Screen", isOn: $showPile)
        Button("Open Screenshots Folder") { model.openFolder() }
            .keyboardShortcut("o")
        Button("Sweep Pile Away") { model.clearPile() }
            .keyboardShortcut(.delete)
            .disabled(!model.canSweep)

        Divider()
        Button("About Where’d It Go?", action: showAbout)
        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",")
        Button("Welcome Tour…", action: showWelcome)
        Link("Visit Website", destination: AppLinks.website)

        Divider()
        Button("Quit Where’d It Go?") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
