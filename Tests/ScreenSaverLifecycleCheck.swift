import AppKit
import Darwin

@main
enum ScreenSaverLifecycleCheck {
    static func main() {
        _ = NSApplication.shared

        guard let firstSaver = DitherScreenSaverView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 180),
            isPreview: true
        ) else {
            fatalError("Could not create screen saver view")
        }

        guard let secondSaver = DitherScreenSaverView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 180),
            isPreview: true
        ) else {
            fatalError("Could not create second screen saver view")
        }

        let firstWindow = makeWindow()
        let secondWindow = makeWindow()
        firstWindow.contentView = firstSaver
        secondWindow.contentView = secondSaver

        firstSaver.startAnimation()
        secondSaver.startAnimation()
        // Duplicate starts must not reset either active intro's timing.
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        firstSaver.startAnimation()
        secondSaver.startAnimation()

        RunLoop.main.run(until: Date().addingTimeInterval(2.2))
        assertIntroCompleted(for: firstSaver)
        assertIntroCompleted(for: secondSaver)

        var staticConfiguration = DitherConfiguration()
        staticConfiguration.intro = false
        staticConfiguration.waveSpeed = 0
        firstSaver.setConfiguration(staticConfiguration)
        secondSaver.setConfiguration(staticConfiguration)
        let firstStaticTime = animationTime(for: firstSaver)
        let secondStaticTime = animationTime(for: secondSaver)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        precondition(animationTime(for: firstSaver) == firstStaticTime)
        precondition(animationTime(for: secondSaver) == secondStaticTime)

        var movingConfiguration = staticConfiguration
        movingConfiguration.waveSpeed = DitherRenderSchedulingPolicy.referenceSpeed
        firstSaver.setConfiguration(movingConfiguration)
        secondSaver.setConfiguration(movingConfiguration)
        assertMotion(for: firstSaver, and: secondSaver)

        firstSaver.isHidden = true
        let hiddenTime = animationTime(for: firstSaver)
        let runningTime = animationTime(for: secondSaver)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        precondition(animationTime(for: firstSaver) == hiddenTime)
        precondition(animationTime(for: secondSaver) > runningTime)
        firstSaver.isHidden = false
        assertMotion(for: firstSaver, and: secondSaver)

        firstSaver.stopAnimation()
        let stoppedTime = animationTime(for: firstSaver)
        let peerTime = animationTime(for: secondSaver)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        precondition(animationTime(for: firstSaver) == stoppedTime)
        precondition(animationTime(for: secondSaver) > peerTime)
        firstSaver.startAnimation()
        assertMotion(for: firstSaver, and: secondSaver)

        firstWindow.contentView = nil
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        firstWindow.contentView = firstSaver
        assertMotion(for: firstSaver, and: secondSaver)

        firstSaver.stopAnimation()
        secondSaver.stopAnimation()
        firstWindow.close()
        secondWindow.close()
        print("ScreenSaverLifecycleCheck passed: two independent timers, configuration changes, and resume")
        exit(EXIT_SUCCESS)
    }

    private static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }

    private static func assertIntroCompleted(for saver: DitherScreenSaverView) {
        guard let reveal = findFloat(named: "reveal", in: Mirror(reflecting: saver)) else {
            fatalError("Could not inspect renderer reveal state")
        }
        guard reveal >= 0.99 else {
            fatalError("Screen saver animation did not advance: reveal=\(reveal)")
        }
    }

    private static func animationTime(for saver: DitherScreenSaverView) -> Float {
        guard let time = findFloat(named: "time", in: Mirror(reflecting: saver)) else {
            fatalError("Could not inspect renderer animation time")
        }
        return time
    }

    private static func assertMotion(
        for first: DitherScreenSaverView,
        and second: DitherScreenSaverView
    ) {
        let firstTime = animationTime(for: first)
        let secondTime = animationTime(for: second)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        precondition(animationTime(for: first) > firstTime, "First display stopped")
        precondition(animationTime(for: second) > secondTime, "Second display stopped")
    }

    private static func findFloat(named name: String, in mirror: Mirror) -> Float? {
        for child in mirror.children {
            if child.label == name, let value = child.value as? Float {
                return value
            }
            if let value = findFloat(named: name, in: Mirror(reflecting: child.value)) {
                return value
            }
        }
        return nil
    }
}
