import Foundation
import CoreGraphics

enum WindowGesture {
    case unchanged, moved, resized

    static func classify(from start: CGRect, to current: CGRect) -> WindowGesture {
        if abs(start.width - current.width) > 2 || abs(start.height - current.height) > 2 { return .resized }
        if abs(start.minX - current.minX) > 3 || abs(start.minY - current.minY) > 3 { return .moved }
        return .unchanged
    }
}

enum CapturedLayout {
    static func make(frames: [CGRect], in area: CGRect) throws -> RegionLayout {
        guard !frames.isEmpty else { throw failure("Select at least one window.") }
        guard ([area] + frames).allSatisfy({ rect in
            [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy { $0.isFinite } && rect.width > 0 && rect.height > 0
        }) else { throw failure("Invalid window geometry. Refresh the window list.") }
        let columns = max(1, Int(min(CGFloat(RegionLayout.maximumDimension), area.width.rounded())))
        let rows = max(1, Int(min(CGFloat(RegionLayout.maximumDimension), area.height.rounded())))
        let sorted = frames.sorted {
            if $0.minY != $1.minY { return $0.minY < $1.minY }
            return $0.minX < $1.minX
        }
        let regions = try sorted.map { frame -> LayoutRegion in
            guard frame.minX >= area.minX - 1, frame.minY >= area.minY - 1,
                  frame.maxX <= area.maxX + 1, frame.maxY <= area.maxY + 1 else {
                throw failure("A selected window extends beyond the usable display. Move it inside or deselect it before saving.")
            }
            let clipped = frame.intersection(area)
            let left = Int(((clipped.minX - area.minX) / area.width * CGFloat(columns)).rounded())
            let right = Int(((clipped.maxX - area.minX) / area.width * CGFloat(columns)).rounded())
            let top = Int(((clipped.minY - area.minY) / area.height * CGFloat(rows)).rounded())
            let bottom = Int(((clipped.maxY - area.minY) / area.height * CGFloat(rows)).rounded())
            return LayoutRegion(x: left, y: top, width: right - left, height: bottom - top)
        }
        let layout = RegionLayout(columns: columns, rows: rows, regions: regions)
        if let error = layout.validationError { throw failure(error) }
        return layout
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "Tile", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
