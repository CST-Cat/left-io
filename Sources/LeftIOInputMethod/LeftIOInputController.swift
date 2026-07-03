import AppKit
import Foundation
import InputMethodKit
import OneHand
import OneHandAppKit

final class LeftIOInputController: IMKInputController, OneHandRimeSession {
    private var composition = ""
    private var symbolLayerActive = false

    var context: OneHandContext {
        OneHandContext(
            isComposing: !composition.isEmpty,
            hasCandidates: !composition.isEmpty
        )
    }

    private lazy var oneHandController = OneHandInputController(session: self)

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let sender else {
            return false
        }

        guard let oneHandEvent = OneHandMacKeyMapper.event(from: event) else {
            return false
        }

        let result = oneHandController.handle(oneHandEvent)
        refreshMarkedText(client: sender)
        return result.isConsumed
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue | NSEvent.EventTypeMask.keyUp.rawValue)
    }

    override func composedString(_ sender: Any!) -> Any! {
        composition
    }

    override func commitComposition(_ sender: Any!) {
        guard let sender else {
            return
        }

        commitCompositionBuffer(client: sender)
    }

    func apply(_ action: OneHandAction) {
        switch action {
        case .enterSymbolLayer:
            symbolLayerActive = true
        case .exitSymbolLayer:
            symbolLayerActive = false
        case .insertSyllableDelimiter:
            if !composition.isEmpty {
                composition.append("'")
            }
        case let .inputT9Code(code):
            composition.append(code)
        case let .inputDigit(digit):
            pendingClientAction = .insertText(String(digit))
        case let .insertText(text):
            pendingClientAction = .insertText(text)
        case .deleteBackward:
            if !composition.isEmpty {
                composition.removeLast()
            } else {
                pendingClientAction = .deleteBackward
            }
        case .pageUp, .pageDown:
            break
        case let .selectCandidate(index):
            commitCandidate(index: index)
        case .commitFirstCandidate:
            commitCandidate(index: 0)
        case .commitComposition:
            pendingClientAction = .commitComposition
        case .insertSpace:
            pendingClientAction = .insertText(" ")
        case .insertNewline:
            pendingClientAction = .insertText("\n")
        case .cancelPendingSpace:
            break
        }
    }

    private enum PendingClientAction {
        case insertText(String)
        case deleteBackward
        case commitComposition
    }

    private var pendingClientAction: PendingClientAction?

    private func refreshMarkedText(client sender: Any) {
        if let pendingClientAction {
            self.pendingClientAction = nil
            perform(pendingClientAction, client: sender)
        }

        guard !composition.isEmpty else {
            clearMarkedText(client: sender)
            return
        }

        setMarkedText(composition, client: sender)
    }

    private func perform(_ action: PendingClientAction, client sender: Any) {
        switch action {
        case let .insertText(text):
            insertText(text, client: sender)
        case .deleteBackward:
            sendCommand(#selector(NSResponder.deleteBackward(_:)), client: sender)
        case .commitComposition:
            commitCompositionBuffer(client: sender)
        }
    }

    private func commitCandidate(index: Int) {
        guard !composition.isEmpty else {
            return
        }

        pendingClientAction = .insertText(composition)
        composition.removeAll()
    }

    private func commitCompositionBuffer(client sender: Any) {
        guard !composition.isEmpty else {
            return
        }

        insertText(composition, client: sender)
        composition.removeAll()
        clearMarkedText(client: sender)
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
}
