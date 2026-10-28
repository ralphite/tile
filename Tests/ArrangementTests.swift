import Foundation
import CoreGraphics

@main
struct ArrangementTests {
    @MainActor static func main() throws {
        let usable = CGRect(x: 0, y: 30, width: 3840, height: 2052)
        let display = ArrangementPlan.Display(frame: CGRect(x: 0, y: 0, width: 3840, height: 2160), usableFrame: usable)
        let cases: [(Int, Int, [CGRect])] = [
            (1, 2, [rect(0,30,1920,2052), rect(1920,30,1920,2052)]),
            (1, 3, [rect(0,30,1280,2052), rect(1280,30,1280,2052), rect(2560,30,1280,2052)]),
            (2, 3, [rect(0,30,1280,1026), rect(1280,30,1280,1026), rect(2560,30,1280,1026),
                    rect(0,1056,1280,1026), rect(1280,1056,1280,1026), rect(2560,1056,1280,1026)]),
            (3, 3, [rect(0,30,1280,684), rect(1280,30,1280,684), rect(2560,30,1280,684),
                    rect(0,714,1280,684), rect(1280,714,1280,684), rect(2560,714,1280,684),
                    rect(0,1398,1280,684), rect(1280,1398,1280,684), rect(2560,1398,1280,684)]),
            (3, 4, [rect(0,30,960,684), rect(960,30,960,684), rect(1920,30,960,684), rect(2880,30,960,684),
                    rect(0,714,960,684), rect(960,714,960,684), rect(1920,714,960,684), rect(2880,714,960,684),
                    rect(0,1398,960,684), rect(960,1398,960,684), rect(1920,1398,960,684), rect(2880,1398,960,684)])
        ]
        var windows = (1...13).map { ArrangementPlan.Window(id: UInt32($0), frame: rect(100,100,900,600)) }
        for (rows, columns, expected) in cases {
            // A normal saved configuration must produce the same plan as editing
            // its row/column values. Carry the previous placement into the next one.
            let preset = LayoutPreset(id: "grid", name: "Test", layout: .grid(rows: rows, columns: columns))
            let loaded = try JSONDecoder().decode(LayoutPreset.self, from: JSONEncoder().encode(preset))
            let plan = ArrangementPlan.make(layout: loaded.layout, windows: windows, displays: [display])
            precondition(plan.placements.map(\.frame) == expected, "Incorrect \(rows)x\(columns) rectangles")
            precondition(plan.placements.map(\.windowID) == (1...expected.count).map(UInt32.init), "Front-to-back assignment changed")
            precondition(plan.overflow == ((expected.count + 1)...13).map(UInt32.init), "Overflow windows must stay untouched")
            let targets = Dictionary(uniqueKeysWithValues: plan.placements.map { ($0.windowID, $0.frame) })
            windows = windows.map { .init(id: $0.id, frame: targets[$0.id] ?? $0.frame) }
        }

        let three = Array(windows.prefix(3))
        let sparse = ArrangementPlan.make(layout: .grid(rows: 2, columns: 3), windows: three, displays: [display])
        precondition(sparse.placements.map(\.frame) == Array(cases[2].2.prefix(3)), "Three windows fill the first three cells")
        let custom = ArrangementPlan.make(layout: .regions(.example), windows: three, displays: [display])
        precondition(custom.placements.map(\.frame) == [rect(0,30,1920,2052), rect(1920,30,1920,684), rect(1920,714,1920,1368)])
        print("ArrangementTests: passed saved 1x2, 1x3, 2x3, 3x3, 3x4, consecutive planning, overflow, custom regions")

        let target = rect(1920,30,1920,2052)
        let normal = TestWindow(frame: rect(2560,1398,1280,684))
        let placed = WindowFrameApplier.apply(target, through: normal, usableFrames: [usable])
        precondition(placed.verified && normal.frame == target, "A normal move and resize must reach the requested frame")

        // Concrete normal-use regression: a small window expands to a full-height
        // half-screen, but the application rejects the exact bottom boundary.
        let dockConstrained = TestWindow(frame: rect(2560,1398,1280,684))
        dockConstrained.rejectHeight = 2052
        let expanded = WindowFrameApplier.apply(target, through: dockConstrained, usableFrames: [usable])
        precondition(expanded.verified && dockConstrained.frame == rect(1920,30,1920,2051), "Expansion must use the same Dock-edge correction as shrinking")

        let ignored = TestWindow(frame: rect(100,100,900,600))
        ignored.ignoreWrites = true
        let unconfirmed = WindowFrameApplier.apply(target, through: ignored, usableFrames: [usable])
        precondition(!unconfirmed.verified && unconfirmed.attempted, "Accepted but ignored writes must never report success")
        print("FrameApplierTests: passed normal placement, full-height expansion, actual-result verification (simulated platform only)")
    }

    static func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

@MainActor
private final class TestWindow: WindowFrameAccess {
    var frame: CGRect
    var rejectHeight: CGFloat?
    var ignoreWrites = false
    init(frame: CGRect) { self.frame = frame }
    func readFrame() -> CGRect? { frame }
    func setPosition(_ position: CGPoint) -> Bool {
        if !ignoreWrites { frame.origin = position }
        return true
    }
    func setSize(_ size: CGSize) -> Bool {
        if !ignoreWrites, size.height != rejectHeight { frame.size = size }
        return true
    }
}
