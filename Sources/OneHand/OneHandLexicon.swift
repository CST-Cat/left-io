import Foundation

public struct OneHandLexiconEntry: Equatable, Sendable {
    public var text: String
    public var code: String
    public var weight: Int

    public init(text: String, code: String, weight: Int) {
        self.text = text
        self.code = code
        self.weight = weight
    }
}

public struct OneHandLexicon: Sendable {
    public enum Error: Swift.Error, Equatable {
        case invalidEncoding
    }

    private let entries: [OneHandLexiconEntry]

    public init(entries: [OneHandLexiconEntry]) {
        self.entries = entries
    }

    public func candidates(matching code: String) -> [OneHandLexiconEntry] {
        guard !code.isEmpty else {
            return []
        }

        return entries
            .filter { $0.code.hasPrefix(code) }
            .sorted(by: { lhs, rhs in
                let lhsIsExact = lhs.code == code
                let rhsIsExact = rhs.code == code
                if lhsIsExact != rhsIsExact {
                    return lhsIsExact
                }
                if lhs.weight != rhs.weight {
                    return lhs.weight > rhs.weight
                }
                if lhs.code.count != rhs.code.count {
                    return lhs.code.count < rhs.code.count
                }
                return lhs.text < rhs.text
            })
    }

    public static func parse(rimeDictionary contents: String) -> OneHandLexicon {
        var entries: [OneHandLexiconEntry] = []

        for line in contents.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed == "---" || trimmed == "..." {
                continue
            }

            if trimmed.contains(":") && !trimmed.contains("\t") {
                continue
            }

            let columns = trimmed.split(separator: "\t", omittingEmptySubsequences: false)
            guard columns.count >= 2 else {
                continue
            }

            let text = String(columns[0]).trimmingCharacters(in: .whitespaces)
            let code = String(columns[1]).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, !code.isEmpty else {
                continue
            }

            let weight: Int
            if columns.count >= 3, let parsedWeight = Int(columns[2].trimmingCharacters(in: .whitespaces)) {
                weight = parsedWeight
            } else {
                weight = 100
            }

            entries.append(.init(text: text, code: code, weight: weight))
        }

        return OneHandLexicon(entries: entries)
    }

    public static func load(from url: URL) throws -> OneHandLexicon {
        let contents = try String(contentsOf: url, encoding: .utf8)
        return parse(rimeDictionary: contents)
    }

    public static let seed = OneHandLexicon(entries: [
        .init(text: "你", code: "64", weight: 1000),
        .init(text: "好", code: "426", weight: 1000),
        .init(text: "你好", code: "64'426", weight: 1000),
        .init(text: "我", code: "96", weight: 1000),
        .init(text: "是", code: "744", weight: 1000),
        .init(text: "的", code: "33", weight: 1000),
        .init(text: "了", code: "536", weight: 900),
        .init(text: "在", code: "924", weight: 900),
        .init(text: "不", code: "28", weight: 900),
        .init(text: "人", code: "736", weight: 800),
        .init(text: "中", code: "94664", weight: 800)
    ])
}
