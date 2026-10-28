import AppKit
import QuartzCore

final class DitherPreviewView: NSView {
    static let displayAspectRatio: CGFloat = 16.0 / 9.0

    private let metalLayer = CAMetalLayer()
    private var renderer: DitherMetalRenderer?
    private var timer: Timer?
    private var configuration = DitherConfiguration()
    private var isActive = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.contentsGravity = .resizeAspect
        metalLayer.backgroundColor = NSColor.black.cgColor
        metalLayer.cornerRadius = 16
        metalLayer.masksToBounds = true
        layer = metalLayer
        renderer = try? DitherMetalRenderer()
        metalLayer.device = renderer?.device
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Live dither preview")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    deinit {
        timer?.invalidate()
    }

    func setConfiguration(_ configuration: DitherConfiguration) {
        self.configuration = configuration
        renderFrame(advance: false)
    }

    func setActive(_ active: Bool) {
        isActive = active
        if active {
            startTimerIfNeeded()
            renderFrame(advance: false)
        } else {
            stopTimer()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopTimer()
        } else {
            startTimerIfNeeded()
            renderFrame(advance: false)
        }
    }

    override func viewDidHide() {
        super.viewDidHide()
        stopTimer()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        startTimerIfNeeded()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        renderFrame(advance: false)
    }

    private func startTimerIfNeeded() {
        guard isActive, window != nil, !isHidden, timer == nil else {
            return
        }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.renderFrame(advance: true)
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        renderer?.resetClock()
    }

    private func renderFrame(advance: Bool) {
        guard window != nil,
              bounds.width > 0,
              bounds.height > 0,
              let renderer else {
            return
        }
        let scale = window?.backingScaleFactor ?? 1
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        guard let drawable = metalLayer.nextDrawable() else {
            return
        }
        do {
            var previewConfiguration = configuration
            if let screenWidth = window?.screen?.frame.width, screenWidth > 0 {
                previewConfiguration.pixelSize *= Float(bounds.width / screenWidth)
            }
            try renderer.render(to: drawable, size: bounds.size, configuration: previewConfiguration, advance: advance)
        } catch {
            NSLog("GeometryClock: preview render failed: %@", String(describing: error))
        }
    }
}
