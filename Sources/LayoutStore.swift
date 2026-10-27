import Foundation

struct TileConfiguration: Codable {
    var version: Int = 1
    var gap: Double = 8
    var presets: [LayoutPreset]
}

@MainActor
final class LayoutStore {
    let url: URL
    private(set) var configuration: TileConfiguration
    private(set) var loadError: String?

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tile", isDirectory: true)
        url = folder.appendingPathComponent("layouts.json")
        configuration = TileConfiguration(presets: [
            LayoutPreset(id: "grid-2-3", name: "2 × 3", layout: .grid(rows: 2, columns: 3)),
            LayoutPreset(id: "grid-3-3", name: "3 × 3", layout: .grid(rows: 3, columns: 3)),
            LayoutPreset(id: "grid-3-4", name: "3 × 4", layout: .grid(rows: 3, columns: 4))
        ])
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let saved = try JSONDecoder().decode(TileConfiguration.self, from: Data(contentsOf: url))
                guard saved.version == 1, saved.gap.isFinite, (0...64).contains(saved.gap),
                      !saved.presets.isEmpty, Set(saved.presets.map(\.id)).count == saved.presets.count,
                      saved.presets.allSatisfy({ !$0.name.isEmpty && $0.layout.capacity > 0 && $0.layout.capacity <= 10_000 }) else {
                    throw NSError(domain: "Tile", code: 1, userInfo: [NSLocalizedDescriptionKey: "配置格式或数值无效"])
                }
                configuration = saved
            } catch {
                loadError = "配置读取失败，暂用默认布局。原文件已保留：\(error.localizedDescription)"
            }
        }
    }

    func save(presets: [LayoutPreset], gap: Double) throws {
        // Preserve a malformed file for manual recovery before replacing it.
        if loadError != nil, FileManager.default.fileExists(atPath: url.path) {
            let backup = url.deletingLastPathComponent().appendingPathComponent("layouts-backup-\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: url, to: backup)
        }
        let updated = TileConfiguration(gap: gap, presets: presets)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(updated).write(to: url, options: .atomic)
        configuration = updated
        loadError = nil
    }
}
