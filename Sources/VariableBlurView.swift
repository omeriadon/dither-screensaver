import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import QuartzCore

/// The edge that receives the maximum blur radius.
public enum VariableBlurDirection {
    case top
    case bottom
    case left
    case right
}

/// An AppKit live backdrop whose blur radius varies across one edge.
///
/// The variable filter and backdrop layer are private macOS APIs. If either is
/// unavailable, this view remains a normal NSVisualEffectView instead of failing.
/// Credit: https://github.com/jtrivedi/VariableBlurView
public final class VariableBlurView: NSVisualEffectView {
    public var maxBlurRadius: CGFloat {
        didSet { updateVariableBlur() }
    }

    public var direction: VariableBlurDirection {
        didSet { updateVariableBlur() }
    }

    /// A negative value starts the maximum blur slightly before the edge.
    public var startOffset: CGFloat {
        didSet { updateVariableBlur() }
    }

    private let gradientSize = CGSize(width: 128, height: 128)

    public init(
        frame frameRect: NSRect = .zero,
        maxBlurRadius: CGFloat = 20,
        direction: VariableBlurDirection = .top,
        startOffset: CGFloat = 0
    ) {
        self.maxBlurRadius = maxBlurRadius
        self.direction = direction
        self.startOffset = startOffset
        super.init(frame: frameRect)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        maxBlurRadius = 20
        direction = .top
        startOffset = 0
        super.init(coder: coder)
        commonInit()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateBackingScale()
        updateVariableBlur()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateBackingScale()
    }

    private func commonInit() {
        blendingMode = .withinWindow
        material = .contentBackground
        state = .active
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Variable blur")
        updateVariableBlur()
    }

    private func updateVariableBlur() {
        guard let backdropLayer = findBackdropLayer() else {
            return
        }

        guard let filter = makeVariableBlurFilter() else {
            return
        }

        guard let mask = makeGradientMask() else {
            return
        }

        filter.setValue(max(0, maxBlurRadius), forKey: "inputRadius")
        filter.setValue(mask, forKey: "inputMaskImage")
        filter.setValue(true, forKey: "inputNormalizeEdges")
        backdropLayer.filters = [filter]
        updateBackingScale(for: backdropLayer)
    }

    private func makeVariableBlurFilter() -> NSObject? {
        guard let filterType = NSClassFromString("CAFilter") as? NSObject.Type else {
            return nil
        }

        let selector = NSSelectorFromString("filterWithType:")
        guard filterType.responds(to: selector),
              let result = filterType.perform(selector, with: "variableBlur"),
              let filter = result.takeUnretainedValue() as? NSObject else {
            return nil
        }
        return filter
    }

    private func makeGradientMask() -> CGImage? {
        let filter = CIFilter.linearGradient()
        filter.color0 = CIColor.black
        filter.color1 = CIColor.clear

        let width = gradientSize.width
        let height = gradientSize.height
        let offset = startOffset * max(width, height)

        switch direction {
        case .top:
            filter.point0 = CGPoint(x: width / 2, y: height)
            filter.point1 = CGPoint(x: width / 2, y: offset)
        case .bottom:
            filter.point0 = CGPoint(x: width / 2, y: 0)
            filter.point1 = CGPoint(x: width / 2, y: height - offset)
        case .left:
            filter.point0 = CGPoint(x: 0, y: height / 2)
            filter.point1 = CGPoint(x: width - offset, y: height / 2)
        case .right:
            filter.point0 = CGPoint(x: width, y: height / 2)
            filter.point1 = CGPoint(x: offset, y: height / 2)
        }

        guard let outputImage = filter.outputImage else {
            return nil
        }

        return CIContext().createCGImage(outputImage, from: CGRect(origin: .zero, size: gradientSize))
    }

    private func updateBackingScale(for backdropLayer: CALayer? = nil) {
        let layer = backdropLayer ?? findBackdropLayer()
        guard let layer,
              layer.responds(to: NSSelectorFromString("setScale:")) else {
            return
        }

        layer.setValue(window?.backingScaleFactor ?? 1, forKey: "scale")
    }

    private func findBackdropLayer() -> CALayer? {
        for subview in subviews {
            if let layer = findBackdropLayer(in: subview.layer) {
                return layer
            }
        }
        return findBackdropLayer(in: layer)
    }

    private func findBackdropLayer(in layer: CALayer?) -> CALayer? {
        guard let layer else {
            return nil
        }

        if NSStringFromClass(type(of: layer)).contains("CABackdropLayer") {
            return layer
        }

        for sublayer in layer.sublayers ?? [] {
            if let backdropLayer = findBackdropLayer(in: sublayer) {
                return backdropLayer
            }
        }
        return nil
    }
}
