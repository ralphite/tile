import Foundation

struct TileConfiguration: Codable {
    var version: Int = 2
    var gap: Double = 0
    var presets: [LayoutPreset]
}

@MainActor
final class LayoutStore {
    let url: URL
    private(set) var configuration: TileConfiguration
    private(set) var loadError: String?
    var onChange: (() -> Void)?

    init(url suppliedURL: URL? = nil) {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tile", isDirectory: true)
        url = suppliedURL ?? folder.appendingPathComponent("layouts.json")
        configuration = TileConfiguration(presets: [
            LayoutPreset(id: "grid-2-3", name: "2 × 3", layout: .grid(rows: 2, columns: 3)),
            LayoutPreset(id: "grid-3-3", name: "3 × 3", layout: .grid(rows: 3, columns: 3)),
            LayoutPreset(id: "grid-3-4", name: "3 × 4", layout: .grid(rows: 3, columns: 4))
        ])
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                var saved = try JSONDecoder().decode(TileConfiguration.self, from: Data(contentsOf: url))
                guard (1...2).contains(saved.version), saved.gap.isFinite else { throw invalid("Invalid configuration version or gap.") }
                try validate(saved.presets)
                let needsMigration = saved.version < 2 || saved.gap != 0
                saved.version = 2
                saved.gap = 0
                configuration = saved
                if needsMigration {
                    try backup(prefix: "layouts-before-zero-gap")
                    try write(saved)
                }
            } catch {
                loadError = "Could not fully read or update the configuration. The original file is preserved: \(error.localizedDescription)"
            }
        }
    }

    func save(presets: [LayoutPreset]) throws {
        try validate(presets)
        // Preserve a malformed file for manual recovery before replacing it.
        if loadError != nil, FileManager.default.fileExists(atPath: url.path) {
            try backup(prefix: "layouts-backup")
        }
        let updated = TileConfiguration(presets: presets)
        try write(updated)
        configuration = updated
        loadError = nil
        onChange?()
    }

    private func write(_ updated: TileConfiguration) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(updated).write(to: url, options: .atomic)
    }

    private func backup(prefix: String) throws {
        let backupURL = url.deletingLastPathComponent().appendingPathComponent("\(prefix)-\(UUID().uuidString).json")
        try FileManager.default.copyItem(at: url, to: backupURL)
    }

    private func validate(_ presets: [LayoutPreset]) throws {
        guard !presets.isEmpty, Set(presets.map(\.id)).count == presets.count else { throw invalid("Keep at least one layout. Layout IDs must be unique.") }
        for preset in presets {
            guard !preset.id.isEmpty, !preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  preset.layout.capacity <= 10_000 else { throw invalid("Invalid layout name or region count.") }
            if let message = preset.layout.validationError { throw invalid(message) }
        }
    }

    private func invalid(_ message: String) -> NSError {
        NSError(domain: "Tile", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
