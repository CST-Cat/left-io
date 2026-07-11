import Foundation

public enum OneHandQFunctionKeyType: Equatable, Sendable {
    case enterSymbolLayer
    case exitSymbolLayer
    case insertSyllableDelimiter

    public static func resolve(
        isSymbolLayerActive: Bool,
        context: OneHandContext
    ) -> OneHandQFunctionKeyType {
        if isSymbolLayerActive {
            return .exitSymbolLayer
        }

        if context.isComposing {
            return .insertSyllableDelimiter
        }

        return .enterSymbolLayer
    }
}
