import Foundation

public struct OneHandKeyboardModifierFlags: OptionSet, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let shift = Self(rawValue: 1 << 0)
    public static let capsLock = Self(rawValue: 1 << 1)
    public static let command = Self(rawValue: 1 << 2)
    public static let option = Self(rawValue: 1 << 3)
    public static let control = Self(rawValue: 1 << 4)
}
