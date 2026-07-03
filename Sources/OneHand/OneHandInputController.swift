import Foundation

public final class OneHandInputController<Session: OneHandRimeSession> {
    private var stateMachine: OneHandStateMachine
    private let session: Session

    public init(session: Session, configuration: OneHandConfiguration = OneHandConfiguration()) {
        self.session = session
        self.stateMachine = OneHandStateMachine(configuration: configuration)
    }

    public func handle(_ event: OneHandKeyEvent) {
        let actions = stateMachine.handle(event, context: session.context)
        for action in actions {
            session.apply(action)
        }
    }

    public func cancelTransientState() {
        let actions = stateMachine.cancelTransientState()
        for action in actions {
            session.apply(action)
        }
    }
}
