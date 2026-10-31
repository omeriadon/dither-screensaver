import AppKit
import ScreenSaver

@objc(DitherScreenSaverViewController)
final class DitherScreenSaverViewController: ScreenSaverViewController {
    override func loadView() {
        NSLog("Dither: extension controller loading view")
        guard let saver = DitherScreenSaverView(frame: .zero, isPreview: false) else {
            NSLog("Dither: failed to create screen saver view")
            view = NSView(frame: .zero)
            return
        }

        saver.autoresizingMask = [.width, .height]
        view = saver
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        (view as? DitherScreenSaverView)?.startAnimation()
    }

    override func viewDidDisappear() {
        (view as? DitherScreenSaverView)?.stopAnimation()
        super.viewDidDisappear()
    }
}
