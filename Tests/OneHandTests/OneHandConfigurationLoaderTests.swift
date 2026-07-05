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
        """)

        XCTAssertEqual(configuration.symbols[.w], .text("，"))
        XCTAssertEqual(configuration.symbols[.e], .text("。"))
        XCTAssertEqual(configuration.symbols[.c], .text("……"))
        XCTAssertFalse(configuration.symbolLayerAutoReturns)
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
}
