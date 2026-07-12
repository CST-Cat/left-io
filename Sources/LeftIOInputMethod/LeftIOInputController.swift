import AppKit
import Carbon.HIToolbox
import Foundation
@preconcurrency import InputMethodKit
import OneHand
import OneHandAppKit

@objc(LeftIOInputController)
final class LeftIOInputController: IMKInputController {
    private static let qLongPressDuration: TimeInterval = 0.45
    private static let sessionBackendFactory = LeftIOSessionBackendFactory()
    private static let inputLogLock = NSLock()
    private static let inputEventLoggingEnabled =
        ProcessInfo.processInfo.environment["LEFTIO_ENABLE_INPUT_EVENT_LOG"] == "1"
        || UserDefaults.standard.bool(forKey: "LeftIOEnableInputEventLogging")
    private lazy var session = Self.makeSession()
    private lazy var oneHandController = OneHandInputController(
        session: session,
        configuration: Self.loadConfiguration()
    )
    private lazy var candidateWindowController = MainActor.assumeIsolated {
        CandidateWindowController()
    }
    private lazy var candidatePanelInteractionController = MainActor.assumeIsolated {
        CandidatePanelInteractionController(inputController: self)
    }
    private let modeIndicatorController = ModeIndicatorController()
    private var hasMarkedText = false
    private var pendingShiftToggle = false
    private var lastShiftToggleUptime: TimeInterval = 0
    private var localAsciiMode = false
    private var isQKeyDown = false
    private var qLongPressWorkItem: DispatchWorkItem?
    fileprivate var isInputServerActive = false
    private var activeInputClient: Any?
    private var candidatePanelPresentation: CandidatePanelPresentation = .compact
    private var expandedCandidateStartIndex = 0
    private var expandedActiveRowIndex = 0

