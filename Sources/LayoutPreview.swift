import AppKit

@MainActor
final class LayoutPreview: NSView {
    var layout: LayoutNode = .grid(rows: 2, columns: 3) { didSet { needsDisplay = true } }
    var selectedRegion: Int? { didSet { needsDisplay = true } }
    var onSelect: ((Int) -> Void)?
    override var isFlipped: Bool { true }

    private var screenRect: CGRect {
        let available = bounds.insetBy(dx: 16, dy: 12)
        let size = NSScreen.main?.visibleFrame.size ?? CGSize(width: 16, height: 9)
        let width = min(available.width, available.height * size.width / size.height)
        let height = width * size.height / size.width
        return CGRect(x: available.midX - width / 2, y: available.midY - height / 2, width: width, height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        let screen = screenRect
        NSColor.windowBackgroundColor.setFill(); screen.fill()
        if case let .regions(custom) = layout, custom.columns > 0, custom.rows > 0 {
            NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
            let lines = NSBezierPath()
            for x in stride(from: 0, through: custom.columns, by: max(1, custom.columns / 32)) {
                let px = screen.minX + CGFloat(x) / CGFloat(custom.columns) * screen.width
                lines.move(to: NSPoint(x: px, y: screen.minY)); lines.line(to: NSPoint(x: px, y: screen.maxY))
            }
            for y in stride(from: 0, through: custom.rows, by: max(1, custom.rows / 24)) {
                let py = screen.minY + CGFloat(y) / CGFloat(custom.rows) * screen.height
                lines.move(to: NSPoint(x: screen.minX, y: py)); lines.line(to: NSPoint(x: screen.maxX, y: py))
            }
            lines.lineWidth = 0.5; lines.stroke()
        }
        for (index, frame) in layout.cellFrames(in: screen, gap: 0).enumerated() {
            let selected = selectedRegion == index
            NSColor.controlAccentColor.withAlphaComponent(selected ? 0.35 : 0.13).setFill(); frame.fill()
            (selected ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
            let outline = NSBezierPath(rect: frame.insetBy(dx: 0.5, dy: 0.5))
            outline.lineWidth = selected ? 2 : 1; outline.stroke()
            if frame.width >= 22 && frame.height >= 22 {
                let label = "\(index + 1)" as NSString
                let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: NSColor.labelColor]
                let size = label.size(withAttributes: attributes)
                label.draw(at: NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2), withAttributes: attributes)
            }
        }
        NSColor.separatorColor.setStroke(); NSBezierPath(rect: screen).stroke()
    }

    override func mouseDown(with event: NSEvent) {
        guard case .regions = layout else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let index = layout.cellFrames(in: screenRect, gap: 0).firstIndex(where: { $0.contains(point) }) { onSelect?(index) }
    }
}
