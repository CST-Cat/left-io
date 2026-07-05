import Foundation

public final class OneHandRecordingSession: OneHandSession {
    public var context: OneHandContext
    public private(set) var appliedActions: [OneHandAction]
    public private(set) var clientActions: [OneHandClientAction]
    public var compositionText = ""
    public var displayedCandidates: [String] = []

    public init(
        context: OneHandContext = OneHandContext(),
        appliedActions: [OneHandAction] = [],
        clientActions: [OneHandClientAction] = []
    ) {
        self.context = context
        self.appliedActions = appliedActions
        self.clientActions = clientActions
    }

    public func apply(_ action: OneHandAction) {
        appliedActions.append(action)
    }

    public func takeClientActions() -> [OneHandClientAction] {
        defer {
            clientActions.removeAll()
        }
        return clientActions
    }

    public func commitCurrentComposition() {}

    public func commitDisplayedCandidate(matching text: String) {}

    public func setAsciiMode(_ enabled: Bool) {
        context.isAsciiMode = enabled
    }

    public func reset() {
        context = OneHandContext()
        compositionText = ""
        displayedCandidates.removeAll()
        resetActions()
    }

    public func resetActions() {
        appliedActions.removeAll()
        clientActions.removeAll()
    }
}
