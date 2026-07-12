import XCTest
@testable import OneHand

final class OneHandSymbolCustomizationTests: XCTestCase {
    func testPropertyListIgnoresReservedAndUnknownKeys() {
        let customization = OneHandSymbolCustomization(propertyList: [
            "W": "《",
            "q": "reserved",
            "V": "unknown",
            "E": "",
            "A": "line\nbreak",
            "D": "line\u{2028}separator"
        ])

        XCTAssertEqual(customization.textByKey, [.w: "《"])
        XCTAssertEqual(customization.propertyList, ["W": "《"])
    }

    func testCustomizationOverlaysTextAndPreservesOtherConfiguration() {
        let base = OneHandConfiguration(
            symbols: [.w: .text("，"), .e: .action(.pageDown)],
            symbolLayerAutoReturns: false,
            qTapLayer: .numeric,
            qLongPressLayer: .symbol
        )

        let configured = OneHandSymbolCustomization(textByKey: [.w: "《"])
            .applying(to: base)

        XCTAssertEqual(configured.symbols[.w], .text("《"))
        XCTAssertEqual(configured.symbols[.e], .action(.pageDown))
        XCTAssertFalse(configured.symbolLayerAutoReturns)
        XCTAssertEqual(configured.qTapLayer, .numeric)
        XCTAssertEqual(configured.qLongPressLayer, .symbol)
    }

    func testOverridesOnlyPersistValuesDifferentFromBundledConfiguration() {
        let base = OneHandConfiguration(
            symbols: [.w: .text("，"), .e: .text("。")]
        )

        let customization = OneHandSymbolCustomization.overrides(
            effectiveTextByKey: [.w: "，", .e: "》"],
            comparedTo: base
        )

        XCTAssertEqual(customization.textByKey, [.e: "》"])
    }

    func testInputControllerAppliesUpdatedConfigurationImmediately() {
        let session = OneHandRecordingSession()
        let controller = OneHandInputController(
            session: session,
            configuration: OneHandConfiguration(symbols: [.w: .text("，")])
        )

        controller.updateConfiguration(
            OneHandConfiguration(symbols: [.w: .text("《")])
        )
        _ = controller.handle(.init(key: .q, phase: .down))
        _ = controller.handle(.init(key: .q, phase: .up))
        let result = controller.handle(.init(key: .w, phase: .down))

        XCTAssertEqual(result.actions, [.insertText("《"), .exitSymbolLayer])
    }
}
