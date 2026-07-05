import XCTest
@testable import OneHand

final class OneHandStateMachineTests: XCTestCase {
    func testQEntersSymbolLayerWhenNotComposing() {
        var machine = OneHandStateMachine()

        XCTAssertEqual(machine.handle(.init(key: .q, phase: .down), context: .init()), [.enterSymbolLayer])
    }

    func testQInsertsSyllableDelimiterWhileComposing() {
        var machine = OneHandStateMachine()

        XCTAssertEqual(machine.handle(.init(key: .q, phase: .down), context: .init(isComposing: true)), [.insertSyllableDelimiter])
    }

    func testQExitsSymbolLayerWhenLayerIsActive() {
        var machine = OneHandStateMachine()

        _ = machine.handle(.init(key: .q, phase: .down), context: .init())

        XCTAssertEqual(machine.handle(.init(key: .q, phase: .down), context: .init()), [.exitSymbolLayer])
    }

    func testGridKeysEmitT9Codes() {
        var machine = OneHandStateMachine()

        XCTAssertEqual(machine.handle(.init(key: .w, phase: .down), context: .init()), [.inputT9Code("2")])
        XCTAssertEqual(machine.handle(.init(key: .c, phase: .down), context: .init()), [.inputT9Code("9")])
    }

    func testAuxiliaryKeysRouteToActions() {
        var machine = OneHandStateMachine()

        XCTAssertEqual(machine.handle(.init(key: .r, phase: .down), context: .init()), [.deleteBackward])
        XCTAssertEqual(machine.handle(.init(key: .v, phase: .down), context: .init()), [.commitComposition])
    }

    func testPageKeysPageOnlyWhenCandidatesExist() {
        var machine = OneHandStateMachine()

        XCTAssertEqual(machine.handle(.init(key: .f, phase: .down), context: .init(hasCandidates: true)), [.pageUp])
        XCTAssertEqual(machine.handle(.init(key: .g, phase: .down), context: .init(hasCandidates: true)), [.pageDown])
    }

    func testPageKeysFallbackToTraditionalSymbolsWithoutCandidates() {
        var machine = OneHandStateMachine()

        XCTAssertEqual(machine.handle(.init(key: .f, phase: .down), context: .init()), [.insertText("-")])
        XCTAssertEqual(machine.handle(.init(key: .g, phase: .down), context: .init()), [.insertText("=")])
        XCTAssertEqual(
            machine.handle(.init(key: .f, phase: .down, modifiers: .shift), context: .init()),
            [.insertText("——")]
        )
        XCTAssertEqual(
            machine.handle(.init(key: .f, phase: .down, modifiers: .shift), context: .init(isAsciiMode: true)),
            [.insertText("_")]
        )
        XCTAssertEqual(
            machine.handle(.init(key: .g, phase: .down, modifiers: .shift), context: .init()),
            [.insertText("+")]
        )
    }

    func testDigitKeysSelectFirstFourCandidates() {
        var machine = OneHandStateMachine()

        XCTAssertEqual(machine.handle(.init(key: .digit1, phase: .down), context: .init()), [.selectCandidate(0)])
        XCTAssertEqual(machine.handle(.init(key: .digit4, phase: .down), context: .init()), [.selectCandidate(3)])
    }

    func testCancelTransientStateClearsSymbolLayerAndPendingSpace() {
        var machine = OneHandStateMachine()

        _ = machine.handle(.init(key: .q, phase: .down), context: .init())
        _ = machine.handle(.init(key: .space, phase: .down), context: .init())

        XCTAssertEqual(machine.cancelTransientState(), [.cancelPendingSpace, .exitSymbolLayer])
    }

    func testEscapeCancelsTransientStateAndComposition() {
        var machine = OneHandStateMachine()

        _ = machine.handle(.init(key: .q, phase: .down), context: .init())
        _ = machine.handle(.init(key: .space, phase: .down), context: .init())

        XCTAssertEqual(
            machine.handle(.init(key: .escape, phase: .down), context: .init(isComposing: true)),
            [.cancelPendingSpace, .exitSymbolLayer, .cancelComposition]
        )
    }
}
