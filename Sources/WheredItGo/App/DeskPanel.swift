import AppKit
import OSLog
import SwiftUI

/// A transparent, non-activating panel that floats above every Space without taking focus.
final class DeskPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        title = String(localized: "Screenshot Pile")
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class DeskHostingView: NSHostingView<DeskView> {
    var onHover: ((Bool) -> Void)?
    var onMove: ((CGPoint, CGSize) -> Void)?
    /// Whether a point (top-left origin) is on the handle that drags the whole panel.
    var isHandle: ((CGPoint) -> Bool)?
    var onGrab: (() -> Void)?
    private var tracking: NSTrackingArea?
    private var showsHand = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Presses on the handle come here rather than to a subview SwiftUI placed under the pointer.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if bounds.contains(local), isHandle?(CGPoint(x: local.x, y: isFlipped ? local.y : bounds.height - local.y)) == true {
            return self
        }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        guard isHandle?(topLeft(event)) == true, let onGrab else { return super.mouseDown(with: event) }
        onGrab()
        updateCursor(topLeft(event))
    }

    override func cursorUpdate(with event: NSEvent) {
        if isHandle?(topLeft(event)) == true { NSCursor.openHand.set() } else { super.cursorUpdate(with: event) }
    }

    /// The panel never activates the app, and the frontmost app can reset the cursor at any time,
    /// so the hand is set again on every move rather than once on entry.
    private func updateCursor(_ point: CGPoint) {
        if isHandle?(point) == true {
            NSCursor.openHand.set()
            showsHand = true
        } else if showsHand {
            NSCursor.arrow.set()
            showsHand = false
        }
    }

    private func topLeft(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x, y: isFlipped ? point.y : bounds.height - point.y)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHover?(true)
        reportPointer(event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover?(false)
        if showsHand {
            NSCursor.arrow.set()
            showsHand = false
        }
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        reportPointer(event)
    }

    private func reportPointer(_ event: NSEvent) {
        let point = topLeft(event)
        onMove?(point, bounds.size)
        updateCursor(point)
    }
}

/// macOS ignores cursor changes from an app that isn't frontmost, and the panel never makes this app
/// frontmost. The window server's `SetsCursorInBackground` connection property lifts that for this
/// app. It's undocumented, so it's looked up at run time and skipped if a future macOS drops it.
enum BackgroundCursor {
    private typealias DefaultConnection = @convention(c) () -> Int32
    private typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32

    static func enable() {
        guard let handle = dlopen(nil, RTLD_NOW),
              let connection = dlsym(handle, "_CGSDefaultConnection"),
              let setProperty = dlsym(handle, "CGSSetConnectionProperty") else { return }
        let id = unsafeBitCast(connection, to: DefaultConnection.self)()
        _ = unsafeBitCast(setProperty, to: SetProperty.self)(id, id, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }
}

/// Keeps the panel sized to exactly what is on screen, so it never blocks clicks elsewhere.
@MainActor
final class DeskPanelController {
    private let model: DeskModel
    private let panel = DeskPanel()
    private var dragging = false
    private var placed: NSRect?
    private let log = Logger(subsystem: "app.whereditgo.mac", category: "panel")

    init(model: DeskModel) {
        self.model = model
        let host = DeskHostingView(rootView: DeskView(model: model))
        host.sizingOptions = []
        host.onHover = { [weak model] inside in model?.pointerHovering(inside) }
        host.onMove = { [weak model] point, size in model?.pointerMoved(to: point, in: size) }
        host.isHandle = { [weak model] point in model?.chipFrame.insetBy(dx: -4, dy: -4).contains(point) ?? false }
        host.onGrab = { [weak self] in self?.drag() }
        panel.contentView = host
        BackgroundCursor.enable()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
        track()
    }

    private func track() {
        let layout = withObservationTracking { model.panelLayout } onChange: { [weak self] in
            Task { @MainActor in self?.track() }
        }
        apply(layout)
    }

    private func layout() { apply(model.panelLayout) }

    private var screen: NSScreen? { panel.screen ?? NSScreen.main ?? NSScreen.screens.first }

    /// Follows the pointer from a press on the chip until release, then leaves the pile there.
    private func drag() {
        guard let area = screen?.visibleFrame, model.beginMove() else {
            log.notice("Pile drag refused: the pile is busy")
            return
        }
        apply(model.panelLayout)
        log.notice("Pile drag began from \(self.panel.frame.debugDescription, privacy: .public)")
        dragging = true
        let startMouse = NSEvent.mouseLocation, startOrigin = panel.frame.origin
        NSCursor.closedHand.push()
        while let event = panel.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]), event.type == .leftMouseDragged {
            NSCursor.closedHand.set()
            let mouse = NSEvent.mouseLocation, size = panel.frame.size
            let x = min(max(startOrigin.x + mouse.x - startMouse.x, area.minX), area.maxX - size.width)
            let y = min(max(startOrigin.y + mouse.y - startMouse.y, area.minY), area.maxY - size.height)
            panel.setFrameOrigin(CGPoint(x: x, y: y))
            model.panelFrame = panel.frame
        }
        NSCursor.pop()
        dragging = false

        // The pile opens toward the middle of the screen, so its side is whichever half it was dropped in.
        let frame = panel.frame
        let corner: Corner = frame.midX >= area.midX ? .bottomTrailing : .bottomLeading
        let inset = corner.isTrailing ? area.maxX - frame.maxX : frame.minX - area.minX
        model.placePile(corner: corner, inset: inset - Layout.screenMargin, lift: frame.minY - area.minY - Layout.screenMargin)
        log.notice("Pile dropped at \(frame.debugDescription, privacy: .public), \(corner.rawValue, privacy: .public)")
        apply(model.panelLayout, animated: true)
    }

    private func apply(_ layout: PanelLayout, animated: Bool = false) {
        guard layout.visible, let screen else {
            panel.orderOut(nil)
            return
        }
        // The pointer owns the panel's position until the drag ends.
        if dragging { return }
        let area = screen.visibleFrame
        var size = layout.expanded
            ? CGSize(width: Layout.fanWidth(count: layout.count), height: Layout.fanHeight)
            : layout.tucked ? Layout.tuckedSize : Layout.pileSize
        if layout.camera {
            size.width = max(size.width, Layout.pileSize.width)
            size.height = Layout.pileSize.height + Layout.stationSize.height
        }
        size.width = min(size.width, area.width - Layout.screenMargin * 2)
        size.height = min(size.height, area.height - Layout.screenMargin * 2)
        let inset = min(layout.inset, max(0, area.width - Layout.screenMargin * 2 - size.width))
        let x = layout.corner.isTrailing ? area.maxX - size.width - Layout.screenMargin - inset : area.minX + Layout.screenMargin + inset
        // A pile dragged up the screen still grows upward, so keep room for the camera and the fan.
        let lift = min(layout.lift, max(0, area.height - Layout.screenMargin * 2 - size.height))
        let frame = NSRect(x: x, y: area.minY + Layout.screenMargin + lift, width: size.width, height: size.height)
        // Skip a repeat of the frame already set, so it can't cut a running snap animation short.
        if !animated, frame == placed, panel.isVisible { return }
        placed = frame
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
        model.panelFrame = frame
        panel.orderFrontRegardless()
        // A window that shrinks out from under the pointer gets no mouse-exited event.
        if model.pointerInside, !frame.contains(NSEvent.mouseLocation) { model.pointerHovering(false) }
    }
}
