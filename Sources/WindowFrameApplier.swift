import CoreGraphics

/// The only operations needed from the platform for placing one window.
@MainActor
protocol WindowFrameAccess {
    func readFrame() -> CGRect?
    @discardableResult func setPosition(_ position: CGPoint) -> Bool
    @discardableResult func setSize(_ size: CGSize) -> Bool
}

struct FrameApplication {
    let actual: CGRect?
    let verified: Bool
    let attempted: Bool
}

@MainActor
enum WindowFrameApplier {
    /// A successful API response alone is never a verified placement.
    static func apply(_ target: CGRect, through window: any WindowFrameAccess,
                      usableFrames: [CGRect]) -> FrameApplication {
        if let before = window.readFrame(), matches(before, target) {
            return FrameApplication(actual: before, verified: true, attempted: false)
        }
        window.setPosition(target.origin)
        window.setSize(target.size)
        window.setPosition(target.origin)
        var actual = window.readFrame()

        // Some windows reject the exact Dock boundary when growing OR shrinking.
        // Keep the retry local to that outer boundary; internal gaps stay zero.
        if let observed = actual, !matches(observed, target), target.height > 1,
           usableFrames.contains(where: { area in
               abs(target.maxY - area.maxY) < 1 && target.minX >= area.minX && target.maxX <= area.maxX
           }) {
            window.setSize(CGSize(width: target.width, height: target.height - 1))
            window.setPosition(target.origin)
            actual = window.readFrame()
        }
        return FrameApplication(actual: actual, verified: actual.map { matches($0, target) } ?? false, attempted: true)
    }

    static func matches(_ actual: CGRect, _ target: CGRect) -> Bool {
        abs(actual.minX - target.minX) <= 2 && abs(actual.minY - target.minY) <= 2
            && abs(actual.width - target.width) <= 2 && abs(actual.height - target.height) <= 2
    }
}
