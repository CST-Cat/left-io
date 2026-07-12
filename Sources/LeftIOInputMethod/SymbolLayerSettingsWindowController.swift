import AppKit
import Foundation
import OneHand

@MainActor
enum LeftIOSymbolSettingsWindow {
    static let shared = SymbolLayerSettingsWindowController()
}

struct LeftIOSymbolSettingsStore {
    static let preferenceKey = "SymbolLayerTextOverrides.v1"
    static let qGesturePreferenceKey = "QGestureLayerOverrides.v1"
    private static let tapKey = "tap"
    private static let longPressKey = "longPress"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func effectiveConfiguration(base: OneHandConfiguration) -> OneHandConfiguration {
        var configuration = customization().applying(to: base)
        let gestureOverrides = defaults.dictionary(forKey: Self.qGesturePreferenceKey) ?? [:]
        if let rawValue = gestureOverrides[Self.tapKey] as? String,
           let layer = OneHandInputLayer(rawValue: rawValue) {
            configuration.qTapLayer = layer
        }
        if let rawValue = gestureOverrides[Self.longPressKey] as? String,
           let layer = OneHandInputLayer(rawValue: rawValue) {
            configuration.qLongPressLayer = layer
        }
        return configuration
    }

    @discardableResult
    func save(
        effectiveTextByKey: [OneHandKey: String],
        qTapLayer: OneHandInputLayer,
        qLongPressLayer: OneHandInputLayer,
        base: OneHandConfiguration
    ) -> OneHandConfiguration {
        let customization = OneHandSymbolCustomization.overrides(
            effectiveTextByKey: effectiveTextByKey,
            comparedTo: base
        )
        if customization.textByKey.isEmpty {
            defaults.removeObject(forKey: Self.preferenceKey)
        } else {
            defaults.set(customization.propertyList, forKey: Self.preferenceKey)
        }

        var gestureOverrides: [String: String] = [:]
        if qTapLayer != base.qTapLayer {
            gestureOverrides[Self.tapKey] = qTapLayer.rawValue
        }
        if qLongPressLayer != base.qLongPressLayer {
            gestureOverrides[Self.longPressKey] = qLongPressLayer.rawValue
        }
        if gestureOverrides.isEmpty {
            defaults.removeObject(forKey: Self.qGesturePreferenceKey)
        } else {
            defaults.set(gestureOverrides, forKey: Self.qGesturePreferenceKey)
        }

        var configuration = customization.applying(to: base)
        configuration.qTapLayer = qTapLayer
        configuration.qLongPressLayer = qLongPressLayer
        return configuration
    }

    private func customization() -> OneHandSymbolCustomization {
        guard let rawValues = defaults.dictionary(forKey: Self.preferenceKey) else {
            return OneHandSymbolCustomization()
        }
        let strings = rawValues.compactMapValues { value in
            value as? String
        }
        return OneHandSymbolCustomization(propertyList: strings)
    }
}

@MainActor
final class SymbolLayerSettingsWindowController: NSWindowController, NSWindowDelegate {
    private let store: LeftIOSymbolSettingsStore
    private var fields: [OneHandKey: NSTextField] = [:]
    private let qTapLayerPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let qLongPressLayerPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private var bundledConfiguration = OneHandConfiguration()
    private var onSave: ((OneHandConfiguration) -> Void)?

    init(store: LeftIOSymbolSettingsStore = LeftIOSymbolSettingsStore()) {
        self.store = store
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 590),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LeftIO 设置"
        window.isReleasedWhenClosed = false
        window.animationBehavior = .documentWindow
        super.init(window: window)
        window.delegate = self
        window.contentView = makeContentView()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show(
        bundledConfiguration: OneHandConfiguration,
        effectiveConfiguration: OneHandConfiguration,
        onSave: @escaping (OneHandConfiguration) -> Void
    ) {
        self.bundledConfiguration = bundledConfiguration
        self.onSave = onSave
        populateFields(from: effectiveConfiguration)
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        fields[.w]?.becomeFirstResponder()
    }

    func windowWillClose(_ notification: Notification) {
        onSave = nil
    }

