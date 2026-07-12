import Foundation
import XCTest
@testable import LeftIOInputMethod
import OneHand

final class InputLayerSettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "LeftIOInputLayerSettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testMissingPreferencesUseBundledGestureDefaults() {
        let base = OneHandConfiguration(qTapLayer: .symbol, qLongPressLayer: .numeric)

        let effective = LeftIOSymbolSettingsStore(defaults: defaults)
            .effectiveConfiguration(base: base)

        XCTAssertEqual(effective.qTapLayer, .symbol)
        XCTAssertEqual(effective.qLongPressLayer, .numeric)
    }

    func testGestureOverridesPersistAndReloadIndependently() {
        let base = OneHandConfiguration(qTapLayer: .symbol, qLongPressLayer: .numeric)
        let store = LeftIOSymbolSettingsStore(defaults: defaults)

        let saved = store.save(
            effectiveTextByKey: base.symbolLayerTextByKey,
            qTapLayer: .numeric,
            qLongPressLayer: .symbol,
            base: base
        )
        let reloaded = store.effectiveConfiguration(base: base)

        XCTAssertEqual(saved.qTapLayer, .numeric)
        XCTAssertEqual(saved.qLongPressLayer, .symbol)
        XCTAssertEqual(reloaded.qTapLayer, .numeric)
        XCTAssertEqual(reloaded.qLongPressLayer, .symbol)
        XCTAssertEqual(
            defaults.dictionary(forKey: LeftIOSymbolSettingsStore.qGesturePreferenceKey) as? [String: String],
            ["tap": "numeric", "longPress": "symbol"]
        )
    }

    func testSavingBundledGestureDefaultsRemovesOverridePreference() {
        let base = OneHandConfiguration(qTapLayer: .symbol, qLongPressLayer: .numeric)
        let store = LeftIOSymbolSettingsStore(defaults: defaults)
        defaults.set(
            ["tap": "numeric", "longPress": "symbol"],
            forKey: LeftIOSymbolSettingsStore.qGesturePreferenceKey
        )

        _ = store.save(
            effectiveTextByKey: base.symbolLayerTextByKey,
            qTapLayer: .symbol,
            qLongPressLayer: .numeric,
            base: base
        )

        XCTAssertNil(defaults.object(forKey: LeftIOSymbolSettingsStore.qGesturePreferenceKey))
    }
}
