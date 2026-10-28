import CoreGraphics

/// Inputs are already eligible windows, ordered front to back. No system calls.
struct ArrangementPlan {
    struct Window {
        let id: UInt32
        let frame: CGRect
    }
    struct Display {
        let frame: CGRect
        let usableFrame: CGRect
    }
    struct Placement: Equatable {
        let windowID: UInt32
        let frame: CGRect
    }

    let placements: [Placement]
    let overflow: [UInt32]
    let outsideDisplays: [UInt32]

    static func make(layout: LayoutNode, gap: CGFloat = 0,
                     windows: [Window], displays: [Display]) -> ArrangementPlan {
        let cells = displays.map { layout.cellFrames(in: $0.usableFrame, gap: gap) }
        var used = Array(repeating: 0, count: displays.count)
        var placements: [Placement] = []
        var overflow: [UInt32] = []
        var outside: [UInt32] = []
        for window in windows {
            guard let screen = displayIndex(for: window.frame, displays: displays) else {
                outside.append(window.id); continue
            }
            guard used[screen] < cells[screen].count else {
                overflow.append(window.id); continue
            }
            placements.append(Placement(windowID: window.id, frame: cells[screen][used[screen]]))
            used[screen] += 1
        }
        return ArrangementPlan(placements: placements, overflow: overflow, outsideDisplays: outside)
    }

    static func displayIndex(for frame: CGRect, displays: [Display]) -> Int? {
        var best: Int?
        var largest: CGFloat = 0
        for (index, display) in displays.enumerated() {
            let overlap = frame.intersection(display.frame)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > largest { best = index; largest = area }
        }
        return best
    }
}
