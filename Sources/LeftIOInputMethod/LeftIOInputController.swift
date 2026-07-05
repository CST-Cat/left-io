import AppKit
import Carbon.HIToolbox
import Foundation
@preconcurrency import InputMethodKit
import OneHand
import OneHandAppKit

@objc(LeftIOInputController)
final class LeftIOInputController: IMKInputController {
    private lazy var session = Self.makeSession()
    private lazy var oneHandController = OneHandInputController(
        session: session,
        configuration: Self.loadConfiguration()
    )
    private let candidateWindowController = CandidateWindowController()
    private let modeIndicatorController = ModeIndicatorController()
    private var hasMarkedText = false
    private var pendingShiftToggle = false
    private var lastShiftToggleUptime: TimeInterval = 0
    private var localAsciiMode = false

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        Self.writeInputLog(
            "controller init server=\(String(describing: server)) delegate=\(String(describing: delegate)) client=\(String(describing: inputClient))"
        )
    }

    deinit {
        Self.writeInputLog("controller deinit")
        RKeyEventTap.close(controller: self)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let sender else {
            return false
        }

        RKeyEventTap.bind(controller: self)

        if event.type == .flagsChanged {
            return handleFlagsChanged(event, client: sender)
        }

        guard let oneHandEvent = OneHandMacKeyMapper.event(from: event) else {
            Self.writeInputLog(
                "pass event type=\(event.type.rawValue) keyCode=\(event.keyCode) chars=\(event.characters ?? "-") charsIgnoring=\(event.charactersIgnoringModifiers ?? "-") flags=\(event.modifierFlags.rawValue)"
            )
            return false
        }

        if oneHandEvent.phase == .down {
            pendingShiftToggle = false
        }

        return handleMappedKeyEvent(
            oneHandEvent,
            source: "handle",
            keyCode: event.keyCode,
            characters: event.characters,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            client: sender
        )
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(
            NSEvent.EventTypeMask.keyDown.rawValue
                | NSEvent.EventTypeMask.keyUp.rawValue
                | NSEvent.EventTypeMask.flagsChanged.rawValue
        )
    }

    override func composedString(_ sender: Any!) -> Any! {
        session.compositionText
    }

    override func candidates(_ sender: Any!) -> [Any]! {
        session.displayedCandidates
    }

    override func commitComposition(_ sender: Any!) {
        guard let sender else {
            return
        }

        session.commitCurrentComposition()
        synchronizeClientState(client: sender)
    }

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        Self.writeInputLog("activateServer sender=\(String(describing: sender))")
        if let client = sender as? IMKTextInput {
            client.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.ABC")
            Self.writeInputLog("activate overrideKeyboard=com.apple.keylayout.ABC")
        } else {
            Self.writeInputLog("activate no IMKTextInput client")
        }
        RKeyEventTap.activate(controller: self)
        hideCandidateWindow()
    }

    override func deactivateServer(_ sender: Any!) {
        Self.writeInputLog("deactivateServer sender=\(String(describing: sender))")
        _ = oneHandController.cancelTransientState()
        RKeyEventTap.deactivate(controller: self)

        if let sender,
           hasMarkedText {
            clearMarkedText(client: sender)
        }

        hideCandidateWindow()
        hideModeIndicator()
        session.reset()
        hasMarkedText = false
        pendingShiftToggle = false
        localAsciiMode = false
        super.deactivateServer(sender)
    }

    override func inputControllerWillClose() {
        Self.writeInputLog("inputControllerWillClose")
        _ = oneHandController.cancelTransientState()
        RKeyEventTap.close(controller: self)
        session.reset()
        hideCandidateWindow()
        hideModeIndicator()
        hasMarkedText = false
        pendingShiftToggle = false
        localAsciiMode = false
        super.inputControllerWillClose()
    }

    override func candidateSelected(_ candidateString: NSAttributedString!) {
        guard let candidateString else {
            return
        }

        session.commitDisplayedCandidate(matching: candidateString.string)
        if let client = client() {
            synchronizeClientState(client: client)
        }
    }

    private func synchronizeClientState(client sender: Any) {
        let actions = session.takeClientActions()
        for action in actions {
            perform(action, client: sender)
        }

        if session.compositionText.isEmpty {
            if hasMarkedText || !actions.isEmpty {
                clearMarkedText(client: sender)
                hasMarkedText = false
            }
        } else {
            setMarkedText(session.compositionText, client: sender)
            hasMarkedText = true
        }

        updateCandidates()
    }

    private func handleFlagsChanged(_ event: NSEvent, client sender: Any) -> Bool {
        RKeyEventTap.bind(controller: self)

        guard event.keyCode == UInt16(kVK_Shift)
                || event.keyCode == UInt16(kVK_RightShift) else {
            pendingShiftToggle = false
            return false
        }

        let hasReservedModifier = event.modifierFlags.intersection([.command, .option, .control]).isEmpty == false
        let isShiftDown = event.modifierFlags.contains(.shift)

        if isShiftDown {
            pendingShiftToggle = !hasReservedModifier
            Self.writeInputLog(
                "flagsChanged shiftDown keyCode=\(event.keyCode) pending=\(pendingShiftToggle) flags=\(event.modifierFlags.rawValue)"
            )
            return pendingShiftToggle
        }

        guard pendingShiftToggle else {
            Self.writeInputLog(
                "flagsChanged shiftUp ignored keyCode=\(event.keyCode) flags=\(event.modifierFlags.rawValue)"
            )
            return false
        }

        pendingShiftToggle = false
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastShiftToggleUptime > 0.12 else {
            Self.writeInputLog(
                "flagsChanged shiftUp debounced keyCode=\(event.keyCode) flags=\(event.modifierFlags.rawValue)"
            )
            return true
        }
        lastShiftToggleUptime = now
        toggleLocalAsciiMode(client: sender)
        return true
    }

    private func toggleLocalAsciiMode(client sender: Any) {
        _ = oneHandController.cancelTransientState()
        localAsciiMode.toggle()
        session.setAsciiMode(false)
        synchronizeClientState(client: sender)
        showModeIndicator(isAsciiMode: localAsciiMode)
        Self.writeInputLog("toggle localAscii=\(localAsciiMode) sessionAscii=\(session.context.isAsciiMode)")
    }

    private func handleMappedKeyEvent(
        _ mappedEvent: OneHandKeyEvent,
        source: String,
        keyCode: UInt16?,
        characters: String?,
        charactersIgnoringModifiers: String?,
        client sender: Any
    ) -> Bool {
        if localAsciiMode {
            return handleLocalAsciiKeyEvent(
                mappedEvent,
                source: source,
                keyCode: keyCode,
                characters: characters,
                charactersIgnoringModifiers: charactersIgnoringModifiers,
                client: sender
            )
        }

        if shouldForceClientDelete(for: mappedEvent) {
            _ = oneHandController.cancelTransientState()
            session.reset()
            hasMarkedText = false
            hideCandidateWindow()
            perform(.deleteBackward, client: sender)
            Self.writeInputLog(
                "\(source) directClientDelete keyCode=\(keyCodeDescription(keyCode)) chars=\(characters ?? "-") charsIgnoring=\(charactersIgnoringModifiers ?? "-") hasMarkedText=false"
            )
            return true
        }

        cancelStalePendingSpaceIfNeeded(before: mappedEvent)

        let result = oneHandController.handle(mappedEvent)
        synchronizeClientState(client: sender)
        Self.writeInputLog(
            "\(source) keyCode=\(keyCodeDescription(keyCode)) chars=\(characters ?? "-") charsIgnoring=\(charactersIgnoringModifiers ?? "-") key=\(mappedEvent.key.rawValue) phase=\(mappedEvent.phase) mods=\(mappedEvent.modifiers.rawValue) localAscii=false sessionAscii=\(session.context.isAsciiMode) actions=\(result.actions) consumed=\(result.isConsumed)"
        )
        return result.isConsumed
    }

    private func shouldForceClientDelete(for event: OneHandKeyEvent) -> Bool {
        event.phase == .down
            && event.key == .r
            && !hasMarkedText
            && !session.context.isComposing
    }

    fileprivate func handleEventTapRKeyDown() {
        guard let sender = client() else {
            Self.writeInputLog("eventTapR no client")
            return
        }

        if hasMarkedText || session.context.isComposing {
            let result = oneHandController.handle(.init(key: .r, phase: .down))
            synchronizeClientState(client: sender)
            Self.writeInputLog(
                "eventTapR routed key=R hasMarkedText=\(hasMarkedText) sessionComposing=\(session.context.isComposing) actions=\(result.actions) consumed=\(result.isConsumed)"
            )
            return
        }

        _ = oneHandController.cancelTransientState()
        session.reset()
        hideCandidateWindow()
        perform(.deleteBackward, client: sender)
        Self.writeInputLog("eventTapR directClientDelete")
    }

    fileprivate func handleEventTapKey(
        _ mappedEvent: OneHandKeyEvent,
        keyCode: UInt16,
        characters: String?,
        charactersIgnoringModifiers: String?
    ) {
        guard let sender = client() else {
            Self.writeInputLog(
                "eventTap key=\(mappedEvent.key.rawValue) no client phase=\(mappedEvent.phase)"
            )
            return
        }

        _ = handleMappedKeyEvent(
            mappedEvent,
            source: "eventTap",
            keyCode: keyCode,
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            client: sender
        )
    }

    private func handleLocalAsciiKeyEvent(
        _ mappedEvent: OneHandKeyEvent,
        source: String,
        keyCode: UInt16?,
        characters: String?,
        charactersIgnoringModifiers: String?,
        client sender: Any
    ) -> Bool {
        guard mappedEvent.phase == .down else {
            return true
        }

        let action: OneHandClientAction?
        switch mappedEvent.key {
        case .r:
            action = .deleteBackward
        case .f:
            action = .insertText(mappedEvent.isShiftModified ? "_" : "-")
        case .g:
            action = .insertText(mappedEvent.isShiftModified ? "+" : "=")
        case .space:
            action = .insertText(" ")
        case .escape:
            action = nil
        default:
            if let text = characters, !text.isEmpty {
                action = .insertText(text)
            } else {
                action = nil
            }
        }

        guard let action else {
            Self.writeInputLog(
                "\(source) localAscii pass keyCode=\(keyCodeDescription(keyCode)) chars=\(characters ?? "-") key=\(mappedEvent.key.rawValue)"
            )
            return false
        }

        if hasMarkedText {
            clearMarkedText(client: sender)
            hasMarkedText = false
        }
        hideCandidateWindow()
        perform(action, client: sender)
        Self.writeInputLog(
            "\(source) localAscii keyCode=\(keyCodeDescription(keyCode)) chars=\(characters ?? "-") charsIgnoring=\(charactersIgnoringModifiers ?? "-") key=\(mappedEvent.key.rawValue) mods=\(mappedEvent.modifiers.rawValue) action=\(action)"
        )
        return true
    }

    private func mappedInputTextEvent(
        string: String?,
        keyCode: Int?,
        modifierFlags flags: NSEvent.ModifierFlags
    ) -> OneHandKeyEvent? {
        let normalizedKeyCode = normalizedKeyCode(keyCode)
        let effectiveFlags = flags.union(inferredModifierFlags(from: string))
        return OneHandMacKeyMapper.map(
            keyCode: normalizedKeyCode ?? UInt16.max,
            characters: string,
            charactersIgnoringModifiers: charactersIgnoringModifiers(
                for: normalizedKeyCode,
                string: string,
                modifierFlags: effectiveFlags
            ),
            modifierFlags: effectiveFlags,
            phase: .down
        )
    }

    private func normalizedKeyCode(_ keyCode: Int?) -> UInt16? {
        guard let keyCode,
              keyCode >= 0,
              keyCode <= Int(UInt16.max) else {
            return nil
        }
        return UInt16(keyCode)
    }

    private func charactersIgnoringModifiers(
        for keyCode: UInt16?,
        string: String?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> String? {
        if let keyCode,
           let character = baseCharacter(for: keyCode) {
            return character
        }

        guard let string,
              string.count == 1 else {
            return string
        }

        if modifierFlags.contains(.shift) {
            return string.lowercased()
        }

        return string
    }

    private func baseCharacter(for keyCode: UInt16) -> String? {
        switch Int(keyCode) {
        case kVK_ANSI_Q: "q"
        case kVK_ANSI_W: "w"
        case kVK_ANSI_E: "e"
        case kVK_ANSI_A: "a"
        case kVK_ANSI_S: "s"
        case kVK_ANSI_D: "d"
        case kVK_ANSI_Z: "z"
        case kVK_ANSI_X: "x"
        case kVK_ANSI_C: "c"
        case kVK_ANSI_R: "r"
        case kVK_ANSI_F: "f"
        case kVK_ANSI_G: "g"
        case kVK_ANSI_V: "v"
        case kVK_ANSI_1: "1"
        case kVK_ANSI_2: "2"
        case kVK_ANSI_3: "3"
        case kVK_ANSI_4: "4"
        case kVK_Space: " "
        case kVK_Escape: "\u{1b}"
        default: nil
        }
    }

    private func inferredModifierFlags(from string: String?) -> NSEvent.ModifierFlags {
        guard let first = string?.first,
              first.isLetter,
              String(first) == String(first).uppercased(),
              String(first) != String(first).lowercased() else {
            return []
        }
        return .shift
    }

    private func keyCodeDescription(_ keyCode: UInt16?) -> String {
        guard let keyCode else {
            return "-"
        }
        return String(keyCode)
    }

    private func cancelStalePendingSpaceIfNeeded(before event: OneHandKeyEvent) {
        guard event.phase == .down,
              event.key != .space,
              !CGEventSource.keyState(
                .combinedSessionState,
                key: CGKeyCode(kVK_Space)
              ) else {
            return
        }

        _ = oneHandController.cancelPendingSpace()
    }

    private func perform(_ action: OneHandClientAction, client sender: Any) {
        switch action {
        case let .insertText(text):
            insertText(text, client: sender)
        case .deleteBackward:
            sendCommand(#selector(NSResponder.deleteBackward(_:)), client: sender)
        }
    }

    private func updateCandidates() {
        let candidates = session.displayedCandidates
        let controller = candidateWindowController
        let imkServer = server()
        MainActor.assumeIsolated {
            controller.update(candidates: candidates, server: imkServer)
        }
    }

    private func insertText(_ text: String, client sender: Any) {
        let replacementRange = NSRange(location: NSNotFound, length: NSNotFound)
        if let client = sender as? IMKTextInput {
            client.insertText(text, replacementRange: replacementRange)
        } else {
            _ = (sender as AnyObject).perform(
                #selector(IMKTextInput.insertText(_:replacementRange:)),
                with: text,
                with: NSValue(range: replacementRange)
            )
        }
    }

    private func setMarkedText(_ text: String, client sender: Any) {
        let selectionRange = NSRange(location: text.count, length: 0)
        let replacementRange = NSRange(location: NSNotFound, length: NSNotFound)
        if let client = sender as? IMKTextInput {
            client.setMarkedText(text, selectionRange: selectionRange, replacementRange: replacementRange)
        }
    }

    private func clearMarkedText(client sender: Any) {
        setMarkedText("", client: sender)
    }

    private func sendCommand(_ selector: Selector, client sender: Any) {
        if let client = sender as? NSTextInputClient {
            client.doCommand(by: selector)
            Self.writeInputLog("sendCommand selector=\(NSStringFromSelector(selector)) via=NSTextInputClient")
        } else if (sender as AnyObject).responds(to: selector) {
            _ = (sender as AnyObject).perform(selector)
            Self.writeInputLog("sendCommand selector=\(NSStringFromSelector(selector)) via=perform")
        } else if selector == #selector(NSResponder.deleteBackward(_:)) {
            Self.postSyntheticDelete()
            Self.writeInputLog("sendCommand selector=\(NSStringFromSelector(selector)) via=syntheticDelete")
        } else {
            Self.writeInputLog("sendCommand selector=\(NSStringFromSelector(selector)) unsupportedClient=\(type(of: sender))")
        }
    }

    fileprivate static func postSyntheticDelete() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyCode = CGKeyCode(kVK_Delete)
        CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)?
            .post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)?
            .post(tap: .cghidEventTap)
    }

    private func hideCandidateWindow() {
        let controller = candidateWindowController
        MainActor.assumeIsolated {
            controller.hide()
        }
    }

    private func showModeIndicator(isAsciiMode: Bool) {
        let controller = modeIndicatorController
        let imkServer = server()
        MainActor.assumeIsolated {
            controller.show(label: isAsciiMode ? "EN" : "中", server: imkServer)
        }
    }

    private func hideModeIndicator() {
        let controller = modeIndicatorController
        MainActor.assumeIsolated {
            controller.hide()
        }
    }

    private static func loadLexicon() -> OneHandLexicon {
        let bundle = Bundle.main
        let candidates = [
            bundle.url(forResource: "onehand_t9", withExtension: "dict.yaml", subdirectory: "Rime"),
            bundle.url(forResource: "onehand_t9", withExtension: "dict.yaml"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("data/onehand_t9.dict.yaml")
        ]

        for url in candidates.compactMap({ $0 }) {
            if let lexicon = try? OneHandLexicon.load(from: url) {
                return lexicon
            }
        }

        return .seed
    }

    private static func loadConfiguration() -> OneHandConfiguration {
        let bundle = Bundle.main
        let candidates = [
            bundle.url(forResource: "onehand_symbols", withExtension: "yaml", subdirectory: "Rime"),
            bundle.url(forResource: "onehand_symbols", withExtension: "yaml"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("data/onehand_symbols.yaml")
        ]

        for url in candidates.compactMap({ $0 }) {
            if let configuration = try? OneHandConfiguration.load(from: url) {
                return configuration
            }
        }

        return OneHandConfiguration()
    }

    private static func makeSession() -> AnyOneHandSession {
        let lexicon = loadLexicon()
        let fallbackSession = AnyOneHandSession(OneHandLexiconSession(lexicon: lexicon))
        guard let layout = try? OneHandRimeDataProvider.prepareLayout() else {
            return fallbackSession
        }

        guard let rimeSession = try? OneHandRimeSession(
            sharedDataDirectory: layout.sharedDataDirectory,
            userDataDirectory: layout.userDataDirectory
        ) else {
            return fallbackSession
        }

        return AnyOneHandSession(rimeSession)
    }

    fileprivate static func writeInputLog(_ message: String) {
        let fileManager = FileManager.default
        let directory = (fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
            .appendingPathComponent("LeftIO", isDirectory: true)
        let url = directory.appendingPathComponent("LeftIO.input.log")
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] pid=\(ProcessInfo.processInfo.processIdentifier) \(message)\n"

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            if let data = line.data(using: .utf8) {
                if fileManager.fileExists(atPath: url.path) {
                    let handle = try FileHandle(forWritingTo: url)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } else {
                    try data.write(to: url)
                }
            }
        } catch {
            NSLog("LeftIO input log write failed: %@", String(describing: error))
        }
    }
}

