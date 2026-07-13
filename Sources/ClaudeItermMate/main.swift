import AppKit

// The executable entry point always runs on the main thread; assume main-actor
// isolation so the @MainActor AppDelegate can be constructed here.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run() // blocks until quit, keeping `delegate` alive for the app's lifetime
}
