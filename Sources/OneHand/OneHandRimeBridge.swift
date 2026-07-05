import CRimeBridge
import Foundation

public protocol OneHandSession: AnyObject {
    var context: OneHandContext { get }
    var compositionText: String { get }
    var displayedCandidates: [String] { get }
    func apply(_ action: OneHandAction)
    func takeClientActions() -> [OneHandClientAction]
    func commitCurrentComposition()
    func commitDisplayedCandidate(matching text: String)
    func setAsciiMode(_ enabled: Bool)
    func reset()
}

public final class AnyOneHandSession: OneHandSession {
    private let session: any OneHandSession

    public init(_ session: any OneHandSession) {
        self.session = session
    }

    public var context: OneHandContext { session.context }
    public var compositionText: String { session.compositionText }
    public var displayedCandidates: [String] { session.displayedCandidates }

    public func apply(_ action: OneHandAction) {
        session.apply(action)
    }

    public func takeClientActions() -> [OneHandClientAction] {
        session.takeClientActions()
    }

    public func commitCurrentComposition() {
        session.commitCurrentComposition()
    }

    public func commitDisplayedCandidate(matching text: String) {
        session.commitDisplayedCandidate(matching: text)
    }

    public func setAsciiMode(_ enabled: Bool) {
        session.setAsciiMode(enabled)
    }

    public func reset() {
        session.reset()
    }
}

protocol OneHandRimeBridgeClient: AnyObject {
    func setInput(_ input: String) -> Bool
    func commitComposition() -> Bool
    func clearComposition()
    func selectCandidateOnCurrentPage(_ index: Int) -> Bool
    func changePage(backward: Bool) -> Bool
    func isAsciiMode() -> Bool
    func setAsciiMode(_ enabled: Bool) -> Bool
    func copyCommitText() -> String?
    func copyInput() -> String?
    func copyPreedit() -> String?
    func candidateCount() -> Int
    func copyCandidate(at index: Int) -> String?
}

final class LiveOneHandRimeBridge: OneHandRimeBridgeClient {
    private let handle: UnsafeMutablePointer<OneHandRimeBridgeHandle>

    init(
        sharedDataDirectory: URL,
        userDataDirectory: URL,
        schemaId: String,
        appName: String
    ) throws {
        Self.configureDynamicLibrarySearchPath()
        try FileManager.default.createDirectory(
            at: userDataDirectory,
            withIntermediateDirectories: true
        )

        guard let createdHandle = sharedDataDirectory.path.withCString({ sharedDataPath in
            userDataDirectory.path.withCString { userDataPath in
                schemaId.withCString { schemaCString in
                    appName.withCString { appNameCString in
                        OneHandRimeBridgeCreate(sharedDataPath, userDataPath, schemaCString, appNameCString)
                    }
                }
            }
        }) else {
            throw OneHandRimeSession.Error.initializationFailed(Self.lastBridgeError())
        }

        handle = createdHandle
    }

    deinit {
        OneHandRimeBridgeDestroy(handle)
    }

    func setInput(_ input: String) -> Bool {
        input.withCString { cString in
            OneHandRimeBridgeSetInput(handle, cString)
        }
    }

    func commitComposition() -> Bool {
        OneHandRimeBridgeCommitComposition(handle)
    }

    func clearComposition() {
        OneHandRimeBridgeClearComposition(handle)
    }

    func selectCandidateOnCurrentPage(_ index: Int) -> Bool {
        OneHandRimeBridgeSelectCandidateOnCurrentPage(handle, index)
    }

    func changePage(backward: Bool) -> Bool {
        OneHandRimeBridgeChangePage(handle, backward)
    }

    func isAsciiMode() -> Bool {
        OneHandRimeBridgeIsAsciiMode(handle)
    }

    func setAsciiMode(_ enabled: Bool) -> Bool {
        OneHandRimeBridgeSetAsciiMode(handle, enabled)
    }

    func copyCommitText() -> String? {
        Self.copyString(from: OneHandRimeBridgeCopyCommitText(handle))
    }

    func copyCurrentSchemaId() -> String? {
        Self.copyString(from: OneHandRimeBridgeCopyCurrentSchemaId(handle))
    }

