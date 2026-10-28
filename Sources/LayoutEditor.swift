import AppKit

@MainActor
final class LayoutEditor: NSWindowController, NSWindowDelegate {
    private let store: LayoutStore
    private let manager: WindowManager
    private let onClose: () -> Void
    private let onArrangeMenu: (NSView) -> Void
    private var presets: [LayoutPreset]
    private let chooser = NSPopUpButton(frame: .zero, pullsDown: false)
    private let nameField = NSTextField(string: "")
    private let rows = NSTextField(string: "2")
    private let columns = NSTextField(string: "3")
    private let gap = NSTextField(string: "8")
    private let message = NSTextField(wrappingLabelWithString: "")
    private let deleteButton = NSButton(title: "删除布局", target: nil, action: nil)
    private let saveButton = NSButton(title: "保存", target: nil, action: nil)
    private let permissionLabel = NSTextField(labelWithString: "")
    private let permissionHint = NSTextField(wrappingLabelWithString: "")
    private let permissionButton = NSButton(title: "打开辅助功能设置…", target: nil, action: nil)

    init(store: LayoutStore, manager: WindowManager, onArrangeMenu: @escaping (NSView) -> Void,
         onClose: @escaping () -> Void) {
        self.store = store
        self.manager = manager
        self.onClose = onClose
        self.onArrangeMenu = onArrangeMenu
        self.presets = store.configuration.presets
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 510),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Tile · 布局配置"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.center()
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 17
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24)
        ])
        permissionLabel.font = .systemFont(ofSize: 13, weight: .medium)
        permissionHint.font = .systemFont(ofSize: 12)
        permissionHint.textColor = .secondaryLabelColor
        permissionHint.isSelectable = true
        permissionButton.target = self
        permissionButton.action = #selector(openPermissions)
        let checkButton = NSButton(title: "检查权限", target: self, action: #selector(refreshPermission))
        let permissionActions = NSStackView(views: [permissionButton, checkButton])
        permissionActions.spacing = 8
        root.addArrangedSubview(permissionLabel)
        root.addArrangedSubview(permissionHint)
        root.addArrangedSubview(permissionActions)
        permissionLabel.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        permissionHint.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        let divider = NSBox()
        divider.boxType = .separator
        root.addArrangedSubview(divider)
        divider.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        chooser.target = self
        chooser.action = #selector(selectionChanged)
        root.addArrangedSubview(row("布局", chooser))
        root.addArrangedSubview(row("名称", nameField))
        root.addArrangedSubview(row("网格", numberPair()))
        root.addArrangedSubview(row("窗口间距", gapControl()))
        let hint = NSTextField(wrappingLabelWithString: "按从左到右、从上到下排列。格子满后，其余窗口保持原位。")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        root.addArrangedSubview(hint)
        message.font = .systemFont(ofSize: 12)
        message.textColor = .secondaryLabelColor
        root.addArrangedSubview(message)
        let buttons = NSStackView()
        buttons.orientation = .horizontal
        deleteButton.target = self
        deleteButton.action = #selector(deletePreset)
        saveButton.target = self
        saveButton.action = #selector(savePreset)
        saveButton.keyEquivalent = "\r"
        buttons.addArrangedSubview(deleteButton)
        buttons.addArrangedSubview(NSButton(title: "排列窗口…", target: self, action: #selector(showArrangeMenu(_:))))
        let spacer = NSView()
        buttons.addArrangedSubview(spacer)
        buttons.addArrangedSubview(saveButton)
        root.addArrangedSubview(buttons)
        for view in [chooser, nameField, hint, message, buttons] {
            if view === chooser || view === nameField { continue }
            view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }
        gap.stringValue = store.configuration.gap.formatted(.number.precision(.fractionLength(0...3)).locale(Locale(identifier: "en_US_POSIX")))
        reloadChooser(select: 0)
        refreshPermission()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func row(_ title: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.widthAnchor.constraint(equalToConstant: 72).isActive = true
        let stack = NSStackView(views: [label, control])
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.widthAnchor.constraint(equalToConstant: 382).isActive = true
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return stack
    }

    private func numberPair() -> NSView {
        rows.widthAnchor.constraint(equalToConstant: 58).isActive = true
        columns.widthAnchor.constraint(equalToConstant: 58).isActive = true
        rows.setAccessibilityLabel("行数")
        columns.setAccessibilityLabel("列数")
        let stack = NSStackView(views: [rows, NSTextField(labelWithString: "行 ×"), columns, NSTextField(labelWithString: "列")])
        stack.spacing = 8
        return stack
    }

    private func gapControl() -> NSView {
        gap.widthAnchor.constraint(equalToConstant: 58).isActive = true
        gap.setAccessibilityLabel("窗口间距")
        let stack = NSStackView(views: [gap, NSTextField(labelWithString: "pt")])
        stack.spacing = 8
        return stack
    }

    private func reloadChooser(select index: Int) {
        chooser.removeAllItems()
        chooser.addItems(withTitles: presets.map(\.name) + ["＋ 新建布局"])
        chooser.selectItem(at: min(index, presets.count))
        selectionChanged()
    }

    @objc private func selectionChanged() {
        let index = chooser.indexOfSelectedItem
        message.stringValue = ""
        if index < presets.count {
            let preset = presets[index]
            nameField.stringValue = preset.name
            if case let .grid(r, c) = preset.layout {
                rows.stringValue = String(r)
                columns.stringValue = String(c)
                rows.isEnabled = true
                columns.isEnabled = true
            } else {
                rows.stringValue = "—"
                columns.stringValue = "—"
                rows.isEnabled = false
                columns.isEnabled = false
                message.stringValue = "此为分区布局；保存时保留原有分区。"
            }
        } else {
            nameField.stringValue = ""
            nameField.placeholderString = "例如：工作布局"
            rows.stringValue = "2"
            columns.stringValue = "2"
            rows.isEnabled = true
            columns.isEnabled = true
        }
        deleteButton.isEnabled = index < presets.count && presets.count > 1
    }

    @objc private func savePreset() {
        let index = chooser.indexOfSelectedItem
        guard let spacing = Double(gap.stringValue), spacing.isFinite, (0...64).contains(spacing) else {
            message.stringValue = "窗口间距请填写 0–64。"; return
        }
        let layout: LayoutNode
        if !rows.isEnabled, index < presets.count {
            layout = presets[index].layout
        } else {
            guard let r = Int(rows.stringValue), let c = Int(columns.stringValue),
                  (1...100).contains(r), (1...100).contains(c) else {
                message.stringValue = "行数和列数请填写 1–100 的整数。"; return
            }
            layout = .grid(rows: r, columns: c)
        }
        var name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty, case let .grid(r, c) = layout { name = "\(r) × \(c)" }
        guard !name.isEmpty else { message.stringValue = "请填写布局名称。"; return }
        let id = index < presets.count ? presets[index].id : UUID().uuidString
        let preset = LayoutPreset(id: id, name: name, layout: layout)
        var updated = presets
        if index < updated.count { updated[index] = preset } else { updated.append(preset) }
        do {
            try store.save(presets: updated, gap: spacing)
            presets = updated
            reloadChooser(select: index)
            message.stringValue = "已保存，菜单中可直接使用。"
        } catch { message.stringValue = "保存失败：\(error.localizedDescription)" }
    }

    @objc private func deletePreset() {
        let index = chooser.indexOfSelectedItem
        guard presets.count > 1, index < presets.count else { return }
        var updated = presets
        updated.remove(at: index)
        do {
            try store.save(presets: updated, gap: store.configuration.gap)
            presets = updated
            reloadChooser(select: min(index, presets.count - 1))
            message.stringValue = "已删除布局。"
        } catch { message.stringValue = "删除失败：\(error.localizedDescription)" }
    }

    @objc private func openPermissions() {
        manager.requestPermission()
    }

    @objc private func showArrangeMenu(_ sender: NSButton) {
        onArrangeMenu(sender)
    }

    @objc private func refreshPermission() {
        let trusted = manager.isTrusted
        permissionLabel.stringValue = trusted ? "辅助功能已开启" : "Tile 尚未检测到辅助功能授权"
        permissionHint.stringValue = trusted
            ? (manager.hasWindowBridge ? "可以从菜单栏选择布局排列窗口。" : "当前 macOS 无法准确识别窗口，请检查兼容性。")
            : "若 Tile 开关已经开启，请移除旧条目，再添加当前应用。\n当前应用：\(Bundle.main.bundlePath)"
        NSLog("Tile permission check: trusted=%@, windowBridge=%@, pid=%d, app=%@",
              String(trusted), String(manager.hasWindowBridge), ProcessInfo.processInfo.processIdentifier, Bundle.main.bundlePath)
    }

    func windowDidBecomeKey(_ notification: Notification) { refreshPermission() }
    func windowWillClose(_ notification: Notification) { onClose() }
}
