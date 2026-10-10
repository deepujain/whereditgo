import AppKit
import Observation
import OSLog
import SwiftUI

struct PanelLayout: Equatable {
    var visible: Bool
    var camera: Bool
    var expanded: Bool
    var tucked: Bool
    var count: Int
    var corner: Corner
}

enum Toast: Equatable {
    case copiedImage, copiedText

    var title: LocalizedStringKey {
        switch self {
        case .copiedImage: "Picture copied"
        case .copiedText: "Text copied"
        }
    }

    var symbol: String {
        switch self {
        case .copiedImage: "photo.on.rectangle"
        case .copiedText: "text.viewfinder"
        }
    }
}

@MainActor
@Observable
final class DeskModel {
    private(set) var shots: [Shot] = []
    private(set) var printing: Shot?
    private(set) var cameraInPanel = false
    private(set) var expandedInPanel = false
    private(set) var corner = Corner.bottomTrailing
    private(set) var pileSize = 6
    private(set) var folderURL = ScreenshotFolder.current
    private(set) var folderReadable = true
    private(set) var arrivals = 0

    var cameraShown = false
    var flash = 0.0
    var eject = 0.0
    /// 0 while the rollers hold the print, 1 once it has dropped flat.
    var relax = 0.0
    /// A still of the undeveloped print, drawn while it curls out of the slot.
    private(set) var feedSheet: NSImage?
    private(set) var motorRunning = false
    /// A brief confirmation shown under the pile, like “Copied”.
    private(set) var toast: Toast?
    var wiggle = 0.0
    var hintVisible = false
    var pileExpanded = false
    var hoveredShot: Shot.ID?
    private(set) var pointerInside = false
    private(set) var sweeping = false
    private(set) var tossed: Set<Shot.ID> = []
    private(set) var sweptCount = 0
    /// Where the pointer is across the lifted card, from 0 (left edge) to 1 (right edge).
    private(set) var sheen = 0.5
    var cameraHop = false
    @ObservationIgnored var panelFrame = CGRect.zero
    private var showPileAlways = true
    private var lingering = false
    /// The pile has tucked away, leaving only its count in the corner.
    private(set) var tucked = false
    private var tuckedInPanel = false
    @ObservationIgnored private var tuckTask: Task<Void, Never>?

    @ObservationIgnored private var developStart = Date.distantFuture
    @ObservationIgnored private var developBonus = 0.0
    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private var seen = Set<String>()
    @ObservationIgnored private var queue: [Shot] = []
    @ObservationIgnored private var presenting = false
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var lingerTask: Task<Void, Never>?
    @ObservationIgnored private var collapseTask: Task<Void, Never>?
    @ObservationIgnored private var undoTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var swept: [Shot] = []
    @ObservationIgnored private var lastPointerX: CGFloat?
    @ObservationIgnored private var pointer: (inward: CGFloat, up: CGFloat)?
    @ObservationIgnored private var lastDirection: CGFloat = 0
    @ObservationIgnored private var travel: CGFloat = 0
    @ObservationIgnored private let launched = Date()
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let log = Logger(subsystem: "app.whereditgo.mac", category: "desk")

    static let developDuration = 1.8
    static let feedDuration = 2.0
    static let maxShots = 40

    var visibleShots: [Shot] { Array(shots.prefix(pileSize)) }
    var todayCount: Int { shots.filter { Calendar.current.isDateInToday($0.date) }.count }
    var isVisible: Bool {
        cameraInPanel || sweptCount > 0 || (!shots.isEmpty && (showPileAlways || lingering || expandedInPanel))
    }
    var canSweep: Bool { !shots.isEmpty && !sweeping && printing == nil }

    var panelLayout: PanelLayout {
        PanelLayout(visible: isVisible, camera: cameraInPanel, expanded: expandedInPanel,
                    tucked: tuckedInPanel && !cameraInPanel && !expandedInPanel && sweptCount == 0,
                    count: visibleShots.count, corner: corner)
    }

    // MARK: Lifecycle

