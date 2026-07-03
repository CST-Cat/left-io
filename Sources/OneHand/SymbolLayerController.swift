import Foundation

public struct SymbolLayerController: Equatable, Sendable {
    public private(set) var isActive = false
    public var configuration: OneHandConfiguration

    public init(configuration: OneHandConfiguration = OneHandConfiguration()) {
        self.configuration = configuration
    }

    public mutating func enter() -> OneHandAction {
        isActive = true
        return .enterSymbolLayer
    }

    public mutating func exit() -> OneHandAction {
        isActive = false
        return .exitSymbolLayer
    }

    public mutating func action(for key: OneHandKey) -> [OneHandAction]? {
        guard isActive else {
            return nil
        }

        if key == .q {
            return [exit()]
        }

        guard let entry = configuration.symbols[key] else {
            return nil
        }

        var actions: [OneHandAction]
        switch entry {
        case let .text(text):
            actions = [.insertText(text)]
        case let .action(action):
            actions = [action]
        }

        if configuration.symbolLayerAutoReturns {
            actions.append(exit())
        }

        return actions
    }
}
