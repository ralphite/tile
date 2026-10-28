import AppKit

@MainActor
final class LayoutEditor: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    private let store: LayoutStore
    private let manager: WindowManager
    private let onClose: () -> Void
    private let onArrangeMenu: (NSView) -> Void
    private let chooser = NSPopUpButton(frame: .zero, pullsDown: false)
    private let kind = NSPopUpButton(frame: .zero, pullsDown: false)
    private let nameField = NSTextField(string: "")
    private let rows = NSTextField(string: "2")
    private let columns = NSTextField(string: "3")
    private let gridLabel = NSTextField(labelWithString: "Grid")
    private let regionChooser = NSPopUpButton(frame: .zero, pullsDown: false)
    private let coordinates = (0..<4).map { _ in NSTextField(string: "0") }
    private let regionControls = NSStackView()
    private let preview = LayoutPreview()
    private let hint = NSTextField(wrappingLabelWithString: "")
    private let message = NSTextField(wrappingLabelWithString: "")
    private let permission = NSTextField(wrappingLabelWithString: "")
    private let permissionButton = NSButton(title: "Allow Accessibility…", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete Layout", target: nil, action: nil)
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)
    private var custom = RegionLayout.example
    private var selectedRegion = 0
    private var legacy: LayoutNode?
    private var loading = false

    init(store: LayoutStore, manager: WindowManager, onArrangeMenu: @escaping (NSView) -> Void,
         onClose: @escaping () -> Void) {
        self.store = store; self.manager = manager
        self.onClose = onClose; self.onArrangeMenu = onArrangeMenu
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 630),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Tile · Layout Editor"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self; window.center()
        let root = NSStackView()
        root.orientation = .vertical; root.alignment = .leading; root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20)
        ])
        permission.font = .systemFont(ofSize: 12); permission.textColor = .secondaryLabelColor
        permissionButton.target = self; permissionButton.action = #selector(openPermissions)
        root.addArrangedSubview(NSStackView(views: [permission, permissionButton]))
        let divider = NSBox(); divider.boxType = .separator
        root.addArrangedSubview(divider); divider.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        chooser.target = self; chooser.action = #selector(selectionChanged)
        root.addArrangedSubview(row("Layout", chooser))
        nameField.placeholderString = "Layout name"
        root.addArrangedSubview(row("Name", nameField))
        kind.addItems(withTitles: ["Equal Grid", "Custom Regions"])
        kind.target = self; kind.action = #selector(kindChanged)
        root.addArrangedSubview(row("Type", kind))
        rows.setAccessibilityLabel("Grid rows"); columns.setAccessibilityLabel("Grid columns")
        for field in [rows, columns] { field.widthAnchor.constraint(equalToConstant: 58).isActive = true; field.delegate = self }
        let dimensions = NSStackView(views: [rows, NSTextField(labelWithString: "rows ×"), columns, NSTextField(labelWithString: "columns"), NSTextField(labelWithString: "   Gap: 0")])
        dimensions.spacing = 8
        gridLabel.widthAnchor.constraint(equalToConstant: 72).isActive = true
        root.addArrangedSubview(NSStackView(views: [gridLabel, dimensions]))
        preview.heightAnchor.constraint(equalToConstant: 200).isActive = true
        preview.setAccessibilityElement(true); preview.setAccessibilityRole(.image)
        preview.setAccessibilityLabel("Layout region preview")
        preview.onSelect = { [weak self] index in self?.selectRegion(index) }
        root.addArrangedSubview(preview); preview.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        regionControls.orientation = .vertical; regionControls.alignment = .leading; regionControls.spacing = 10
        regionChooser.target = self; regionChooser.action = #selector(regionChanged)
        regionChooser.widthAnchor.constraint(equalToConstant: 150).isActive = true
        regionControls.addArrangedSubview(NSStackView(views: [
            regionChooser, NSButton(title: "Add Region", target: self, action: #selector(addRegion)),
            NSButton(title: "Remove Region", target: self, action: #selector(removeRegion))]))
        let fields = NSStackView(); fields.spacing = 10
        for (index, title) in ["Left", "Top", "Width", "Height"].enumerated() {
            let field = coordinates[index]
            field.widthAnchor.constraint(equalToConstant: 65).isActive = true
            field.setAccessibilityLabel("Region \(title)"); field.delegate = self
            fields.addArrangedSubview(NSTextField(labelWithString: title)); fields.addArrangedSubview(field)
        }
        fields.addArrangedSubview(NSTextField(labelWithString: "cells"))
        regionControls.addArrangedSubview(fields); root.addArrangedSubview(regionControls)
        hint.font = .systemFont(ofSize: 12); hint.textColor = .secondaryLabelColor
        root.addArrangedSubview(hint)
        message.font = .systemFont(ofSize: 12); message.heightAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
        root.addArrangedSubview(message)
        deleteButton.target = self; deleteButton.action = #selector(deletePreset)
        saveButton.target = self; saveButton.action = #selector(savePreset); saveButton.keyEquivalent = "\r"
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [deleteButton,
            NSButton(title: "Arrange Windows…", target: self, action: #selector(showArrangeMenu(_:))), spacer,
            NSButton(title: "Save a Copy", target: self, action: #selector(saveCopy)), saveButton])
        root.addArrangedSubview(buttons)
        for view in [hint, message, buttons] { view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true }
        reloadChooser(select: store.configuration.presets.first?.id); refreshPermission()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func row(_ title: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title); label.widthAnchor.constraint(equalToConstant: 72).isActive = true
        let stack = NSStackView(views: [label, control]); stack.spacing = 12
        stack.widthAnchor.constraint(equalToConstant: 712).isActive = true
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return stack
    }
    private var presetID: String? { chooser.selectedItem?.representedObject as? String }

    func refreshPresets() {
        let id = presetID
        reloadChooser(select: id, updateFields: id != nil && !store.configuration.presets.contains { $0.id == id })
    }

    private func reloadChooser(select id: String?, updateFields: Bool = true) {
        chooser.removeAllItems()
        // Titles are presentation; identity is always the saved preset ID.
        for preset in store.configuration.presets {
            let item = NSMenuItem(title: preset.name, action: nil, keyEquivalent: "")
            item.representedObject = preset.id; chooser.menu!.addItem(item)
        }
        chooser.menu!.addItem(NSMenuItem(title: "+ New Layout", action: nil, keyEquivalent: ""))
        chooser.selectItem(at: chooser.itemArray.firstIndex { ($0.representedObject as? String) == id } ?? 0)
        if updateFields { selectionChanged() }
    }

    @objc private func selectionChanged() {
        loading = true
        while kind.numberOfItems > 2 { kind.removeItem(at: 2) }
        legacy = nil
        if let preset = store.configuration.presets.first(where: { $0.id == presetID }) {
            nameField.stringValue = preset.name
            switch preset.layout {
            case let .grid(r, c):
                kind.selectItem(at: 0); rows.stringValue = String(r); columns.stringValue = String(c)
            case let .regions(layout):
                kind.selectItem(at: 1); custom = layout
                rows.stringValue = String(layout.rows); columns.stringValue = String(layout.columns)
            case .split:
                legacy = preset.layout; kind.addItem(withTitle: "Existing Split"); kind.selectItem(at: 2)
            }
        } else {
            nameField.stringValue = ""; kind.selectItem(at: 1); custom = .example
            rows.stringValue = "12"; columns.stringValue = "12"
        }
        selectedRegion = 0; loadRegionChooser(); loading = false
        updateKindUI(); updatePreview(); message.stringValue = ""
        deleteButton.isEnabled = presetID != nil && store.configuration.presets.count > 1
    }

    @objc private func kindChanged() {
        loading = true
        if kind.indexOfSelectedItem == 1 {
            custom = .example; selectedRegion = 0
            rows.stringValue = String(custom.rows); columns.stringValue = String(custom.columns); loadRegionChooser()
        } else if kind.indexOfSelectedItem == 0 {
            rows.stringValue = "2"; columns.stringValue = "3"
        }
        loading = false; updateKindUI(); updatePreview()
    }

    private func updateKindUI() {
        let isCustom = kind.indexOfSelectedItem == 1
        regionControls.isHidden = !isCustom
        rows.isEnabled = kind.indexOfSelectedItem != 2; columns.isEnabled = rows.isEnabled
        gridLabel.stringValue = isCustom ? "Base Grid" : "Grid"
        hint.stringValue = isCustom
            ? "Left and Top start at 0; size is in grid cells. Empty space is allowed; overlap is not. Windows fill numbered regions; extras stay in place."
            : "Fill left to right, then top to bottom, with zero gaps. Extra windows stay in place."
    }

    private func loadRegionChooser() {
        regionChooser.removeAllItems()
        regionChooser.addItems(withTitles: custom.regions.indices.map { "Region \($0 + 1)" })
        selectedRegion = min(selectedRegion, max(0, custom.regions.count - 1))
        if !custom.regions.isEmpty { regionChooser.selectItem(at: selectedRegion) }
        loadCoordinates()
    }
    private func loadCoordinates() {
        let region = custom.regions.indices.contains(selectedRegion) ? custom.regions[selectedRegion] : nil
        let values = region.map { [$0.x, $0.y, $0.width, $0.height] } ?? [0, 0, 1, 1]
        for (field, value) in zip(coordinates, values) { field.stringValue = String(value); field.isEnabled = region != nil }
        preview.selectedRegion = kind.indexOfSelectedItem == 1 && region != nil ? selectedRegion : nil
    }

    private func candidateLayout() throws -> LayoutNode {
        if kind.indexOfSelectedItem == 2, let legacy { return legacy }
        guard let r = Int(rows.stringValue), let c = Int(columns.stringValue), (1...RegionLayout.maximumDimension).contains(r), (1...RegionLayout.maximumDimension).contains(c) else { throw inputError("Rows and columns must be integers from 1 to \(RegionLayout.maximumDimension).") }
        if kind.indexOfSelectedItem == 0 {
            let layout = LayoutNode.grid(rows: r, columns: c)
            if let error = layout.validationError { throw inputError(error) }
            return layout
        }
        var candidate = custom; candidate.rows = r; candidate.columns = c
        if candidate.regions.indices.contains(selectedRegion) {
            let numbers = coordinates.compactMap { Int($0.stringValue) }
            guard numbers.count == 4 else { throw inputError("Region positions and sizes must be whole grid cells.") }
            candidate.regions[selectedRegion] = LayoutRegion(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
        }
        if let error = candidate.validationError { throw inputError(error) }
        return .regions(candidate)
    }

    @discardableResult private func updatePreview() -> Bool {
        guard !loading else { return true }
        do {
            let layout = try candidateLayout()
            if case let .regions(candidate) = layout { custom = candidate }
            preview.layout = layout; preview.selectedRegion = kind.indexOfSelectedItem == 1 ? selectedRegion : nil
            preview.setAccessibilityValue("\(layout.capacity) regions")
            message.stringValue = ""; saveButton.isEnabled = true; return true
        } catch {
            message.textColor = .systemRed; message.stringValue = error.localizedDescription
            saveButton.isEnabled = false; return false
        }
    }
    func controlTextDidChange(_ notification: Notification) { updatePreview() }
    @objc private func regionChanged() { selectRegion(regionChooser.indexOfSelectedItem) }
    private func selectRegion(_ index: Int) {
        window?.makeFirstResponder(nil)
        guard updatePreview(), custom.regions.indices.contains(index) else { regionChooser.selectItem(at: selectedRegion); return }
        selectedRegion = index; regionChooser.selectItem(at: index); loadCoordinates()
    }

    @objc private func addRegion() {
        window?.makeFirstResponder(nil)
        if !custom.regions.isEmpty && !updatePreview() { return }
        guard let r = Int(rows.stringValue), let c = Int(columns.stringValue), (1...RegionLayout.maximumDimension).contains(r), (1...RegionLayout.maximumDimension).contains(c) else { return }
        let xs = Set([0] + custom.regions.map { $0.x + $0.width }).filter { $0 < c }.sorted()
        let ys = Set([0] + custom.regions.map { $0.y + $0.height }).filter { $0 < r }.sorted()
        for y in ys { for x in xs {
            let candidate = RegionLayout(columns: c, rows: r, regions: custom.regions + [LayoutRegion(x: x, y: y, width: 1, height: 1)])
            if candidate.validationError == nil {
                custom = candidate; selectedRegion = custom.regions.count - 1; loadRegionChooser(); updatePreview(); return
            }
        } }
        message.textColor = .secondaryLabelColor; message.stringValue = "No empty space remains. Resize or remove a region first."
    }
    @objc private func removeRegion() {
        guard custom.regions.indices.contains(selectedRegion) else { return }
        custom.regions.remove(at: selectedRegion); loadRegionChooser()
        if custom.regions.isEmpty { preview.layout = .regions(custom) }
        updatePreview()
    }

    @objc private func savePreset() { save(copy: false) }
    @objc private func saveCopy() { save(copy: true) }
    private func save(copy: Bool) {
        window?.makeFirstResponder(nil)
        do {
            let layout = try candidateLayout()
            var name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                if case let .grid(r, c) = layout { name = "\(r) × \(c)" } else { name = "Custom Layout" }
            }
            if copy && presetID != nil { name += " Copy" }
            let id = copy ? UUID().uuidString : (presetID ?? UUID().uuidString)
            let preset = LayoutPreset(id: id, name: name, layout: layout)
            var updated = store.configuration.presets
            if let index = updated.firstIndex(where: { $0.id == id }) { updated[index] = preset } else { updated.append(preset) }
            try store.save(presets: updated); reloadChooser(select: id)
            message.textColor = .secondaryLabelColor; message.stringValue = "Saved. Choose this layout from Arrange Windows to apply it."
        } catch { message.textColor = .systemRed; message.stringValue = error.localizedDescription }
    }
    @objc private func deletePreset() {
        guard let id = presetID, store.configuration.presets.count > 1 else { return }
        do {
            let updated = store.configuration.presets.filter { $0.id != id }
            try store.save(presets: updated); reloadChooser(select: updated.first?.id)
            message.textColor = .secondaryLabelColor; message.stringValue = "Layout deleted."
        } catch { message.textColor = .systemRed; message.stringValue = error.localizedDescription }
    }
    private func inputError(_ message: String) -> NSError { NSError(domain: "Tile", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    @objc private func openPermissions() { manager.requestPermission() }
    @objc private func showArrangeMenu(_ sender: NSButton) { onArrangeMenu(sender) }
    private func refreshPermission() {
        permission.stringValue = manager.isTrusted ? "Accessibility enabled · Current desktop only" : "Accessibility permission is required to arrange windows."
        permissionButton.isHidden = manager.isTrusted
    }
    func windowDidBecomeKey(_ notification: Notification) { refreshPermission() }
    func windowWillClose(_ notification: Notification) { onClose() }
}