    func start() {
        Prefs.register()
        reloadPrefs()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadPrefs() }
        }
        FolderAccess.restore()
        watch(ScreenshotFolder.current, initial: true)
    }

    /// In the App Sandbox, asks the user to choose the screenshot folder, then watches it.
    func grantAccess() {
        guard let folder = FolderAccess.request(folderURL) else { return }
        watch(folder, initial: true)
    }

    /// Picks up a new screenshot location chosen in the Screenshot app.
    func refreshFolder() {
        let folder = ScreenshotFolder.current
        guard folder != folderURL else { return scan(initial: false) }
        watch(folder, initial: false)
    }

    private func watch(_ folder: URL, initial: Bool) {
        folderURL = folder
        watcher = FolderWatcher(url: folder) { [weak self] in
            Task { @MainActor in self?.folderChanged() }
        }
        scan(initial: initial)
    }

    private func reloadPrefs() {
        corner = Corner(rawValue: defaults.string(forKey: Prefs.corner) ?? "") ?? .bottomTrailing
        pileSize = min(10, max(3, defaults.integer(forKey: Prefs.pileSize)))
        showPileAlways = defaults.bool(forKey: Prefs.showPile)
    }

    // MARK: Folder scanning

    private func folderChanged() {
        scanTask?.cancel()
        scanTask = Task {
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }
            scan(initial: false)
        }
    }

    private func scan(initial: Bool) {
        let folder = folderURL
        Task {
            let found = await Work.run(on: Work.scanning) { ScreenshotFolder.screenshots(in: folder) }
            folderReadable = await Work.run(on: Work.scanning) { ScreenshotFolder.isReadable(folder) }
            ingest(found, initial: initial)
        }
    }

    private func ingest(_ found: [FoundShot], initial: Bool) {
        let missing = shots.filter { !FileManager.default.fileExists(atPath: $0.url.path) }
        if !missing.isEmpty {
            withAnimation(.spring(duration: 0.4)) { shots.removeAll { shot in missing.contains { $0 === shot } } }
        }

        if initial {
            log.info("Watching \(self.folderURL.path, privacy: .private): \(found.count) screenshots, readable: \(self.folderReadable)")
            found.forEach { seen.insert($0.url.path) }
            shots = found.filter { Calendar.current.isDateInToday($0.created) }
                .prefix(Self.maxShots)
                .map { Shot(url: $0.url, date: $0.created, app: nil) }
            shots.forEach(load)
            scheduleTuck()
            return
        }

        let fresh = found.filter { !seen.contains($0.url.path) && $0.created > launched.addingTimeInterval(-10) }
        for item in fresh.reversed() {
            seen.insert(item.url.path)
            arrive(item)
        }
    }

    private func arrive(_ found: FoundShot) {
        var url = found.url
        if defaults.bool(forKey: Prefs.tidyDesktop), let moved = ScreenshotFolder.archive(url, created: found.created) {
            url = moved
            seen.insert(moved.path)
        }
        let shot = Shot(url: url, date: found.created, app: Self.frontmostAppName())
        log.info("New screenshot \(url.lastPathComponent, privacy: .private) from \(shot.app ?? "unknown", privacy: .public)")
        if defaults.bool(forKey: Prefs.copyToClipboard) { copy(shot, announce: false) }
        arrivals += 1
        Task {
            // The picture is ready before the camera fires, so the print never comes out blank.
            await loadImage(shot)
            readText(shot, on: Work.readingNew)
            queue.append(shot)
            if !presenting { await drainQueue() }
        }
    }

    private func load(_ shot: Shot) {
        Task {
            await loadImage(shot)
            readText(shot, on: Work.readingBacklog)
        }
    }

    private func loadImage(_ shot: Shot) async {
        let url = shot.url
        if let thumbnail = await Work.run(on: Work.imaging, { ShotImaging.thumbnail(url, maxPixel: 720) }) {
            shot.image = NSImage(cgImage: thumbnail.cgImage, size: .zero)
        }
    }

    private func readText(_ shot: Shot, on queue: DispatchQueue) {
        let url = shot.url
        let smart = defaults.bool(forKey: Prefs.smartCaptions)
        Task {
            guard let reading = await Work.run(on: queue, { ShotImaging.read(url) }) else { return }
            shot.text = reading.text
            if smart, let headline = reading.headline {
                withAnimation(.easeInOut(duration: 0.4)) { shot.title = headline }
            }
        }
    }

    private static func frontmostAppName() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              app.bundleIdentifier != "com.apple.screencaptureui" else { return nil }
        return app.localizedName
    }

    // MARK: Printing

    func developProgress(at date: Date) -> Double {
        min(1, max(0, date.timeIntervalSince(developStart) / Self.developDuration + developBonus))
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private func drainQueue() async {
        presenting = true
        untuck()
        collapse(animated: false)
        while !queue.isEmpty {
            await runPrint(queue.removeFirst())
        }
        presenting = false
        guard cameraInPanel else { return linger() }
        withAnimation(.easeIn(duration: 0.28)) { cameraShown = false }
        try? await Task.sleep(for: .milliseconds(300))
        if !presenting {
            cameraInPanel = false
            linger()
        }
    }

    private func runPrint(_ shot: Shot) async {
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.25)) { insert(shot) }
            playLanding()
            return
        }

        if !cameraInPanel {
            cameraInPanel = true
            try? await Task.sleep(for: .milliseconds(16))
            withAnimation(.spring(duration: 0.3, bounce: 0.3)) { cameraShown = true }
            try? await Task.sleep(for: .milliseconds(170))
        }

        withAnimation(.easeOut(duration: 0.05)) { flash = 1 }
        try? await Task.sleep(for: .milliseconds(50))
        withAnimation(.easeOut(duration: 0.5)) { flash = 0 }

        eject = 0
        relax = 0
        developBonus = 0
        developStart = .distantFuture
        feedSheet = PrintSheet.render(shot)
        printing = shot
        try? await Task.sleep(for: .milliseconds(120))
        motorRunning = true
        Sounds.motor()
        withAnimation(.timingCurve(0.2, 0.05, 0.8, 0.95, duration: Self.feedDuration)) { eject = 1 }
        try? await Task.sleep(for: .seconds(Self.feedDuration))
        motorRunning = false
        withAnimation(.spring(duration: 0.6, bounce: 0.45)) { relax = 1 }
        try? await Task.sleep(for: .milliseconds(520))
        feedSheet = nil
        developStart = .now
        if developProgress(at: .now) < 0.6 {
            withAnimation(.easeOut(duration: 0.2)) { hintVisible = true }
        }

        let deadline = Date().addingTimeInterval(Self.developDuration + 1)
        while developProgress(at: .now) < 1, Date() < deadline {
            if developProgress(at: .now) > 0.75, hintVisible {
                withAnimation(.easeIn(duration: 0.2)) { hintVisible = false }
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        withAnimation(.easeIn(duration: 0.15)) { hintVisible = false }
        try? await Task.sleep(for: .milliseconds(queue.isEmpty ? 350 : 150))

        withAnimation(.spring(duration: 0.55, bounce: 0.22)) {
            insert(shot)
            printing = nil
        }
        try? await Task.sleep(for: .milliseconds(300))
        log.info("Print landed: \(shot.title, privacy: .private); pile has \(self.shots.count)")
        playLanding()
        withAnimation(.spring(duration: 0.18, bounce: 0.6)) { cameraHop = true }
        try? await Task.sleep(for: .milliseconds(160))
        withAnimation(.spring(duration: 0.45, bounce: 0.55)) { cameraHop = false }
        try? await Task.sleep(for: .milliseconds(300))
    }

    private func insert(_ shot: Shot) {
        shots.insert(shot, at: 0)
        if shots.count > Self.maxShots { shots.removeLast(shots.count - Self.maxShots) }
    }

    private func linger() {
        lingerTask?.cancel()
        lingering = true
        scheduleTuck()
        lingerTask = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { lingering = false }
        }
    }

    /// After a quiet spell, folds the pile down to its count so it stops covering the screen.
    private func scheduleTuck(after delay: Duration = .seconds(6)) {
        tuckTask?.cancel()
        tuckTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            // Hover can go stale when a drag carries the pointer out; trust where it really is.
            if pointerInside, !panelFrame.contains(NSEvent.mouseLocation) { return pointerHovering(false) }
            guard !pointerInside, !presenting, !cameraInPanel, !sweeping, sweptCount == 0,
                  !pileExpanded, !shots.isEmpty else { return }
            withAnimation(.spring(duration: 0.45, bounce: 0.15)) { tucked = true }
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, tucked else { return }
            tuckedInPanel = true
        }
    }

    private func untuck() {
        tuckTask?.cancel()
        guard tucked || tuckedInPanel else { return }
        tuckedInPanel = false
        withAnimation(.spring(duration: 0.45, bounce: 0.3)) { tucked = false }
    }

    func showPile() {
        untuck()
        scheduleTuck()
    }

    private func playLanding() {
        Sounds.landing()
    }

    // MARK: Pointer

    func pointerHovering(_ inside: Bool) {
        withAnimation(.easeOut(duration: 0.2)) { pointerInside = inside }
        if inside {
            untuck()
            guard !sweeping else { return }
            collapseTask?.cancel()
            guard !cameraInPanel, visibleShots.count > 1, !pileExpanded else { return }
            expandedInPanel = true
            withAnimation(.spring(duration: 0.45, bounce: 0.28)) { pileExpanded = true }
            updateHoveredCard()
        } else {
            lastPointerX = nil
            pointer = nil
            collapse(animated: true)
            scheduleTuck(after: .seconds(3))
        }
    }

    private func collapse(animated: Bool) {
        guard pileExpanded || expandedInPanel else { return }
        collapseTask?.cancel()
        hoveredShot = nil
        guard animated else {
            pileExpanded = false
            expandedInPanel = false
            return
        }
        withAnimation(.spring(duration: 0.4, bounce: 0.2)) { pileExpanded = false }
        collapseTask = Task {
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled, !pileExpanded else { return }
            expandedInPanel = false
        }
    }

    /// `point` has a top-left origin within a panel of `size`.
    func pointerMoved(to point: CGPoint, in size: CGSize) {
        pointer = (corner.isTrailing ? size.width - point.x : point.x, size.height - point.y)
        updateHoveredCard()
        shake(x: point.x)
    }

    private func updateHoveredCard() {
        var target: Shot.ID?
        if pileExpanded, let pointer {
            let items = visibleShots
            let lifted = items.firstIndex { $0.id == hoveredShot }
            if let index = Layout.fanCard(inward: pointer.inward, up: pointer.up, count: items.count,
                                          trailing: corner.isTrailing, lifted: lifted) {
                target = items[index].id
                let across = (Layout.fanCardCenter(index: index) - pointer.inward) / Layout.cardWidth
                sheen = min(1, max(0, 0.5 + (corner.isTrailing ? across : -across)))
            }
        }
        guard target != hoveredShot else { return }
        withAnimation(.spring(duration: 0.25, bounce: 0.3)) { hoveredShot = target }
    }

    /// Which way the camera lens looks to face the pointer, as a vector up to length 1 (y points up).
    func lensGaze() -> CGSize {
        guard panelFrame != .zero else { return .zero }
        let lens = CGPoint(x: corner.isTrailing ? panelFrame.maxX - Layout.lensInset.width : panelFrame.minX + Layout.lensInset.width,
                           y: panelFrame.maxY - Layout.lensInset.height)
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - lens.x, dy = mouse.y - lens.y
        let distance = max(1, hypot(dx, dy))
        let reach = min(1, distance / 260)
        return CGSize(width: dx / distance * reach, height: dy / distance * reach)
    }

    /// Wiggling the pointer over a developing print speeds it up, like shaking a Polaroid.
    private func shake(x: CGFloat) {
        defer { lastPointerX = x }
        guard printing != nil, feedSheet == nil, let last = lastPointerX else { return }
        let delta = x - last
        guard abs(delta) > 0.5 else { return }
        let direction: CGFloat = delta > 0 ? 1 : -1
        travel += abs(delta)
        if direction != lastDirection, travel > 10 {
            lastDirection = direction
            travel = 0
            developBonus += 0.075
            withAnimation(.spring(duration: 0.18, bounce: 0.5)) { wiggle = Double(direction) * 5 }
            Task {
                try? await Task.sleep(for: .milliseconds(120))
                withAnimation(.spring(duration: 0.35, bounce: 0.55)) { wiggle = 0 }
            }
        }
    }

    // MARK: Actions

    func dragProvider(for shot: Shot) -> NSItemProvider {
        NSItemProvider(contentsOf: shot.url) ?? NSItemProvider()
    }

    func open(_ shot: Shot) {
        NSWorkspace.shared.open(shot.url)
    }

    func reveal(_ shot: Shot) {
        NSWorkspace.shared.activateFileViewerSelecting([shot.url])
    }

    /// Copies the picture. Pass `announce: false` for automatic copies nobody asked for.
    func copy(_ shot: Shot, announce: Bool = true) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let image = NSImage(contentsOf: shot.url) {
            pasteboard.writeObjects([image])
        }
        if announce { show(.copiedImage) }
    }

    func copyText(_ shot: Shot) {
        guard let text = shot.text, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        show(.copiedText)
    }

    private func show(_ toast: Toast) {
        Sounds.copied()
        toastTask?.cancel()
        withAnimation(.spring(duration: 0.35, bounce: 0.4)) { self.toast = toast }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { self.toast = nil }
        }
    }

    func remove(_ shot: Shot) {
        withAnimation(.spring(duration: 0.4)) { shots.removeAll { $0 === shot } }
    }

    func trash(_ shot: Shot) {
        try? FileManager.default.trashItem(at: shot.url, resultingItemURL: nil)
        remove(shot)
    }

    /// Flicks every print off the pile, one after another. The files stay where they are.
    func clearPile() {
        guard canSweep else { return }
        sweeping = true
        undoTask?.cancel()
        Task {
            if pileExpanded {
                collapse(animated: true)
                try? await Task.sleep(for: .milliseconds(280))
            }
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.3)) { tossed = Set(shots.map(\.id)) }
                try? await Task.sleep(for: .milliseconds(320))
            } else {
                for (index, shot) in visibleShots.enumerated() {
                    Sounds.swish(index)
                    withAnimation(.timingCurve(0.55, 0, 0.8, 0.45, duration: 0.5)) { _ = tossed.insert(shot.id) }
                    try? await Task.sleep(for: .milliseconds(110))
                }
                tossed = Set(shots.map(\.id))
                try? await Task.sleep(for: .milliseconds(380))
            }
            Sounds.poof()
            swept = shots.filter { tossed.contains($0.id) }
            shots.removeAll { tossed.contains($0.id) }
            tossed = []
            log.info("Swept \(self.swept.count) prints off the pile")
            withAnimation(.spring(duration: 0.4, bounce: 0.35)) { sweptCount = swept.count }
            sweeping = false
            offerUndo()
        }
    }

    private func offerUndo() {
        undoTask = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { sweptCount = 0 }
            swept = []
        }
    }

    func undoClear() {
        guard !swept.isEmpty else { return }
        undoTask?.cancel()
        let restored = swept
        swept = []
        withAnimation(.spring(duration: 0.55, bounce: 0.3)) {
            sweptCount = 0
            shots = (shots + restored).sorted { $0.date > $1.date }
        }
        Sounds.landing()
        showPile()
    }

    func openFolder() {
        NSWorkspace.shared.open(folderURL)
    }
}

