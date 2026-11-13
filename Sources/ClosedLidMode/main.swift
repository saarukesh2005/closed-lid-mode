import AppKit

// LSUIElement in Info.plist plus .accessory here: a menu bar app with no Dock
// icon and no windows of its own.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
