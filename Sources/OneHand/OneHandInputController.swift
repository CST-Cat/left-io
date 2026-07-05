import Foundation

public final class OneHandInputController<Session: OneHandSession> {
    private var stateMachine: OneHandStateMachine
    private let session: Session

    public init(session: Session, configuration: OneHandConfiguration = OneHandConfiguration()) {
        self.session = session
        self.stateMachine = OneHandStateMachine(configuration: configuration)
    }

    @discardableResult
    public func handle(_ event: OneHandKeyEvent) -> OneHandHandleResult {
        let actions = stateMachine.handle(event, context: session.context)
        for action in actions {
            session.apply(action)
        }
        let isConsumed = event.key != .escape || !actions.isEmpty
        return OneHandHandleResult(actions: actions, isConsumed: isConsumed)
    }

    @discardableResult
    public func cancelTransientState() -> [OneHandAction] {
        let actions = stateMachine.cancelTransientState()
        for action in actions {
            session.apply(action)
        }
        return actions
    }

    @discardableResult
    public func cancelPendingSpace() -> [OneHandAction] {
        let actions = stateMachine.cancelPendingSpace()
        for action in actions {
            session.apply(action)
        }
        return actions
    }
}
