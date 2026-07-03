import AppKit
import Foundation
@preconcurrency import InputMethodKit
import OneHand
import OneHandAppKit

final class LeftIOInputController: IMKInputController {
    private lazy var session = OneHandLexiconSession(lexicon: Self.loadLexicon())
    private lazy var oneHandController = OneHandInputController(session: session)
    private var cachedCandidateWindow: IMKCandidates?

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let sender else {
            return false
        }

        guard let oneHandEvent = OneHandMacKeyMapper.event(from: event) else {
            return false
        }

        let result = oneHandController.handle(oneHandEvent)
        synchronizeClientState(client: sender)
        return result.isConsumed
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue | NSEvent.EventTypeMask.keyUp.rawValue)
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

        if let sender {
            synchronizeClientState(client: sender)
        }
    }

    override func deactivateServer(_ sender: Any!) {
        _ = oneHandController.cancelTransientState()
        session.commitCurrentComposition()

        if let sender {
            synchronizeClientState(client: sender)
            clearMarkedText(client: sender)
        }

        hideCandidateWindow()
        session.reset()
        super.deactivateServer(sender)
    }

    override func inputControllerWillClose() {
        _ = oneHandController.cancelTransientState()
        session.reset()
        hideCandidateWindow()
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
        for action in session.takeClientActions() {
            perform(action, client: sender)
        }

        if session.compositionText.isEmpty {
            clearMarkedText(client: sender)
        } else {
            setMarkedText(session.compositionText, client: sender)
        }

        updateCandidates()
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
        guard !candidates.isEmpty else {
            hideCandidateWindow()
            return
        }

        let candidateWindow: IMKCandidates
        if let cachedCandidateWindow {
            candidateWindow = cachedCandidateWindow
        } else {
            guard let server = server(),
                  let newWindow = IMKCandidates(
                server: server,
                panelType: kIMKSingleColumnScrollingCandidatePanel
            ) else {
                fatalError("Failed to create IMKCandidates")
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
            cachedCandidateWindow = newWindow
            candidateWindow = newWindow
        }

        candidateWindow.setCandidateData(candidates)
        if candidateWindow.isVisible() {
            candidateWindow.update()
        } else {
            candidateWindow.show(kIMKLocateCandidatesBelowHint)
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
        _ = (sender as AnyObject).perform(selector)
    }

    private func hideCandidateWindow() {
        cachedCandidateWindow?.hide()
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
}
