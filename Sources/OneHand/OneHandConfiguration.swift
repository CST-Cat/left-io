import Foundation

public struct OneHandConfiguration: Equatable, Sendable {
    public var symbols: [OneHandKey: SymbolLayerEntry]
    public var symbolLayerAutoReturns: Bool

    public init(
        symbols: [OneHandKey: SymbolLayerEntry] = OneHandConfiguration.defaultSymbols,
        symbolLayerAutoReturns: Bool = true
    ) {
        self.symbols = symbols
        self.symbolLayerAutoReturns = symbolLayerAutoReturns
    }

    public static let defaultSymbols: [OneHandKey: SymbolLayerEntry] = [
        .w: .text(","),
        .e: .text("."),
        .a: .text("?"),
        .s: .text("!"),
        .d: .text("'"),
        .z: .text(";"),
        .x: .text(":"),
        .c: .text("/")
    ]
}

public enum SymbolLayerEntry: Equatable, Sendable {
    case text(String)
    case action(OneHandAction)
}
