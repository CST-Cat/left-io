import AppKit
import Foundation
import InputMethodKit

private let connectionName = "LeftIO_1_Connection"
private let bundleIdentifier = "io.github.cstcat.leftio"

@main
final class LeftIOInputMethodApp: NSObject, NSApplicationDelegate {
    private var server: IMKServer?

    static func main() {
        let app = NSApplication.shared
        let delegate = LeftIOInputMethodApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        server = IMKServer(
            name: connectionName,
            bundleIdentifier: bundleIdentifier
        )
    }
}
