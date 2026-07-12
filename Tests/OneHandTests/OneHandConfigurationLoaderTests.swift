import XCTest
@testable import OneHand

final class OneHandConfigurationLoaderTests: XCTestCase {
    func testParsesSymbolMappingsAndAutoReturn() throws {
        let configuration = try OneHandConfiguration.parse(yaml: """
        symbols:
          W: "，"
          E: "。"
          C: "……"
        auto_return: false
        q_tap_layer: numeric
        q_long_press_layer: symbol
        """)

        XCTAssertEqual(configuration.symbols[.w], .text("，"))
        XCTAssertEqual(configuration.symbols[.e], .text("。"))
        XCTAssertEqual(configuration.symbols[.c], .text("……"))
        XCTAssertFalse(configuration.symbolLayerAutoReturns)
        XCTAssertEqual(configuration.qTapLayer, .numeric)
        XCTAssertEqual(configuration.qLongPressLayer, .symbol)
    }

    func testIgnoresCommentsAndKeepsDefaultsForMissingSlots() throws {
        let configuration = try OneHandConfiguration.parse(yaml: """
        # symbol layer overrides
        symbols:
          W: "，"
        """)

        XCTAssertEqual(configuration.symbols[.w], .text("，"))
        XCTAssertEqual(configuration.symbols[.z], OneHandConfiguration.defaultSymbols[.z])
        XCTAssertTrue(configuration.symbolLayerAutoReturns)
        XCTAssertEqual(configuration.qTapLayer, .symbol)
        XCTAssertEqual(configuration.qLongPressLayer, .numeric)
    }

    func testParsesBuiltInSymbolLayerActions() throws {
        let configuration = try OneHandConfiguration.parse(yaml: """
        symbols:
          W: action:page_up
          E: "action:page_down"
          A: action:delete_backward
        """)

        XCTAssertEqual(configuration.symbols[.w], .action(.pageUp))
        XCTAssertEqual(configuration.symbols[.e], .action(.pageDown))
        XCTAssertEqual(configuration.symbols[.a], .action(.deleteBackward))
    }

    func testRejectsUnknownSymbolKeys() {
        XCTAssertThrowsError(try OneHandConfiguration.parse(yaml: """
        symbols:
          V: "\\n"
        """)) { error in
            XCTAssertEqual(error as? OneHandConfigurationLoader.Error, .invalidSymbolKey("V"))
        }
    }

    func testRejectsUnknownSymbolActions() {
        XCTAssertThrowsError(try OneHandConfiguration.parse(yaml: """
        symbols:
          W: action:launch_missiles
        """)) { error in
            XCTAssertEqual(error as? OneHandConfigurationLoader.Error, .invalidSymbolAction("launch_missiles"))
        }
    }

    func testRejectsUnknownInputLayer() {
        XCTAssertThrowsError(try OneHandConfiguration.parse(yaml: "q_long_press_layer: emoji")) { error in
            XCTAssertEqual(error as? OneHandConfigurationLoader.Error, .invalidInputLayer("emoji"))
        }
    }
}
