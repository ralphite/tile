import Foundation
import CoreGraphics

enum SplitAxis: String, Codable {
    /// Horizontal places children left to right; vertical places them top to bottom.
    case horizontal, vertical
}

struct LayoutPart: Codable, Equatable {
    var weight: Double
    var node: LayoutNode
}

indirect enum LayoutNode: Codable, Equatable {
    case grid(rows: Int, columns: Int)
    case split(axis: SplitAxis, children: [LayoutPart])

    var capacity: Int {
        switch self {
        case let .grid(rows, columns):
            guard rows > 0, columns > 0 else { return 0 }
            let product = rows.multipliedReportingOverflow(by: columns)
            return product.overflow ? Int.max : product.partialValue
        case let .split(_, children):
            return children.filter { $0.weight.isFinite && $0.weight > 0 }.reduce(0) { total, part in
                let sum = total.addingReportingOverflow(part.node.capacity)
                return sum.overflow ? Int.max : sum.partialValue
            }
        }
    }

    /// All coordinates are in the global, top-left-origin coordinate system used by AX.
    /// A gap is applied once around the outside and between adjacent cells/parts.
    func cellFrames(in rect: CGRect, gap: CGFloat) -> [CGRect] {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.height.isFinite,
              rect.width > 0, rect.height > 0 else { return [] }
        let spacing = gap.isFinite ? max(0, gap) : 0
        let content = rect.insetBy(dx: spacing, dy: spacing)
        guard content.width > 0, content.height > 0 else { return [] }
        return frames(in: content, gap: spacing)
    }

    private func frames(in rect: CGRect, gap: CGFloat) -> [CGRect] {
        switch self {
        case let .grid(rows, columns):
            guard rows > 0, columns > 0 else { return [] }
            let width = (rect.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
            let height = (rect.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
            guard width > 0, height > 0 else { return [] }
            var result: [CGRect] = []
            for row in 0..<rows {
                for column in 0..<columns {
                    result.append(CGRect(x: rect.minX + CGFloat(column) * (width + gap),
                                         y: rect.minY + CGFloat(row) * (height + gap),
                                         width: width, height: height))
                }
            }
            return result
        case let .split(axis, children):
            let parts = children.filter { $0.weight.isFinite && $0.weight > 0 && $0.node.capacity > 0 }
            guard !parts.isEmpty else { return [] }
            // Normalize first so even large, finite weights do not overflow their sum.
            let maximum = parts.map(\.weight).max()!
            let weights = parts.map { $0.weight / maximum }
            let total = weights.reduce(0, +)
            let available = (axis == .horizontal ? rect.width : rect.height) - gap * CGFloat(parts.count - 1)
            guard available > 0 else { return [] }
            var offset: CGFloat = 0
            var result: [CGRect] = []
            for (index, part) in parts.enumerated() {
                let length = available * CGFloat(weights[index] / total)
                let childRect = axis == .horizontal
                    ? CGRect(x: rect.minX + offset, y: rect.minY, width: length, height: rect.height)
                    : CGRect(x: rect.minX, y: rect.minY + offset, width: rect.width, height: length)
                result.append(contentsOf: part.node.frames(in: childRect, gap: gap))
                offset += length + gap
            }
            return result
        }
    }
}

struct LayoutPreset: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var layout: LayoutNode
}
