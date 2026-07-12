import XCTest
@testable import OneHand

final class QGestureAndNumericLayerTests: XCTestCase {
    func testSpaceImmediatelyCommitsFirstCandidate() {
        var machine = OneHandStateMachine()

        XCTAssertEqual(
            machine.handle(.init(key: .space, phase: .down), context: .init(hasCandidates: true)),
            [.commitFirstCandidate]
        )
        XCTAssertEqual(
            machine.handle(.init(key: .space, phase: .up), context: .init(hasCandidates: true)),
            []
        )
    }

    func testSpaceImmediatelyInsertsSpaceWhenIdle() {
        var machine = OneHandStateMachine()

        XCTAssertEqual(
            machine.handle(.init(key: .space, phase: .down), context: .init()),
            [.insertSpace]
        )
        XCTAssertEqual(machine.handle(.init(key: .space, phase: .up), context: .init()), [])
    }

    func testSpaceAndGridKeyNoLongerFormNumericChord() {
        var machine = OneHandStateMachine()

        XCTAssertEqual(
            machine.handle(.init(key: .space, phase: .down), context: .init()),
            [.insertSpace]
        )
        XCTAssertEqual(
            machine.handle(.init(key: .w, phase: .down), context: .init()),
            [.inputT9Code("2")]
        )
    }

    func testDefaultQTapEntersSymbolLayerOnRelease() {
        var machine = OneHandStateMachine()

        XCTAssertEqual(machine.handle(.init(key: .q, phase: .down), context: .init()), [])
        XCTAssertEqual(
            machine.handle(.init(key: .q, phase: .up), context: .init()),
            [.enterSymbolLayer]
        )
    }

    func testDefaultQLongPressEntersNumericLayer() {
        var machine = OneHandStateMachine()

        _ = machine.handle(.init(key: .q, phase: .down), context: .init())

        XCTAssertEqual(machine.triggerQLongPress(context: .init()), [.enterNumericLayer])
        XCTAssertEqual(machine.handle(.init(key: .q, phase: .up), context: .init()), [])
    }

    func testNumericLayerOutputsFullPhysicalGrid() {
        var machine = OneHandStateMachine()
        _ = machine.handle(.init(key: .q, phase: .down), context: .init())
        _ = machine.triggerQLongPress(context: .init())
        _ = machine.handle(.init(key: .q, phase: .up), context: .init())

        XCTAssertEqual(machine.handle(.init(key: .q, phase: .down), context: .init()), [])
        XCTAssertEqual(machine.handle(.init(key: .q, phase: .up), context: .init()), [.inputDigit(1)])
        XCTAssertEqual(machine.handle(.init(key: .w, phase: .down), context: .init()), [.inputDigit(2)])
        XCTAssertEqual(machine.handle(.init(key: .e, phase: .down), context: .init()), [.inputDigit(3)])
        XCTAssertEqual(machine.handle(.init(key: .a, phase: .down), context: .init()), [.inputDigit(4)])
        XCTAssertEqual(machine.handle(.init(key: .s, phase: .down), context: .init()), [.inputDigit(5)])
        XCTAssertEqual(machine.handle(.init(key: .d, phase: .down), context: .init()), [.inputDigit(6)])
        XCTAssertEqual(machine.handle(.init(key: .z, phase: .down), context: .init()), [.inputDigit(7)])
        XCTAssertEqual(machine.handle(.init(key: .x, phase: .down), context: .init()), [.inputDigit(8)])
        XCTAssertEqual(machine.handle(.init(key: .c, phase: .down), context: .init()), [.inputDigit(9)])
    }

    func testLongPressQAgainExitsNumericLayer() {
        var machine = OneHandStateMachine()
        _ = machine.handle(.init(key: .q, phase: .down), context: .init())
        _ = machine.triggerQLongPress(context: .init())
        _ = machine.handle(.init(key: .q, phase: .up), context: .init())
        _ = machine.handle(.init(key: .q, phase: .down), context: .init())

        XCTAssertEqual(machine.triggerQLongPress(context: .init()), [.exitNumericLayer])
        XCTAssertEqual(machine.handle(.init(key: .q, phase: .up), context: .init()), [])
    }

    func testGridKeyWhileLongPressedQIsStillDownDoesNotEmitOne() {
        var machine = OneHandStateMachine()
        _ = machine.handle(.init(key: .q, phase: .down), context: .init())
        _ = machine.triggerQLongPress(context: .init())

        XCTAssertEqual(
            machine.handle(.init(key: .w, phase: .down), context: .init()),
            [.inputDigit(2)]
        )
        XCTAssertEqual(machine.handle(.init(key: .q, phase: .up), context: .init()), [])
    }

    func testTapAndLongPressLayersAreIndependentlyConfigurable() {
        let configuration = OneHandConfiguration(qTapLayer: .numeric, qLongPressLayer: .symbol)
        var tapMachine = OneHandStateMachine(configuration: configuration)
        _ = tapMachine.handle(.init(key: .q, phase: .down), context: .init())
        XCTAssertEqual(
            tapMachine.handle(.init(key: .q, phase: .up), context: .init()),
            [.enterNumericLayer]
        )

        var longPressMachine = OneHandStateMachine(configuration: configuration)
        _ = longPressMachine.handle(.init(key: .q, phase: .down), context: .init())
        XCTAssertEqual(longPressMachine.triggerQLongPress(context: .init()), [.enterSymbolLayer])
    }

    func testOverlappingQThenWResolvesTapBeforeW() {
        let configuration = OneHandConfiguration(symbols: [.w: .text("，")])
        var machine = OneHandStateMachine(configuration: configuration)
        _ = machine.handle(.init(key: .q, phase: .down), context: .init())

        XCTAssertEqual(
            machine.handle(.init(key: .w, phase: .down), context: .init()),
            [.enterSymbolLayer, .insertText("，"), .exitSymbolLayer]
        )
    }
}
