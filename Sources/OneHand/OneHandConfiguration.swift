import Foundation

public enum OneHandInputLayer: String, CaseIterable, Equatable, Sendable {
    case symbol
    case numeric
}

public struct OneHandConfiguration: Equatable, Sendable {
    public var symbols: [OneHandKey: SymbolLayerEntry]
    public var symbolLayerAutoReturns: Bool
    public var qTapLayer: OneHandInputLayer
    public var qLongPressLayer: OneHandInputLayer

    public init(
        symbols: [OneHandKey: SymbolLayerEntry] = OneHandConfiguration.defaultSymbols,
        symbolLayerAutoReturns: Bool = true,
        qTapLayer: OneHandInputLayer = .symbol,
        qLongPressLayer: OneHandInputLayer = .numeric
    ) {
        self.symbols = symbols
        self.symbolLayerAutoReturns = symbolLayerAutoReturns
        self.qTapLayer = qTapLayer
        self.qLongPressLayer = qLongPressLayer
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
