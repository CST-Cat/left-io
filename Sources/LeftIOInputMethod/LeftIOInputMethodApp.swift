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
        LeftIOInputController.prewarmSessionBackend()
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
        let targetURL = Self.userInstalledBundleURL()
        let shouldRestoreLeftIO = Self.currentInputSourceIsLeftIO()
        if shouldRestoreLeftIO,
           !Self.selectASCIIFallback() {
            return .failed(
                "当前正在使用 LeftIO，但安装器无法先切到安全的 ASCII 输入源，因此没有替换正在运行的输入法。"
            )
        }

        Self.terminateInstalledInputMethodInstances(at: targetURL)
        let result = runInstallTransaction()

        guard shouldRestoreLeftIO else {
            return result
        }
        guard Self.restoreLeftIOSelection(at: targetURL) else {
            switch result {
            case .registered:
                return .failed("LeftIO 已安装并注册，但无法恢复为当前输入法。")
            case .copiedButNotRegistered:
                return .failed("LeftIO 已复制但未完成注册，而且无法恢复之前的 LeftIO 选择状态。")
            case let .failed(message):
                return .failed("\(message)；同时无法恢复之前的 LeftIO 选择状态。")
            }
        }
        return result
    }

    private func runInstallTransaction() -> InstallResult {
        let fileManager = FileManager.default
        let sourceURL = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let targetURL = Self.userInstalledBundleURL()
        let systemInstalledURL = URL(
            fileURLWithPath: "/Library/Input Methods/LeftIO.app",
            isDirectory: true
        )
        if fileManager.fileExists(atPath: systemInstalledURL.path) {
            return .failed(
                "已存在系统级 LeftIO：\(systemInstalledURL.path)。请先移除或更新该副本，不要再创建重复的用户输入源。"
            )
        }
        let transactionURL = (fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? targetURL.deletingLastPathComponent())
            .appendingPathComponent("LeftIO/InstallTransactions/\(UUID().uuidString)", isDirectory: true)
        let stagingURL = transactionURL.appendingPathComponent("staged.app", isDirectory: true)
        var previousBundleWasSwapped = false
        var removeTransactionOnExit = true

        defer {
            if removeTransactionOnExit {
                try? fileManager.removeItem(at: transactionURL)
            }
        }

        do {
            try fileManager.createDirectory(
                at: targetURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: transactionURL,
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: sourceURL, to: stagingURL)
            try Self.runTool("/usr/bin/xattr", arguments: ["-cr", stagingURL.path])
            try Self.ensureNoUnsafeExtendedAttributes(at: stagingURL)
            try Self.runTool(
                "/usr/bin/codesign",
                arguments: ["--verify", "--deep", "--strict", stagingURL.path]
            )
            previousBundleWasSwapped = try Self.activateStagedBundle(
                stagingURL,
                at: targetURL,
                fileManager: fileManager
            )
        } catch {
            return .failed("复制到 ~/Library/Input Methods 失败：\(error.localizedDescription)")
        }

        do {
            try Self.ensureNoUnsafeExtendedAttributes(at: targetURL)
            try Self.runTool(
                "/usr/bin/codesign",
                arguments: ["--verify", "--deep", "--strict", targetURL.path]
            )
        } catch {
            if previousBundleWasSwapped {
                if Self.swapBundles(stagingURL, targetURL) {
                    return .failed("最终完整性检查失败，已恢复之前安装的 LeftIO：\(error.localizedDescription)")
                }
                removeTransactionOnExit = false
                return .failed(
                    "最终完整性检查失败，且无法自动回滚。之前的安装已保留在 \(stagingURL.path)：\(error.localizedDescription)"
                )
            }
            do {
                try fileManager.removeItem(at: targetURL)
            } catch let removalError {
                return .failed(
                    "最终完整性检查失败，且无法移除无效副本 \(targetURL.path)：\(removalError.localizedDescription)"
                )
            }
            return .failed("最终完整性检查失败，已移除无效副本：\(error.localizedDescription)")
        }

        guard runInstalledRegistrationHelper(at: targetURL) else {
            if previousBundleWasSwapped {
                if Self.swapBundles(stagingURL, targetURL) {
                    if runInstalledRegistrationHelper(at: targetURL) {
                        return .failed("系统注册失败，已恢复并重新验证之前安装的 LeftIO。")
                    }
                    return .failed(
                        "系统注册失败；之前的 LeftIO 文件已恢复，但其 TIS 注册也无法重新验证。"
                    )
                }
                removeTransactionOnExit = false
                return .failed(
                    "系统注册失败，且无法自动回滚。之前的安装已保留在 \(stagingURL.path)，未被删除。"
                )
            }
            return .copiedButNotRegistered
        }

        do {
            try Self.normalizeRuntimeAddedAttributes(at: targetURL)
        } catch {
            if previousBundleWasSwapped {
                if Self.swapBundles(stagingURL, targetURL) {
                    guard runInstalledRegistrationHelper(at: targetURL) else {
                        return .failed(
                            "注册后完整性检查失败；之前的 LeftIO 文件已恢复，但其 TIS 注册无法重新验证：\(error.localizedDescription)"
                        )
                    }
                    do {
                        try Self.normalizeRuntimeAddedAttributes(at: targetURL)
                        return .failed(
                            "注册后完整性检查失败，已恢复并重新验证之前安装的 LeftIO：\(error.localizedDescription)"
                        )
                    } catch let restoreError {
                        return .failed(
                            "注册后完整性检查失败；之前的 LeftIO 已恢复，但其完整性验证也失败：\(restoreError.localizedDescription)"
                        )
                    }
                }
                removeTransactionOnExit = false
                return .failed(
                    "注册后完整性检查失败，且无法自动回滚。之前的安装已保留在 \(stagingURL.path)：\(error.localizedDescription)"
                )
            }

            do {
                try fileManager.removeItem(at: targetURL)
            } catch let removalError {
                return .failed(
                    "注册后完整性检查失败，且无法移除无效副本 \(targetURL.path)：\(removalError.localizedDescription)"
                )
            }
            return .failed("注册后完整性检查失败，已移除无效副本：\(error.localizedDescription)")
        }

        return .registered
    }

    private static func currentInputSourceIsLeftIO() -> Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return false
        }
        return inputSourceIsLeftIO(source)
    }

    private static func inputSourceIsLeftIO(_ source: TISInputSource) -> Bool {
        let bundleID = bundleIdentifier as String
        let modeID = inputModeIdentifier as String
        return stringProperty(kTISPropertyInputSourceID, for: source) == bundleID
            || stringProperty(kTISPropertyBundleID, for: source) == bundleID
            || stringProperty(kTISPropertyInputSourceID, for: source) == modeID
            || stringProperty(kTISPropertyInputModeID, for: source) == modeID
    }

    private static func selectASCIIFallback() -> Bool {
        guard let fallback = TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue(),
              !inputSourceIsLeftIO(fallback),
              boolProperty(kTISPropertyInputSourceIsEnabled, for: fallback) == true,
              boolProperty(kTISPropertyInputSourceIsSelectCapable, for: fallback) == true,
              TISSelectInputSource(fallback) == noErr else {
            return false
        }
        drainRunLoop(for: 0.25)
        return !currentInputSourceIsLeftIO()
    }

    private static func restoreLeftIOSelection(at bundleURL: URL) -> Bool {
        for _ in 0..<3 {
            try? runTool(
                "/usr/bin/open",
                arguments: ["-n", "-gj", bundleURL.path]
            )
            drainRunLoop(for: 0.4)

            let modeID = inputModeIdentifier as String
            let mode = inputSources(
                property: nil,
                value: kCFNull,
                includeAllInstalled: true
            ).first { source in
                (stringProperty(kTISPropertyInputSourceID, for: source) == modeID
                    || stringProperty(kTISPropertyInputModeID, for: source) == modeID)
                    && boolProperty(kTISPropertyInputSourceIsEnabled, for: source) == true
                    && boolProperty(kTISPropertyInputSourceIsSelectCapable, for: source) == true
            }

            guard let mode,
                  TISSelectInputSource(mode) == noErr else {
                continue
            }
            drainRunLoop(for: 0.25)
            if currentInputSourceIsLeftIO() {
                return true
            }
        }
        return false
    }

    private static func terminateInstalledInputMethodInstances(at bundleURL: URL) {
        let expectedPath = bundleURL.resolvingSymlinksInPath().standardizedFileURL.path
        let applications = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier as String
        ).filter { application in
            guard application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  let runningBundleURL = application.bundleURL else {
                return false
            }
            return runningBundleURL.resolvingSymlinksInPath().standardizedFileURL.path == expectedPath
        }

        for application in applications {
            application.terminate()
        }
        let deadline = Date().addingTimeInterval(0.8)
        while applications.contains(where: { !$0.isTerminated }),
              deadline.timeIntervalSinceNow > 0 {
            drainRunLoop(for: min(0.1, deadline.timeIntervalSinceNow))
        }
        for application in applications where !application.isTerminated {
            application.forceTerminate()
        }
        if !applications.isEmpty {
            drainRunLoop(for: 0.2)
        }
    }

    private func presentInstallResult(_ result: InstallResult) {
        let alert = NSAlert()
        alert.addButton(withTitle: "好")

        switch result {
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

    private static func activateStagedBundle(
        _ stagingURL: URL,
        at targetURL: URL,
        fileManager: FileManager
    ) throws -> Bool {
        guard fileManager.fileExists(atPath: targetURL.path) else {
            try fileManager.moveItem(at: stagingURL, to: targetURL)
            return false
        }

        guard swapBundles(stagingURL, targetURL) else {
            let errorCode = errno
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errorCode),
                userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errorCode))]
            )
        }
        return true
    }

    private static func swapBundles(_ firstURL: URL, _ secondURL: URL) -> Bool {
        firstURL.path.withCString { firstPath in
            secondURL.path.withCString { secondPath in
                renamex_np(firstPath, secondPath, UInt32(RENAME_SWAP)) == 0
            }
        }
    }

    private static func runTool(_ executablePath: String, arguments: [String]) throws {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardError = errorPipe
        try process.run()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorText = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackMessage = "\(executablePath) 失败，退出码 \(process.terminationStatus)"
            throw NSError(
                domain: "io.github.cstcat.inputmethod.leftio.install",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: errorText.flatMap { $0.isEmpty ? nil : $0 }
                        ?? fallbackMessage
                ]
            )
        }
    }

    private static func normalizeRuntimeAddedAttributes(at url: URL) throws {
        var lastError: Error?
        for attempt in 0..<4 {
            for attribute in ["com.apple.quarantine", "com.apple.macl"] {
                try? runTool(
                    "/usr/bin/xattr",
                    arguments: ["-dr", attribute, url.path]
                )
            }

            do {
                try ensureNoUnsafeExtendedAttributes(at: url)
                try runTool(
                    "/usr/bin/codesign",
                    arguments: ["--verify", "--deep", "--strict", url.path]
                )
                return
            } catch {
                lastError = error
                if attempt < 3 {
                    Thread.sleep(forTimeInterval: 0.2)
                }
            }
        }

        throw lastError ?? NSError(
            domain: "io.github.cstcat.inputmethod.leftio.install",
            code: 2,
            userInfo: [
                NSLocalizedDescriptionKey: "无法清除 LeftIO 的 quarantine 或 macl 扩展属性"
            ]
        )
    }

    private static func ensureNoUnsafeExtendedAttributes(at url: URL) throws {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-lr", url.path]
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: outputData, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "io.github.cstcat.inputmethod.leftio.install",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: output.isEmpty
                        ? "无法检查暂存应用的扩展属性"
                        : output.trimmingCharacters(in: .whitespacesAndNewlines)
                ]
            )
        }

        for attribute in ["com.apple.quarantine", "com.apple.macl"] {
            if output.contains(": \(attribute):") {
                throw NSError(
                    domain: "io.github.cstcat.inputmethod.leftio.install",
                    code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey: "暂存应用仍包含不安全的扩展属性 \(attribute)"
                    ]
                )
            }
        }
    }

    private func runInstalledRegistrationHelper(at bundleURL: URL) -> Bool {
        let executableURL = bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("LeftIO")

        let process = Process()
        process.executableURL = executableURL
        process.arguments = [Self.registerArgument]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
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

        let allSources = inputSources(
            property: nil,
            value: kCFNull,
            includeAllInstalled: true
        )
        let parentSources = inputMethodSources.filter { source in
            stringProperty(kTISPropertyInputSourceID, for: source) == bundleIdentifier as String
        }
        let modeSources = allSources.filter { source in
            stringProperty(kTISPropertyInputSourceID, for: source) == inputModeIdentifier as String
                || stringProperty(kTISPropertyInputModeID, for: source) == inputModeIdentifier as String
        }
        guard parentSources.count == 1, modeSources.count == 1 else {
            writeLog(
                "register helper failed: expected one parent and mode, got parent=\(parentSources.count) mode=\(modeSources.count)"
            )
            return false
        }

        var enableSucceeded = true
        for source in inputMethodSources {
            let enableStatus = TISEnableInputSource(source)
            writeLog("register helper enable bundle source status=\(enableStatus) \(describeInputSource(source))")
            enableSucceeded = enableSucceeded && enableStatus == noErr
        }
        guard enableSucceeded else {
            writeLog("register helper failed: one or more bundle sources could not be enabled")
            return false
        }

        let inputMode = modeSources[0]

        let enableModeStatus = TISEnableInputSource(inputMode)
        drainRunLoop(for: 1.5)
        writeLog("register helper mode enable status=\(enableModeStatus)")
        guard enableModeStatus == noErr else {
            writeLog("register helper failed: mode enable status=\(enableModeStatus)")
            return false
        }

        let verifiedBundleEnabled = boolProperty(
            kTISPropertyInputSourceIsEnabled,
            for: parentSources[0]
        ) == true
        let verifiedModeEnabled = boolProperty(
            kTISPropertyInputSourceIsEnabled,
            for: inputMode
        ) == true
        let verifiedModeSelectCapable = boolProperty(
            kTISPropertyInputSourceIsSelectCapable,
            for: inputMode
        ) == true
        guard verifiedBundleEnabled,
              verifiedModeEnabled,
              verifiedModeSelectCapable else {
            writeLog(
                "register helper failed final verification bundleEnabled=\(verifiedBundleEnabled) modeEnabled=\(verifiedModeEnabled) modeSelectCapable=\(verifiedModeSelectCapable)"
            )
            return false
        }

        let persistentSources = CFPreferencesCopyAppValue(
            "AppleEnabledThirdPartyInputSources" as CFString,
            "com.apple.inputsources" as CFString
        ) as? [[String: Any]] ?? []
        let persistentParentCount = persistentSources.filter { source in
            source["Bundle ID"] as? String == bundleIdentifier as String
                && source["InputSourceKind"] as? String == "Keyboard Input Method"
                && source["Input Mode"] == nil
        }.count
        let persistentModeCount = persistentSources.filter { source in
            source["Bundle ID"] as? String == bundleIdentifier as String
                && source["InputSourceKind"] as? String == "Input Mode"
                && source["Input Mode"] as? String == inputModeIdentifier as String
        }.count
        writeLog(
            "register helper persistent parent=\(persistentParentCount) mode=\(persistentModeCount)"
        )
        guard persistentParentCount == 1,
              persistentModeCount == 1 else {
            writeLog("register helper failed: persistent parent/mode entries are not unique")
            return false
        }

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
        let rootDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return [
            rootDirectory
                .appendingPathComponent("LeftIO", isDirectory: true)
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

    private static func boolProperty(
        _ property: CFString?,
        for source: TISInputSource
    ) -> Bool? {
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

}