#if DEBUG
extension DeskModel {
    func stage(shots: [Shot], printing: Shot?, develop: Double, expanded: Bool, hint: Bool) {
        self.shots = shots
        self.printing = printing
        cameraInPanel = printing != nil
        cameraShown = printing != nil
        eject = 1
        hintVisible = hint
        developBonus = 0
        developStart = Date().addingTimeInterval(-develop * Self.developDuration)
        pileExpanded = expanded
        expandedInPanel = expanded
        pointerInside = false
        tucked = false
        tuckedInPanel = false
        tossed = []
        sweptCount = 0
    }

    func stageHover(index: Int, sheen: Double) {
        hoveredShot = visibleShots[index].id
        self.sheen = sheen
    }

    func stageFeed(_ progress: Double, relax: Double = 0) {
        eject = progress
        self.relax = relax
        feedSheet = printing.flatMap(PrintSheet.render)
        motorRunning = progress < 1
        hintVisible = false
    }

    func stageTucked(_ tucked: Bool) {
        self.tucked = tucked
        tuckedInPanel = tucked
    }

    func stageToast(_ toast: Toast?) {
        self.toast = toast
    }

    func stageSweep(pointerInside: Bool, tossed count: Int, swept: Int) {
        self.pointerInside = pointerInside
        tossed = Set(visibleShots.prefix(count).map(\.id))
        sweptCount = swept
    }
}
#endif

/// Dedicated queues keep folder scans from waiting behind text recognition,
/// which can take seconds per image and would otherwise fill the shared thread pool.
private enum Work {
    static let scanning = DispatchQueue(label: "app.whereditgo.scanning", qos: .userInteractive)
    static let imaging = DispatchQueue(label: "app.whereditgo.imaging", qos: .userInitiated, attributes: .concurrent)
    static let readingNew = DispatchQueue(label: "app.whereditgo.reading-new", qos: .userInitiated)
    static let readingBacklog = DispatchQueue(label: "app.whereditgo.reading-backlog", qos: .background)

    static func run<T: Sendable>(on queue: DispatchQueue, _ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }
}
