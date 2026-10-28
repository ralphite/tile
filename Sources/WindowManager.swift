import AppKit
import ApplicationServices
import Darwin

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
        if write.mayHaveChanged {
            originals = [OriginalWindow(id: window.id, pid: window.pid, element: window.element, frame: window.originalFrame)]
        }
        if let actual = frame(of: window.element), approximatelyEqual(actual, target) { return "Window snapped. Use Restore Last Arrangement to undo." }
        return write.fullySubmitted ? "Window moved, but the app limited its size." : "Could not snap the window. Use Restore Last Arrangement if it moved."
    }

    func captureWindows(on screen: NSScreen) -> [CaptureWindow] {
        guard isTrusted, hasWindowBridge, let primary = NSScreen.screens.first else { return [] }
        let screens = NSScreen.screens
        let areas = screens.map { axFrame($0.frame, primaryTop: primary.frame.maxY) }
        guard let screenIndex = screens.firstIndex(of: screen) else { return [] }
        return managedWindows().compactMap { window in
            let intersections = areas.map { intersectionArea($0, window.visible.bounds) }
            guard intersections.indices.max(by: { intersections[$0] < intersections[$1] }) == screenIndex,
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
        let screenFrames = screens.map { axFrame($0.frame, primaryTop: primary.frame.maxY) }
        let cells = screens.map { preset.layout.cellFrames(in: axFrame($0.visibleFrame, primaryTop: primary.frame.maxY), gap: gap) }
        let windows = managedWindows()
        guard !windows.isEmpty else { return "No eligible windows on the current desktop." }

        var grouped = Array(repeating: [ManagedWindow](), count: screens.count)
        var skipped = 0
        for window in windows {
            let areas = screenFrames.map { intersectionArea($0, window.visible.bounds) }
            guard let best = areas.indices.max(by: { areas[$0] < areas[$1] }), areas[best] > 0 else {
                skipped += 1
                continue
            }
            grouped[best].append(window)
        }

        var nextOriginals: [OriginalWindow] = []
        var placed = 0
        var limited = 0
        var failed = 0
        var overflow = 0
        for index in grouped.indices {
            let ordered = grouped[index].sorted { $0.visible.order < $1.visible.order }
            overflow += max(0, ordered.count - cells[index].count)
            for (window, target) in zip(ordered, cells[index]) {
                // Re-query immediately before every write; never act on a stale
                // list captured before a Space switch, minimize, or app hide.
                guard stillEligible(window), let before = frame(of: window.element) else {
                    skipped += 1
                    continue
                }
                if approximatelyEqual(before, target) {
                    placed += 1
                    continue
                }
                let saved = OriginalWindow(id: window.visible.id, pid: window.visible.pid,
                                           element: window.element, frame: before)
                let write = setFrame(target, on: window.element)
                let actual = frame(of: window.element)
                // Apps may apply an accepted AX write after the first readback.
                // Keep its original frame even when this read still looks unchanged.
                // A timeout is also uncertain: the receiving app may apply it later.
                if write.mayHaveChanged || actual == nil || !approximatelyEqual(actual!, before) {
                    nextOriginals.append(saved)
                }
                if let actual, approximatelyEqual(actual, target) {
                    placed += 1
                } else if write.fullySubmitted {
                    limited += 1
                } else {
                    failed += 1
                }
            }
        }
        if !nextOriginals.isEmpty { originals = nextOriginals }
        var details = ["Arranged \(placed) windows"]
        if limited > 0 { details.append("\(limited) limited by app size or position constraints") }
        if overflow > 0 { details.append("\(overflow) beyond capacity, left unchanged") }
        if skipped > 0 { details.append("\(skipped) skipped after their state changed") }
        if failed > 0 { details.append("\(failed) failed") }
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
            _ = setFrame(saved.frame, on: saved.element)
            if let actual = frame(of: saved.element), approximatelyEqual(actual, saved.frame) {
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
        guard let positionValue = attribute(element, kAXPositionAttribute as CFString),
              let sizeValue = attribute(element, kAXSizeAttribute as CFString),
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    private func setFrame(_ frame: CGRect, on element: AXUIElement) -> (fullySubmitted: Bool, mayHaveChanged: Bool) {
        var size = frame.size
        var position = frame.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size), let positionValue = AXValueCreate(.cgPoint, &position) else { return (false, false) }
        // Move first so expansion is not clipped by the old origin near an edge.
        // An old large frame may clamp this first move; repeat after resizing.
        let initialMove = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
        var resized = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        var finalMove = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
        var responses = [initialMove, resized, finalMove]
        // Some native windows reserve one point at the Dock boundary. When an
        // exact-edge resize is ignored, retry inside that system boundary only;
        // never introduce spacing between neighboring regions.
        if let actual = self.frame(of: element), actual.height > frame.height + 2,
           frame.height > 1, let primary = NSScreen.screens.first,
           NSScreen.screens.contains(where: {
               let area = axFrame($0.visibleFrame, primaryTop: primary.frame.maxY)
               return abs(frame.maxY - area.maxY) < 1 && frame.minX >= area.minX && frame.maxX <= area.maxX
           }) {
            var edgeSize = CGSize(width: frame.width, height: frame.height - 1)
            if let edgeValue = AXValueCreate(.cgSize, &edgeSize) {
                resized = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, edgeValue)
                finalMove = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
                responses += [resized, finalMove]
            }
        }
        // The final size and move determine submission success. Any of the three
        // writes may change the window, so partial/uncertain writes remain undoable.
        let mayHaveChanged = responses.contains { $0 == .success || $0 == .cannotComplete }
        return (resized == .success && finalMove == .success, mayHaveChanged)
    }

    private func axFrame(_ rect: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryTop - rect.maxY, width: rect.width, height: rect.height)
    }

    private func intersectionArea(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let intersection = first.intersection(second)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    private func approximatelyEqual(_ first: CGRect, _ second: CGRect) -> Bool {
        abs(first.minX - second.minX) <= 2 && abs(first.minY - second.minY) <= 2
            && abs(first.width - second.width) <= 2 && abs(first.height - second.height) <= 2
    }
}