    @objc
    private func saveSettings(_ sender: Any?) {
        var values: [OneHandKey: String] = [:]
        for key in OneHandKey.symbolLayerSlots {
            guard let text = fields[key]?.stringValue,
                  !text.isEmpty else {
                presentValidationError("按键 \(key.rawValue) 的符号不能为空。")
                return
            }
            guard OneHandSymbolCustomization.isValidSymbolText(text) else {
                presentValidationError("按键 \(key.rawValue) 的符号不能包含控制字符或换行。")
                return
            }
            values[key] = text
        }

        let configuration = store.save(
            effectiveTextByKey: values,
            qTapLayer: selectedLayer(in: qTapLayerPopUp),
            qLongPressLayer: selectedLayer(in: qLongPressLayerPopUp),
            base: bundledConfiguration
        )
        onSave?(configuration)
        window?.close()
    }

    @objc
    private func restoreBundledDefaults(_ sender: Any?) {
        populateFields(from: bundledConfiguration)
    }

    @objc
    private func cancel(_ sender: Any?) {
        window?.close()
    }

    private func populateFields(from configuration: OneHandConfiguration) {
        let fallback = OneHandConfiguration().symbolLayerTextByKey
        let configured = configuration.symbolLayerTextByKey
        for key in OneHandKey.symbolLayerSlots {
            fields[key]?.stringValue = configured[key] ?? fallback[key] ?? ""
        }
        select(configuration.qTapLayer, in: qTapLayerPopUp)
        select(configuration.qLongPressLayer, in: qLongPressLayerPopUp)
    }

