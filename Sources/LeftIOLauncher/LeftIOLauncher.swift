import AppKit
import Carbon
import Foundation

@main
@MainActor
final class LeftIOLauncher: NSObject, NSApplicationDelegate {
    private let systemInstallURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    private let userInstallURL = URL(fileURLWithPath: ("~/Applications" as NSString).expandingTildeInPath, isDirectory: true)
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
        guard isInstalledInApplicationsFolder() else {
            return (
                "把 LeftIO 拖到 Applications",
                "这个 app 本身就是输入法容器。请把 LeftIO.app 拖到 DMG 里的 Applications 快捷方式，不需要再打开别的安装器。"
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
                "app 已复制到 Applications，但系统还没把输入法注册出来。请先注销后重新登录，再去“系统设置 > 键盘 > 文本输入”里检查。"
            )
        }
    }

    private func isInstalledInApplicationsFolder() -> Bool {
        let bundleURL = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let parentDirectory = bundleURL.deletingLastPathComponent().path
        return parentDirectory == systemInstallURL.path || parentDirectory == userInstallURL.path
    }

    private func prepareInstalledInputSource() -> ActivationResult {
        guard let currentInputMode = currentSourceID(),
              currentInputMode == inputModeIdentifier as String else {
            return enableInputSource()
        }

        return .alreadySelected
    }

    private func enableInputSource() -> ActivationResult {
        guard let keyboardInputMethod = firstMatchingInputSource(
            property: kTISPropertyBundleID,
            value: bundleIdentifier,
            includeAllInstalled: true
        ) else {
            return .notRegistered
        }

        _ = TISEnableInputSource(keyboardInputMethod)

        let inputMode = firstMatchingInputSource(
            property: kTISPropertyInputSourceID,
            value: inputModeIdentifier,
            includeAllInstalled: true
        ) ?? firstMatchingInputSource(
            property: kTISPropertyInputModeID,
            value: inputModeIdentifier,
            includeAllInstalled: true
        )

        guard let inputMode else {
            return .registeredButModeMissing
        }

        _ = TISEnableInputSource(inputMode)
        return .enabled
    }

    private func currentSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        return stringProperty(kTISPropertyInputSourceID, for: source)
    }

    private func firstMatchingInputSource(
        property: CFString?,
        value: CFTypeRef,
        includeAllInstalled: Bool
    ) -> TISInputSource? {
        guard let property else {
            return nil
        }

        let filter = [property as String: value] as CFDictionary
        guard let unmanagedList = TISCreateInputSourceList(filter, includeAllInstalled) else {
            return nil
        }

        let list = unmanagedList.takeRetainedValue() as [AnyObject]
        return list.first.flatMap { unsafeBitCast($0, to: TISInputSource?.self) }
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
}

private enum ActivationResult {
    case enabled
    case alreadySelected
    case registeredButModeMissing
    case notRegistered
}