    private static let expandedCandidateColumnCount = 4
    private static let expandedCandidateVisibleLimit = 24

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        Self.writeInputLog(
            "controller init server=\(String(describing: server)) delegate=\(String(describing: delegate)) client=\(String(describing: inputClient))"
        )
    }

    deinit {
        qLongPressWorkItem?.cancel()
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

        if event.type == .keyDown {
            pendingShiftToggle = false
        }

        guard let oneHandEvent = OneHandMacKeyMapper.event(from: event) else {
            Self.writeInputEventLog(
                "pass event type=\(event.type.rawValue) keyCode=\(event.keyCode) chars=\(event.characters ?? "-") charsIgnoring=\(event.charactersIgnoringModifiers ?? "-") flags=\(event.modifierFlags.rawValue)"
            )
            return false
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

    override func menu() -> NSMenu! {
        let menu = NSMenu(title: "LeftIO")
        let item = NSMenuItem(
            title: "自定义输入层…",
            action: #selector(showSymbolLayerSettings(_:)),
            keyEquivalent: ""
        )
        item.target = self
        menu.addItem(item)
        return menu
    }

    override func showPreferences(_ sender: Any!) {
        showSymbolLayerSettings(sender)
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
        isInputServerActive = true
        activeInputClient = sender
        oneHandController.updateConfiguration(Self.loadConfiguration())
        if let client = sender as? IMKTextInput {
            client.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.ABC")
            Self.writeInputLog("activate overrideKeyboard=com.apple.keylayout.ABC")
        } else {
            Self.writeInputLog("activate no IMKTextInput client")
        }
        RKeyEventTap.activate(controller: self)
        hideCandidateWindow()
    }

    @objc
    private func showSymbolLayerSettings(_ sender: Any?) {
        if isInputServerActive {
            _ = cancelTransientInputState()
        }
        let bundledConfiguration = Self.loadBundledConfiguration()
        let effectiveConfiguration = LeftIOSymbolSettingsStore()
            .effectiveConfiguration(base: bundledConfiguration)
        let settingsController = MainActor.assumeIsolated {
            LeftIOSymbolSettingsWindow.shared
        }
        MainActor.assumeIsolated {
            settingsController.show(
                bundledConfiguration: bundledConfiguration,
                effectiveConfiguration: effectiveConfiguration,
                onSave: { configuration in
                    let appliedControllerCount = RKeyEventTap
                        .applyConfigurationToActiveControllers(configuration)
                    LeftIOInputController.writeInputLog(
                        "input layer settings saved appliedControllerCount=\(appliedControllerCount)"
                    )
                }
            )
        }
    }

    fileprivate func applySymbolLayerConfiguration(_ configuration: OneHandConfiguration) {
        guard isInputServerActive else {
            return
        }
        _ = cancelTransientInputState()
        oneHandController.updateConfiguration(configuration)
    }

    override func deactivateServer(_ sender: Any!) {
        Self.writeInputLog("deactivateServer sender=\(String(describing: sender))")
        isInputServerActive = false
        _ = cancelTransientInputState()
        RKeyEventTap.deactivate(controller: self)

        if let sender,
           hasMarkedText {
            clearMarkedText(client: sender)
        }

        hideCandidateWindow()
        hideModeIndicator()
        session.reset()
        activeInputClient = nil
        hasMarkedText = false
        pendingShiftToggle = false
        localAsciiMode = false
        collapseCandidatePanel()
        super.deactivateServer(sender)
    }

    override func inputControllerWillClose() {
        Self.writeInputLog("inputControllerWillClose")
        isInputServerActive = false
        _ = cancelTransientInputState()
        RKeyEventTap.close(controller: self)
        session.reset()
        activeInputClient = nil
        hideCandidateWindow()
        hideModeIndicator()
        hasMarkedText = false
        pendingShiftToggle = false
        localAsciiMode = false
        collapseCandidatePanel()
        super.inputControllerWillClose()
    }

    override func candidateSelected(_ candidateString: NSAttributedString!) {
        guard let candidateString else {
            return
        }

        session.commitDisplayedCandidate(matching: candidateString.string)
        collapseCandidatePanel()
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
            Self.writeInputEventLog(
                "flagsChanged shiftDown keyCode=\(event.keyCode) pending=\(pendingShiftToggle) flags=\(event.modifierFlags.rawValue)"
            )
            return pendingShiftToggle
        }

        guard pendingShiftToggle else {
            Self.writeInputEventLog(
                "flagsChanged shiftUp ignored keyCode=\(event.keyCode) flags=\(event.modifierFlags.rawValue)"
            )
            return false
        }

        pendingShiftToggle = false
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastShiftToggleUptime > 0.12 else {
            Self.writeInputEventLog(
                "flagsChanged shiftUp debounced keyCode=\(event.keyCode) flags=\(event.modifierFlags.rawValue)"
            )
            return true
        }
        lastShiftToggleUptime = now
        toggleLocalAsciiMode(client: sender)
        return true
    }

    private func toggleLocalAsciiMode(client sender: Any) {
        _ = cancelTransientInputState()
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
        if mappedEvent.phase == .down {
            pendingShiftToggle = false
        }

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

        let shouldScheduleQLongPress: Bool
        if mappedEvent.key == .q {
            switch mappedEvent.phase {
            case .down:
                if isQKeyDown {
                    Self.writeInputEventLog("\(source) qRepeat ignored")
                    return true
                }
                isQKeyDown = true
                shouldScheduleQLongPress = true
            case .up:
                cancelQLongPressTimer()
                isQKeyDown = false
                shouldScheduleQLongPress = false
            }
        } else {
            shouldScheduleQLongPress = false
            preparePendingQPressForNonQKeyDown(mappedEvent)
        }

        if shouldForceClientDelete(for: mappedEvent) {
            _ = cancelTransientInputState()
            session.reset()
            hasMarkedText = false
            collapseCandidatePanel()
            hideCandidateWindow()
            perform(.deleteBackward, client: sender)
            Self.writeInputEventLog(
                "\(source) directClientDelete keyCode=\(keyCodeDescription(keyCode)) chars=\(characters ?? "-") charsIgnoring=\(charactersIgnoringModifiers ?? "-") hasMarkedText=false"
            )
            return true
        }

        if handleCandidatePanelShortcut(
            mappedEvent,
            source: source,
            keyCode: keyCode,
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            client: sender
        ) {
            return true
        }

        let result = oneHandController.handle(mappedEvent)
        if shouldScheduleQLongPress {
            scheduleQLongPress()
        }
        updateCandidatePanelPresentation(after: result.actions, event: mappedEvent)
        synchronizeClientState(client: sender)
        Self.writeInputEventLog(
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

    private func scheduleQLongPress() {
        cancelQLongPressTimer()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            self.qLongPressWorkItem = nil
            guard self.isQKeyDown,
                  let sender = self.eventTapClient() else {
                return
            }

            let result = self.oneHandController.triggerQLongPress()
            self.updateCandidatePanelPresentation(
                after: result.actions,
                event: .init(key: .q, phase: .down)
            )
            self.synchronizeClientState(client: sender)
            Self.writeInputEventLog(
                "qLongPress threshold=\(Self.qLongPressDuration) actions=\(result.actions)"
            )
        }
        qLongPressWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.qLongPressDuration,
            execute: workItem
        )
    }

    private func cancelQLongPressTimer() {
        qLongPressWorkItem?.cancel()
        qLongPressWorkItem = nil
    }

    @discardableResult
    private func cancelTransientInputState() -> [OneHandAction] {
        cancelQLongPressTimer()
        isQKeyDown = false
        return oneHandController.cancelTransientState()
    }

    private func preparePendingQPressForNonQKeyDown(_ event: OneHandKeyEvent) {
        guard event.phase == .down, isQKeyDown else {
            return
        }

        cancelQLongPressTimer()
        guard !isPhysicalQDown() else {
            return
        }

        isQKeyDown = false
        _ = oneHandController.cancelPendingQPress()
    }

    fileprivate func handleEventTapRKeyDown() -> Bool {
        guard let sender = eventTapClient() else {
            Self.writeInputEventLog("eventTapR no client")
            return false
        }

        preparePendingQPressForNonQKeyDown(.init(key: .r, phase: .down))

        if hasMarkedText || session.context.isComposing {
            let result = oneHandController.handle(.init(key: .r, phase: .down))
            updateCandidatePanelPresentation(after: result.actions, event: .init(key: .r, phase: .down))
            synchronizeClientState(client: sender)
            Self.writeInputEventLog(
                "eventTapR routed key=R hasMarkedText=\(hasMarkedText) sessionComposing=\(session.context.isComposing) actions=\(result.actions) consumed=\(result.isConsumed)"
            )
            return result.isConsumed
        }

        _ = cancelTransientInputState()
        session.reset()
        collapseCandidatePanel()
        hideCandidateWindow()
        perform(.deleteBackward, client: sender)
        Self.writeInputEventLog("eventTapR directClientDelete")
        return true
    }

    private func updateCandidatePanelPresentation(
        after actions: [OneHandAction],
        event: OneHandKeyEvent
    ) {
        guard event.phase == .down else {
            return
        }

        if actions.contains(.pageUp) || actions.contains(.pageDown) {
            candidatePanelPresentation = .expanded
            expandedCandidateStartIndex = clampExpandedCandidateStartIndex(expandedCandidateStartIndex)
            clampExpandedActiveRowIndex()
            return
        }

        if actions.contains(where: Self.collapsesCandidatePanel) {
            collapseCandidatePanel()
        }
    }

    private func handleCandidatePanelShortcut(
        _ mappedEvent: OneHandKeyEvent,
        source: String,
        keyCode: UInt16?,
        characters: String?,
        charactersIgnoringModifiers: String?,
        client sender: Any
    ) -> Bool {
        guard mappedEvent.phase == .down,
              !isQKeyDown,
              session.context.hasCandidates else {
            return false
        }

        if mappedEvent.key == .f || mappedEvent.key == .g {
            moveExpandedCandidateWindow(backward: mappedEvent.key == .f)
            updateCandidates()
            Self.writeInputEventLog(
                "\(source) candidatePanelNavigate keyCode=\(keyCodeDescription(keyCode)) chars=\(characters ?? "-") charsIgnoring=\(charactersIgnoringModifiers ?? "-") key=\(mappedEvent.key.rawValue) start=\(expandedCandidateStartIndex) activeRow=\(expandedActiveRowIndex)"
            )
            return true
        }

        guard candidatePanelPresentation == .expanded,
              let selectionIndex = mappedEvent.key.candidateIndex else {
            return false
        }

        let candidateIndex = expandedCandidateStartIndex
            + expandedActiveRowIndex * Self.expandedCandidateColumnCount
            + selectionIndex
        guard !session.expandedCandidateWindow(startingAt: candidateIndex, limit: 1).isEmpty else {
            return true
        }

        session.commitExpandedCandidate(at: candidateIndex)
        collapseCandidatePanel()
        synchronizeClientState(client: sender)
        Self.writeInputEventLog(
            "\(source) candidatePanelSelectExpanded keyCode=\(keyCodeDescription(keyCode)) key=\(mappedEvent.key.rawValue) candidateIndex=\(candidateIndex)"
        )
        return true
    }

    private func moveExpandedCandidateWindow(backward: Bool) {
        candidatePanelPresentation = .expanded
        expandedCandidateStartIndex = clampExpandedCandidateStartIndex(expandedCandidateStartIndex)

        let visibleCandidates = session.expandedCandidateWindow(
            startingAt: expandedCandidateStartIndex,
            limit: Self.expandedCandidateVisibleLimit
        )
        let visibleRowCount = expandedVisibleRowCount(for: visibleCandidates.count)
        guard visibleRowCount > 0 else {
            expandedActiveRowIndex = 0
            return
        }

        expandedActiveRowIndex = min(expandedActiveRowIndex, visibleRowCount - 1)
        if backward {
            if expandedActiveRowIndex > 0 {
                expandedActiveRowIndex -= 1
                return
            }

            let previousStartIndex = expandedCandidateStartIndex - Self.expandedCandidateVisibleLimit
            guard previousStartIndex >= 0 else {
                expandedActiveRowIndex = 0
                return
            }

            expandedCandidateStartIndex = previousStartIndex
            let previousCandidates = session.expandedCandidateWindow(
                startingAt: expandedCandidateStartIndex,
                limit: Self.expandedCandidateVisibleLimit
            )
            expandedActiveRowIndex = max(expandedVisibleRowCount(for: previousCandidates.count) - 1, 0)
            return
        }

        let nextRowStartInWindow = (expandedActiveRowIndex + 1) * Self.expandedCandidateColumnCount
        if nextRowStartInWindow < visibleCandidates.count {
            expandedActiveRowIndex += 1
            return
        }

        let nextStartIndex = expandedCandidateStartIndex + Self.expandedCandidateVisibleLimit
        if session.expandedCandidateWindow(startingAt: nextStartIndex, limit: 1).isEmpty {
            expandedActiveRowIndex = visibleRowCount - 1
        } else {
            expandedCandidateStartIndex = nextStartIndex
            expandedActiveRowIndex = 0
        }
    }

    private func clampExpandedCandidateStartIndex(_ startIndex: Int) -> Int {
        let alignedStartIndex = max(0, startIndex / Self.expandedCandidateVisibleLimit * Self.expandedCandidateVisibleLimit)
        guard !session.expandedCandidateWindow(startingAt: alignedStartIndex, limit: 1).isEmpty else {
            return 0
        }

        return alignedStartIndex
    }

    private func clampExpandedActiveRowIndex() {
        let visibleCandidates = session.expandedCandidateWindow(
            startingAt: expandedCandidateStartIndex,
            limit: Self.expandedCandidateVisibleLimit
        )
        let visibleRowCount = expandedVisibleRowCount(for: visibleCandidates.count)
        guard visibleRowCount > 0 else {
            expandedActiveRowIndex = 0
            return
        }

        expandedActiveRowIndex = min(max(expandedActiveRowIndex, 0), visibleRowCount - 1)
    }

    private func expandedVisibleRowCount(for candidateCount: Int) -> Int {
        guard candidateCount > 0 else {
            return 0
        }

        return Int(ceil(Double(candidateCount) / Double(Self.expandedCandidateColumnCount)))
    }

    private func collapseCandidatePanel() {
        candidatePanelPresentation = .compact
        expandedCandidateStartIndex = 0
        expandedActiveRowIndex = 0
    }

    private static func collapsesCandidatePanel(_ action: OneHandAction) -> Bool {
        switch action {
        case .inputT9Code,
             .inputDigit,
             .insertSyllableDelimiter,
             .deleteBackward,
             .selectCandidate,
             .commitFirstCandidate,
             .commitComposition,
             .cancelComposition:
            true
        default:
            false
        }
    }

    fileprivate func handleEventTapKey(
        _ mappedEvent: OneHandKeyEvent,
        keyCode: UInt16,
        characters: String?,
        charactersIgnoringModifiers: String?
    ) -> Bool {
        guard let sender = eventTapClient() else {
            Self.writeInputEventLog(
                "eventTap key=\(mappedEvent.key.rawValue) no client phase=\(mappedEvent.phase)"
            )
            return false
        }

        return handleMappedKeyEvent(
            mappedEvent,
            source: "eventTap",
            keyCode: keyCode,
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            client: sender
        )
    }

    private func eventTapClient() -> Any? {
        client() ?? activeInputClient
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
            Self.writeInputEventLog(
                "\(source) localAscii pass keyCode=\(keyCodeDescription(keyCode)) chars=\(characters ?? "-") key=\(mappedEvent.key.rawValue)"
            )
            return false
        }

        if hasMarkedText {
            clearMarkedText(client: sender)
            hasMarkedText = false
        }
        collapseCandidatePanel()
        hideCandidateWindow()
        perform(action, client: sender)
        Self.writeInputEventLog(
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

    private func isPhysicalQDown() -> Bool {
        CGEventSource.keyState(
            .combinedSessionState,
            key: CGKeyCode(kVK_ANSI_Q)
        )
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
        if candidates.isEmpty {
            collapseCandidatePanel()
        }

        var expandedCandidates: [String]
        if candidatePanelPresentation == .expanded {
            expandedCandidateStartIndex = clampExpandedCandidateStartIndex(expandedCandidateStartIndex)
            expandedCandidates = session.expandedCandidateWindow(
                startingAt: expandedCandidateStartIndex,
                limit: Self.expandedCandidateVisibleLimit
            )
            if expandedCandidateStartIndex == 0,
               expandedCandidates.count <= candidates.count {
                collapseCandidatePanel()
                expandedCandidates = []
            } else {
                clampExpandedActiveRowIndex()
            }
        } else {
            expandedCandidates = []
        }

        let controller = candidateWindowController
        let interactionController = candidatePanelInteractionController
        let inputClient = client()
        let imkServer = server()
        let presentation = candidatePanelPresentation
        let expandedStartIndex = expandedCandidateStartIndex
        let expandedActiveRowIndex = expandedActiveRowIndex
        MainActor.assumeIsolated {
            controller.update(
                candidates: candidates,
                expandedCandidates: expandedCandidates,
                expandedStartIndex: expandedStartIndex,
                expandedActiveRowIndex: expandedActiveRowIndex,
                presentation: presentation,
                server: imkServer,
                client: inputClient,
                onSelectCandidate: { visibleIndex, effectivePresentation in
                    interactionController.commitCandidate(
                        visibleIndex: visibleIndex,
                        presentation: effectivePresentation
                    )
                },
                onExpand: {
                    interactionController.expandCandidatePanel()
                }
            )
        }
    }

    @MainActor
    fileprivate func commitCandidateFromPanel(
        visibleIndex: Int,
        presentation: CandidatePanelPresentation
    ) {
        guard visibleIndex >= 0,
              let sender = client() else {
            return
        }

        switch presentation {
        case .compact:
            session.commitDisplayedCandidate(at: visibleIndex)
        case .expanded:
            session.commitExpandedCandidate(at: expandedCandidateStartIndex + visibleIndex)
        }

        collapseCandidatePanel()
        synchronizeClientState(client: sender)
    }

    @MainActor
    fileprivate func expandCandidatePanelFromMouse() {
        let displayedCount = session.displayedCandidates.count
        let available = session.expandedCandidateWindow(
            startingAt: 0,
            limit: max(displayedCount + 1, Self.expandedCandidateVisibleLimit)
        )
        guard available.count > displayedCount else {
            return
        }

        candidatePanelPresentation = .expanded
        expandedCandidateStartIndex = 0
        expandedActiveRowIndex = 0
        updateCandidates()
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
            let posted = Self.postSyntheticDelete()
            Self.writeInputLog(
                "sendCommand selector=\(NSStringFromSelector(selector)) via=syntheticDelete posted=\(posted)"
            )
        } else {
            Self.writeInputLog("sendCommand selector=\(NSStringFromSelector(selector)) unsupportedClient=\(type(of: sender))")
        }
    }

    @discardableResult
    fileprivate static func postSyntheticDelete() -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyCode = CGKeyCode(kVK_Delete)
        guard let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: true
        ), let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: false
        ) else {
            return false
        }
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
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

    fileprivate static func loadLexicon() -> OneHandLexicon {
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

    private static func loadBundledConfiguration() -> OneHandConfiguration {
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

    private static func loadConfiguration() -> OneHandConfiguration {
        LeftIOSymbolSettingsStore().effectiveConfiguration(
            base: loadBundledConfiguration()
        )
    }

    private static func makeSession() -> AnyOneHandSession {
        sessionBackendFactory.makeSession()
    }

    static func prewarmSessionBackend() {
        sessionBackendFactory.prewarm()
    }

    fileprivate static func writeInputLog(_ message: String) {
        inputLogLock.lock()
        defer { inputLogLock.unlock() }
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

    fileprivate static func writeInputEventLog(_ message: String) {
        guard inputEventLoggingEnabled else {
            return
        }
        writeInputLog(message)
    }
}

private final class LeftIOSessionBackendFactory: @unchecked Sendable {
    private enum Backend: Sendable {
        case rime(OneHandRimeDataProvider.Layout)
        case lexicon(OneHandLexicon)
    }

    private let queue = DispatchQueue(label: "io.github.cstcat.leftio.session-prewarm", qos: .userInitiated)
    private var backend: Backend?

    func prewarm() {
        queue.async { [self] in
            guard backend == nil else {
                return
            }
            backend = prepareBackend()
        }
    }

    func makeSession() -> AnyOneHandSession {
        let preparedBackend = queue.sync { [self] in
            let preparedBackend = backend ?? prepareBackend()
            backend = preparedBackend
            return preparedBackend
        }

        // Construct the long-lived session on the IMK caller thread. The
        // serial queue only protects/prepares the reusable backend state.
        switch preparedBackend {
        case let .rime(layout):
            do {
                let session = try OneHandRimeSession(
                    sharedDataDirectory: layout.sharedDataDirectory,
                    userDataDirectory: layout.userDataDirectory
                )
                LeftIOInputController.writeInputLog("session backend=librime")
                return AnyOneHandSession(session)
            } catch {
                return makeFallbackSession(after: error)
            }
        case let .lexicon(lexicon):
            LeftIOInputController.writeInputLog("session backend=indexed-lexicon")
            return AnyOneHandSession(OneHandLexiconSession(lexicon: lexicon))
        }
    }

    private func prepareBackend() -> Backend {
        do {
            let layout = try OneHandRimeDataProvider.prepareLayout()
            _ = try OneHandRimeSession(
                sharedDataDirectory: layout.sharedDataDirectory,
                userDataDirectory: layout.userDataDirectory
            )
            LeftIOInputController.writeInputLog("session prewarm backend=librime complete")
            return .rime(layout)
        } catch {
            let lexicon = LeftIOInputController.loadLexicon()
            LeftIOInputController.writeInputLog(
                "session prewarm librime unavailable error=\(error.localizedDescription); indexed lexicon ready"
            )
            return .lexicon(lexicon)
        }
    }

    private func makeFallbackSession(after error: Error) -> AnyOneHandSession {
        let lexicon = LeftIOInputController.loadLexicon()
        queue.sync { [self] in
            backend = .lexicon(lexicon)
        }
        LeftIOInputController.writeInputLog(
            "session librime unavailable error=\(error.localizedDescription); using indexed lexicon fallback"
        )
        return AnyOneHandSession(OneHandLexiconSession(lexicon: lexicon))
    }
}

// InputMethodKit delivers controller callbacks on the input method's main run
// loop. The event tap also refuses to route off-main before touching a
// controller, so transferring the weak UI interaction reference is safe.
extension LeftIOInputController: @unchecked Sendable {}

final class RKeyEventTap {
    private final class WeakControllerReference {
        weak var controller: LeftIOInputController?

        init(_ controller: LeftIOInputController) {
            self.controller = controller
        }
    }

    private static let inputSourceID = "io.github.cstcat.inputmethod.leftio.onehandt9"
    private static let bundleInputSourceID = "io.github.cstcat.inputmethod.leftio"
    // InputMethodKit may keep more than one controller alive while focus moves
    // between clients. Retain weak references to every active controller so a
    // temporary controller deactivating cannot erase the route to an older,
    // still-active client.
    nonisolated(unsafe) private static var activeControllers: [WeakControllerReference] = []
    nonisolated(unsafe) private static var eventTap: CFMachPort?
    nonisolated(unsafe) private static var runLoopSource: CFRunLoopSource?

    static func activateProcessWide() {
        ensureEventTap()
    }

    static func activate(controller: LeftIOInputController) {
        bind(controller: controller)
        ensureEventTap()
        LeftIOInputController.writeInputLog(
            "eventTapR controllerBound active=\(controller.isInputServerActive) currentSourceIsLeftIO=\(currentInputSourceIsLeftIO())"
        )
    }

    static func bind(controller: LeftIOInputController) {
        activeControllers.removeAll { reference in
            reference.controller == nil || reference.controller === controller
        }
        guard controller.isInputServerActive else {
            return
        }
        activeControllers.append(WeakControllerReference(controller))
    }

    @discardableResult
    static func applyConfigurationToActiveControllers(
        _ configuration: OneHandConfiguration
    ) -> Int {
        activeControllers.removeAll { reference in
            guard let controller = reference.controller else {
                return true
            }
            return !controller.isInputServerActive
        }

        var appliedCount = 0
        for reference in activeControllers {
            guard let controller = reference.controller else {
                continue
            }
            controller.applySymbolLayerConfiguration(configuration)
            appliedCount += 1
        }
        return appliedCount
    }

    private static func ensureEventTap() {
        if eventTap != nil {
            LeftIOInputController.writeInputLog("eventTapR active reused")
            return
        }

        LeftIOInputController.writeInputLog(
            "eventTapR permission listen=\(CGPreflightListenEventAccess()) accessibility=\(AXIsProcessTrusted())"
        )

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
        LeftIOInputController.writeInputLog("eventTapR enabled=\(CGEvent.tapIsEnabled(tap: tap))")
    }

    static func deactivate(controller: LeftIOInputController) {
        remove(controller: controller, reason: "deactivate")
    }

    static func close(controller: LeftIOInputController) {
        remove(controller: controller, reason: "close")
    }

    private static func remove(controller: LeftIOInputController, reason: String) {
        activeControllers.removeAll { reference in
            reference.controller == nil || reference.controller === controller
        }
        let fallback = currentActiveController()
        LeftIOInputController.writeInputLog(
            "eventTapR controllerRemoved reason=\(reason) fallback=\(fallback != nil) activeCount=\(activeControllers.count)"
        )
    }

    private static func currentActiveController() -> LeftIOInputController? {
        activeControllers.removeAll { reference in
            guard let controller = reference.controller else {
                return true
            }
            return !controller.isInputServerActive
        }
        return activeControllers.last?.controller
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

        let controller = currentActiveController()
        let hasActiveController = controller?.isInputServerActive == true
        guard hasActiveController || currentInputSourceIsLeftIO() else {
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

        guard Thread.isMainThread else {
            return Unmanaged.passUnretained(event)
        }

        if let controller,
           controller.isInputServerActive {
            LeftIOInputController.writeInputEventLog(
                "eventTap routeToController key=\(mappedEvent.key.rawValue) phase=\(mappedEvent.phase)"
            )
            let consumed: Bool
            if mappedEvent.key == .r, mappedEvent.phase == .down {
                consumed = controller.handleEventTapRKeyDown()
            } else {
                consumed = controller.handleEventTapKey(
                    mappedEvent,
                    keyCode: keyCode,
                    characters: characters,
                    charactersIgnoringModifiers: charactersIgnoringModifiers
                )
            }
            if consumed {
                return nil
            }
            if mappedEvent.key == .r, mappedEvent.phase == .down {
                let posted = LeftIOInputController.postSyntheticDelete()
                LeftIOInputController.writeInputEventLog(
                    "eventTapR fallbackSyntheticDelete noClient posted=\(posted)"
                )
                return posted ? nil : Unmanaged.passUnretained(event)
            }
            return Unmanaged.passUnretained(event)
        }

        if mappedEvent.key == .r {
            if mappedEvent.phase == .down {
                let posted = LeftIOInputController.postSyntheticDelete()
                LeftIOInputController.writeInputEventLog(
                    "eventTapR fallbackSyntheticDelete noController posted=\(posted)"
                )
                return posted ? nil : Unmanaged.passUnretained(event)
            }
            return Unmanaged.passUnretained(event)
        }

        DispatchQueue.main.async {
            LeftIOInputController.writeInputEventLog(
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
private final class CandidatePanelInteractionController {
    private weak var inputController: LeftIOInputController?

    init(inputController: LeftIOInputController) {
        self.inputController = inputController
    }

    func commitCandidate(
        visibleIndex: Int,
        presentation: CandidatePanelPresentation
    ) {
        inputController?.commitCandidateFromPanel(
            visibleIndex: visibleIndex,
            presentation: presentation
        )
    }

    func expandCandidatePanel() {
        inputController?.expandCandidatePanelFromMouse()
    }
}

@MainActor
private enum CandidatePanelPresentation {
    case compact
    case expanded
}

@MainActor
private final class CandidateWindowController {
    private var panel: NSPanel?
    private let contentView = CandidatePanelContentView()

    func update(
        candidates: [String],
        expandedCandidates: [String],
        expandedStartIndex: Int,
        expandedActiveRowIndex: Int,
        presentation: CandidatePanelPresentation,
        server: IMKServer?,
        client: (any IMKTextInput)?,
        onSelectCandidate: @escaping (Int, CandidatePanelPresentation) -> Void,
        onExpand: @escaping () -> Void
    ) {
        let visibleCandidates: [String]
        let effectivePresentation: CandidatePanelPresentation
        if presentation == .expanded,
           !expandedCandidates.isEmpty,
           (expandedStartIndex > 0 || expandedCandidates.count > candidates.count) {
            visibleCandidates = expandedCandidates
            effectivePresentation = .expanded
        } else {
            visibleCandidates = candidates
            effectivePresentation = .compact
        }

        guard !visibleCandidates.isEmpty else {
            hide()
            return
        }

        let panel = panel ?? makePanel()
        self.panel = panel
        contentView.configure(
            candidates: visibleCandidates,
            presentation: effectivePresentation,
            highlightedRowIndex: expandedActiveRowIndex,
            onSelectCandidate: { index in
                onSelectCandidate(index, effectivePresentation)
            },
            onExpand: onExpand
        )
        let size = contentView.preferredPanelSize
        let frame = NSRect(origin: origin(for: size, client: client), size: size)
        panel.setFrame(frame, display: false)
        panel.contentView?.frame = NSRect(origin: .zero, size: size)
        contentView.frame = NSRect(origin: .zero, size: size)
        contentView.needsLayout = true
        contentView.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        panel.orderFrontRegardless()
        LeftIOInputController.writeInputLog(
            "candidatePanel show count=\(visibleCandidates.count) expandedStart=\(expandedStartIndex) activeRow=\(expandedActiveRowIndex) requestedPresentation=\(presentation) effectivePresentation=\(effectivePresentation) frame=\(panel.frame)"
        )
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let effectView = NSVisualEffectView()
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 13
        effectView.layer?.borderWidth = 0.5
        effectView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.38).cgColor
        effectView.layer?.masksToBounds = true
        contentView.autoresizingMask = [.width, .height]
        effectView.addSubview(contentView)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentView.preferredPanelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = effectView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return panel
    }

    private func origin(for panelSize: NSSize, client: (any IMKTextInput)?) -> NSPoint {
        var lineRect = NSRect.zero
        _ = client?.attributes(forCharacterIndex: 0, lineHeightRectangle: &lineRect)
        if lineRect.width > 0 || lineRect.height > 0 {
            return clampedOrigin(anchorRect: lineRect, panelSize: panelSize)
        }

        let mouseLocation = NSEvent.mouseLocation
        let fallbackAnchor = NSRect(x: mouseLocation.x, y: mouseLocation.y, width: 1, height: 1)
        return clampedOrigin(anchorRect: fallbackAnchor, panelSize: panelSize)
    }

    private func clampedOrigin(anchorRect: NSRect, panelSize: NSSize) -> NSPoint {
        let screen = NSScreen.screens.first { screen in
            screen.frame.intersects(anchorRect)
        } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        let gap: CGFloat = 8

        let belowY = anchorRect.minY - panelSize.height - gap
        let aboveY = anchorRect.maxY + gap
        let minY = visibleFrame.minY + gap
        let maxY = max(minY, visibleFrame.maxY - panelSize.height - gap)
        let y: CGFloat
        if belowY >= minY {
            y = belowY
        } else if aboveY <= maxY {
            y = aboveY
        } else {
            y = min(max(belowY, minY), maxY)
        }

        let minX = visibleFrame.minX + gap
        let maxX = max(minX, visibleFrame.maxX - panelSize.width - gap)
        let x = min(max(anchorRect.minX, minX), maxX)
        return NSPoint(x: x, y: y)
    }
}

@MainActor
private final class CandidatePanelContentView: NSView {
    private let stackView = NSStackView()
    private let separatorView = NSView()
    private let chevronField = NSTextField(labelWithString: "⌄")
    private var presentation: CandidatePanelPresentation = .compact
    private var candidateCount = 0
    private var expandedColumnWidths: [CGFloat] = Array(repeating: 96, count: 4)
    private var onSelectCandidate: ((Int) -> Void)?
    private var onExpand: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupStackView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupStackView()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if presentation == .compact,
           !chevronField.isHidden,
           chevronField.frame.contains(point) {
            return self
        }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if presentation == .compact,
           !chevronField.isHidden,
           chevronField.frame.contains(point) {
            onExpand?()
            return
        }
        super.mouseDown(with: event)
    }

    var preferredPanelSize: NSSize {
        switch presentation {
        case .compact:
            let width = stackView.arrangedSubviews.reduce(CGFloat(0)) { partial, view in
                partial + view.intrinsicContentSize.width
            } + CGFloat(max(stackView.arrangedSubviews.count - 1, 0)) * stackView.spacing + 48
            return NSSize(width: max(width, 86), height: 44)
        case .expanded:
            let rows = max(Int(ceil(Double(candidateCount) / 4.0)), 1)
            let width = expandedColumnWidths.reduce(CGFloat(0), +) + 16
            return NSSize(width: max(width, 86), height: CGFloat(rows * 40 + 10))
        }
    }

    func configure(
        candidates: [String],
        presentation: CandidatePanelPresentation,
        highlightedRowIndex: Int,
        onSelectCandidate: @escaping (Int) -> Void,
        onExpand: @escaping () -> Void
    ) {
        self.presentation = presentation
        self.candidateCount = candidates.count
        self.onSelectCandidate = onSelectCandidate
        self.onExpand = onExpand
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        switch presentation {
        case .compact:
            configureCompact(candidates: candidates)
        case .expanded:
            configureExpanded(candidates: candidates, highlightedRowIndex: highlightedRowIndex)
        }

        needsLayout = true
    }

    override func layout() {
        super.layout()
        switch presentation {
        case .compact:
            stackView.frame = NSRect(x: 6, y: 5, width: max(0, bounds.width - 48), height: bounds.height - 10)
            separatorView.isHidden = false
            chevronField.isHidden = false
            separatorView.frame = NSRect(x: bounds.width - 35, y: 8, width: 1, height: bounds.height - 16)
            chevronField.frame = NSRect(x: bounds.width - 30, y: 6, width: 24, height: bounds.height - 12)
        case .expanded:
            stackView.frame = NSRect(x: 8, y: 5, width: max(0, bounds.width - 16), height: bounds.height - 10)
            separatorView.isHidden = true
            chevronField.isHidden = true
        }
    }

    private func setupStackView() {
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .gravityAreas
        stackView.spacing = 2
        addSubview(stackView)

        separatorView.wantsLayer = true
        separatorView.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        addSubview(separatorView)

        chevronField.alignment = .center
        chevronField.font = NSFont.systemFont(ofSize: 22, weight: .regular)
        chevronField.textColor = NSColor.secondaryLabelColor.withAlphaComponent(0.78)
        chevronField.toolTip = "展开候选"
        addSubview(chevronField)
    }

    private func configureCompact(candidates: [String]) {
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .gravityAreas
        stackView.spacing = 2

        for (index, candidate) in candidates.enumerated() {
            stackView.addArrangedSubview(
                CandidateItemView(
                    number: index + 1,
                    candidate: candidate,
                    isHighlighted: index == 0,
                    presentation: .compact,
                    onSelect: { [weak self] in
                        self?.onSelectCandidate?(index)
                    }
                )
            )
        }
    }

    private func configureExpanded(candidates: [String], highlightedRowIndex: Int) {
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.distribution = .fillEqually
        stackView.spacing = 0
        expandedColumnWidths = Self.columnWidths(for: candidates)

        let rows = stride(from: 0, to: candidates.count, by: 4).map { rowStart in
            Array(candidates[rowStart..<min(rowStart + 4, candidates.count)])
        }

        for (rowIndex, rowCandidates) in rows.enumerated() {
            let rowStack = NSStackView()
            rowStack.orientation = .horizontal
            rowStack.alignment = .centerY
            rowStack.distribution = .gravityAreas
            rowStack.spacing = 0
            rowStack.widthAnchor.constraint(equalToConstant: expandedColumnWidths.reduce(CGFloat(0), +)).isActive = true

            for columnIndex in 0..<4 {
                if rowCandidates.indices.contains(columnIndex) {
                    let itemView = CandidateItemView(
                        number: columnIndex + 1,
                        candidate: rowCandidates[columnIndex],
                        isHighlighted: rowIndex == highlightedRowIndex && columnIndex == 0,
                        presentation: .expanded,
                        onSelect: { [weak self] in
                            self?.onSelectCandidate?(rowIndex * 4 + columnIndex)
                        }
                    )
                    itemView.widthAnchor.constraint(equalToConstant: expandedColumnWidths[columnIndex]).isActive = true
                    rowStack.addArrangedSubview(itemView)
                } else {
                    let spacer = NSView()
                    spacer.widthAnchor.constraint(equalToConstant: expandedColumnWidths[columnIndex]).isActive = true
                    rowStack.addArrangedSubview(spacer)
                }
            }
            stackView.addArrangedSubview(rowStack)
        }
    }

    private static func columnWidths(for candidates: [String]) -> [CGFloat] {
        var widths = Array(repeating: CGFloat(74), count: 4)
        for (index, candidate) in candidates.enumerated() {
            let columnIndex = index % 4
            let candidateWidth = ceil(
                (candidate as NSString).size(
                    withAttributes: [
                        .font: NSFont.systemFont(ofSize: 21, weight: .medium)
                    ]
                ).width
            )
            widths[columnIndex] = max(widths[columnIndex], min(candidateWidth + 34, 180))
        }
        return widths
    }
}

@MainActor
private final class CandidateItemView: NSView {
    private let number: Int
    private let candidate: String
    private let isHighlighted: Bool
    private let presentation: CandidatePanelPresentation
    private let onSelect: (() -> Void)?
    private let numberField = NSTextField(labelWithString: "")
    private let candidateField = NSTextField(labelWithString: "")

    init(
        number: Int,
        candidate: String,
        isHighlighted: Bool,
        presentation: CandidatePanelPresentation,
        onSelect: (() -> Void)? = nil
    ) {
        self.number = number
        self.candidate = candidate
        self.isHighlighted = isHighlighted
        self.presentation = presentation
        self.onSelect = onSelect
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        self.number = 0
        self.candidate = ""
        self.isHighlighted = false
        self.presentation = .compact
        self.onSelect = nil
        super.init(coder: coder)
        setup()
    }

    override var intrinsicContentSize: NSSize {
        let candidateWidth = ceil((candidate as NSString).size(withAttributes: [.font: candidateField.font as Any]).width)
        switch presentation {
        case .compact:
            return NSSize(width: max(42, candidateWidth + 31), height: 34)
        case .expanded:
            return NSSize(width: 138, height: 38)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    @objc
    private func selectCandidate(_ recognizer: NSClickGestureRecognizer) {
        onSelect?()
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = presentation == .compact ? 10 : 8
        layer?.masksToBounds = true
        layer?.backgroundColor = isHighlighted
            ? NSColor.controlAccentColor.cgColor
            : NSColor.clear.cgColor
        toolTip = candidate
        addGestureRecognizer(
            NSClickGestureRecognizer(target: self, action: #selector(selectCandidate(_:)))
        )

        numberField.stringValue = "\(number)"
        numberField.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        numberField.textColor = isHighlighted
            ? NSColor.white.withAlphaComponent(0.86)
            : NSColor.secondaryLabelColor.withAlphaComponent(0.72)
        numberField.alignment = .right
        numberField.translatesAutoresizingMaskIntoConstraints = false

        candidateField.stringValue = candidate
        candidateField.font = NSFont.systemFont(
            ofSize: presentation == .compact ? 22 : 21,
            weight: .medium
        )
        candidateField.textColor = isHighlighted ? .white : .labelColor
        candidateField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(numberField)
        addSubview(candidateField)
        NSLayoutConstraint.activate([
            numberField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            numberField.widthAnchor.constraint(equalToConstant: 11),
            numberField.firstBaselineAnchor.constraint(equalTo: candidateField.firstBaselineAnchor, constant: -6),

            candidateField.leadingAnchor.constraint(equalTo: numberField.trailingAnchor, constant: 3),
            candidateField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            candidateField.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -0.5)
        ])
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
