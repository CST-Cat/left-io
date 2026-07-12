import Foundation

public struct OneHandStateMachine: Equatable, Sendable {
    public private(set) var configuration: OneHandConfiguration
    public var symbolLayer: SymbolLayerController
    public var numericLayer = NumericLayerController()
    public private(set) var isQPressPending = false
    public private(set) var didTriggerQLongPress = false

    public init(configuration: OneHandConfiguration = OneHandConfiguration()) {
        self.configuration = configuration
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

    public mutating func triggerQLongPress(context: OneHandContext) -> [OneHandAction] {
        guard isQPressPending, !didTriggerQLongPress else {
            return []
        }

        didTriggerQLongPress = true
        return toggleLayer(configuration.qLongPressLayer)
    }

    public mutating func cancelTransientState() -> [OneHandAction] {
        var actions = cancelPendingQPress()
        if symbolLayer.isActive {
            actions.append(symbolLayer.exit())
        }
        if numericLayer.isActive {
            actions.append(numericLayer.exit())
        }
        return actions
    }

    public mutating func cancelPendingQPress() -> [OneHandAction] {
        guard isQPressPending else {
            return []
        }

        isQPressPending = false
        didTriggerQLongPress = false
        return [.cancelPendingQPress]
    }

    public mutating func updateConfiguration(_ configuration: OneHandConfiguration) {
        self.configuration = configuration
        symbolLayer.configuration = configuration
    }

    private mutating func handleKeyDown(_ event: OneHandKeyEvent, context: OneHandContext) -> [OneHandAction] {
        let key = event.key

        if key == .q {
            guard !isQPressPending else {
                return []
            }
            isQPressPending = true
            didTriggerQLongPress = false
            return []
        }

        if key == .escape {
            return routeKeyDown(event, context: context)
        }

        var actions: [OneHandAction] = []
        if isQPressPending {
            if didTriggerQLongPress {
                isQPressPending = false
                didTriggerQLongPress = false
            } else {
                actions.append(contentsOf: finishQTap(context: context))
            }
        }
        actions.append(contentsOf: routeKeyDown(event, context: context))
        return actions
    }

    private mutating func handleKeyUp(_ key: OneHandKey, context: OneHandContext) -> [OneHandAction] {
        guard key == .q, isQPressPending else {
            return []
        }

        if didTriggerQLongPress {
            isQPressPending = false
            didTriggerQLongPress = false
            return []
        }

        return finishQTap(context: context)
    }

    private mutating func finishQTap(context: OneHandContext) -> [OneHandAction] {
        isQPressPending = false
        didTriggerQLongPress = false

        if numericLayer.isActive {
            return [.inputDigit(1)]
        }

        if symbolLayer.isActive {
            return [symbolLayer.exit()]
        }

        if context.isComposing || context.hasCandidates {
            return [.insertSyllableDelimiter]
        }

        return activateLayer(configuration.qTapLayer)
    }

    private mutating func routeKeyDown(_ event: OneHandKeyEvent, context: OneHandContext) -> [OneHandAction] {
        let key = event.key

        if let numericAction = numericLayer.action(for: key) {
            return [numericAction]
        }

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

        if key == .space {
            return [(context.isComposing || context.hasCandidates) ? .commitFirstCandidate : .insertSpace]
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

    private mutating func toggleLayer(_ layer: OneHandInputLayer) -> [OneHandAction] {
        switch layer {
        case .symbol:
            if symbolLayer.isActive {
                return [symbolLayer.exit()]
            }
            return activateLayer(.symbol)
        case .numeric:
            if numericLayer.isActive {
                return [numericLayer.exit()]
            }
            return activateLayer(.numeric)
        }
    }

    private mutating func activateLayer(_ layer: OneHandInputLayer) -> [OneHandAction] {
        var actions: [OneHandAction] = []
        switch layer {
        case .symbol:
            if numericLayer.isActive {
                actions.append(numericLayer.exit())
            }
            if !symbolLayer.isActive {
                actions.append(symbolLayer.enter())
            }
        case .numeric:
            if symbolLayer.isActive {
                actions.append(symbolLayer.exit())
            }
            if !numericLayer.isActive {
                actions.append(numericLayer.enter())
            }
        }
        return actions
    }

    private func fallbackTextForF(event: OneHandKeyEvent, context: OneHandContext) -> String {
        guard event.isShiftModified else {
            return "-"
        }

        return context.isAsciiMode ? "_" : "——"
    }
}
