import AppKit
import Foundation
import OneHand
import OneHandKeyboard

public enum OneHandMacKeyMapper {
    public static func event(from event: NSEvent) -> OneHandKeyEvent? {
        let phase: OneHandKeyPhase
        switch event.type {
        case .keyDown:
            phase = .down
        case .keyUp:
            phase = .up
        default:
            return nil
        }

        return map(
            keyCode: event.keyCode,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifierFlags: keyboardFlags(from: event.modifierFlags),
            phase: phase
        )
    }

    public static func map(
        keyCode: UInt16,
        charactersIgnoringModifiers: String?,
        modifierFlags: OneHandKeyboardModifierFlags,
        phase: OneHandKeyPhase
    ) -> OneHandKeyEvent? {
        OneHandPhysicalKeyMapper.map(
            keyCode: keyCode,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            modifierFlags: modifierFlags,
            phase: phase
        )
    }

    private static func keyboardFlags(from flags: NSEvent.ModifierFlags) -> OneHandKeyboardModifierFlags {
        var result: OneHandKeyboardModifierFlags = []
        if flags.contains(.shift) {
            result.insert(.shift)
        }
        if flags.contains(.capsLock) {
            result.insert(.capsLock)
        }
        if flags.contains(.command) {
            result.insert(.command)
        }
        if flags.contains(.option) {
            result.insert(.option)
        }
        if flags.contains(.control) {
            result.insert(.control)
        }
        return result
    }
}
