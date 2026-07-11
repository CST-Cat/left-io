import XCTest
@testable import OneHand

final class SpaceChordTests: XCTestCase {
    func testSpaceAloneCommitsFirstCandidateWhenCandidatesExist() {
        var machine = OneHandStateMachine()

        XCTAssertEqual(machine.handle(.init(key: .space, phase: .down), context: .init(hasCandidates: true)), [])
        XCTAssertEqual(machine.handle(.init(key: .space, phase: .up), context: .init(hasCandidates: true)), [.commitFirstCandidate])
    }

    func testSpaceAloneInsertsSpaceWithoutCandidates() {
        var machine = OneHandStateMachine()

        _ = machine.handle(.init(key: .space, phase: .down), context: .init())

        XCTAssertEqual(machine.handle(.init(key: .space, phase: .up), context: .init()), [.insertSpace])
    }

    func testSpaceAloneCommitsCompositionEvenWithoutVisibleCandidates() {
        var machine = OneHandStateMachine()

        _ = machine.handle(.init(key: .space, phase: .down), context: .init(isComposing: true))

        XCTAssertEqual(
            machine.handle(.init(key: .space, phase: .up), context: .init(isComposing: true)),
            [.commitFirstCandidate]
        )
    }

    func testSpaceWithGridKeyInputsDigitAndSuppressesSpaceOnRelease() {
        var machine = OneHandStateMachine()

        _ = machine.handle(.init(key: .space, phase: .down), context: .init(hasCandidates: true))

        XCTAssertEqual(machine.handle(.init(key: .w, phase: .down), context: .init(hasCandidates: true)), [.inputDigit(2)])
        XCTAssertEqual(machine.handle(.init(key: .space, phase: .up), context: .init(hasCandidates: true)), [])
    }

    func testRepeatedSpaceDownDoesNotResetUsedChord() {
        var machine = OneHandStateMachine()

        _ = machine.handle(.init(key: .space, phase: .down), context: .init())
        XCTAssertEqual(machine.handle(.init(key: .w, phase: .down), context: .init()), [.inputDigit(2)])

        // Holding Space can emit repeated key-down events. They must not turn an
        // already-used chord back into a standalone Space press.
        _ = machine.handle(.init(key: .space, phase: .down), context: .init())

        XCTAssertEqual(machine.handle(.init(key: .space, phase: .up), context: .init()), [])
    }

    func testSpaceWithVInsertsNewline() {
        var machine = OneHandStateMachine()

        _ = machine.handle(.init(key: .space, phase: .down), context: .init())

        XCTAssertEqual(machine.handle(.init(key: .v, phase: .down), context: .init()), [.insertNewline])
        XCTAssertEqual(machine.handle(.init(key: .space, phase: .up), context: .init()), [])
    }

    func testNonChordKeyFlushesPendingSpaceBeforeRoutingKey() {
        var machine = OneHandStateMachine()

        _ = machine.handle(.init(key: .space, phase: .down), context: .init(hasCandidates: true))

        XCTAssertEqual(machine.handle(.init(key: .r, phase: .down), context: .init(hasCandidates: true)), [
            .commitFirstCandidate,
            .deleteBackward
        ])
    }

    func testNonChordPageKeyUsesPostCommitContext() {
        var machine = OneHandStateMachine()

        _ = machine.handle(
            .init(key: .space, phase: .down),
            context: .init(isComposing: true, hasCandidates: true)
        )

        XCTAssertEqual(
            machine.handle(
                .init(key: .f, phase: .down),
                context: .init(isComposing: true, hasCandidates: true)
            ),
            [.commitFirstCandidate, .insertText("-")]
        )
    }

    func testCancelPendingSpaceOnlyClearsSpaceChord() {
        var machine = OneHandStateMachine()

        _ = machine.handle(.init(key: .space, phase: .down), context: .init())

        XCTAssertEqual(machine.cancelPendingSpace(), [.cancelPendingSpace])
        XCTAssertEqual(machine.handle(.init(key: .w, phase: .down), context: .init()), [.inputT9Code("2")])
    }

    func testCancelPendingSpaceDoesNotExitSymbolLayer() {
        let configuration = OneHandConfiguration(symbols: [.w: .text("，")])
        var machine = OneHandStateMachine(configuration: configuration)

        _ = machine.handle(.init(key: .q, phase: .down), context: .init())
        _ = machine.handle(.init(key: .space, phase: .down), context: .init())

        XCTAssertEqual(machine.cancelPendingSpace(), [.cancelPendingSpace])
        XCTAssertEqual(machine.handle(.init(key: .w, phase: .down), context: .init()), [.insertText("，"), .exitSymbolLayer])
    }
}
