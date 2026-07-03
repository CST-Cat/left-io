import AppKit
import Foundation

@main
@MainActor
final class LeftIOLauncher: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = LeftIOLauncher()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        openInputMethodIfInstalled()
        openKeyboardSettings()
        showInstalledMessage()
        NSApp.terminate(nil)
    }

    private func openInputMethodIfInstalled() {
        let inputMethodURL = URL(fileURLWithPath: "/Library/Input Methods/LeftIO.app")
        guard FileManager.default.fileExists(atPath: inputMethodURL.path) else {
            return
        }

        NSWorkspace.shared.open(inputMethodURL)
    }

    private func openKeyboardSettings() {
        guard let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") else {
            return
        }

        NSWorkspace.shared.open(settingsURL)
    }

    private func showInstalledMessage() {
        let alert = NSAlert()
        alert.messageText = "LeftIO 已安装"
        alert.informativeText = "已打开键盘设置。请在“文本输入 / 输入法”里添加 LeftIO。真正的输入法宿主安装在 /Library/Input Methods。"
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
