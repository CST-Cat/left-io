import XCTest
import OneHand
@testable import OneHandKeyboard

final class OneHandPhysicalKeyMapperTests: XCTestCase {
    func testMapsANSIGridKeysByPhysicalKeyCode() {
        XCTAssertEqual(map(OneHandANSIKeyCode.q), .init(key: .q, phase: .down))
        XCTAssertEqual(map(OneHandANSIKeyCode.w), .init(key: .w, phase: .down))
        XCTAssertEqual(map(OneHandANSIKeyCode.e), .init(key: .e, phase: .down))
        XCTAssertEqual(map(OneHandANSIKeyCode.a), .init(key: .a, phase: .down))
        XCTAssertEqual(map(OneHandANSIKeyCode.s), .init(key: .s, phase: .down))
        XCTAssertEqual(map(OneHandANSIKeyCode.d), .init(key: .d, phase: .down))
        XCTAssertEqual(map(OneHandANSIKeyCode.z), .init(key: .z, phase: .down))
        XCTAssertEqual(map(OneHandANSIKeyCode.x), .init(key: .x, phase: .down))
        XCTAssertEqual(map(OneHandANSIKeyCode.c), .init(key: .c, phase: .down))
    }

    func testMapsAuxiliaryAndCandidateKeys() {
        XCTAssertEqual(map(OneHandANSIKeyCode.r), .init(key: .r, phase: .down))
        XCTAssertEqual(map(OneHandANSIKeyCode.f), .init(key: .f, phase: .down))
        XCTAssertEqual(map(OneHandANSIKeyCode.g), .init(key: .g, phase: .down))
        XCTAssertEqual(map(OneHandANSIKeyCode.v), .init(key: .v, phase: .down))
        XCTAssertEqual(map(OneHandANSIKeyCode.space), .init(key: .space, phase: .down))
        XCTAssertEqual(map(OneHandANSIKeyCode.digit1), .init(key: .digit1, phase: .down))
        XCTAssertEqual(map(OneHandANSIKeyCode.digit4), .init(key: .digit4, phase: .down))
    }

    func testPreservesKeyUpPhase() {
        let event = OneHandPhysicalKeyMapper.map(
            keyCode: OneHandANSIKeyCode.space,
            charactersIgnoringModifiers: " ",
            modifierFlags: [],
            phase: .up
        )

        XCTAssertEqual(event, .init(key: .space, phase: .up))
    }

    func testIgnoresCommandOptionAndControlModifiedEvents() {
        XCTAssertNil(map(OneHandANSIKeyCode.w, modifiers: .command))
        XCTAssertNil(map(OneHandANSIKeyCode.w, modifiers: .option))
        XCTAssertNil(map(OneHandANSIKeyCode.w, modifiers: .control))
    }

    func testAllowsShiftAndCapsLockModifiedEvents() {
        XCTAssertEqual(map(OneHandANSIKeyCode.w, modifiers: .shift), .init(key: .w, phase: .down))
        XCTAssertEqual(map(OneHandANSIKeyCode.w, modifiers: .capsLock), .init(key: .w, phase: .down))
    }

    func testFallsBackToCharactersForNonANSIKeyCodes() {
        let event = OneHandPhysicalKeyMapper.map(
            keyCode: 999,
            charactersIgnoringModifiers: "v",
            modifierFlags: [],
            phase: .down
        )

        XCTAssertEqual(event, .init(key: .v, phase: .down))
    }

    func testUnknownKeysReturnNil() {
        XCTAssertNil(OneHandPhysicalKeyMapper.map(
            keyCode: 999,
            charactersIgnoringModifiers: nil,
            modifierFlags: [],
            phase: .down
        ))
    }

    private func map(
        _ keyCode: UInt16,
        modifiers: OneHandKeyboardModifierFlags = []
    ) -> OneHandKeyEvent? {
        OneHandPhysicalKeyMapper.map(
            keyCode: keyCode,
            charactersIgnoringModifiers: nil,
            modifierFlags: modifiers,
            phase: .down
        )
    }
}
