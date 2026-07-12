import XCTest
@testable import OneHand

final class OneHandInputControllerTests: XCTestCase {
    func testReturnsAndAppliesActions() {
        let session = OneHandRecordingSession()
        let controller = OneHandInputController(session: session)

        let result = controller.handle(.init(key: .w, phase: .down))

        XCTAssertEqual(result, .init(actions: [.inputT9Code("2")], isConsumed: true))
        XCTAssertEqual(session.appliedActions, [.inputT9Code("2")])
    }

    func testSpaceUsesCurrentSessionContextOnKeyDown() {
        let session = OneHandRecordingSession(context: .init(hasCandidates: true))
        let controller = OneHandInputController(session: session)

        XCTAssertEqual(
            controller.handle(.init(key: .space, phase: .down)),
            .init(actions: [.commitFirstCandidate], isConsumed: true)
        )
        session.context.hasCandidates = false

        XCTAssertEqual(controller.handle(.init(key: .space, phase: .up)), .init(actions: [], isConsumed: true))
        XCTAssertEqual(session.appliedActions, [.commitFirstCandidate])
    }

    func testSpaceKeyDownUsesComposingStateEvenWithoutCandidates() {
        let session = OneHandRecordingSession(context: .init(isComposing: true))
        let controller = OneHandInputController(session: session)

        XCTAssertEqual(
            controller.handle(.init(key: .space, phase: .down)),
            .init(actions: [.commitFirstCandidate], isConsumed: true)
        )
        XCTAssertEqual(controller.handle(.init(key: .space, phase: .up)), .init(actions: [], isConsumed: true))
        XCTAssertEqual(session.appliedActions, [.commitFirstCandidate])
    }

    func testLongPressTriggerActionsFlowThroughSession() {
        let session = OneHandRecordingSession()
        let controller = OneHandInputController(session: session)

        _ = controller.handle(.init(key: .q, phase: .down))

        XCTAssertEqual(
            controller.triggerQLongPress(),
            .init(actions: [.enterNumericLayer], isConsumed: true)
        )
        XCTAssertEqual(session.appliedActions, [.enterNumericLayer])
    }

    func testSymbolLayerActionsFlowThroughSession() {
        let configuration = OneHandConfiguration(symbols: [.w: .text("，")])
        let session = OneHandRecordingSession()
        let controller = OneHandInputController(session: session, configuration: configuration)

        XCTAssertEqual(controller.handle(.init(key: .q, phase: .down)), .init(actions: [], isConsumed: true))
        XCTAssertEqual(controller.handle(.init(key: .q, phase: .up)), .init(actions: [.enterSymbolLayer], isConsumed: true))
        XCTAssertEqual(controller.handle(.init(key: .w, phase: .down)), .init(actions: [.insertText("，"), .exitSymbolLayer], isConsumed: true))
        XCTAssertEqual(session.appliedActions, [.enterSymbolLayer, .insertText("，"), .exitSymbolLayer])
    }

    func testSpaceDoesNotStartNumericChord() {
        let session = OneHandRecordingSession(context: .init(hasCandidates: true))
        let controller = OneHandInputController(session: session)

        XCTAssertEqual(controller.handle(.init(key: .space, phase: .down)), .init(actions: [.commitFirstCandidate], isConsumed: true))
        session.context = .init()
        XCTAssertEqual(controller.handle(.init(key: .w, phase: .down)), .init(actions: [.inputT9Code("2")], isConsumed: true))
        XCTAssertEqual(controller.handle(.init(key: .space, phase: .up)), .init(actions: [], isConsumed: true))
        XCTAssertEqual(session.appliedActions, [.commitFirstCandidate, .inputT9Code("2")])
    }

    func testCancelTransientStateReturnsAppliedCleanupActions() {
        let session = OneHandRecordingSession()
        let controller = OneHandInputController(session: session)

        _ = controller.handle(.init(key: .q, phase: .down))
        _ = controller.handle(.init(key: .q, phase: .up))
        _ = controller.handle(.init(key: .q, phase: .down))

        XCTAssertEqual(controller.cancelTransientState(), [.cancelPendingQPress, .exitSymbolLayer])
        XCTAssertEqual(session.appliedActions, [.enterSymbolLayer, .cancelPendingQPress, .exitSymbolLayer])
    }

    func testEscapePassesThroughWhenNothingNeedsCancellation() {
        let session = OneHandRecordingSession()
        let controller = OneHandInputController(session: session)

        XCTAssertEqual(controller.handle(.init(key: .escape, phase: .down)), .init(actions: [], isConsumed: false))
        XCTAssertTrue(session.appliedActions.isEmpty)
    }

    func testAuxiliaryKeysAreConsumedWithoutCandidates() {
        let session = OneHandRecordingSession()
        let controller = OneHandInputController(session: session)

        XCTAssertEqual(
            controller.handle(.init(key: .r, phase: .down)),
            .init(actions: [.deleteBackward], isConsumed: true)
        )
        XCTAssertEqual(
            controller.handle(.init(key: .f, phase: .down)),
            .init(actions: [.insertText("-")], isConsumed: true)
        )
        XCTAssertEqual(
            controller.handle(.init(key: .g, phase: .down, modifiers: .shift)),
            .init(actions: [.insertText("+")], isConsumed: true)
        )
        XCTAssertEqual(session.appliedActions, [.deleteBackward, .insertText("-"), .insertText("+")])
    }
}
