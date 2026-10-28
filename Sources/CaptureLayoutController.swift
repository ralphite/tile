import AppKit

@MainActor
final class CaptureLayoutController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    private let store: LayoutStore
    private let manager: WindowManager
    private let onSave: (LayoutPreset) -> Void
    private let onClose: () -> Void
    private let name = NSTextField(string: "Current Windows")
    private let screenChooser = NSPopUpButton(frame: .zero, pullsDown: false)
    private let list = NSStackView()
    private let preview = LayoutPreview()
    private let message = NSTextField(wrappingLabelWithString: "")
    private let saveButton = NSButton(title: "Save as New Layout", target: nil, action: nil)
    private var screens: [NSScreen] = []
    private var candidates: [WindowManager.CaptureWindow] = []
    private var selected: Set<CGWindowID> = []
    private var area = CGRect.zero
    private var validLayout: RegionLayout?

    init(store: LayoutStore, manager: WindowManager, onSave: @escaping (LayoutPreset) -> Void, onClose: @escaping () -> Void) {
        self.store = store; self.manager = manager; self.onSave = onSave; self.onClose = onClose
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 640),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Tile · Save Current Windows"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self; window.center()
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20)
        ])
        name.setAccessibilityLabel("New layout name"); name.delegate = self
        let nameRow = NSStackView(views: [NSTextField(labelWithString: "Name"), name]); nameRow.spacing = 12
        root.addArrangedSubview(nameRow)
        screenChooser.target = self; screenChooser.action = #selector(screenChanged)
        screenChooser.setAccessibilityLabel("Display to capture")
        let screenRow = NSStackView(views: [NSTextField(labelWithString: "Display"), screenChooser,
            NSButton(title: "Refresh Windows", target: self, action: #selector(refresh))])
        screenRow.spacing = 12; root.addArrangedSubview(screenRow)
        let hint = NSTextField(wrappingLabelWithString: "Select windows to save as regions. Empty space is allowed; overlap is not. Refresh after moving or resizing windows. Layouts are not bound to apps.")
        hint.font = .systemFont(ofSize: 12); hint.textColor = .secondaryLabelColor
        root.addArrangedSubview(hint)
        root.addArrangedSubview(NSStackView(views: [
            NSButton(title: "Select All", target: self, action: #selector(selectAllWindows)),
            NSButton(title: "Deselect All", target: self, action: #selector(deselectAllWindows))]))
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        list.orientation = .vertical; list.alignment = .leading; list.spacing = 8
        list.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        list.translatesAutoresizingMaskIntoConstraints = false; scroll.documentView = list
        list.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor).isActive = true
        list.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor).isActive = true
        list.topAnchor.constraint(equalTo: scroll.contentView.topAnchor).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 170).isActive = true
        root.addArrangedSubview(scroll)
        preview.heightAnchor.constraint(equalToConstant: 200).isActive = true
        preview.setAccessibilityElement(true); preview.setAccessibilityRole(.image)
        preview.setAccessibilityLabel("Selected window regions")
        root.addArrangedSubview(preview)
        message.font = .systemFont(ofSize: 12)
        message.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        root.addArrangedSubview(message)
        saveButton.target = self; saveButton.action = #selector(save); saveButton.keyEquivalent = "\r"
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [spacer, NSButton(title: "Cancel", target: self, action: #selector(cancel)), saveButton])
        root.addArrangedSubview(buttons)
        for view in [nameRow, hint, scroll, preview, message, buttons] {
            view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }
        screens = NSScreen.screens
        screenChooser.addItems(withTitles: screens.enumerated().map { "\($0.offset + 1) · \($0.element.localizedName)" })
        let underPointer = screens.firstIndex { $0.frame.contains(NSEvent.mouseLocation) } ?? 0
        screenChooser.selectItem(at: underPointer)
        screenChanged()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func screenChanged() { loadWindows(preservingSelection: false) }
    @objc private func refresh() { loadWindows(preservingSelection: true) }

    private func loadWindows(preservingSelection: Bool) {
        let index = screenChooser.indexOfSelectedItem
        guard screens.indices.contains(index) else { return }
        let screen = screens[index]
        let oldIDs = Set(candidates.map(\.id))
        area = manager.usableFrame(of: screen)
        candidates = manager.captureWindows(on: screen).sorted {
            $0.frame.minY == $1.frame.minY ? $0.frame.minX < $1.frame.minX : $0.frame.minY < $1.frame.minY
        }
        let newIDs = Set(candidates.map(\.id))
        selected = preservingSelection ? selected.intersection(newIDs).union(newIDs.subtracting(oldIDs)) : newIDs
        rebuildList(); validate()
    }

    private func rebuildList() {
        for view in list.arrangedSubviews { list.removeArrangedSubview(view); view.removeFromSuperview() }
        if candidates.isEmpty { list.addArrangedSubview(NSTextField(labelWithString: "No eligible windows on this display.")) }
        for (index, candidate) in candidates.enumerated() {
            let button = NSButton(checkboxWithTitle: candidate.title, target: self, action: #selector(selectionChanged(_:)))
            button.tag = index; button.state = selected.contains(candidate.id) ? .on : .off
            button.lineBreakMode = .byTruncatingTail; button.toolTip = candidate.title
            list.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: list.widthAnchor, constant: -20).isActive = true
        }
    }

    @objc private func selectionChanged(_ sender: NSButton) {
        guard candidates.indices.contains(sender.tag) else { return }
        let id = candidates[sender.tag].id
        if sender.state == .on { selected.insert(id) } else { selected.remove(id) }
        validate()
    }
    @objc private func selectAllWindows() { selected = Set(candidates.map(\.id)); rebuildList(); validate() }
    @objc private func deselectAllWindows() { selected.removeAll(); rebuildList(); validate() }
    func controlTextDidChange(_ notification: Notification) { validate() }

    private func validate() {
        let frames = candidates.filter { selected.contains($0.id) }.map(\.frame)
        preview.screenSize = area.size
        preview.normalizedFrames = frames.map {
            CGRect(x: ($0.minX - area.minX) / area.width, y: ($0.minY - area.minY) / area.height,
                   width: $0.width / area.width, height: $0.height / area.height)
        }
        preview.setAccessibilityValue("\(frames.count) regions")
        do {
            validLayout = try CapturedLayout.make(frames: frames, in: area)
            guard !name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NSError(domain: "Tile", code: 2, userInfo: [NSLocalizedDescriptionKey: "Enter a name for the new layout."])
            }
            message.textColor = .secondaryLabelColor
            message.stringValue = "Save \(frames.count) regions, numbered top to bottom, then left to right."
            saveButton.isEnabled = true
        } catch {
            validLayout = nil; saveButton.isEnabled = false
            message.textColor = .systemRed; message.stringValue = error.localizedDescription
        }
    }

    @objc private func save() {
        validate()
        guard let layout = validLayout else { return }
        let preset = LayoutPreset(id: UUID().uuidString, name: name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), layout: .regions(layout))
        do {
            try store.save(presets: store.configuration.presets + [preset])
            onSave(preset); close()
        } catch { message.textColor = .systemRed; message.stringValue = error.localizedDescription }
    }
    @objc private func cancel() { close() }
    func windowWillClose(_ notification: Notification) { onClose() }
}
