import Foundation

public enum OneHandConfigurationLoader {
    public enum Error: Swift.Error, Equatable {
        case invalidTopLevelKey(String)
        case invalidSymbolKey(String)
        case invalidSymbolAction(String)
        case invalidInputLayer(String)
        case invalidBoolean(String)
        case malformedSymbolLine(String)
    }

    public static func load(from url: URL) throws -> OneHandConfiguration {
        let contents = try String(contentsOf: url, encoding: .utf8)
        return try parse(yaml: contents)
    }

    public static func parse(yaml: String) throws -> OneHandConfiguration {
        var symbols = OneHandConfiguration.defaultSymbols
        var autoReturn = true
        var qTapLayer: OneHandInputLayer = .symbol
        var qLongPressLayer: OneHandInputLayer = .numeric
        var inSymbolsSection = false

        for rawLine in yaml.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            if !line.hasPrefix(" ") && !line.hasPrefix("\t") {
                inSymbolsSection = false
                if trimmed == "symbols:" {
                    inSymbolsSection = true
                    continue
                }
                if trimmed.hasPrefix("auto_return:") {
                    let value = trimmed.dropFirst("auto_return:".count)
                        .trimmingCharacters(in: .whitespaces)
                    guard let parsed = parseBoolean(value) else {
                        throw Error.invalidBoolean(String(value))
                    }
                    autoReturn = parsed
                    continue
                }
                if trimmed.hasPrefix("q_tap_layer:") {
                    let value = trimmed.dropFirst("q_tap_layer:".count)
                        .trimmingCharacters(in: .whitespaces)
                    qTapLayer = try parseInputLayer(value)
                    continue
                }
                if trimmed.hasPrefix("q_long_press_layer:") {
                    let value = trimmed.dropFirst("q_long_press_layer:".count)
                        .trimmingCharacters(in: .whitespaces)
                    qLongPressLayer = try parseInputLayer(value)
                    continue
                }
                throw Error.invalidTopLevelKey(trimmed)
            }

            guard inSymbolsSection else {
                throw Error.invalidTopLevelKey(trimmed)
            }

            let parts = trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                throw Error.malformedSymbolLine(trimmed)
            }

            let rawKey = parts[0].trimmingCharacters(in: .whitespaces).uppercased()
            guard let key = OneHandKey(rawValue: rawKey), key.isSymbolLayerSlot else {
                throw Error.invalidSymbolKey(rawKey)
            }

            let rawValue = parts[1].trimmingCharacters(in: .whitespaces)
            symbols[key] = try parseSymbolEntry(rawValue)
        }

        return OneHandConfiguration(
            symbols: symbols,
            symbolLayerAutoReturns: autoReturn,
            qTapLayer: qTapLayer,
            qLongPressLayer: qLongPressLayer
        )
    }

    private static func parseInputLayer(_ value: String) throws -> OneHandInputLayer {
        guard let layer = OneHandInputLayer(rawValue: value.lowercased()) else {
            throw Error.invalidInputLayer(value)
        }
        return layer
    }

    private static func parseBoolean(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "true", "yes", "on":
            true
        case "false", "no", "off":
            false
        default:
            nil
        }
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2 else {
            return value
        }

        let first = value.first
        let last = value.last
        guard (first == "\"" && last == "\"") || (first == "'" && last == "'") else {
            return value
        }

        var unquoted = String(value.dropFirst().dropLast())
        unquoted = unquoted.replacingOccurrences(of: #"\""#, with: "\"")
        unquoted = unquoted.replacingOccurrences(of: #"\'"#, with: "'")
        return unquoted
    }

    private static func parseSymbolEntry(_ rawValue: String) throws -> SymbolLayerEntry {
        let value = unquote(rawValue)
        guard value.hasPrefix("action:") else {
            return .text(value)
        }

        let actionName = value.dropFirst("action:".count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard let action = parseAction(actionName) else {
            throw Error.invalidSymbolAction(String(actionName))
        }

        return .action(action)
    }

    private static func parseAction(_ rawValue: String) -> OneHandAction? {
        switch rawValue.replacingOccurrences(of: "-", with: "_") {
        case "delete_backward":
            .deleteBackward
        case "page_up":
            .pageUp
        case "page_down":
            .pageDown
        case "commit_first_candidate":
            .commitFirstCandidate
        case "commit_composition":
            .commitComposition
        case "cancel_composition":
            .cancelComposition
        case "insert_space":
            .insertSpace
        case "insert_newline":
            .insertNewline
        default:
            nil
        }
    }
}

public extension OneHandConfiguration {
    static func load(from url: URL) throws -> OneHandConfiguration {
        try OneHandConfigurationLoader.load(from: url)
    }

    static func parse(yaml: String) throws -> OneHandConfiguration {
        try OneHandConfigurationLoader.parse(yaml: yaml)
    }
}
