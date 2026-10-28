import Foundation
import CoreGraphics

@main
struct LayoutTests {
    @MainActor static func main() throws {
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
        let preset = LayoutPreset(id: "mixed", name: "Mixed Layout", layout: mixed)
        let decoded = try JSONDecoder().decode(LayoutPreset.self, from: JSONEncoder().encode(preset))
        expect(decoded == preset, "recursive layout JSON round trip")
        let custom = RegionLayout.example
        let desktop = CGRect(x: 0, y: 30, width: 3840, height: 2052)
        let regions = custom.frames(in: desktop)
        near(regions[0], CGRect(x: 0, y: 30, width: 1920, height: 2052), "left half fills usable desktop")
        near(regions[1], CGRect(x: 1920, y: 30, width: 1920, height: 684), "right upper third")
        near(regions[2], CGRect(x: 1920, y: 714, width: 1920, height: 1368), "right lower two thirds")
        expect(regions[0].maxX == regions[1].minX && regions[1].maxY == regions[2].minY, "no internal gap")
        let uneven = LayoutNode.grid(rows: 3, columns: 3).cellFrames(in: CGRect(x: -1919, y: 30, width: 1919, height: 1079), gap: 0)
        expect(uneven[0].maxX == uneven[1].minX && uneven[0].maxY == uneven[3].minY, "rounded grid boundaries have no seams")
        near(uneven.last!.maxX, 0, "zero outer gap at right edge")
        var blank = custom
        blank.regions.removeLast()
        expect(blank.validationError == nil && blank.frames(in: desktop).count == 2, "blank space allowed")
        var overlapping = custom
        overlapping.regions[1].x = 5
        expect(overlapping.validationError != nil, "overlapping regions rejected")
        var outside = custom
        outside.regions[2].height = 9
        expect(outside.validationError != nil, "out of bounds region rejected")
        let customPreset = LayoutPreset(id: "custom", name: "Left Half + Right Split", layout: .regions(custom))
        let decodedCustom = try JSONDecoder().decode(LayoutPreset.self, from: JSONEncoder().encode(customPreset))
        expect(decodedCustom == customPreset, "custom regions round trip")
        let manualArea = CGRect(x: -2560, y: 38, width: 2560, height: 1362)
        let manual = [CGRect(x: -2550, y: 48, width: 901, height: 800),
                      CGRect(x: -1600, y: 48, width: 1100, height: 500),
                      CGRect(x: -1600, y: 560, width: 1100, height: 700)]
        let captured = try CapturedLayout.make(frames: manual.reversed(), in: manualArea)
        expect(captured.frames(in: manualArea) == manual, "manual rectangles preserve positions, sizes, blank space, and negative screen origin")
        expect(WindowGesture.classify(from: manual[0], to: manual[0].offsetBy(dx: 200, dy: 100)) == .moved, "window movement snaps")
        expect(WindowGesture.classify(from: manual[0], to: manual[0].insetBy(dx: 10, dy: 20)) == .resized, "manual resizing stays free")
        expect(WindowGesture.classify(from: manual[0], to: manual[0]) == .unchanged, "content dragging does not move window")
        do { _ = try CapturedLayout.make(frames: [manual[0], manual[0]], in: manualArea); preconditionFailure("overlap accepted") } catch { }
        do { _ = try CapturedLayout.make(frames: [], in: manualArea); preconditionFailure("empty capture accepted") } catch { }
        let capturePreset = LayoutPreset(id: "captured", name: "Manual Layout", layout: .regions(captured))
        let captureData = try JSONEncoder().encode(capturePreset)
        let captureJSON = String(data: captureData, encoding: .utf8)!
        expect(!captureJSON.contains("title") && !captureJSON.contains("pid"), "captured preset contains geometry only")
        try verifyStoreMigration(capturePreset)
        try verifyStoreMigration(customPreset)
        print("LayoutTests: passed geometry, weighted splits, bounds, invalid inputs, Codable")
    }

    @MainActor static func verifyStoreMigration(_ custom: LayoutPreset) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TileTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("layouts.json")
        let existing = LayoutPreset(id: "existing", name: "Existing Layout", layout: .grid(rows: 2, columns: 3))
        let oldData = try JSONEncoder().encode(TileConfiguration(version: 1, gap: 8, presets: [existing]))
        try oldData.write(to: url)
        let store = LayoutStore(url: url)
        expect(store.loadError == nil && store.configuration.version == 2 && store.configuration.gap == 0, "legacy gap migrated to zero")
        expect(store.configuration.presets == [existing], "migration preserves existing layout IDs and content")
        let backups = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("layouts-before") }
        expect(backups.count == 1, "migration creates one backup")
        let backupData = try Data(contentsOf: backups[0])
        expect(backupData == oldData, "backup preserves exact original configuration")
        try store.save(presets: [existing, custom])
        let reopened = LayoutStore(url: url)
        expect(reopened.configuration.presets == [existing, custom] && reopened.configuration.gap == 0, "saved custom and old layouts survive restart")
        var invalid = custom
        invalid.layout = .regions(RegionLayout(columns: 12, rows: 12, regions: [LayoutRegion(x: 0, y: 0, width: 13, height: 12)]))
        do { try store.save(presets: [invalid]); preconditionFailure("invalid custom layout saved") } catch { }
        expect(store.configuration.presets == [existing, custom], "invalid save preserves existing state")
        print("StoreTests: passed migration, backup, zero gap, custom persistence, invalid save")
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
