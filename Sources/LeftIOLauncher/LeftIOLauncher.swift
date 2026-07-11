import AppKit
import Carbon
import Foundation

@main
@MainActor
final class LeftIOLauncher: NSObject, NSApplicationDelegate {
    private let systemInputMethodsURL = URL(fileURLWithPath: "/Library/Input Methods", isDirectory: true)
    private let userInputMethodsURL = URL(fileURLWithPath: ("~/Library/Input Methods" as NSString).expandingTildeInPath, isDirectory: true)
    private let bundleIdentifier = "io.github.cstcat.inputmethod.leftio" as CFString
    private let inputModeIdentifier = "io.github.cstcat.inputmethod.leftio.onehandt9" as CFString

    static func main() {
        let app = NSApplication.shared
        let delegate = LeftIOLauncher()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)

        let (title, message) = launchMessage()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()

        NSApp.terminate(nil)
    }

    private func launchMessage() -> (String, String) {
        guard isInstalledInInputMethodsFolder() else {
            return (
                "打开 LeftIO.app 安装",
                "请从 DMG 打开 LeftIO.app 或 Install LeftIO.command。LeftIO 会复制到 ~/Library/Input Methods，不需要拖到 Applications。"
            )
        }

        switch prepareInstalledInputSource() {
        case .enabled:
            return (
                "LeftIO 已启用",
                "系统已经识别并启用 LeftIO。请到“系统设置 > 键盘 > 文本输入”手动添加 LeftIO 单手九宫格；如果列表没有刷新，请注销后重新登录。"
            )
        case .alreadySelected:
            return (
                "LeftIO 已就绪",
                "LeftIO 已经在当前输入法列表里了，可以直接使用。"
            )
        case .registeredButModeMissing:
            return (
                "LeftIO 已安装",
                "系统已经识别到 LeftIO app，但还没有枚举到 LeftIO 单手九宫格输入模式。请注销后重新登录，再到“系统设置 > 键盘 > 文本输入”手动添加。"
            )
        case .notRegistered:
            return (
                "LeftIO 已安装",
                "app 已复制到 Input Methods，但系统还没把输入法注册出来。请先注销后重新登录，再去“系统设置 > 键盘 > 文本输入”里检查。"
            )
        case .duplicateSources:
            return (
                "LeftIO 来源重复",
                "系统检测到多个 LeftIO 父来源或输入模式。请运行 make repair-input-method-sources 后再检查。"
            )
        case .enableFailed:
            return (
                "LeftIO 启用失败",
                "TIS 未能启用 LeftIO 父来源和输入模式，或该模式当前不可选。请重新安装并运行 make verify-input-method。"
            )
        }
    }

    private func isInstalledInInputMethodsFolder() -> Bool {
        let bundleURL = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let parentDirectory = bundleURL.deletingLastPathComponent().path
        return parentDirectory == systemInputMethodsURL.path || parentDirectory == userInputMethodsURL.path
    }

    private func prepareInstalledInputSource() -> ActivationResult {
        let result = enableInputSource()
        guard case .enabled = result else {
            return result
        }

        return currentSourceID() == inputModeIdentifier as String
            ? .alreadySelected
            : .enabled
    }

    private func enableInputSource() -> ActivationResult {
        let bundleSources = matchingInputSources(
            property: kTISPropertyBundleID,
            value: bundleIdentifier,
            includeAllInstalled: true
        )
        let parentSources = bundleSources.filter { source in
            stringProperty(kTISPropertyInputSourceID, for: source) == bundleIdentifier as String
        }
        guard !parentSources.isEmpty else {
            return .notRegistered
        }

        let allSources = matchingInputSources(
            property: nil,
            value: kCFNull,
            includeAllInstalled: true
        )
        let inputModes = allSources.filter { source in
            stringProperty(kTISPropertyInputSourceID, for: source) == inputModeIdentifier as String
                || stringProperty(kTISPropertyInputModeID, for: source) == inputModeIdentifier as String
        }
        guard !inputModes.isEmpty else {
            return .registeredButModeMissing
        }
        guard parentSources.count == 1, inputModes.count == 1 else {
            return .duplicateSources
        }

        let parent = parentSources[0]
        let inputMode = inputModes[0]
        guard TISEnableInputSource(parent) == noErr,
              TISEnableInputSource(inputMode) == noErr else {
            return .enableFailed
        }
        drainRunLoop(for: 1.5)
        guard
              boolProperty(kTISPropertyInputSourceIsEnabled, for: parent) == true,
              boolProperty(kTISPropertyInputSourceIsEnabled, for: inputMode) == true,
              boolProperty(kTISPropertyInputSourceIsSelectCapable, for: inputMode) == true else {
            return .enableFailed
        }
        return .enabled
    }

    private func currentSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        return stringProperty(kTISPropertyInputSourceID, for: source)
    }

    private func drainRunLoop(for duration: TimeInterval) {
        let deadline = Date().addingTimeInterval(duration)
        while deadline.timeIntervalSinceNow > 0 {
            let remaining = max(0, min(0.2, deadline.timeIntervalSinceNow))
            CFRunLoopRunInMode(.defaultMode, remaining, false)
        }
    }

    private func matchingInputSources(
        property: CFString?,
        value: CFTypeRef,
        includeAllInstalled: Bool
    ) -> [TISInputSource] {
        let filter = property.map { [$0 as String: value] as CFDictionary }
        guard let unmanagedList = TISCreateInputSourceList(filter, includeAllInstalled) else {
            return []
        }

        let list = unmanagedList.takeRetainedValue() as [AnyObject]
        return list.map { unsafeDowncast($0, to: TISInputSource.self) }
    }

    private func stringProperty(_ property: CFString?, for source: TISInputSource) -> String? {
        guard let property,
              let unmanagedValue = TISGetInputSourceProperty(source, property) else {
            return nil
        }

        let value = unsafeBitCast(unmanagedValue, to: CFTypeRef.self)
        guard CFGetTypeID(value) == CFStringGetTypeID() else {
            return nil
        }

        return value as? String
    }

    private func boolProperty(_ property: CFString?, for source: TISInputSource) -> Bool? {
        guard let property,
              let rawValue = TISGetInputSourceProperty(source, property) else {
            return nil
        }
        let value = unsafeBitCast(rawValue, to: CFTypeRef.self)
        guard CFGetTypeID(value) == CFBooleanGetTypeID() else {
            return nil
        }
        return CFBooleanGetValue(unsafeDowncast(value, to: CFBoolean.self))
    }
}

private enum ActivationResult {
    case enabled
    case alreadySelected
    case registeredButModeMissing
    case notRegistered
    case duplicateSources
    case enableFailed
}
