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

    func testUsesCurrentSessionContextForSpaceRelease() {
        let session = OneHandRecordingSession(context: .init(hasCandidates: true))
        let controller = OneHandInputController(session: session)

        XCTAssertEqual(controller.handle(.init(key: .space, phase: .down)), .init(actions: [], isConsumed: true))
        session.context.hasCandidates = false

        XCTAssertEqual(controller.handle(.init(key: .space, phase: .up)), .init(actions: [.insertSpace], isConsumed: true))
        XCTAssertEqual(session.appliedActions, [.insertSpace])
    }

    func testSymbolLayerActionsFlowThroughSession() {
        let configuration = OneHandConfiguration(symbols: [.w: .text("，")])
        let session = OneHandRecordingSession()
        let controller = OneHandInputController(session: session, configuration: configuration)

        XCTAssertEqual(controller.handle(.init(key: .q, phase: .down)), .init(actions: [.enterSymbolLayer], isConsumed: true))
        XCTAssertEqual(controller.handle(.init(key: .w, phase: .down)), .init(actions: [.insertText("，"), .exitSymbolLayer], isConsumed: true))
        XCTAssertEqual(session.appliedActions, [.enterSymbolLayer, .insertText("，"), .exitSymbolLayer])
    }

    func testSpaceChordSuppressesStandaloneSpaceAction() {
        let session = OneHandRecordingSession(context: .init(hasCandidates: true))
        let controller = OneHandInputController(session: session)

        XCTAssertEqual(controller.handle(.init(key: .space, phase: .down)), .init(actions: [], isConsumed: true))
        XCTAssertEqual(controller.handle(.init(key: .w, phase: .down)), .init(actions: [.inputDigit(2)], isConsumed: true))
        XCTAssertEqual(controller.handle(.init(key: .space, phase: .up)), .init(actions: [], isConsumed: true))
        XCTAssertEqual(session.appliedActions, [.inputDigit(2)])
    }

    func testCancelTransientStateReturnsAppliedCleanupActions() {
        let session = OneHandRecordingSession()
        let controller = OneHandInputController(session: session)

        _ = controller.handle(.init(key: .q, phase: .down))
        _ = controller.handle(.init(key: .space, phase: .down))

        XCTAssertEqual(controller.cancelTransientState(), [.cancelPendingSpace, .exitSymbolLayer])
        XCTAssertEqual(session.appliedActions, [.enterSymbolLayer, .cancelPendingSpace, .exitSymbolLayer])
    }
}
