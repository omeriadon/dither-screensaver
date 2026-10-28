import AppKit
import Metal
import QuartzCore

@main
enum MetalLayerCheck {
    static func main() {
        _ = NSApplication.shared
        guard let view = DitherScreenSaverView(frame: NSRect(x: 0, y: 0, width: 320, height: 180), isPreview: true),
              let layer = view.layer as? CAMetalLayer,
              layer.device != nil else {
            fatalError("The screen saver Metal layer has no graphics device")
        }
        print("MetalLayerCheck passed")
    }
}
