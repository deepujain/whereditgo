import AppKit

struct FoundShot: Sendable {
    let url: URL
    let created: Date
}

/// Reads macOS screenshot settings and finds screenshots on disk.
enum ScreenshotFolder {
    static let domain = "com.apple.screencapture"
    private static let imageTypes: Set<String> = ["png", "jpg", "jpeg", "heic", "tif", "tiff"]

    static var current: URL {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["WHEREDITGO_FOLDER"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        #endif
        let defaults = UserDefaults(suiteName: domain)
        if let path = defaults?.string(forKey: "location"), !path.isEmpty {
            let url = path.hasPrefix("~")
                ? home.appending(path: String(path.dropFirst()), directoryHint: .isDirectory)
                : URL(fileURLWithPath: path, isDirectory: true)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return url
            }
        }
        return home.appending(path: "Desktop", directoryHint: .isDirectory)
    }

    /// The user's real home folder. In the App Sandbox, `NSHomeDirectory()` is the app's container.
    static var home: URL {
        guard let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir else {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
    }

    static var archiveRoot: URL {
        home.appending(path: "Pictures/Where’d It Go", directoryHint: .isDirectory)
    }

    /// macOS holds the file back while its floating thumbnail is on screen.
    static var showsFloatingThumbnail: Bool {
        UserDefaults(suiteName: domain)?.object(forKey: "show-thumbnail") as? Bool ?? true
    }

    /// A sandboxed app can read the Screenshot app's settings but not change them.
    static var canChangeFloatingThumbnail: Bool { !FolderAccess.isSandboxed }

    /// Opens the Screenshot app, whose Options menu has Show Floating Thumbnail.
    static func openScreenshotOptions() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app"))
    }

    static func setShowsFloatingThumbnail(_ show: Bool) {
        guard canChangeFloatingThumbnail else { return openScreenshotOptions() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", domain, "show-thumbnail", "-bool", show ? "true" : "false"]
        try? process.run()
        process.waitUntilExit()
    }

    static func isReadable(_ folder: URL) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) != nil
    }

    static func screenshots(in folder: URL) -> [FoundShot] {
        let keys: Set<URLResourceKey> = [.creationDateKey, .isRegularFileKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants, .skipsPackageDescendants]
        ) else { return [] }

        return urls.compactMap { url -> FoundShot? in
            guard isScreenshot(url),
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { return nil }
            return FoundShot(url: url, created: values.creationDate ?? .distantPast)
        }
        .sorted { $0.created > $1.created }
    }

    /// Screenshots carry a Spotlight attribute in every language; file names are only a fallback.
    static func isScreenshot(_ url: URL) -> Bool {
        guard imageTypes.contains(url.pathExtension.lowercased()) else { return false }
        let tagged = url.withUnsafeFileSystemRepresentation { path -> Bool in
            guard let path else { return false }
            return getxattr(path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) >= 0
        }
        if tagged { return true }
        let name = url.lastPathComponent
        return name.hasPrefix("Screenshot") || name.hasPrefix("Screen Shot")
    }

    /// Files a screenshot under Pictures › Where’d It Go › yyyy-MM-dd.
    static func archive(_ url: URL, created: Date) -> URL? {
        let day = created.formatted(.iso8601.year().month().day())
        let folder = archiveRoot.appending(path: day, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var destination = folder.appending(path: url.lastPathComponent)
            var copy = 2
            while FileManager.default.fileExists(atPath: destination.path) {
                let base = url.deletingPathExtension().lastPathComponent
                destination = folder.appending(path: "\(base) \(copy).\(url.pathExtension)")
                copy += 1
            }
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }
}

/// Calls `handler` on a background queue whenever the folder's contents change.
final class FolderWatcher {
    private let source: DispatchSourceFileSystemObject

    init?(url: URL, handler: @escaping @Sendable () -> Void) {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .extend, .attrib, .link],
            queue: .global(qos: .utility)
        )
        source.setEventHandler(handler: handler)
        source.setCancelHandler { close(descriptor) }
        source.resume()
    }

    deinit { source.cancel() }
}
