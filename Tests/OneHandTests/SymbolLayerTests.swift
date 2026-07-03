import XCTest
@testable import OneHand

final class SymbolLayerTests: XCTestCase {
    func testSymbolLayerInsertsConfiguredTextAndAutoReturns() {
        let configuration = OneHandConfiguration(symbols: [.w: .text("，")], symbolLayerAutoReturns: true)
        var machine = OneHandStateMachine(configuration: configuration)

        _ = machine.handle(.init(key: .q, phase: .down), context: .init())

        XCTAssertEqual(machine.handle(.init(key: .w, phase: .down), context: .init()), [
            .insertText("，"),
            .exitSymbolLayer
        ])
    }

    func testSymbolLayerCanStayActiveAfterInput() {
        let configuration = OneHandConfiguration(symbols: [.w: .text("，")], symbolLayerAutoReturns: false)
        var machine = OneHandStateMachine(configuration: configuration)

        _ = machine.handle(.init(key: .q, phase: .down), context: .init())

        XCTAssertEqual(machine.handle(.init(key: .w, phase: .down), context: .init()), [.insertText("，")])
        XCTAssertEqual(machine.handle(.init(key: .q, phase: .down), context: .init()), [.exitSymbolLayer])
    }
}
