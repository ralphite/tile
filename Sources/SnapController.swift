import AppKit

@MainActor
final class SnapController {
    private let manager: WindowManager
    private let onResult: (String) -> Void
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var windows: [NSPanel] = []
    private var drag: WindowManager.WindowReference?
    private var resized = false
    private var lastSample: TimeInterval = 0
    private var generation = 0
    private(set) var preset: LayoutPreset?
    var isEnabled: Bool { monitor != nil }

    init(manager: WindowManager, onResult: @escaping (String) -> Void) {
        self.manager = manager; self.onResult = onResult
    }

    func select(_ preset: LayoutPreset) {
        self.preset = preset
        cancelDrag()
    }

    func start(with preset: LayoutPreset) -> Bool {
        stop()
        guard manager.isTrusted, manager.hasWindowBridge else { return false }
        self.preset = preset
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.handle(event)
        }
        guard monitor != nil else { return false }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.async { self?.cancelDrag() }
            })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.async { self?.cancelDrag() }
            })
        return true
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        cancelDrag()
    }

    private func cancelDrag() {
        generation += 1; drag = nil; resized = false; lastSample = 0
        hidePreview()
    }

    private func handle(_ event: NSEvent) {
        guard isEnabled else { return }
        guard manager.isTrusted else { stop(); onResult("Accessibility permission is off. Snapping has stopped."); return }
        let point = event.cgEvent?.location ?? CGPoint(x: NSEvent.mouseLocation.x,
            y: (NSScreen.screens.first?.frame.maxY ?? 0) - NSEvent.mouseLocation.y)
        switch event.type {
        case .leftMouseDown:
            cancelDrag()
            drag = manager.dragWindow(at: point)
        case .leftMouseDragged:
            guard event.timestamp - lastSample >= 0.03 else { return }
            lastSample = event.timestamp
            guard let drag, let current = manager.currentFrame(of: drag) else { hidePreview(); return }
            switch WindowGesture.classify(from: drag.originalFrame, to: current) {
            case .resized: resized = true; hidePreview()
            case .moved:
                if !resized { showPreview(at: point) }
            case .unchanged: break
            }
        case .leftMouseUp:
            guard let drag else { return }
            let cancelledByResize = resized
            self.drag = nil
            hidePreview()
            let token = generation
            // One event-triggered completion, after the source app handles mouse-up.
            // There is no idle polling, timer loop, or persistent mouse tracking when off.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, self.isEnabled, self.generation == token, !cancelledByResize,
                      let current = self.manager.currentFrame(of: drag),
                      WindowGesture.classify(from: drag.originalFrame, to: current) == .moved,
                      let target = self.target(at: point) else { return }
                if let result = self.manager.snap(drag, to: target) { self.onResult(result) }
            }
        default: break
        }
    }

    private func target(at point: CGPoint) -> CGRect? {
        guard let preset else { return nil }
        for screen in NSScreen.screens {
            let area = manager.usableFrame(of: screen)
            if area.contains(point) {
                return preset.layout.cellFrames(in: area, gap: 0).first { $0.contains(point) }
            }
        }
        return nil
    }

    private func showPreview(at point: CGPoint) {
        guard let preset else { return }
        if windows.isEmpty {
            let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
            for screen in NSScreen.screens {
                let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.isOpaque = false; panel.backgroundColor = .clear
                panel.hasShadow = false; panel.ignoresMouseEvents = true
                panel.level = .floating; panel.isReleasedWhenClosed = false
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
                let view = SnapOverlay(frame: NSRect(origin: .zero, size: screen.frame.size))
                let origin = CGPoint(x: screen.frame.minX, y: primaryTop - screen.frame.maxY)
                view.globalOrigin = origin
                view.regions = preset.layout.cellFrames(in: manager.usableFrame(of: screen), gap: 0)
                panel.contentView = view
                windows.append(panel)
                panel.orderFrontRegardless()
            }
        }
        for panel in windows {
            guard let view = panel.contentView as? SnapOverlay else { continue }
            view.highlighted = view.regions.firstIndex { $0.contains(point) }
        }
    }

    private func hidePreview() {
        windows.forEach { $0.close() }
        windows.removeAll()
    }
}

@MainActor
private final class SnapOverlay: NSView {
    var regions: [CGRect] = []
    var globalOrigin = CGPoint.zero
    var highlighted: Int? { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        for (index, globalFrame) in regions.enumerated() {
            let frame = globalFrame.offsetBy(dx: -globalOrigin.x, dy: -globalOrigin.y)
            let selected = index == highlighted
            NSColor.controlAccentColor.withAlphaComponent(selected ? 0.23 : 0.035).setFill()
            frame.fill()
            NSColor.controlAccentColor.withAlphaComponent(selected ? 1 : 0.55).setStroke()
            let border = NSBezierPath(rect: frame.insetBy(dx: 1.5, dy: 1.5))
            border.lineWidth = selected ? 3 : 1
            border.stroke()
            let text = "\(index + 1)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 25, weight: .semibold),
                .foregroundColor: NSColor.white,
                .strokeColor: NSColor.black.withAlphaComponent(0.6), .strokeWidth: -3
            ]
            text.draw(at: CGPoint(x: frame.minX + 16, y: frame.minY + 12), withAttributes: attributes)
        }
    }
}