    func copyInput() -> String? {
        Self.copyString(from: OneHandRimeBridgeCopyInput(handle))
    }

    func copyPreedit() -> String? {
        Self.copyString(from: OneHandRimeBridgeCopyPreedit(handle))
    }

    func candidateCount() -> Int {
        Int(OneHandRimeBridgeCandidateCount(handle))
    }

    func copyCandidate(at index: Int) -> String? {
        Self.copyString(from: OneHandRimeBridgeCopyCandidateAtIndex(handle, index))
    }

    private static func copyString(from pointer: UnsafeMutablePointer<CChar>?) -> String? {
        guard let pointer else {
            return nil
        }
        defer {
            OneHandRimeBridgeFreeString(pointer)
        }
        return String(cString: pointer)
    }

    private static func lastBridgeError() -> String {
        guard let error = OneHandRimeBridgeGetLastError() else {
            return "unknown librime bridge error"
        }
        let message = String(cString: error)
        return message.isEmpty ? "unknown librime bridge error" : message
    }

    func lastErrorMessage() -> String {
        Self.lastBridgeError()
    }

    private static func configureDynamicLibrarySearchPath() {
        guard ProcessInfo.processInfo.environment["LEFTIO_LIBRIME_PATH"]?.isEmpty != false else {
            return
        }

        let bundleCandidates = [
            Bundle.main.privateFrameworksURL?.appendingPathComponent("librime.1.dylib"),
            Bundle.main.privateFrameworksURL?.appendingPathComponent("librime.dylib"),
            Bundle.main.builtInPlugInsURL?
                .appendingPathComponent("LeftIOInputMethod.appex", isDirectory: true)
                .appendingPathComponent("Contents/Frameworks/librime.1.dylib"),
            Bundle.main.builtInPlugInsURL?
                .appendingPathComponent("LeftIOInputMethod.appex", isDirectory: true)
                .appendingPathComponent("Contents/Frameworks/librime.dylib")
        ].compactMap { $0 }

        let repoRoot = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        let repoCandidates = [
            repoRoot.appendingPathComponent("vendor/librime/build/lib/librime.1.dylib"),
            repoRoot.appendingPathComponent("vendor/librime/build/lib/Release/librime.1.dylib"),
            repoRoot.appendingPathComponent("vendor/librime/dist/lib/librime.1.dylib"),
            repoRoot.appendingPathComponent("vendor/librime/build/lib/librime.dylib"),
            repoRoot.appendingPathComponent("vendor/librime/build/lib/Release/librime.dylib"),
            repoRoot.appendingPathComponent("vendor/librime/dist/lib/librime.dylib")
        ]

        let fileManager = FileManager.default
        if let path = (bundleCandidates + repoCandidates)
            .first(where: { fileManager.fileExists(atPath: $0.path) })?.path {
            setenv("LEFTIO_LIBRIME_PATH", path, 0)
        }
    }
}

public final class OneHandRimeSession: OneHandSession {
    public enum Error: Swift.Error, LocalizedError, Equatable {
        case initializationFailed(String)

        public var errorDescription: String? {
            switch self {
            case let .initializationFailed(message):
                return message
            }
        }
    }

    public private(set) var compositionText = ""
    public private(set) var displayedCandidates: [String] = []

    private let bridge: any OneHandRimeBridgeClient
    private let pageSize: Int
    private var rawInput = ""
    private var pendingClientActions: [OneHandClientAction] = []

    public var context: OneHandContext {
        OneHandContext(
            isComposing: !rawInput.isEmpty,
            hasCandidates: !displayedCandidates.isEmpty,
            isAsciiMode: bridge.isAsciiMode()
        )
    }

    public init(
        sharedDataDirectory: URL,
        userDataDirectory: URL,
        schemaId: String = "onehand_t9",
        appName: String = "rime.leftio",
        pageSize: Int = 4
    ) throws {
        self.bridge = try LiveOneHandRimeBridge(
            sharedDataDirectory: sharedDataDirectory,
            userDataDirectory: userDataDirectory,
            schemaId: schemaId,
            appName: appName
        )
        self.pageSize = pageSize
        refreshState()
    }

