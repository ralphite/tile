import AppKit
import ApplicationServices
import Darwin
import OSLog

@MainActor
final class WindowManager {
    struct WindowReference {
        fileprivate let id: CGWindowID
        fileprivate let pid: pid_t
        fileprivate let element: AXUIElement
        let originalFrame: CGRect
    }

    struct CaptureWindow {
        let id: CGWindowID
        let title: String
        let frame: CGRect
    }
    private typealias WindowIDFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> Int32

    // macOS has no public AX-to-CGWindowID bridge. This local utility uses the
    // private symbol only for exact identity; if unavailable, it fails closed.
    // No title/geometry fallback may select a window from another Space.
    private let windowIDFunction: WindowIDFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: WindowIDFunction.self)
    }()

    private struct VisibleWindow {
        let id: CGWindowID
        let pid: pid_t
        let bounds: CGRect
        let order: Int
    }

    private struct ManagedWindow {
        let visible: VisibleWindow
        let element: AXUIElement
    }

    private struct OriginalWindow {
        let id: CGWindowID
        let pid: pid_t
        let element: AXUIElement
        let frame: CGRect
    }

    private let frameLogger = Logger(subsystem: "dev.yadong.tile", category: "WindowFrames")
    private var originals: [OriginalWindow] = []
    private var hasRequestedPermission = false
    var canUndo: Bool { !originals.isEmpty }
    var isTrusted: Bool { AXIsProcessTrusted() }
    var hasWindowBridge: Bool { windowIDFunction != nil }

    func dragWindow(at point: CGPoint) -> WindowReference? {
        guard isTrusted, hasWindowBridge,
              let visible = visibleWindows().first(where: { $0.bounds.contains(point) }) else { return nil }
        let app = AXUIElementCreateApplication(visible.pid)
        AXUIElementSetMessagingTimeout(app, 0.08)
        guard let windows = attribute(app, kAXWindowsAttribute as CFString) as? [AXUIElement],
              let element = windows.first(where: { windowID(of: $0) == visible.id }) else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.08)
        guard eligible(element, pid: visible.pid), let bounds = frame(of: element) else { return nil }
        return WindowReference(id: visible.id, pid: visible.pid, element: element, originalFrame: bounds)
    }

    func currentFrame(of window: WindowReference) -> CGRect? {
        guard windowID(of: window.element) == window.id else { return nil }
        return frame(of: window.element)
    }

    func snap(_ window: WindowReference, to target: CGRect) -> String? {
        guard isTrusted, let visible = visibleWindows().first(where: { $0.id == window.id && $0.pid == window.pid }),
              stillEligible(ManagedWindow(visible: visible, element: window.element)) else { return nil }
        let write = setFrame(target, on: window.element)
        if write.attempted {
            originals = [OriginalWindow(id: window.id, pid: window.pid, element: window.element, frame: window.originalFrame)]
        }
        if write.verified { return "Window snapped. Use Restore Last Arrangement to undo." }
        return "The window did not reach its target frame. Use Restore Last Arrangement if it moved."
    }

    func captureWindows(on screen: NSScreen) -> [CaptureWindow] {
        guard isTrusted, hasWindowBridge, let primary = NSScreen.screens.first else { return [] }
        let screens = NSScreen.screens
        let displays = screens.map { ArrangementPlan.Display(frame: axFrame($0.frame, primaryTop: primary.frame.maxY), usableFrame: usableFrame(of: $0)) }
        guard let screenIndex = screens.firstIndex(of: screen) else { return [] }
        return managedWindows().compactMap { window in
            guard ArrangementPlan.displayIndex(for: window.visible.bounds, displays: displays) == screenIndex,
                  stillEligible(window), let bounds = frame(of: window.element) else { return nil }
            let appName = NSRunningApplication(processIdentifier: window.visible.pid)?.localizedName ?? "App"
            let title = attribute(window.element, kAXTitleAttribute as CFString) as? String ?? ""
            return CaptureWindow(id: window.visible.id, title: title.isEmpty ? appName : "\(appName) · \(title)", frame: bounds)
        }
    }

    func usableFrame(of screen: NSScreen) -> CGRect {
        axFrame(screen.visibleFrame, primaryTop: NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY)
    }

    func requestPermission() {
        if !hasRequestedPermission && !isTrusted {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            hasRequestedPermission = true
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func currentWindowCount() -> Int {
        guard isTrusted, windowIDFunction != nil else { return 0 }
        return managedWindows().count
    }

    func arrange(_ preset: LayoutPreset, gap: CGFloat) -> String {
        guard isTrusted else { return "Allow Tile in System Settings > Privacy & Security > Accessibility." }
        guard windowIDFunction != nil else { return "Window identification is unavailable on this macOS version. No windows were moved." }
        guard preset.layout.capacity > 0 else { return "This layout has no usable regions." }
        let screens = NSScreen.screens
        guard let primary = screens.first else { return "No display is available." }
        let displays = screens.map { ArrangementPlan.Display(frame: axFrame($0.frame, primaryTop: primary.frame.maxY), usableFrame: usableFrame(of: $0)) }
        let windows = managedWindows()
        guard !windows.isEmpty else { return "No eligible windows on the current desktop." }
        let byID = Dictionary(uniqueKeysWithValues: windows.map { ($0.visible.id, $0) })
        let plan = ArrangementPlan.make(layout: preset.layout, gap: gap,
            windows: windows.map { ArrangementPlan.Window(id: $0.visible.id, frame: $0.visible.bounds) }, displays: displays)
        var nextOriginals: [OriginalWindow] = []
        var placed = 0
        var failed = 0
        var skipped = plan.outsideDisplays.count
        let overflow = plan.overflow.count
        for placement in plan.placements {
            guard let window = byID[placement.windowID], stillEligible(window), let before = frame(of: window.element) else {
                skipped += 1; continue
            }
            let result = setFrame(placement.frame, on: window.element)
            // An unconfirmed AX write can still take effect. Preserve the original
            // for every attempted adjustment, including a timeout or partial move.
            if result.attempted {
                nextOriginals.append(OriginalWindow(id: window.visible.id, pid: window.visible.pid,
                                                   element: window.element, frame: before))
            }
            if result.verified { placed += 1 } else { failed += 1 }
        }
        if !nextOriginals.isEmpty { originals = nextOriginals }
        var details = ["Arranged \(placed) windows"]
        if overflow > 0 { details.append("\(overflow) beyond capacity, left unchanged") }
        if skipped > 0 { details.append("\(skipped) skipped after their state changed") }
        if failed > 0 { details.append("\(failed) did not reach their target frame") }
        return details.joined(separator: "; ") + "."
    }

    func undo() -> String {
        guard isTrusted else { return "Allow Tile to use Accessibility first." }
        guard windowIDFunction != nil else { return "Window identification is unavailable on this macOS version. No windows were moved." }
        guard !originals.isEmpty else { return "No arrangement to restore." }
        var restored = 0
        var unavailable = 0
        var remaining: [OriginalWindow] = []
        for saved in originals {
            guard windowID(of: saved.element) == saved.id,
                  NSRunningApplication(processIdentifier: saved.pid) != nil else {
                // Closed windows cannot ever be restored; discard their snapshots.
                unavailable += 1
                continue
            }
            guard let visible = visibleWindows().first(where: { $0.id == saved.id && $0.pid == saved.pid }),
                  eligible(saved.element, pid: saved.pid) else {
                // A window on another Space must not be brought here. Keep its
                // snapshot so it can be restored when that Space is active.
                unavailable += 1
                remaining.append(saved)
                continue
            }
            let window = ManagedWindow(visible: visible, element: saved.element)
            guard stillEligible(window) else {
                unavailable += 1
                remaining.append(saved)
                continue
            }
            let result = setFrame(saved.frame, on: saved.element)
            if result.verified {
                restored += 1
            } else {
                unavailable += 1
                remaining.append(saved)
            }
        }
        originals = remaining
        let suffix = unavailable > 0 ? "; \(unavailable) on another desktop, closed, or restricted were not restored" : ""
        return "Restored \(restored) windows\(suffix)."
    }

    private func managedWindows() -> [ManagedWindow] {
        let visible = visibleWindows()
        let byID = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0) })
        var result: [ManagedWindow] = []
        var seen = Set<CGWindowID>()
        for pid in Set(visible.map(\.pid)) {
            guard NSRunningApplication(processIdentifier: pid)?.isHidden == false else { continue }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.35)
            guard let windows = attribute(app, kAXWindowsAttribute as CFString) as? [AXUIElement] else { continue }
            for element in windows {
                AXUIElementSetMessagingTimeout(element, 0.35)
                guard let id = windowID(of: element), let info = byID[id], info.pid == pid,
                      !seen.contains(id), eligible(element, pid: pid) else { continue }
                seen.insert(id)
                result.append(ManagedWindow(visible: info, element: element))
            }
        }
        return result.sorted { $0.visible.order < $1.visible.order }
    }

    private func visibleWindows() -> [VisibleWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.enumerated().compactMap { order, item in
            guard let id = item[kCGWindowNumber as String] as? NSNumber,
                  let pidNumber = item[kCGWindowOwnerPID as String] as? NSNumber,
                  pidNumber.int32Value != ProcessInfo.processInfo.processIdentifier,
                  let layer = item[kCGWindowLayer as String] as? NSNumber, layer.intValue == 0,
                  (item[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let dictionary = item[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
                  bounds.width > 0, bounds.height > 0 else { return nil }
            return VisibleWindow(id: id.uint32Value, pid: pidNumber.int32Value, bounds: bounds, order: order)
        }
    }

    private func stillEligible(_ window: ManagedWindow) -> Bool {
        windowID(of: window.element) == window.visible.id
            && visibleWindows().contains { $0.id == window.visible.id && $0.pid == window.visible.pid }
            && eligible(window.element, pid: window.visible.pid)
    }

    private func eligible(_ element: AXUIElement, pid: pid_t) -> Bool {
        guard NSRunningApplication(processIdentifier: pid)?.isHidden == false,
              attribute(element, kAXRoleAttribute as CFString) as? String == kAXWindowRole as String,
              attribute(element, kAXSubroleAttribute as CFString) as? String == kAXStandardWindowSubrole as String,
              attribute(element, kAXMinimizedAttribute as CFString) as? Bool != true,
              attribute(element, "AXFullScreen" as CFString) as? Bool != true,
              attribute(element, kAXModalAttribute as CFString) as? Bool != true else { return false }
        var movable = DarwinBoolean(false)
        var resizable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &movable) == .success
            && AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &resizable) == .success
            && movable.boolValue && resizable.boolValue
    }

    private func windowID(of element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        guard windowIDFunction?(element, &id) == AXError.success.rawValue, id != 0 else { return nil }
        return id
    }

    private func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name, &result) == .success ? result : nil
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        AXWindowFrameAccess(element: element).readFrame()
    }

    private func setFrame(_ frame: CGRect, on element: AXUIElement) -> FrameApplication {
        let access = AXWindowFrameAccess(element: element)
        let result = access.withImmediateFrameChanges {
            WindowFrameApplier.apply(frame, through: access,
                                     usableFrames: NSScreen.screens.map { usableFrame(of: $0) })
        }
        if !result.verified {
            frameLogger.error("Placement unverified. Target: \(String(describing: frame), privacy: .public); actual: \(String(describing: result.actual), privacy: .public)")
        }
        return result
    }

    private func axFrame(_ rect: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryTop - rect.maxY, width: rect.width, height: rect.height)
    }

}
