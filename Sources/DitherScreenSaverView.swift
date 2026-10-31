import AppKit
import Foundation
import Metal
import QuartzCore
import ScreenSaver
import simd

@objc(DitherScreenSaverView)
public final class DitherScreenSaverView: ScreenSaverView {
    private var renderer: DitherMetalRenderer?
    private var configuration = DitherConfiguration()
#if DITHER_APPEX
    private let settings = DitherSettings.shared
#endif

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        wantsLayer = true
        let metalLayer = CAMetalLayer()
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = true
        layer = metalLayer
        // Keep the host timer stable; static configurations skip GPU work in animateOneFrame.
        animationTimeInterval = 1.0 / 30.0
        do {
            renderer = try DitherMetalRenderer()
            metalLayer.device = renderer?.device
        } catch {
            NSLog("Dither: Metal renderer unavailable: %@", String(describing: error))
            metalLayer.backgroundColor = NSColor.black.cgColor
        }
#if DITHER_APPEX
        configuration = settings.configuration
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange),
            name: DitherSettings.didChangeNotification,
            object: nil
        )
#endif
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        renderer?.resetAnimationTiming()
        guard window != nil else {
            return
        }
        renderFrame(advance: false)
    }

    public override func startAnimation() {
        guard !isAnimating else {
            return
        }
        renderer?.resetAnimationTiming()
        renderer?.seedAnimationTiming()
        super.startAnimation()
        renderFrame(advance: false)
    }

    public override func stopAnimation() {
        super.stopAnimation()
        renderer?.resetAnimationTiming()
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        renderFrame(advance: false)
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        renderFrame(advance: false)
    }

    public override func animateOneFrame() {
        guard window != nil, !isHiddenOrHasHiddenAncestor else {
            renderer?.resetAnimationTiming()
            return
        }
        guard renderInterval != nil else {
            renderer?.resetAnimationTiming()
            return
        }
        renderFrame(advance: true)
    }

    public override func viewDidHide() {
        super.viewDidHide()
        renderer?.resetAnimationTiming()
    }

    public override func viewDidUnhide() {
        super.viewDidUnhide()
        renderer?.seedAnimationTiming()
        renderFrame(advance: false)
    }

    @objc private func settingsDidChange() {
#if DITHER_APPEX
        settings.reload()
        setConfiguration(settings.configuration)
#endif
    }

    func setConfiguration(_ configuration: DitherConfiguration) {
        guard self.configuration != configuration else {
            return
        }
        if !self.configuration.intro && configuration.intro {
            renderer?.restartIntro()
        }
        self.configuration = configuration
        renderer?.seedAnimationTiming()
        renderFrame(advance: false)
    }

    private var renderInterval: TimeInterval? {
        DitherRenderSchedulingPolicy.interval(
            for: configuration,
            introComplete: renderer?.isIntroComplete ?? true
        )
    }

    private func renderFrame(advance: Bool) {
        guard window != nil,
              !isHiddenOrHasHiddenAncestor,
              let metalLayer = layer as? CAMetalLayer,
              bounds.width > 0,
              bounds.height > 0 else {
            return
        }
        let ratio = window?.backingScaleFactor ?? 1
        metalLayer.contentsScale = ratio
        let drawableSize = CGSize(width: bounds.width * ratio, height: bounds.height * ratio)
        if metalLayer.drawableSize != drawableSize {
            metalLayer.drawableSize = drawableSize
        }
        guard let drawable = metalLayer.nextDrawable() else {
            return
        }
        do {
            guard let renderer else {
                return
            }
            try renderer.render(to: drawable, size: bounds.size, configuration: configuration, advance: advance)
        } catch {
            NSLog("Dither: frame render failed: %@", String(describing: error))
            metalLayer.backgroundColor = NSColor.black.cgColor
        }
    }
}
