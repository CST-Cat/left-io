import Foundation

public struct OneHandStateMachine: Equatable, Sendable {
    public var spaceChord = SpaceChordController()
    public var symbolLayer: SymbolLayerController

    public init(configuration: OneHandConfiguration = OneHandConfiguration()) {
        self.symbolLayer = SymbolLayerController(configuration: configuration)
    }

    public mutating func handle(_ event: OneHandKeyEvent, context: OneHandContext) -> [OneHandAction] {
        switch event.phase {
        case .down:
            return handleKeyDown(event, context: context)
        case .up:
            return handleKeyUp(event.key, context: context)
        }
    }

    public mutating func cancelTransientState() -> [OneHandAction] {
        var actions: [OneHandAction] = []
        if let action = spaceChord.cancel() {
            actions.append(action)
        }
        if symbolLayer.isActive {
            actions.append(symbolLayer.exit())
        }
        return actions
    }

    public mutating func cancelPendingSpace() -> [OneHandAction] {
        guard let action = spaceChord.cancel() else {
            return []
        }

        return [action]
    }

    private mutating func handleKeyDown(_ event: OneHandKeyEvent, context: OneHandContext) -> [OneHandAction] {
        let key = event.key

        if key == .space {
            spaceChord.begin()
            return []
        }

        if spaceChord.isHoldingSpace {
            if key == .escape {
                return routeNonSpaceKeyDown(event, context: context)
            }

            if let chord = spaceChord.chordAction(for: key) {
                return [chord]
            }

            var actions: [OneHandAction] = []
            if let standaloneSpace = spaceChord.end(context: context) {
                actions.append(standaloneSpace)
            }
            actions.append(contentsOf: routeNonSpaceKeyDown(event, context: context))
            return actions
        }

        return routeNonSpaceKeyDown(event, context: context)
    }

    private mutating func handleKeyUp(_ key: OneHandKey, context: OneHandContext) -> [OneHandAction] {
        guard key == .space else {
            return []
        }

        if let action = spaceChord.end(context: context) {
            return [action]
        }

        return []
    }

    private mutating func routeNonSpaceKeyDown(_ event: OneHandKeyEvent, context: OneHandContext) -> [OneHandAction] {
        let key = event.key

        if let symbolActions = symbolLayer.action(for: key) {
            return symbolActions
        }

        if key == .escape {
            var actions = cancelTransientState()
            if context.isComposing {
                actions.append(.cancelComposition)
            }
            return actions
        }

        if key == .q {
            if context.isComposing {
                return [.insertSyllableDelimiter]
            }

            return [symbolLayer.enter()]
        }

        if let code = key.t9Code {
            return [.inputT9Code(code)]
        }

        if let index = key.candidateIndex {
            return [.selectCandidate(index)]
        }

        switch key {
        case .r:
            return [.deleteBackward]
        case .f:
            if context.hasCandidates {
                return [.pageUp]
            }
            return [.insertText(fallbackTextForF(event: event, context: context))]
        case .g:
            if context.hasCandidates {
                return [.pageDown]
            }
            return [.insertText(event.isShiftModified ? "+" : "=")]
        case .v:
            return [.commitComposition]
        default:
            return []
        }
    }

    private func fallbackTextForF(event: OneHandKeyEvent, context: OneHandContext) -> String {
        guard event.isShiftModified else {
            return "-"
        }

        return context.isAsciiMode ? "_" : "——"
    }
}