final class RKeyEventTap {
    private static let inputSourceID = "io.github.cstcat.inputmethod.leftio.onehandt9"
    private static let bundleInputSourceID = "io.github.cstcat.inputmethod.leftio"
    nonisolated(unsafe) private static var activeController: LeftIOInputController?
    nonisolated(unsafe) private static var eventTap: CFMachPort?
    nonisolated(unsafe) private static var runLoopSource: CFRunLoopSource?

    static func activateProcessWide() {
        ensureEventTap()
    }

    static func activate(controller: LeftIOInputController) {
        bind(controller: controller)
        ensureEventTap()
    }

    static func bind(controller: LeftIOInputController) {
        activeController = controller
    }

    private static func ensureEventTap() {
        if eventTap != nil {
            LeftIOInputController.writeInputLog("eventTapR active reused")
            return
        }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: nil
        ) else {
            LeftIOInputController.writeInputLog("eventTapR create failed")
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            LeftIOInputController.writeInputLog("eventTapR runLoopSource failed")
            return
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        LeftIOInputController.writeInputLog("eventTapR enabled")
    }

    static func deactivate(controller: LeftIOInputController) {
        guard activeController === controller else {
            return
        }

        LeftIOInputController.writeInputLog("eventTapR controllerRetainedAfterDeactivate")
    }

