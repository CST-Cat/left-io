import Foundation

public struct OneHandSymbolCustomization: Equatable, Sendable {
    public var textByKey: [OneHandKey: String]

    public init(textByKey: [OneHandKey: String] = [:]) {
        self.textByKey = textByKey.filter { key, text in
            key.isSymbolLayerSlot && Self.isValidSymbolText(text)
        }
    }

    public init(propertyList: [String: String]) {
        self.init(
            textByKey: Dictionary(uniqueKeysWithValues: propertyList.compactMap { rawKey, text in
                guard let key = OneHandKey(rawValue: rawKey.uppercased()),
                      key.isSymbolLayerSlot else {
                    return nil
                }
                return (key, text)
            })
        )
    }

    public var propertyList: [String: String] {
        Dictionary(uniqueKeysWithValues: textByKey.map { key, text in
            (key.rawValue, text)
        })
    }

    public static func isValidSymbolText(_ text: String) -> Bool {
        let disallowedCharacters = CharacterSet.controlCharacters.union(.newlines)
        return !text.isEmpty && text.rangeOfCharacter(from: disallowedCharacters) == nil
    }

    public func applying(to base: OneHandConfiguration) -> OneHandConfiguration {
        var configuration = base
        for key in OneHandKey.symbolLayerSlots {
            if let text = textByKey[key] {
                configuration.symbols[key] = .text(text)
            }
        }
        return configuration
    }

    public static func overrides(
        effectiveTextByKey: [OneHandKey: String],
        comparedTo base: OneHandConfiguration
    ) -> OneHandSymbolCustomization {
        var overrides: [OneHandKey: String] = [:]
        for key in OneHandKey.symbolLayerSlots {
            guard let effectiveText = effectiveTextByKey[key] else {
                continue
            }
            if base.symbols[key] != .text(effectiveText) {
                overrides[key] = effectiveText
            }
        }
        return OneHandSymbolCustomization(textByKey: overrides)
    }
}

public extension OneHandConfiguration {
    var symbolLayerTextByKey: [OneHandKey: String] {
        Dictionary(uniqueKeysWithValues: OneHandKey.symbolLayerSlots.compactMap { key in
            guard case let .text(text) = symbols[key] else {
                return nil
            }
            return (key, text)
        })
    }
}
