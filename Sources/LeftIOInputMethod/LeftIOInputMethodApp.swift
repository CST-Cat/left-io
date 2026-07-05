import AppKit
import Carbon
import Foundation
import InputMethodKit

@main
@MainActor
final class LeftIOInputMethodApp: NSObject, NSApplicationDelegate {
    private static let registerArgument = "--register-installed-input-source"

    private enum LaunchMode {
        case installAndRegister
        case runInputMethod
    }

    private enum InstallResult {
        case activated
        case registered
        case copiedButNotRegistered
        case failed(String)
    }

    private static let bundleIdentifier = "io.github.cstcat.inputmethod.leftio" as CFString
    private static let inputModeIdentifier = "io.github.cstcat.inputmethod.leftio.onehandt9" as CFString

    private let launchMode: LaunchMode
    private var server: IMKServer?
    private var processActivity: NSObjectProtocol?

    override init() {
        self.launchMode = Self.isRunningFromInstalledInputMethodsLocation() ? .runInputMethod : .installAndRegister
        super.init()
        let bundleURL = Bundle.main.bundleURL
        let resolvedURL = bundleURL.resolvingSymlinksInPath()
        let launchMessage = "init mode=\(String(describing: launchMode)) bundle=\(bundleURL.path) resolved=\(resolvedURL.path) home=\(NSHomeDirectory()) args=\(CommandLine.arguments)"
        Self.writeLifecycleLog(launchMessage)
        NSLog(
            "LeftIO launch: mode=%@ bundle=%@ resolved=%@",
            String(describing: launchMode),
            bundleURL.path,
            resolvedURL.path
        )
    }

