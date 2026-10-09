import AppKit
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
    private var tracking: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        reportPointer(event)
    }

    private func reportPointer(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onMove?(CGPoint(x: point.x, y: isFlipped ? point.y : bounds.height - point.y), bounds.size)
    }
}

/// Keeps the panel sized to exactly what is on screen, so it never blocks clicks elsewhere.
@MainActor
final class DeskPanelController {
    private let model: DeskModel
    private let panel = DeskPanel()

    init(model: DeskModel) {
        self.model = model
        let host = DeskHostingView(rootView: DeskView(model: model))
        host.sizingOptions = []
        host.onHover = { [weak model] inside in model?.pointerHovering(inside) }
        host.onMove = { [weak model] point, size in model?.pointerMoved(to: point, in: size) }
        panel.contentView = host

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

    private func apply(_ layout: PanelLayout) {
        guard layout.visible, let screen = NSScreen.main ?? NSScreen.screens.first else {
            panel.orderOut(nil)
            return
        }
        let area = screen.visibleFrame
        var size = layout.expanded
            ? CGSize(width: Layout.fanWidth(count: layout.count), height: Layout.fanHeight)
            : Layout.pileSize
        if layout.camera {
            size.width = max(size.width, Layout.pileSize.width)
            size.height = Layout.pileSize.height + Layout.stationSize.height
        }
        size.width = min(size.width, area.width - Layout.screenMargin * 2)
        size.height = min(size.height, area.height - Layout.screenMargin * 2)
        let x = layout.corner.isTrailing ? area.maxX - size.width - Layout.screenMargin : area.minX + Layout.screenMargin
        let frame = NSRect(x: x, y: area.minY + Layout.screenMargin, width: size.width, height: size.height)
        panel.setFrame(frame, display: true)
        model.panelFrame = frame
        panel.orderFrontRegardless()
    }
}