    static func close(controller: LeftIOInputController) {
        guard activeController === controller else {
            return
        }

        activeController = nil
        LeftIOInputController.writeInputLog("eventTapR controllerClearedOnClose")
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, _ in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard isLeftIOKeyCode(keyCode) else {
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        guard flags.intersection([.maskCommand, .maskAlternate, .maskControl]).isEmpty else {
            return Unmanaged.passUnretained(event)
        }

        guard currentInputSourceIsLeftIO() else {
            return Unmanaged.passUnretained(event)
        }

        let phase: OneHandKeyPhase = type == .keyDown ? .down : .up
        let charactersIgnoringModifiers = charactersIgnoringModifiers(for: keyCode)
        let characters = characters(
            for: keyCode,
            flags: flags,
            charactersIgnoringModifiers: charactersIgnoringModifiers
        )

        guard let mappedEvent = OneHandMacKeyMapper.map(
            keyCode: keyCode,
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            modifierFlags: modifierFlags(from: flags),
            phase: phase
        ) else {
            return Unmanaged.passUnretained(event)
        }

        if let controller = activeController {
            DispatchQueue.main.async {
                LeftIOInputController.writeInputLog(
                    "eventTap routeToController key=\(mappedEvent.key.rawValue) phase=\(mappedEvent.phase)"
                )
                if mappedEvent.key == .r, mappedEvent.phase == .down {
                    controller.handleEventTapRKeyDown()
                } else {
                    controller.handleEventTapKey(
                        mappedEvent,
                        keyCode: keyCode,
                        characters: characters,
                        charactersIgnoringModifiers: charactersIgnoringModifiers
                    )
                }
            }
            return nil
        }

        DispatchQueue.main.async {
            LeftIOInputController.writeInputLog(
                "eventTap passThrough activeController=false keyCode=\(keyCode)"
            )
        }
        return Unmanaged.passUnretained(event)
    }

    private static func isLeftIOKeyCode(_ keyCode: UInt16) -> Bool {
        switch Int(keyCode) {
        case kVK_ANSI_Q, kVK_ANSI_W, kVK_ANSI_E,
             kVK_ANSI_A, kVK_ANSI_S, kVK_ANSI_D,
             kVK_ANSI_Z, kVK_ANSI_X, kVK_ANSI_C,
             kVK_ANSI_R, kVK_ANSI_F, kVK_ANSI_G,
             kVK_ANSI_V,
             kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
             kVK_Space, kVK_Escape:
            return true
        default:
            return false
        }
    }

    private static func modifierFlags(from flags: CGEventFlags) -> NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if flags.contains(.maskShift) {
            result.insert(.shift)
        }
        if flags.contains(.maskAlphaShift) {
            result.insert(.capsLock)
        }
        if flags.contains(.maskCommand) {
            result.insert(.command)
        }
        if flags.contains(.maskAlternate) {
            result.insert(.option)
        }
        if flags.contains(.maskControl) {
            result.insert(.control)
        }
        return result
    }