    init(
        bridge: any OneHandRimeBridgeClient,
        pageSize: Int = 4
    ) {
        self.bridge = bridge
        self.pageSize = pageSize
        refreshState()
    }

    public func apply(_ action: OneHandAction) {
        switch action {
        case .enterSymbolLayer, .exitSymbolLayer, .cancelPendingSpace:
            break
        case .cancelComposition:
            bridge.clearComposition()
        case let .inputT9Code(code):
            replaceInput(with: rawInput + code)
        case .insertSyllableDelimiter:
            guard !rawInput.isEmpty else {
                return
            }
            replaceInput(with: rawInput + "'")
        case .deleteBackward:
            guard !rawInput.isEmpty else {
                pendingClientActions.append(.deleteBackward)
                return
            }
            replaceInput(with: String(rawInput.dropLast()))
        case .pageUp:
            _ = bridge.changePage(backward: true)
        case .pageDown:
            _ = bridge.changePage(backward: false)
        case let .selectCandidate(index):
            _ = bridge.selectCandidateOnCurrentPage(index)
        case .commitFirstCandidate:
            if displayedCandidates.isEmpty {
                queueLiteralCommitIfNeeded()
            } else {
                _ = bridge.selectCandidateOnCurrentPage(0)
            }
        case .commitComposition:
            commitCurrentComposition()
            return
        case let .inputDigit(digit):
            flushCompositionBeforeDirectOutput()
            pendingClientActions.append(.insertText(String(digit)))
        case let .insertText(text):
            flushCompositionBeforeDirectOutput()
            pendingClientActions.append(.insertText(text))
        case .insertSpace:
            flushCompositionBeforeDirectOutput()
            pendingClientActions.append(.insertText(" "))
        case .insertNewline:
            flushCompositionBeforeDirectOutput()
            pendingClientActions.append(.insertText("\n"))
        }

        drainCommitText()
        refreshState()
    }

    public func takeClientActions() -> [OneHandClientAction] {
        defer {
            pendingClientActions.removeAll()
        }
        return pendingClientActions
    }

    public func commitCurrentComposition() {
        guard !rawInput.isEmpty else {
            return
        }

        if displayedCandidates.isEmpty {
            queueLiteralCommitIfNeeded()
        } else {
            _ = bridge.commitComposition()
        }

        drainCommitText()
        refreshState()
    }

    public func commitDisplayedCandidate(matching text: String) {
        guard let index = displayedCandidates.firstIndex(of: text) else {
            return
        }
        _ = bridge.selectCandidateOnCurrentPage(index)
        drainCommitText()
        refreshState()
    }

    public func setAsciiMode(_ enabled: Bool) {
        _ = bridge.setAsciiMode(enabled)
        if !rawInput.isEmpty {
            bridge.clearComposition()
        }
        drainCommitText()
        refreshState()
    }

    public func reset() {
        bridge.clearComposition()
        rawInput = ""
        compositionText = ""
        displayedCandidates.removeAll()
        pendingClientActions.removeAll()
    }

    public static func defaultUserDataDirectory() -> URL {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        return applicationSupportURL
            .appendingPathComponent("LeftIO", isDirectory: true)
            .appendingPathComponent("Rime", isDirectory: true)
    }

    private func replaceInput(with input: String) {
        _ = bridge.setInput(input)
    }

    private func queueLiteralCommitIfNeeded() {
        guard !rawInput.isEmpty else {
            return
        }
        pendingClientActions.append(.insertText(rawInput))
        bridge.clearComposition()
    }

    private func flushCompositionBeforeDirectOutput() {
        guard !rawInput.isEmpty else {
            return
        }
        commitCurrentComposition()
    }

    private func drainCommitText() {
        guard let commitText = bridge.copyCommitText(),
              !commitText.isEmpty else {
            return
        }
        pendingClientActions.append(.insertText(commitText))
    }

    private func refreshState() {
        rawInput = bridge.copyInput() ?? ""
        compositionText = bridge.copyPreedit() ?? rawInput

        let count = min(bridge.candidateCount(), pageSize)
        displayedCandidates = (0..<count).compactMap { index in
            bridge.copyCandidate(at: index)
        }
    }
}
