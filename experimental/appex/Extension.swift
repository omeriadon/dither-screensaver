import AppKit

@objc(GeometryClockScreenSaverExtension)
final class GeometryClockScreenSaverExtension: ScreenSaverExtension {
    override init() {
        super.init()
        NSLog("GeometryClock: extension initialized from %@", Bundle(for: type(of: self)).bundlePath)
    }
}
