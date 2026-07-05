import Foundation

public struct OneHandContext: Equatable, Sendable {
    public var isComposing: Bool
    public var hasCandidates: Bool
    public var isAsciiMode: Bool

    public init(
        isComposing: Bool = false,
        hasCandidates: Bool = false,
        isAsciiMode: Bool = false
    ) {
        self.isComposing = isComposing
        self.hasCandidates = hasCandidates
        self.isAsciiMode = isAsciiMode
    }
}
