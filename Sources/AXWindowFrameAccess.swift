import ApplicationServices
import OSLog

/// Thin macOS boundary. Layout rules and placement policy live outside this type.
@MainActor
struct AXWindowFrameAccess: WindowFrameAccess {
    let element: AXUIElement
    private static let logger = Logger(subsystem: "dev.yadong.tile", category: "WindowFrames")

    /// AppKit can animate AX changes when enhanced accessibility is enabled.
    /// Separate position/size requests then animate from stale frames and undo
    /// each other. Scope immediate changes to this operation, preserving the
    /// application's original accessibility state even if placement fails.
    func withImmediateFrameChanges<T>(_ body: () -> T) -> T {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return body() }
        let app = AXUIElementCreateApplication(pid)
        let attribute = "AXEnhancedUserInterface" as CFString
        var original: CFTypeRef?
        let enabled = AXUIElementCopyAttributeValue(app, attribute, &original) == .success
            && (original as? Bool) == true
        let changed = enabled && AXUIElementSetAttributeValue(app, attribute, kCFBooleanFalse) == .success
        defer {
            if changed {
                let restored = AXUIElementSetAttributeValue(app, attribute, kCFBooleanTrue)
                if restored != .success { Self.logger.error("Could not restore AXEnhancedUserInterface: \(restored.rawValue)") }
            }
        }
        return body()
    }

    func readFrame() -> CGRect? {
        guard let positionValue = value(kAXPositionAttribute as CFString),
              let sizeValue = value(kAXSizeAttribute as CFString) else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    @discardableResult func setPosition(_ position: CGPoint) -> Bool {
        var position = position
        guard let value = AXValueCreate(.cgPoint, &position) else { return false }
        return write(value, attribute: kAXPositionAttribute as CFString)
    }

    @discardableResult func setSize(_ size: CGSize) -> Bool {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return write(value, attribute: kAXSizeAttribute as CFString)
    }

    private func value(_ attribute: CFString) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }

    private func write(_ value: AXValue, attribute: CFString) -> Bool {
        let result = AXUIElementSetAttributeValue(element, attribute, value)
        if result != .success { Self.logger.error("AX write \(attribute as String, privacy: .public) failed: \(result.rawValue)") }
        return result == .success
    }
}
