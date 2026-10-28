import AppKit

@main
final class GeometryClockHost: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?

    static func main() {
        let application = NSApplication.shared
        let delegate = GeometryClockHost()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 190),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Dither Screen Saver"
        window.delegate = self

        let title = NSTextField(labelWithString: "Dither Screen Saver")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let description = NSTextField(wrappingLabelWithString: "Dither is installed as a macOS screen saver. Choose it in Wallpaper settings and use Options to adjust the effect.")
        description.textColor = .secondaryLabelColor

        let settingsButton = NSButton(title: "Open System Settings", target: self, action: #selector(openSettings))
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        settingsButton.imagePosition = .imageLeading
        settingsButton.setAccessibilityLabel("Open System Settings")

        let content = NSStackView(views: [title, description, settingsButton])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 16
        content.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(content)
        if let container = window.contentView {
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
                content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
                content.topAnchor.constraint(equalTo: container.topAnchor, constant: 24)
            ])
        }

        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}
