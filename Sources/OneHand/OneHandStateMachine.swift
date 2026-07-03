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
            return handleKeyDown(event.key, context: context)
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

    private mutating func handleKeyDown(_ key: OneHandKey, context: OneHandContext) -> [OneHandAction] {
        if key == .space {
            spaceChord.begin()
            return []
        }

        if spaceChord.isHoldingSpace {
            if let chord = spaceChord.chordAction(for: key) {
                return [chord]
            }

            var actions: [OneHandAction] = []
            if let standaloneSpace = spaceChord.end(context: context) {
                actions.append(standaloneSpace)
            }
            actions.append(contentsOf: routeNonSpaceKeyDown(key, context: context))
            return actions
        }

        return routeNonSpaceKeyDown(key, context: context)
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

    private mutating func routeNonSpaceKeyDown(_ key: OneHandKey, context: OneHandContext) -> [OneHandAction] {
        if let symbolActions = symbolLayer.action(for: key) {
            return symbolActions
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
            return [.pageUp]
        case .g:
            return [.pageDown]
        case .v:
            return [.commitComposition]
        default:
            return []
        }
    }
}
