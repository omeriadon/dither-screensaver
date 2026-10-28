import AppKit

@main
final class SettingsPreviewHarness: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let view = DitherOptionsView(frame: NSRect(x: 0, y: 0, width: 760, height: 820))
        view.loadValues([
            "waveSpeed": 0.05,
            "waveFrequency": 3.0,
            "waveAmplitude": 0.3,
            "waveColor": "#F04438",
            "backgroundColor": "#000000",
            "colorNum": 4.0,
            "pixelSize": 5.0,
            "gap": 0.2,
            "cornerRadius": 0.35,
            "scale": 1.0,
            "contrast": 1.0,
            "brightness": 0.0,
            "palette": "#F04438, #B7A6E6, #8FE3C0",
            "dpr": 0.0,
            "disableAnimation": false,
            "intro": false,
            "transparent": false,
            "ditherMode": 0
        ])
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 820),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Dither Settings Preview"
        window.contentView = view
        window.center()
        window.makeKeyAndOrderFront(nil)
        view.beginPreview()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }
}