    private func presentValidationError(_ message: String) {
        guard let window else {
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "无法保存输入层设置"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.beginSheetModal(for: window)
    }

    private func makeContentView() -> NSView {
        let contentView = NSView()

        let titleLabel = NSTextField(labelWithString: "自定义输入层")
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)

        let descriptionLabel = NSTextField(wrappingLabelWithString: "短按 Q（无组字或候选时）和长按 Q 可以分别进入符号层或数字层。默认短按进入符号层、长按进入数字层；保存后立即生效。")
        descriptionLabel.font = .systemFont(ofSize: 13)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.maximumNumberOfLines = 0

        let qGestureSettings = makeQGestureSettings()

        let gridStack = NSStackView()
        gridStack.orientation = .vertical
        gridStack.alignment = .centerX
        gridStack.spacing = 10
        gridStack.addArrangedSubview(makeTopRow())
        gridStack.addArrangedSubview(makeEditorRow(keys: [.a, .s, .d]))
        gridStack.addArrangedSubview(makeEditorRow(keys: [.z, .x, .c]))

        let hintLabel = NSTextField(labelWithString: "可以输入一个或多个字符，例如「，」「……」「→」。")
        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.textColor = .tertiaryLabelColor

        let restoreButton = NSButton(
            title: "恢复默认",
            target: self,
            action: #selector(restoreBundledDefaults(_:))
        )
        restoreButton.bezelStyle = .rounded

        let cancelButton = NSButton(
            title: "取消",
            target: self,
            action: #selector(cancel(_:))
        )
        cancelButton.bezelStyle = .rounded

        let saveButton = NSButton(
            title: "保存",
            target: self,
            action: #selector(saveSettings(_:))
        )
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        let flexibleSpace = NSView()
        flexibleSpace.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttonRow = NSStackView(views: [restoreButton, flexibleSpace, cancelButton, saveButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8

        let rootStack = NSStackView(views: [titleLabel, descriptionLabel, qGestureSettings, gridStack, hintLabel, buttonRow])
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 14
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.setCustomSpacing(8, after: titleLabel)
        rootStack.setCustomSpacing(14, after: descriptionLabel)
        rootStack.setCustomSpacing(18, after: qGestureSettings)
        rootStack.setCustomSpacing(18, after: hintLabel)
        contentView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 30),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -30),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 26),
            rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -22),
            descriptionLabel.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            qGestureSettings.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            gridStack.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            buttonRow.widthAnchor.constraint(equalTo: rootStack.widthAnchor)
        ])

        return contentView
    }

    private func makeQGestureSettings() -> NSView {
        configureLayerPopUp(qTapLayerPopUp)
        configureLayerPopUp(qLongPressLayerPopUp)

        let titleLabel = NSTextField(labelWithString: "Q 键触发")
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        let tapLabel = NSTextField(labelWithString: "单击 Q")
        let longPressLabel = NSTextField(labelWithString: "长按 Q")
        tapLabel.font = .systemFont(ofSize: 13)
        longPressLabel.font = .systemFont(ofSize: 13)

        let tapRow = NSStackView(views: [tapLabel, qTapLayerPopUp])
        tapRow.orientation = .horizontal
        tapRow.alignment = .centerY
        tapRow.distribution = .fillEqually
        tapRow.spacing = 12

        let longPressRow = NSStackView(views: [longPressLabel, qLongPressLayerPopUp])
        longPressRow.orientation = .horizontal
        longPressRow.alignment = .centerY
        longPressRow.distribution = .fillEqually
        longPressRow.spacing = 12

        let stack = NSStackView(views: [titleLabel, tapRow, longPressRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            tapRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            longPressRow.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        return container
    }

    private func configureLayerPopUp(_ popUp: NSPopUpButton) {
        popUp.removeAllItems()
        for layer in OneHandInputLayer.allCases {
            popUp.addItem(withTitle: title(for: layer))
            popUp.lastItem?.representedObject = layer.rawValue
        }
    }

    private func select(_ layer: OneHandInputLayer, in popUp: NSPopUpButton) {
        guard let index = popUp.itemArray.firstIndex(where: {
            ($0.representedObject as? String) == layer.rawValue
        }) else {
            return
        }
        popUp.selectItem(at: index)
    }

    private func selectedLayer(in popUp: NSPopUpButton) -> OneHandInputLayer {
        guard let rawValue = popUp.selectedItem?.representedObject as? String,
              let layer = OneHandInputLayer(rawValue: rawValue) else {
            return .symbol
        }
        return layer
    }

    private func title(for layer: OneHandInputLayer) -> String {
        switch layer {
        case .symbol:
            "符号层"
        case .numeric:
            "数字层"
        }
    }

    private func makeTopRow() -> NSStackView {
        let triggerCell = SymbolLayerSettingCellView.triggerCell()
        let row = NSStackView(views: [triggerCell, makeEditorCell(key: .w), makeEditorCell(key: .e)])
        configureEditorRow(row)
        return row
    }

    private func makeEditorRow(keys: [OneHandKey]) -> NSStackView {
        let row = NSStackView(views: keys.map(makeEditorCell(key:)))
        configureEditorRow(row)
        return row
    }

    private func configureEditorRow(_ row: NSStackView) {
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
    }

    private func makeEditorCell(key: OneHandKey) -> NSView {
        let cell = SymbolLayerSettingCellView(key: key)
        fields[key] = cell.textField
        return cell
    }
}

@MainActor
private final class SymbolLayerSettingCellView: NSView {
    let textField: NSTextField

    init(key: OneHandKey) {
        textField = NSTextField(string: "")
        super.init(frame: .zero)
        configureCard()

        let keyLabel = NSTextField(labelWithString: key.rawValue)
        keyLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        keyLabel.textColor = .secondaryLabelColor

        textField.alignment = .center
        textField.font = .systemFont(ofSize: 21, weight: .medium)
        textField.placeholderString = "符号"
        textField.focusRingType = .default

        let stack = NSStackView(views: [keyLabel, textField])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 130),
            heightAnchor.constraint(equalToConstant: 74),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textField.widthAnchor.constraint(equalToConstant: 96)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    static func triggerCell() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 10
        view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.32).cgColor

        let keyLabel = NSTextField(labelWithString: "Q")
        keyLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        keyLabel.textColor = .controlAccentColor
        let detailLabel = NSTextField(labelWithString: "层控制键")
        detailLabel.font = .systemFont(ofSize: 14, weight: .medium)
        detailLabel.textColor = .controlAccentColor

        let stack = NSStackView(views: [keyLabel, detailLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 130),
            view.heightAnchor.constraint(equalToConstant: 74),
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        return view
    }

    private func configureCard() {
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.82).cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
    }
}
