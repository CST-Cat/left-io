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

    func testSpaceWithGridKeyInputsDigitAndSuppressesSpaceOnRelease() {
        var machine = OneHandStateMachine()

        _ = machine.handle(.init(key: .space, phase: .down), context: .init(hasCandidates: true))

        XCTAssertEqual(machine.handle(.init(key: .w, phase: .down), context: .init(hasCandidates: true)), [.inputDigit(2)])
        XCTAssertEqual(machine.handle(.init(key: .space, phase: .up), context: .init(hasCandidates: true)), [])
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
}
