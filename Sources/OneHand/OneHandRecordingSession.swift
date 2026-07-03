import Foundation

public final class OneHandRecordingSession: OneHandRimeSession {
    public var context: OneHandContext
    public private(set) var appliedActions: [OneHandAction]

    public init(
        context: OneHandContext = OneHandContext(),
        appliedActions: [OneHandAction] = []
    ) {
        self.context = context
        self.appliedActions = appliedActions
    }

    public func apply(_ action: OneHandAction) {
        appliedActions.append(action)
    }

    public func resetActions() {
        appliedActions.removeAll()
    }
}