    private static func characters(for keyCode: UInt16, flags: CGEventFlags, charactersIgnoringModifiers: String?) -> String? {
        guard let charactersIgnoringModifiers else {
            return nil
        }

        if flags.contains(.maskShift) {
            switch Int(keyCode) {
            case kVK_ANSI_F:
                return "_"
            case kVK_ANSI_G:
                return "+"
            default:
                return charactersIgnoringModifiers.uppercased()
            }
        }

        return charactersIgnoringModifiers
    }

    private static func charactersIgnoringModifiers(for keyCode: UInt16) -> String? {
        switch Int(keyCode) {
        case kVK_ANSI_Q: "q"
        case kVK_ANSI_W: "w"
        case kVK_ANSI_E: "e"
        case kVK_ANSI_A: "a"
        case kVK_ANSI_S: "s"
        case kVK_ANSI_D: "d"
        case kVK_ANSI_Z: "z"
        case kVK_ANSI_X: "x"
        case kVK_ANSI_C: "c"
        case kVK_ANSI_R: "r"
        case kVK_ANSI_F: "f"
        case kVK_ANSI_G: "g"
        case kVK_ANSI_V: "v"
        case kVK_ANSI_1: "1"
        case kVK_ANSI_2: "2"
        case kVK_ANSI_3: "3"
        case kVK_ANSI_4: "4"
        case kVK_Space: " "
        case kVK_Escape: "\u{1b}"
        default: nil
        }
    }

