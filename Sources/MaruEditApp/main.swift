import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.applicationIconImage = NSImage(named: "AppIcon")

// A command-line SwiftPM executable has no actor-isolated `main` declaration,
// but AppKit enters here on the process main thread and remains there for its
// event loop.
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
