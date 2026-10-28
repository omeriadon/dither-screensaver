import AppKit
import ScreenSaver

@objc(GeometryClockScreenSaverViewController)
final class GeometryClockScreenSaverViewController: ScreenSaverViewController {
    override func loadView() {
        NSLog("GeometryClock: extension controller loading view")
        guard let clock = BauhausClockView(frame: .zero, isPreview: false) else {
            NSLog("GeometryClock: failed to create clock view")
            view = NSView(frame: .zero)
            return
        }

        clock.autoresizingMask = [.width, .height]
        view = clock
    }
}
