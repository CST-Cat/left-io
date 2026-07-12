import Foundation

public enum OneHandAction: Equatable, Sendable {
    case enterSymbolLayer
    case exitSymbolLayer
    case enterNumericLayer
    case exitNumericLayer
    case insertSyllableDelimiter
    case inputT9Code(String)
    case inputDigit(Int)
    case insertText(String)
    case deleteBackward
    case pageUp
    case pageDown
    case selectCandidate(Int)
    case commitFirstCandidate
    case commitComposition
    case insertSpace
    case insertNewline
    case cancelPendingQPress
    case cancelComposition
}
