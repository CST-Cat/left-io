import Foundation

public protocol OneHandRimeSession {
    var context: OneHandContext { get }
    func apply(_ action: OneHandAction)
}
