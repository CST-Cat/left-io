import Foundation

public enum OneHandClientAction: Equatable, Sendable {
    case insertText(String)
    case deleteBackward
}
