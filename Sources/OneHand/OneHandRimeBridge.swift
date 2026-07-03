import Foundation

public protocol OneHandSession: AnyObject {
    var context: OneHandContext { get }
    var compositionText: String { get }
    var displayedCandidates: [String] { get }
    func apply(_ action: OneHandAction)
    func takeClientActions() -> [OneHandClientAction]
}

public typealias OneHandRimeSession = OneHandSession
