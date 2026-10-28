import AppKit

@objc(DitherScreenSaverExtension)
final class DitherScreenSaverExtension: ScreenSaverExtension {
    override init() {
        super.init()
        NSLog("Dither: extension initialized from %@", Bundle(for: type(of: self)).bundlePath)
    }
}
