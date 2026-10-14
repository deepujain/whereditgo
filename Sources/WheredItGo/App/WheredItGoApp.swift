import AppKit
import SwiftUI

@main
struct WheredItGoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--render-icon"), arguments.indices.contains(flag + 1) {
            do {
                try AppIconRenderer.writeIconset(to: URL(fileURLWithPath: arguments[flag + 1], isDirectory: true))
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("Icon rendering failed: \(error)\n".utf8))
                exit(1)
            }
        }
        #if DEBUG
        if let flag = arguments.firstIndex(of: "--read-text"), arguments.indices.contains(flag + 1) {
            let reading = ShotImaging.read(URL(fileURLWithPath: arguments[flag + 1]))
            print("Caption: \(reading?.headline ?? "none")\n---\n\(reading?.text ?? "no text found")")
            exit(0)
        }
        if let flag = arguments.firstIndex(of: "--snapshots"), arguments.indices.contains(flag + 1) {
            let images = arguments.dropFirst(flag + 2).map { URL(fileURLWithPath: $0) }
            do {
                try Snapshots.render(to: URL(fileURLWithPath: arguments[flag + 1], isDirectory: true), images: images)
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("Snapshots failed: \(error)\n".utf8))
                exit(1)
            }
        }
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: appDelegate.model, showWelcome: appDelegate.showWelcome, showAbout: appDelegate.showAbout)
        } label: {
            Image(systemName: "photo.stack")
                .accessibilityLabel(Text("Where’d It Go?"))
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: appDelegate.model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = DeskModel()
    private var panel: DeskPanelController?
    private var welcomeWindow: NSWindow?
    private var aboutWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.start()
        panel = DeskPanelController(model: model)
        if !UserDefaults.standard.bool(forKey: Prefs.hasOnboarded) {
            showWelcome()
        }
    }

    func showWelcome() {
        if welcomeWindow == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.title = String(localized: "Welcome to Where’d It Go?")
            window.contentView = NSHostingView(rootView: WelcomeView(model: model) { [weak self] in
                UserDefaults.standard.set(true, forKey: Prefs.hasOnboarded)
                self?.welcomeWindow?.close()
            })
            window.center()
            welcomeWindow = window
        }
        NSApp.activate()
        welcomeWindow?.makeKeyAndOrderFront(nil)
    }

    func showAbout() {
        // A fresh window each time, so the camera prints the credits again.
        aboutWindow?.close()
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.title = String(localized: "About Where’d It Go?")
        window.contentView = NSHostingView(rootView: AboutView(model: model))
        window.center()
        aboutWindow = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

enum AppLinks {
    static let website = URL(string: "https://1xaispark.com/apps/wherediditgo.html")!
    static let websiteLabel = "1xaispark.com/apps/wherediditgo.html"
}
