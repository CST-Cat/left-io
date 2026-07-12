import Foundation

public struct NumericLayerController: Equatable, Sendable {
    public private(set) var isActive = false

    public init() {}

    public mutating func enter() -> OneHandAction {
        isActive = true
        return .enterNumericLayer
    }

    public mutating func exit() -> OneHandAction {
        isActive = false
        return .exitNumericLayer
    }

    public func action(for key: OneHandKey) -> OneHandAction? {
        guard isActive, let digit = key.numericLayerValue else {
            return nil
        }
        return .inputDigit(digit)
    }
}