    private static func postSyntheticDelete() {
        LeftIOInputController.postSyntheticDelete()
    }

    private static func currentInputSourceIsLeftIO() -> Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return false
        }

        return stringProperty(kTISPropertyInputSourceID, for: source) == inputSourceID
            || stringProperty(kTISPropertyInputModeID, for: source) == inputSourceID
            || stringProperty(kTISPropertyInputSourceID, for: source) == bundleInputSourceID
            || stringProperty(kTISPropertyBundleID, for: source) == bundleInputSourceID
    }

    private static func stringProperty(_ property: CFString?, for source: TISInputSource) -> String? {
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

@MainActor
private final class CandidateWindowController {
    private var cachedCandidateWindow: IMKCandidates?

    func update(candidates: [String], server: IMKServer?) {
        guard !candidates.isEmpty else {
            hide()
            return
        }

        let candidateWindow: IMKCandidates
        if let existingWindow = cachedCandidateWindow {
            candidateWindow = existingWindow
        } else {
            guard let server,
                  let newWindow = IMKCandidates(
                    server: server,
                    panelType: kIMKSingleRowSteppingCandidatePanel
                  ) else {
                return
            }
            newWindow.setSelectionKeys([
                NSNumber(value: 18),
                NSNumber(value: 19),
                NSNumber(value: 20),
                NSNumber(value: 21)
            ])
            newWindow.setAttributes([
                IMKCandidatesSendServerKeyEventFirst: NSNumber(value: true)
            ])
            self.cachedCandidateWindow = newWindow
            candidateWindow = newWindow
        }

        candidateWindow.setCandidateData(candidates)
        if candidateWindow.isVisible() {
            candidateWindow.update()
        } else {
            candidateWindow.show(kIMKLocateCandidatesBelowHint)
        }
    }

    func hide() {
        cachedCandidateWindow?.hide()
    }
}

@MainActor
private final class ModeIndicatorController {
    private var panel: NSPanel?
    private var labelField: NSTextField?
    private var generation = 0

    func show(label: String, server: IMKServer?) {
        generation += 1
        let currentGeneration = generation

        let panel = panel ?? makePanel()
        self.panel = panel
        labelField?.stringValue = label

        let width: CGFloat = label == "EN" ? 56 : 42
        let height: CGFloat = 30
        panel.setContentSize(NSSize(width: width, height: height))
        panel.setFrameOrigin(frameOrigin(width: width, height: height))
        panel.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            guard let self,
                  self.generation == currentGeneration else {
                return
            }
            self.hide()
        }
    }

    func hide() {
        generation += 1
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 56, height: 30))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        contentView.layer?.cornerRadius = 15
        contentView.layer?.masksToBounds = true

        let labelField = NSTextField(labelWithString: "")
        labelField.alignment = .center
        labelField.font = .systemFont(ofSize: 18, weight: .semibold)
        labelField.textColor = .white
        labelField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(labelField)
        NSLayoutConstraint.activate([
            labelField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            labelField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            labelField.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])

        let panel = NSPanel(
            contentRect: contentView.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = contentView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        self.labelField = labelField
        return panel
    }

    private func frameOrigin(width: CGFloat, height: CGFloat) -> NSPoint {
        let mouseLocation = NSEvent.mouseLocation
        let visibleFrame = NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        }?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        var origin = NSPoint(x: mouseLocation.x + 12, y: mouseLocation.y - height - 12)
        origin.x = min(max(origin.x, visibleFrame.minX + 8), visibleFrame.maxX - width - 8)
        origin.y = min(max(origin.y, visibleFrame.minY + 8), visibleFrame.maxY - height - 8)
        return origin
    }
}
