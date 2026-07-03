import Foundation
import OneHand

public enum OneHandPhysicalKeyMapper {
    public static let reservedModifierMask: OneHandKeyboardModifierFlags = [
        .command,
        .option,
        .control
    ]

    public static func map(
        keyCode: UInt16,
        charactersIgnoringModifiers: String?,
        modifierFlags: OneHandKeyboardModifierFlags,
        phase: OneHandKeyPhase
    ) -> OneHandKeyEvent? {
        if !modifierFlags.intersection(reservedModifierMask).isEmpty {
            return nil
        }

        let key = physicalKey(for: keyCode) ?? characterKey(for: charactersIgnoringModifiers)
        guard let key else {
            return nil
        }

        return OneHandKeyEvent(key: key, phase: phase)
    }

    private static func physicalKey(for keyCode: UInt16) -> OneHandKey? {
        return switch keyCode {
        case OneHandANSIKeyCode.q: .q
        case OneHandANSIKeyCode.w: .w
        case OneHandANSIKeyCode.e: .e
        case OneHandANSIKeyCode.a: .a
        case OneHandANSIKeyCode.s: .s
        case OneHandANSIKeyCode.d: .d
        case OneHandANSIKeyCode.z: .z
        case OneHandANSIKeyCode.x: .x
        case OneHandANSIKeyCode.c: .c
        case OneHandANSIKeyCode.r: .r
        case OneHandANSIKeyCode.f: .f
        case OneHandANSIKeyCode.g: .g
        case OneHandANSIKeyCode.v: .v
        case OneHandANSIKeyCode.space: .space
        case OneHandANSIKeyCode.digit1: .digit1
        case OneHandANSIKeyCode.digit2: .digit2
        case OneHandANSIKeyCode.digit3: .digit3
        case OneHandANSIKeyCode.digit4: .digit4
        default: nil
        }
    }

    private static func characterKey(for charactersIgnoringModifiers: String?) -> OneHandKey? {
        guard let first = charactersIgnoringModifiers?.lowercased().first else {
            return nil
        }

        return switch first {
        case "q": .q
        case "w": .w
        case "e": .e
        case "a": .a
        case "s": .s
        case "d": .d
        case "z": .z
        case "x": .x
        case "c": .c
        case "r": .r
        case "f": .f
        case "g": .g
        case "v": .v
        case " ": .space
        case "1": .digit1
        case "2": .digit2
        case "3": .digit3
        case "4": .digit4
        default: nil
        }
    }
}
