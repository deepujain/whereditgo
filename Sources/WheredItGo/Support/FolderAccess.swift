import AppKit

/// In the App Sandbox the app may read only folders the user has picked. This asks once and keeps
/// the permission across launches as a security-scoped bookmark.
@MainActor
enum FolderAccess {
    nonisolated static let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    private static let key = "screenshotFolderBookmark"
    private static var opened: URL?

    /// Reopens the folder granted on an earlier launch.
    static func restore() {
        guard isSandboxed, let data = UserDefaults.standard.data(forKey: key) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                 bookmarkDataIsStale: &stale) else { return }
        open(url)
        if stale { save(url) }
    }

    /// Asks the user to choose the screenshot folder, starting at `suggested`.
    static func request(_ suggested: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = suggested
        panel.prompt = String(localized: "Allow Access")
        panel.message = String(localized: "Choose the folder where macOS saves your screenshots, so Where’d It Go? can print them.")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        if isSandboxed {
            save(url)
            open(url)
        }
        return url
    }

    private static func save(_ url: URL) {
        guard let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil,
                                               relativeTo: nil) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func open(_ url: URL) {
        guard opened != url else { return }
        opened?.stopAccessingSecurityScopedResource()
        opened = url.startAccessingSecurityScopedResource() ? url : nil
    }
}
