import Foundation

public struct SpaceChordController: Equatable, Sendable {
    public private(set) var isHoldingSpace = false
    public private(set) var didUseChord = false

    public init() {}

    public mutating func begin() {
        isHoldingSpace = true
        didUseChord = false
    }

    public mutating func chordAction(for key: OneHandKey) -> OneHandAction? {
        guard isHoldingSpace else {
            return nil
        }

        if key == .v {
            didUseChord = true
            return .insertNewline
        }

        if let digit = key.numericChordValue {
            didUseChord = true
            return .inputDigit(digit)
        }

        return nil
    }

    public mutating func end(context: OneHandContext) -> OneHandAction? {
        guard isHoldingSpace else {
            return nil
        }

        defer {
            isHoldingSpace = false
            didUseChord = false
        }

        if didUseChord {
            return nil
        }

        return context.hasCandidates ? .commitFirstCandidate : .insertSpace
    }

    public mutating func cancel() -> OneHandAction? {
        guard isHoldingSpace else {
            return nil
        }

        isHoldingSpace = false
        didUseChord = false
        return .cancelPendingSpace
    }
}