    static func main() {
        writeLifecycleLog(
            "main entry pid=\(ProcessInfo.processInfo.processIdentifier) ppid=\(getppid()) uid=\(getuid()) euid=\(geteuid()) home=\(NSHomeDirectory()) args=\(CommandLine.arguments)"
        )
        if CommandLine.arguments.contains(registerArgument) {
            writeLifecycleLog("main dispatch register helper")
            let exitCode: Int32 = completeInstalledRegistration() ? 0 : 1
            writeLifecycleLog("main register helper exitCode=\(exitCode)")
            Foundation.exit(exitCode)
        }

        let app = NSApplication.shared
        let delegate = LeftIOInputMethodApp()
        app.delegate = delegate
        app.setActivationPolicy(delegate.launchMode == .runInputMethod ? .accessory : .regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.writeLifecycleLog("applicationDidFinishLaunching mode=\(String(describing: launchMode))")
        switch launchMode {
        case .runInputMethod:
            Self.writeLifecycleLog("enter runInputMethod")
            startInputMethodServer()
        case .installAndRegister:
            Self.writeLifecycleLog("enter installAndRegister")
            NSApp.activate(ignoringOtherApps: true)
            presentInstallResult(runInstallFlow())
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        writeServerLog("application will terminate")
        Self.writeLifecycleLog("applicationWillTerminate mode=\(String(describing: launchMode))")
        NSLog("LeftIO server: application will terminate")
        if let processActivity {
            ProcessInfo.processInfo.endActivity(processActivity)
            self.processActivity = nil
        }
    }

    private func startInputMethodServer() {
        let bundle = Bundle.main
        let connectionName = bundle.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String
        let startupMessage = "starting input method server bundle=\(bundle.bundleIdentifier ?? "-") connection=\(connectionName ?? "-") home=\(NSHomeDirectory()) args=\(CommandLine.arguments)"
        writeServerLog(startupMessage)
        NSLog("LeftIO server: %@", startupMessage)
        processActivity = ProcessInfo.processInfo.beginActivity(
            options: [.automaticTerminationDisabled, .suddenTerminationDisabled],
            reason: "LeftIO input method server"
        )
        server = IMKServer(
            name: connectionName,
            bundleIdentifier: bundle.bundleIdentifier
        )
        RKeyEventTap.activateProcessWide()
        writeServerLog("IMKServer initialized=\(server != nil)")
        NSLog("LeftIO server: IMKServer initialized=%{public}@", server != nil ? "true" : "false")
    }

    private func runInstallFlow() -> InstallResult {
        let fileManager = FileManager.default
        let sourceURL = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let targetURL = Self.userInstalledBundleURL()

        do {
            try fileManager.createDirectory(
                at: targetURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }

            try fileManager.copyItem(at: sourceURL, to: targetURL)
        } catch {
            return .failed("复制到 ~/Library/Input Methods 失败：\(error.localizedDescription)")
        }

        let registrationScheduled = scheduleInstalledRegistrationHelper(at: targetURL)
        guard registrationScheduled else {
            return .copiedButNotRegistered
        }

        return .registered
    }

    private func presentInstallResult(_ result: InstallResult) {
        let alert = NSAlert()
        alert.addButton(withTitle: "好")

        switch result {
        case .activated:
            alert.messageText = "LeftIO 已就绪"
            alert.informativeText = "LeftIO 已复制到 ~/Library/Input Methods，并且已经向系统注册。请到“系统设置 > 键盘 > 文本输入”手动添加；如果列表没有刷新，请注销后重新登录。"
        case .registered:
            alert.messageText = "LeftIO 已注册"
            alert.informativeText = "LeftIO 已复制到 ~/Library/Input Methods，并且已经向系统注册。请到“系统设置 > 键盘 > 文本输入”手动添加；如果列表没有刷新，请注销后重新登录。"
        case .copiedButNotRegistered:
            alert.messageText = "LeftIO 已复制"
            alert.informativeText = "LeftIO 已复制到 ~/Library/Input Methods，但系统这次没有立刻完成注册。请注销后重新登录，再到“系统设置 > 键盘 > 文本输入”手动添加。"
        case let .failed(message):
            alert.messageText = "LeftIO 安装失败"
            alert.informativeText = message
        }

        alert.runModal()
    }

    private static func isRunningFromInstalledInputMethodsLocation() -> Bool {
        let candidateDirectories = Set([
            Bundle.main.bundleURL.deletingLastPathComponent().path,
            Bundle.main.bundleURL.resolvingSymlinksInPath().deletingLastPathComponent().path,
            Bundle.main.bundleURL.standardizedFileURL.deletingLastPathComponent().path
        ])

        let userInputMethodsPath = ("~/Library/Input Methods" as NSString).expandingTildeInPath
        return candidateDirectories.contains { parentDirectory in
            parentDirectory == "/Library/Input Methods"
                || parentDirectory == "/System/Volumes/Data/Library/Input Methods"
                || parentDirectory == userInputMethodsPath
        }
    }

    private static func userInstalledBundleURL() -> URL {
        URL(fileURLWithPath: ("~/Library/Input Methods" as NSString).expandingTildeInPath, isDirectory: true)
            .appendingPathComponent("LeftIO.app", isDirectory: true)
    }

    private func scheduleInstalledRegistrationHelper(at bundleURL: URL) -> Bool {
        let executableURL = bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("LeftIO")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "sleep 1; exec '\(executableURL.path)' \(Self.registerArgument)"
        ]

        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    private static func completeInstalledRegistration() -> Bool {
        func writeLog(_ message: String) {
            writeRegistrationLog(message)
        }

        writeLog("register helper started: \(Bundle.main.bundleURL.path)")
        writeLog("register helper bundle id: \(Bundle.main.bundleIdentifier ?? "-")")
        writeLog(
            "register helper context pid=\(ProcessInfo.processInfo.processIdentifier) ppid=\(getppid()) uid=\(getuid()) euid=\(geteuid()) home=\(NSHomeDirectory()) args=\(CommandLine.arguments)"
        )
        logInputSourceDiagnostics(stage: "before-register", writeLog)

        let existingBundleSources = inputSources(
            property: kTISPropertyBundleID,
            value: bundleIdentifier,
            includeAllInstalled: true
        )
        let existingModeSource = firstInputSource(
            property: kTISPropertyInputSourceID,
            value: inputModeIdentifier,
            includeAllInstalled: true
        ) ?? firstInputSource(
            property: kTISPropertyInputModeID,
            value: inputModeIdentifier,
            includeAllInstalled: true
        )

        if !existingBundleSources.isEmpty || existingModeSource != nil {
            writeLog("register helper refreshing existing LeftIO source with TISRegisterInputSource")
        }

        let registerStatus = TISRegisterInputSource(Bundle.main.bundleURL as CFURL)
        drainRunLoop(for: 1.5)
        writeLog("register helper register status=\(registerStatus)")
        logInputSourceDiagnostics(stage: "after-register", writeLog)
        guard registerStatus == noErr else {
            writeLog("register helper failed: register status=\(registerStatus)")
            return false
        }

        let inputMethodSources = inputSources(
            property: kTISPropertyBundleID,
            value: bundleIdentifier,
            includeAllInstalled: true
        )

        writeLog("register helper bundle matches=\(inputMethodSources.count)")
        guard !inputMethodSources.isEmpty else {
            writeLog("register helper failed: bundle not found")
            return false
        }

        for source in inputMethodSources {
            let enableStatus = TISEnableInputSource(source)
            writeLog("register helper enable bundle source status=\(enableStatus) \(describeInputSource(source))")
        }

        guard let inputMode = firstInputSource(
            property: kTISPropertyInputSourceID,
            value: inputModeIdentifier,
            includeAllInstalled: true
        ) ?? firstInputSource(
            property: kTISPropertyInputModeID,
            value: inputModeIdentifier,
            includeAllInstalled: true
        ) else {
            writeLog("register helper failed: mode not found")
            return false
        }

        let enableModeStatus = TISEnableInputSource(inputMode)
        drainRunLoop(for: 1.5)
        writeLog("register helper mode enable status=\(enableModeStatus)")
        writeLog("register helper succeeded without selecting current input source")
        logInputSourceDiagnostics(stage: "after-enable", writeLog)
        return true
    }

    private static func firstInputSource(
        property: CFString?,
        value: CFTypeRef,
        includeAllInstalled: Bool
    ) -> TISInputSource? {
        inputSources(
            property: property,
            value: value,
            includeAllInstalled: includeAllInstalled
        ).first
    }

    private static func inputSources(
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

    private func writeServerLog(_ message: String) {
        Self.appendLog(named: "LeftIO.server.log", message: message)
    }

    private static func writeRegistrationLog(_ message: String) {
        appendLog(named: "LeftIO.register.log", message: message)
    }

    private static func writeLifecycleLog(_ message: String) {
        appendLog(named: "LeftIO.launch.log", message: message)
    }

    private static func appendLog(named fileName: String, message: String) {
        let formatter = ISO8601DateFormatter()
        let line = "\(formatter.string(from: Date())) \(message)\n"

        for logURL in logURLs(named: fileName) {
            try? FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if FileManager.default.fileExists(atPath: logURL.path),
               let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(line.utf8))
            } else {
                try? line.write(to: logURL, atomically: true, encoding: .utf8)
            }
        }
    }

    private static func logURLs(named fileName: String) -> [URL] {
        [
            URL(
                fileURLWithPath: ("~/Library/Input Methods" as NSString).expandingTildeInPath,
                isDirectory: true
            ).appendingPathComponent(fileName, isDirectory: false),
            URL(fileURLWithPath: "/Users/Shared", isDirectory: true)
                .appendingPathComponent(fileName, isDirectory: false)
        ]
    }

    private static func drainRunLoop(for duration: TimeInterval) {
        let deadline = Date().addingTimeInterval(duration)
        while deadline.timeIntervalSinceNow > 0 {
            let remaining = max(0, min(0.2, deadline.timeIntervalSinceNow))
            CFRunLoopRunInMode(CFRunLoopMode.defaultMode, remaining, false)
        }
    }

    private static func logInputSourceDiagnostics(
        stage: String,
        _ writeLog: (String) -> Void
    ) {
        let allSources = inputSources(
            property: nil,
            value: kCFNull,
            includeAllInstalled: true
        )
        writeLog("register helper snapshot[\(stage)] all=\(allSources.count)")

        let bundleMatches = inputSources(
            property: kTISPropertyBundleID,
            value: bundleIdentifier,
            includeAllInstalled: true
        )
        writeLog("register helper snapshot[\(stage)] bundleMatches=\(bundleMatches.count)")

        let sourceIDMatches = inputSources(
            property: kTISPropertyInputSourceID,
            value: inputModeIdentifier,
            includeAllInstalled: true
        )
        writeLog("register helper snapshot[\(stage)] sourceIDMatches=\(sourceIDMatches.count)")

        let inputModeMatches = inputSources(
            property: kTISPropertyInputModeID,
            value: inputModeIdentifier,
            includeAllInstalled: true
        )
        writeLog("register helper snapshot[\(stage)] inputModeMatches=\(inputModeMatches.count)")

        let matchingSources = allSources.filter(sourceMatchesRelevantIdentifiers)
        if matchingSources.isEmpty {
            writeLog("register helper snapshot[\(stage)] matchingSources=0")
        } else {
            for (index, source) in matchingSources.enumerated() {
                writeLog("register helper snapshot[\(stage)] source[\(index)] \(describeInputSource(source))")
            }
        }

        if let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() {
            writeLog("register helper snapshot[\(stage)] current \(describeInputSource(current))")
        } else {
            writeLog("register helper snapshot[\(stage)] current -")
        }
    }

    private static func sourceMatchesRelevantIdentifiers(_ source: TISInputSource) -> Bool {
        let identifiers = [
            stringProperty(kTISPropertyInputSourceID, for: source),
            stringProperty(kTISPropertyInputModeID, for: source),
            stringProperty(kTISPropertyBundleID, for: source)
        ]
            .compactMap { $0?.lowercased() }

        return identifiers.contains { identifier in
            identifier.contains("leftio") || identifier.contains("cstcat")
        }
    }

    private static func describeInputSource(_ source: TISInputSource) -> String {
        [
            "sourceID=\(valueDescription(kTISPropertyInputSourceID, for: source))",
            "modeID=\(valueDescription(kTISPropertyInputModeID, for: source))",
            "bundleID=\(valueDescription(kTISPropertyBundleID, for: source))",
            "type=\(valueDescription(kTISPropertyInputSourceType, for: source))",
            "name=\(valueDescription(kTISPropertyLocalizedName, for: source))",
            "enabled=\(valueDescription(kTISPropertyInputSourceIsEnabled, for: source))",
            "selectCapable=\(valueDescription(kTISPropertyInputSourceIsSelectCapable, for: source))",
            "selected=\(valueDescription(kTISPropertyInputSourceIsSelected, for: source))"
        ].joined(separator: " | ")
    }

    private static func stringProperty(
        _ property: CFString?,
        for source: TISInputSource
    ) -> String? {
        guard let property,
              let rawValue = TISGetInputSourceProperty(source, property) else {
            return nil
        }

        let value = unsafeBitCast(rawValue, to: CFTypeRef.self)
        guard CFGetTypeID(value) == CFStringGetTypeID() else {
            return nil
        }

        return value as? String
    }

    private static func valueDescription(
        _ property: CFString?,
        for source: TISInputSource
    ) -> String {
        guard let property,
              let rawValue = TISGetInputSourceProperty(source, property) else {
            return "-"
        }

        return String(describing: unsafeBitCast(rawValue, to: CFTypeRef.self))
    }

    private func firstMatchingInputSource(
        property: CFString?,
        value: CFTypeRef,
        includeAllInstalled: Bool
    ) -> TISInputSource? {
        matchingInputSources(
            property: property,
            value: value,
            includeAllInstalled: includeAllInstalled
        ).first
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
}
