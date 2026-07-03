import AppKit
import Foundation

@main
@MainActor
final class LeftIOLauncher: NSObject, NSApplicationDelegate {
    private let applicationsDirectoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    private let installedInputMethodURL = URL(fileURLWithPath: "/Library/Input Methods/LeftIO.app")
    private let userInstalledInputMethodURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Input Methods/LeftIO.app")

    static func main() {
        let app = NSApplication.shared
        let delegate = LeftIOLauncher()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)

        guard isRunningFromApplicationsFolder() else {
            openApplicationsFolder()
            showAlert(
                title: "请先拖到 Applications",
                message: "请先把 LeftIO.app 从 DMG 拖到 Applications 文件夹，再从 /Applications 启动它完成安装。这样后续更新也只需要重新打开同一个 app。"
            )
            NSApp.terminate(nil)
            return
        }

        do {
            try installEmbeddedInputMethod()
            openInstalledInputMethodIfPresent()
            openKeyboardSettings()
            showAlert(
                title: "LeftIO 已安装",
                message: "已将输入法安装到 /Library/Input Methods，并打开键盘设置。请在“文本输入 / 输入法”里启用 LeftIO。之后重新打开 /Applications/LeftIO.app 会执行更新安装。"
            )
        } catch {
            showAlert(
                title: "LeftIO 安装失败",
                message: error.localizedDescription
            )
        }

        NSApp.terminate(nil)
    }

    private func isRunningFromApplicationsFolder() -> Bool {
        let bundlePath = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let systemApplicationsPath = applicationsDirectoryURL.path + "/"
        let userApplicationsPath = ("~/Applications" as NSString).expandingTildeInPath + "/"
        return bundlePath.hasPrefix(systemApplicationsPath) || bundlePath.hasPrefix(userApplicationsPath)
    }

    private func installEmbeddedInputMethod() throws {
        let payloadURL = try embeddedInputMethodURL()
        try installPayloadWithAdministratorPrivileges(payloadURL)
        try refreshInputMethodRegistration()
    }

    private func embeddedInputMethodURL() throws -> URL {
        guard let resourceURL = Bundle.main.resourceURL else {
            throw InstallerError.missingBundleResource
        }

        let payloadURL = resourceURL
            .appendingPathComponent("InputMethod", isDirectory: true)
            .appendingPathComponent("LeftIO.app", isDirectory: true)

        guard FileManager.default.fileExists(atPath: payloadURL.path) else {
            throw InstallerError.missingPayload(payloadURL.path)
        }

        return payloadURL
    }

    private func installPayloadWithAdministratorPrivileges(_ payloadURL: URL) throws {
        let payloadPath = shellQuoted(payloadURL.path)
        let userInstalledPath = shellQuoted(userInstalledInputMethodURL.path)
        let command = [
            "pkill -x LeftIOInputMethod 2>/dev/null || true",
            "rm -rf \(userInstalledPath)",
            "rm -rf '/Library/Input Methods/LeftIO.app'",
            "ditto \(payloadPath) '/Library/Input Methods/LeftIO.app'",
            "chown -R root:wheel '/Library/Input Methods/LeftIO.app'",
            "xattr -dr com.apple.quarantine '/Library/Input Methods/LeftIO.app' 2>/dev/null || true"
        ].joined(separator: "; ")

        let appleScript = "do shell script \(appleScriptQuoted(command)) with administrator privileges"
        try runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: ["-e", appleScript]
        )
    }

    private func refreshInputMethodRegistration() throws {
        try? runProcess(executableURL: URL(fileURLWithPath: "/usr/bin/pkill"), arguments: ["-x", "TextInputMenuAgent"])
        try? runProcess(executableURL: URL(fileURLWithPath: "/usr/bin/pkill"), arguments: ["-x", "TextInputSwitcher"])
        try? runProcess(executableURL: URL(fileURLWithPath: "/usr/bin/pkill"), arguments: ["-x", "imklaunchagent"])
        try? runProcess(executableURL: URL(fileURLWithPath: "/usr/bin/killall"), arguments: ["cfprefsd"])

        let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        try? runProcess(executableURL: URL(fileURLWithPath: lsregister), arguments: ["-u", userInstalledInputMethodURL.path])
        try? runProcess(executableURL: URL(fileURLWithPath: lsregister), arguments: ["-u", installedInputMethodURL.path])
        try? runProcess(executableURL: URL(fileURLWithPath: lsregister), arguments: ["-f", installedInputMethodURL.path])
    }

    private func openInstalledInputMethodIfPresent() {
        guard FileManager.default.fileExists(atPath: installedInputMethodURL.path) else {
            return
        }

        NSWorkspace.shared.open(installedInputMethodURL)
    }

    private func openApplicationsFolder() {
        NSWorkspace.shared.open(applicationsDirectoryURL)
    }

    private func openKeyboardSettings() {
        guard let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") else {
            return
        }

        NSWorkspace.shared.open(settingsURL)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func runProcess(executableURL: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardError = outputPipe
        process.standardOutput = outputPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw InstallerError.commandFailed(output?.isEmpty == false ? output! : executableURL.path)
        }
    }

    private func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func appleScriptQuoted(_ string: String) -> String {
        "\"" + string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

private enum InstallerError: LocalizedError {
    case missingBundleResource
    case missingPayload(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingBundleResource:
            return "找不到应用资源目录。"
        case let .missingPayload(path):
            return "找不到内置输入法载荷：\(path)"
        case let .commandFailed(output):
            return "安装命令执行失败：\(output)"
        }
    }
}
