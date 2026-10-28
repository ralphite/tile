import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let store = LayoutStore()
    private let manager = WindowManager()
    private var editor: LayoutEditor?
    private var lastResult: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.grid.3x3", accessibilityDescription: "Tile · 排列窗口")
        statusItem.button?.toolTip = "Tile · 排列当前桌面的窗口"
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        lastResult = store.loadError
        if CommandLine.arguments.contains("--show-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.statusItem.button?.performClick(nil) }
        } else if !manager.isTrusted || !UserDefaults.standard.bool(forKey: "hasLaunched") {
            configure()
            UserDefaults.standard.set(true, forKey: "hasLaunched")
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        configure()
        return true
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        let header = NSMenuItem(title: "Tile · 当前桌面", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        if !manager.isTrusted {
            add("授权辅助功能…", action: #selector(authorize), to: menu)
        }
        menu.addItem(.separator())
        for preset in store.configuration.presets {
            let title: String
            if case let .grid(rows, columns) = preset.layout {
                let dimensions = "\(rows) 行 × \(columns) 列"
                title = preset.name == "\(rows) × \(columns)" ? dimensions : "\(preset.name)  ·  \(dimensions)"
            } else {
                title = preset.name
            }
            let item = NSMenuItem(title: title, action: #selector(arrange(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.id
            item.image = preview(preset.layout)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let undo = add("恢复上次排列", action: #selector(undo), to: menu)
        undo.isEnabled = manager.canUndo
        add("布局配置…", action: #selector(configure), to: menu)
        if let lastResult {
            menu.addItem(.separator())
            let item = NSMenuItem(title: lastResult, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())
        add("退出 Tile", action: #selector(quit), to: menu)
    }

    @discardableResult
    private func add(_ title: String, action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    private func preview(_ layout: LayoutNode) -> NSImage {
        let image = NSImage(size: NSSize(width: 30, height: 22), flipped: true) { rect in
            NSColor.labelColor.setFill()
            for cell in layout.cellFrames(in: rect.insetBy(dx: 1, dy: 1), gap: 2) {
                NSBezierPath(roundedRect: cell, xRadius: 0.6, yRadius: 0.6).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func arrange(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let preset = store.configuration.presets.first(where: { $0.id == id }) else { return }
        guard manager.isTrusted else {
            lastResult = "Tile 尚未检测到辅助功能授权"
            configure()
            return
        }
        // Defer until the status menu has closed, so its window is never a candidate.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            self.lastResult = self.manager.arrange(preset, gap: self.store.configuration.gap)
            self.statusItem.button?.toolTip = self.lastResult
        }
    }

    @objc private func undo() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            self.lastResult = self.manager.undo()
            self.statusItem.button?.toolTip = self.lastResult
        }
    }

    @objc private func authorize() {
        manager.requestPermission()
    }

    @objc private func configure() {
        if editor == nil {
            editor = LayoutEditor(store: store, manager: manager) { [weak self] in self?.editor = nil }
        }
        editor?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        editor?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

@main
struct TileApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
