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

/// Integer grid coordinates, independent of display resolution and application identity.
struct LayoutRegion: Codable, Equatable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int

    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

struct RegionLayout: Codable, Equatable {
    static let maximumDimension = 100_000
    var columns: Int
    var rows: Int
    var regions: [LayoutRegion]

    static let example = RegionLayout(columns: 12, rows: 12, regions: [
        LayoutRegion(x: 0, y: 0, width: 6, height: 12),
        LayoutRegion(x: 6, y: 0, width: 6, height: 4),
        LayoutRegion(x: 6, y: 4, width: 6, height: 8)
    ])

    var validationError: String? {
        guard (1...Self.maximumDimension).contains(columns), (1...Self.maximumDimension).contains(rows) else { return "Base grid dimensions must be between 1 and \(Self.maximumDimension)." }
        guard !regions.isEmpty else { return "Add at least one region." }
        for (index, region) in regions.enumerated() {
            guard region.x >= 0, region.y >= 0, region.width > 0, region.height > 0,
                  region.x < columns, region.y < rows,
                  region.width <= columns - region.x, region.height <= rows - region.y else {
                return "Region \(index + 1) is outside the grid or has a nonpositive size."
            }
            for other in regions[..<index] {
                let overlap = region.rect.intersection(other.rect)
                if !overlap.isNull && overlap.width > 0 && overlap.height > 0 {
                    return "Region \(index + 1) overlaps another region. Touching edges are allowed."
                }
            }
        }
        return nil
    }

    /// Shared boundaries use identical rounded endpoints, avoiding a one-pixel seam.
    func frames(in rect: CGRect) -> [CGRect] {
        guard validationError == nil else { return [] }
        return regions.map { region in
            let left = (rect.minX + rect.width * CGFloat(region.x) / CGFloat(columns)).rounded()
            let right = (rect.minX + rect.width * CGFloat(region.x + region.width) / CGFloat(columns)).rounded()
            let top = (rect.minY + rect.height * CGFloat(region.y) / CGFloat(rows)).rounded()
            let bottom = (rect.minY + rect.height * CGFloat(region.y + region.height) / CGFloat(rows)).rounded()
            return CGRect(x: left, y: top, width: right - left, height: bottom - top)
        }
    }
}

indirect enum LayoutNode: Codable, Equatable {
    case grid(rows: Int, columns: Int)
    case split(axis: SplitAxis, children: [LayoutPart])
    case regions(RegionLayout)

    var capacity: Int {
        switch self {
        case let .regions(layout):
            return layout.validationError == nil ? layout.regions.count : 0
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

    var validationError: String? {
        switch self {
        case let .regions(layout): return layout.validationError
        case let .grid(rows, columns):
            return rows > 0 && columns > 0 && capacity <= 10_000 ? nil : "Invalid grid dimensions or too many regions."
        case let .split(_, children):
            guard !children.isEmpty, children.allSatisfy({ $0.weight.isFinite && $0.weight > 0 }) else { return "Invalid split weights." }
            return children.compactMap { $0.node.validationError }.first
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
        case let .regions(layout):
            return layout.frames(in: rect)
        case let .grid(rows, columns):
            guard rows > 0, columns > 0 else { return [] }
            let width = (rect.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
            let height = (rect.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
            guard width > 0, height > 0 else { return [] }
            var result: [CGRect] = []
            for row in 0..<rows {
                for column in 0..<columns {
                    if gap == 0 {
                        let left = (rect.minX + CGFloat(column) * width).rounded()
                        let right = (rect.minX + CGFloat(column + 1) * width).rounded()
                        let top = (rect.minY + CGFloat(row) * height).rounded()
                        let bottom = (rect.minY + CGFloat(row + 1) * height).rounded()
                        result.append(CGRect(x: left, y: top, width: right - left, height: bottom - top))
                    } else {
                        result.append(CGRect(x: rect.minX + CGFloat(column) * (width + gap),
                                             y: rect.minY + CGFloat(row) * (height + gap),
                                             width: width, height: height))
                    }
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
