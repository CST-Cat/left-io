import Foundation

public enum OneHandT9Encoder {
    private static let letterToCode: [Character: Character] = [
        "a": "2", "b": "2", "c": "2",
        "d": "3", "e": "3", "f": "3",
        "g": "4", "h": "4", "i": "4",
        "j": "5", "k": "5", "l": "5",
        "m": "6", "n": "6", "o": "6",
        "p": "7", "q": "7", "r": "7", "s": "7",
        "t": "8", "u": "8", "v": "8",
        "w": "9", "x": "9", "y": "9", "z": "9"
    ]

    public static func encode(_ pinyin: String) -> String? {
        let normalized = pinyin
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "u:", with: "v")
            .replacingOccurrences(of: "ü", with: "v")

        var result = ""
        for character in normalized {
            if character == " " || character == "'" {
                result.append("'")
                continue
            }
            guard let code = letterToCode[character] else {
                return nil
            }
            result.append(code)
        }
        return result
    }
}
