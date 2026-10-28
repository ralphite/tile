import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let store = LayoutStore()
    private let manager = WindowManager()
    private var editor: LayoutEditor?
    private var capture: CaptureLayoutController?
    private var lastResult: String?
    private var selectedPresetID = UserDefaults.standard.string(forKey: "snapPresetID")
    private lazy var snapper = SnapController(manager: manager) { [weak self] result in self?.report(result) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installEditingMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.grid.3x3", accessibilityDescription: "Tile · Arrange Windows")
        statusItem.button?.toolTip = "Tile · Arrange windows on the current desktop"
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        lastResult = store.loadError
        store.onChange = { [weak self] in
            self?.synchronizeSnapPreset()
            self?.editor?.refreshPresets()
        }
        updateMenu(menu)
        if CommandLine.arguments.contains("--show-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.statusItem.button?.performClick(nil) }
        } else if !manager.isTrusted || !UserDefaults.standard.bool(forKey: "hasLaunched") {
            configure()
            UserDefaults.standard.set(true, forKey: "hasLaunched")
        }
    }

    private func installEditingMenu() {
        let main = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "Tile")
        let quit = applicationMenu.addItem(withTitle: "Quit Tile", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        applicationItem.submenu = applicationMenu
        main.addItem(applicationItem)
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        for (title, selector, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"),
                                       ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: NSSelectorFromString(selector), keyEquivalent: key)
        }
        editItem.submenu = edit; main.addItem(editItem)
        NSApp.mainMenu = main
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        configure()
        return true
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateMenu(menu)
    }

    private func updateMenu(_ menu: NSMenu) {
        synchronizeSnapPreset()
        menu.removeAllItems()
        let header = NSMenuItem(title: "Tile · Current Desktop", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        if !manager.isTrusted {
            add("Allow Accessibility…", action: #selector(authorize), to: menu)
        }
        menu.addItem(.separator())
        for preset in store.configuration.presets {
            let title: String
            if case let .grid(rows, columns) = preset.layout {
                let dimensions = "\(rows) rows × \(columns) columns"
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
        let snapLayout = NSMenuItem(title: "Snap Layout: \(selectedPreset?.name ?? "None")", action: nil, keyEquivalent: "")
        let choices = NSMenu(); choices.autoenablesItems = false
        for preset in store.configuration.presets {
            let item = NSMenuItem(title: preset.name, action: #selector(selectSnapLayout(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = preset.id
            item.state = preset.id == selectedPreset?.id ? .on : .off
            item.image = preview(preset.layout); choices.addItem(item)
        }
        snapLayout.submenu = choices; menu.addItem(snapLayout)
        add(snapper.isEnabled ? "Disable Drag Snapping" : "Enable Drag Snapping", action: #selector(toggleSnapping), to: menu)
        menu.addItem(.separator())
        let undo = add("Restore Last Arrangement", action: #selector(undo), to: menu)
        undo.isEnabled = manager.canUndo
        add("Save Current Windows as Layout…", action: #selector(captureLayout), to: menu)
        add("Edit Layouts…", action: #selector(configure), to: menu)
        if let lastResult {
            menu.addItem(.separator())
            let item = NSMenuItem(title: lastResult, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())
        add("Quit Tile", action: #selector(quit), to: menu)
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
            for cell in layout.cellFrames(in: rect.insetBy(dx: 1, dy: 1), gap: 0) {
                NSBezierPath(roundedRect: cell.insetBy(dx: 0.7, dy: 0.7), xRadius: 0.6, yRadius: 0.6).fill()
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
            lastResult = "Tile does not have Accessibility permission."
            configure()
            return
        }
        // Tile's own windows are already excluded by WindowManager. Execute the
        // selected command now, so reopening the menu cannot display a stale
        // result or leave an older layout queued behind a later click.
        lastResult = manager.arrange(preset, gap: store.configuration.gap)
        selectPreset(preset)
        statusItem.button?.toolTip = lastResult
    }

    @objc private func undo() {
        lastResult = manager.undo()
        statusItem.button?.toolTip = lastResult
    }

    @objc private func authorize() {
        manager.requestPermission()
    }

    private var selectedPreset: LayoutPreset? {
        store.configuration.presets.first { $0.id == selectedPresetID } ?? store.configuration.presets.first
    }

    private func synchronizeSnapPreset() {
        if !manager.isTrusted && snapper.isEnabled { snapper.stop() }
        if let preset = selectedPreset, snapper.preset != preset { snapper.select(preset) }
        statusItem?.button?.contentTintColor = snapper.isEnabled ? .controlAccentColor : nil
    }

    private func selectPreset(_ preset: LayoutPreset) {
        selectedPresetID = preset.id
        UserDefaults.standard.set(preset.id, forKey: "snapPresetID")
        snapper.select(preset)
    }

    @objc private func selectSnapLayout(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let preset = store.configuration.presets.first(where: { $0.id == id }) else { return }
        selectPreset(preset)
        report("Snap layout selected: \(preset.name).")
    }

    @objc private func toggleSnapping() {
        if snapper.isEnabled {
            snapper.stop(); report("Drag snapping is off.")
        } else if let preset = selectedPreset {
            if snapper.start(with: preset) {
                report("Drag snapping is on: \(preset.name). Drag to preview; release to fill. Resizing stays free.")
            } else {
                report("Could not enable snapping. Check Accessibility permission.")
                configure()
            }
        }
        synchronizeSnapPreset()
    }

    private func report(_ message: String) {
        lastResult = message
        statusItem?.button?.toolTip = message
    }

    func applicationWillTerminate(_ notification: Notification) { snapper.stop() }

    @objc private func captureLayout() {
        guard manager.isTrusted else { configure(); return }
        if capture == nil {
            capture = CaptureLayoutController(store: store, manager: manager, onSave: { [weak self] preset in
                self?.selectPreset(preset)
                self?.report("Saved \(preset.name) as a new layout with \(preset.layout.capacity) regions.")
            }, onClose: { [weak self] in self?.capture = nil })
        }
        capture?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        capture?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func configure() {
        if editor == nil {
            editor = LayoutEditor(store: store, manager: manager, onArrangeMenu: { [weak self] sender in
                guard let self else { return }
                self.statusItem.menu?.popUp(positioning: nil,
                    at: NSPoint(x: 0, y: sender.bounds.maxY), in: sender)
            }) { [weak self] in self?.editor = nil }
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
