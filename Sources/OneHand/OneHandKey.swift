import Foundation

public enum OneHandKey: String, CaseIterable, Sendable {
    case q = "Q"
    case w = "W"
    case e = "E"
    case a = "A"
    case s = "S"
    case d = "D"
    case z = "Z"
    case x = "X"
    case c = "C"
    case r = "R"
    case f = "F"
    case g = "G"
    case v = "V"
    case space = "Space"
    case digit1 = "1"
    case digit2 = "2"
    case digit3 = "3"
    case digit4 = "4"
    case escape = "Escape"
    case other = "Other"

    public var t9Code: String? {
        switch self {
        case .w: "2"
        case .e: "3"
        case .a: "4"
        case .s: "5"
        case .d: "6"
        case .z: "7"
        case .x: "8"
        case .c: "9"
        default: nil
        }
    }

    public var numericChordValue: Int? {
        switch self {
        case .q: 1
        case .w: 2
        case .e: 3
        case .a: 4
        case .s: 5
        case .d: 6
        case .z: 7
        case .x: 8
        case .c: 9
        default: nil
        }
    }

    public var candidateIndex: Int? {
        switch self {
        case .digit1: 0
        case .digit2: 1
        case .digit3: 2
        case .digit4: 3
        default: nil
        }
    }

    public var isSymbolLayerSlot: Bool {
        switch self {
        case .w, .e, .a, .s, .d, .z, .x, .c:
            true
        default:
            false
        }
    }
}

public enum OneHandKeyPhase: Sendable {
    case down
    case up
}

public struct OneHandKeyEvent: Sendable, Equatable {
    public var key: OneHandKey
    public var phase: OneHandKeyPhase
    public var modifiers: OneHandKeyModifiers

    public init(
        key: OneHandKey,
        phase: OneHandKeyPhase,
        modifiers: OneHandKeyModifiers = []
    ) {
        self.key = key
        self.phase = phase
        self.modifiers = modifiers
    }

    public var isShiftModified: Bool {
        modifiers.contains(.shift)
    }
}

public struct OneHandKeyModifiers: OptionSet, Equatable, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let shift = Self(rawValue: 1 << 0)
    public static let capsLock = Self(rawValue: 1 << 1)
}
