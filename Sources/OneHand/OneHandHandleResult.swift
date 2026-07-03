import Foundation

public struct OneHandHandleResult: Equatable, Sendable {
    public var actions: [OneHandAction]
    public var isConsumed: Bool

    public init(actions: [OneHandAction], isConsumed: Bool) {
        self.actions = actions
        self.isConsumed = isConsumed
    }
}
