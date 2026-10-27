import Foundation
import CoreGraphics

@main
struct LayoutTests {
    static func main() throws {
        let screen = CGRect(x: -1440, y: 25, width: 1440, height: 900)
        let grid = LayoutNode.grid(rows: 2, columns: 3)
        let frames = grid.cellFrames(in: screen, gap: 10)
        expect(grid.capacity == 6 && frames.count == 6, "2×3 capacity")
        near(frames[0], CGRect(x: -1430, y: 35, width: 1400.0 / 3, height: 435), "negative display coordinates")
        expect(frames[0].maxX + 10 == frames[1].minX, "horizontal gap")
        expect(frames[0].maxY + 10 == frames[3].minY, "top-to-bottom row order")
        near(frames[5].maxX, screen.maxX - 10, "last column right boundary")
        near(frames[5].maxY, screen.maxY - 10, "last row bottom boundary")

        let mixed = LayoutNode.split(axis: .horizontal, children: [
            LayoutPart(weight: 2, node: .grid(rows: 1, columns: 1)),
            LayoutPart(weight: 1, node: .split(axis: .vertical, children: [
                LayoutPart(weight: 1, node: .grid(rows: 1, columns: 1)),
                LayoutPart(weight: 1, node: .grid(rows: 1, columns: 1))
            ]))
        ])
        let mixedFrames = mixed.cellFrames(in: CGRect(x: 0, y: 0, width: 930, height: 620), gap: 10)
        expect(mixed.capacity == 3 && mixedFrames.count == 3, "nested split capacity")
        near(mixedFrames[0], CGRect(x: 10, y: 10, width: 600, height: 600), "weighted left panel")
        near(mixedFrames[1], CGRect(x: 620, y: 10, width: 300, height: 295), "upper right panel")
        near(mixedFrames[2], CGRect(x: 620, y: 315, width: 300, height: 295), "lower right panel")

        expect(LayoutNode.grid(rows: 0, columns: 3).capacity == 0, "invalid grid capacity")
        expect(LayoutNode.grid(rows: -1, columns: 3).cellFrames(in: screen, gap: 0).isEmpty, "invalid grid frames")
        expect(grid.cellFrames(in: .zero, gap: 0).isEmpty, "zero-sized display")
        expect(grid.cellFrames(in: screen, gap: 1000).isEmpty, "gap larger than available area")
        expect(grid.cellFrames(in: screen, gap: -5) == grid.cellFrames(in: screen, gap: 0), "negative gaps normalize to zero")
        expect(LayoutNode.split(axis: .vertical, children: []).cellFrames(in: screen, gap: 10).isEmpty, "empty split")
        let invalidWeights = LayoutNode.split(axis: .horizontal, children: [
            LayoutPart(weight: .nan, node: grid), LayoutPart(weight: -1, node: grid),
            LayoutPart(weight: 1, node: .grid(rows: 1, columns: 1))
        ])
        expect(invalidWeights.capacity == 1 && invalidWeights.cellFrames(in: screen, gap: 0) == [screen], "invalid weights do not create phantom capacity")
        let largeWeights = LayoutNode.split(axis: .horizontal, children: [
            LayoutPart(weight: Double.greatestFiniteMagnitude, node: .grid(rows: 1, columns: 1)),
            LayoutPart(weight: Double.greatestFiniteMagnitude, node: .grid(rows: 1, columns: 1))
        ])
        expect(largeWeights.cellFrames(in: screen, gap: 0).allSatisfy { $0.width == screen.width / 2 }, "weight normalization avoids overflow")
        let preset = LayoutPreset(id: "mixed", name: "混合布局", layout: mixed)
        let decoded = try JSONDecoder().decode(LayoutPreset.self, from: JSONEncoder().encode(preset))
        expect(decoded == preset, "recursive layout JSON round trip")
        print("LayoutTests: passed geometry, weighted splits, bounds, invalid inputs, Codable")
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    static func near(_ actual: CGFloat, _ expected: CGFloat, _ message: String) {
        expect(abs(actual - expected) < 0.000_001, message)
    }

    static func near(_ actual: CGRect, _ expected: CGRect, _ message: String) {
        near(actual.minX, expected.minX, message)
        near(actual.minY, expected.minY, message)
        near(actual.width, expected.width, message)
        near(actual.height, expected.height, message)
    }
}
