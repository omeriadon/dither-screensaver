import AppKit
import SwiftUI

struct DitherOptionsValues {
    let textFields: [String: String]
    let checks: [String: Bool]
    let ditherMode: Int
}

private let lumePalette = [
    "#000000", "#FF2600", "#FF9300", "#BBB4FF", "#FFA5C2", "#85D4C1", "#46E1FC",
    "#FFD2A2", "#00F900", "#00FBCA", "#FFE100", "#78FBAB", "#00FCFF", "#FFFEFF"
]

private let lumeNames = [
    "Black", "Red", "Orange", "Lavender", "Pink", "Mint", "Sky",
    "Peach", "Green", "Teal", "Yellow", "Light green", "Aqua", "White"
]

private enum DitherOptionsError: LocalizedError {
    case invalidNumber(String)
    case invalidValue(String)
    case invalidColor(String)

    var errorDescription: String? {
        switch self {
        case let .invalidNumber(label):
            return "\(label) must be a finite number."
        case let .invalidValue(message):
            return message
        case let .invalidColor(label):
            return "\(label) must use the format #RRGGBB."
        }
    }
}

final class DitherOptionsModel: ObservableObject {
    @Published var textValues: [String: String] = [:]
    @Published var checks: [String: Bool] = [:]
    @Published var ditherMode = 0
    @Published var selectedColors: [Int] = []
    @Published var isMulticolor = false
    @Published var backgroundStyle = "black"
    @Published private(set) var configuration = DitherConfiguration()
    @Published private(set) var isPreviewActive = false
    @Published var scrollToken = UUID()

    var onCancel: (() -> Void)?
    var onSave: (() -> Void)?
    var onPreviewChanged: ((DitherConfiguration) -> Void)?

    private var originalText: [String: String] = [:]

    private let numericRules: [String: (label: String, minimum: Double?, maximum: Double?)] = [
        "waveSpeed": ("Wave speed", nil, nil),
        "waveFrequency": ("Wave frequency", 0.01, nil),
        "waveAmplitude": ("Wave amplitude", 0, nil),
        "colorNum": ("Color levels", 2, nil),
        "pixelSize": ("Pixel size", 1, 4096),
        "gap": ("Grid gap", 0, 0.45),
        "cornerRadius": ("Corner radius", 0, 0.5)
    ]

    func loadValues(_ values: [String: Any], configuration: DitherConfiguration = DitherConfiguration()) {
        self.configuration = configuration
        var loaded: [String: String] = [:]
        for key in numericRules.keys.sorted() + ["waveColor", "backgroundColor", "palette"] {
            let fallback: Any = key == "gap" ? configuration.gap : key == "cornerRadius" ? configuration.cornerRadius : ""
            loaded[key] = String(describing: values[key] ?? fallback)
        }
        textValues = loaded
        originalText = loaded
        checks = ["intro": values["intro"] as? Bool == true]
        ditherMode = values["ditherMode"] as? Int ?? 0
        backgroundStyle = values["backgroundStyle"] as? String ?? "custom"

        let palette = loaded["palette"]?.split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespaces).uppercased()
        } ?? []
        let wave = loaded["waveColor"]?.uppercased()
        let paletteIndices = palette.compactMap { lumePalette.firstIndex(of: $0) }
        if paletteIndices.count >= 2 {
            selectedColors = paletteIndices
            isMulticolor = true
        } else if let waveIndex = lumePalette.firstIndex(of: wave ?? "") {
            selectedColors = [waveIndex]
            isMulticolor = false
        } else {
            selectedColors = []
            isMulticolor = false
        }
        normalizeBackground()
        publishPreview()
        scrollToken = UUID()
    }

    func beginPreview() {
        isPreviewActive = true
    }

    func endPreview() {
        isPreviewActive = false
    }

    func scrollToTop() {
        scrollToken = UUID()
    }

    func setText(_ value: String, for key: String) {
        textValues[key] = value
        if key == "waveColor" {
            if let index = lumePalette.firstIndex(of: value.uppercased()) {
                selectedColors = [index]
                isMulticolor = false
            }
            normalizeBackground()
        }
        publishPreview()
    }

    func setSlider(_ value: Double, for key: String) {
        setText(String(format: "%.3f", value), for: key)
    }

    func selectColor(_ index: Int) {
        guard lumePalette.indices.contains(index) else {
            return
        }
        if isMulticolor {
            if let existing = selectedColors.firstIndex(of: index) {
                selectedColors.remove(at: existing)
            } else if selectedColors.count < 8 {
                selectedColors.append(index)
            }
        } else {
            selectedColors = [index]
        }
        applySelectedColors()
        publishPreview()
    }

    func setMulticolor(_ enabled: Bool) {
        isMulticolor = enabled
        if !enabled, let first = selectedColors.first {
            selectedColors = [first]
        }
        applySelectedColors()
        publishPreview()
    }

    func setBackgroundStyle(_ style: String) {
        backgroundStyle = style
        if selectedColors.contains(0), style != "white" {
            backgroundStyle = "white"
        }
        textValues["backgroundColor"] = backgroundHex
        publishPreview()
    }

    func values() throws -> DitherOptionsValues {
        var result = textValues
        for (key, rule) in numericRules {
            let raw = textValues[key] ?? ""
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let number = Double(value), number.isFinite else {
                if originalText[key] != raw {
                    throw DitherOptionsError.invalidNumber(rule.label)
                }
                continue
            }
            if originalText[key] != raw {
                if let minimum = rule.minimum, number < minimum {
                    throw DitherOptionsError.invalidValue("\(rule.label) must be at least \(minimum).")
                }
                if let maximum = rule.maximum, number > maximum {
                    throw DitherOptionsError.invalidValue("\(rule.label) must be at most \(maximum).")
                }
                result[key] = value
            }
        }
        for key in ["waveColor", "backgroundColor"] where originalText[key] != textValues[key] {
            guard NSColor(hexString: textValues[key] ?? "") != nil else {
                throw DitherOptionsError.invalidColor(key == "waveColor" ? "Wave color" : "Background color")
            }
        }
        let palette = textValues["palette"] ?? ""
        if originalText["palette"] != palette {
            try validatePalette(palette)
        }
        guard (0..<8).contains(ditherMode) else {
            throw DitherOptionsError.invalidValue("Choose a dither pattern.")
        }
        result["backgroundStyle"] = backgroundStyle
        return DitherOptionsValues(textFields: result, checks: checks, ditherMode: ditherMode)
    }

    private var backgroundHex: String {
        switch backgroundStyle {
        case "black":
            return "#000000"
        case "white":
            return "#FFFFFF"
        case "dim":
            return (NSColor(hexString: textValues["waveColor"] ?? "")?.withBrightness(0.2).hexString) ?? "#000000"
        default:
            return textValues["backgroundColor"] ?? "#000000"
        }
    }

    private func applySelectedColors() {
        guard let first = selectedColors.first else {
            textValues["palette"] = ""
            return
        }
        textValues["waveColor"] = lumePalette[first]
        textValues["palette"] = selectedColors.count >= 2
            ? selectedColors.map { lumePalette[$0] }.joined(separator: ", ")
            : ""
        normalizeBackground()
    }

    private func normalizeBackground() {
        if selectedColors.contains(0), backgroundStyle != "white" {
            backgroundStyle = "white"
        }
        textValues["backgroundColor"] = backgroundHex
    }

    private func validatePalette(_ value: String) throws {
        let colors = value.split(separator: ",", omittingEmptySubsequences: true)
        guard colors.count <= 8 else {
            throw DitherOptionsError.invalidValue("Palette supports at most 8 colors.")
        }
        for color in colors {
            guard NSColor(hexString: String(color).trimmingCharacters(in: .whitespacesAndNewlines)) != nil else {
                throw DitherOptionsError.invalidColor("Palette color")
            }
        }
    }

    private func publishPreview() {
        var result = configuration
        result.waveSpeed = number("waveSpeed", fallback: result.waveSpeed)
        result.waveFrequency = max(0.01, number("waveFrequency", fallback: result.waveFrequency))
        result.waveAmplitude = max(0, number("waveAmplitude", fallback: result.waveAmplitude))
        result.colorNum = max(2, number("colorNum", fallback: result.colorNum))
        result.pixelSize = min(4096, max(1, number("pixelSize", fallback: result.pixelSize)))
        result.gap = min(0.45, max(0, number("gap", fallback: result.gap)))
        result.cornerRadius = min(0.5, max(0, number("cornerRadius", fallback: result.cornerRadius)))
        result.waveColor = vectorColor(textValues["waveColor"], fallback: result.waveColor)
        result.backgroundColor = vectorColor(textValues["backgroundColor"], fallback: result.backgroundColor)
        switch backgroundStyle {
        case "black": result.backgroundColor = .zero
        case "white": result.backgroundColor = SIMD3<Float>(repeating: 1)
        case "dim": result.backgroundColor = result.waveColor * 0.2
        default: break
        }
        result.palette = textValues["palette"]?.split(separator: ",").compactMap {
            vectorColor(String($0), fallback: nil)
        } ?? []
        result.intro = false
        result.transparent = false
        result.ditherMode = ditherMode
        configuration = result
        onPreviewChanged?(result)
    }

    private func number(_ key: String, fallback: Float) -> Float {
        guard let value = Float(textValues[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""), value.isFinite else {
            return fallback
        }
        return value
    }

    private func vectorColor(_ value: String?, fallback: SIMD3<Float>?) -> SIMD3<Float> {
        guard let color = value.flatMap(NSColor.init(hexString:)) else {
            return fallback ?? .zero
        }
        return SIMD3<Float>(Float(color.redComponent), Float(color.greenComponent), Float(color.blueComponent))
    }
}

struct DitherOptionsView: View {
    @ObservedObject var model: DitherOptionsModel

    var body: some View {
        if #available(macOS 26, *) {
            content
                .safeAreaBar(edge: .top) { preview }
                .safeAreaBar(edge: .bottom) { footer }
                .scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            content
                .safeAreaInset(edge: .top) { preview }
                .safeAreaInset(edge: .bottom) { footer }
        }
    }

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Color.clear.frame(height: 1).id("top")
                    MotionSection(model: model)
                    PatternSection(model: model)
                    ColorSection(model: model)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
            }
            .onChange(of: model.scrollToken) { _ in
                proxy.scrollTo("top", anchor: .top)
            }
        }
    }

    private var preview: some View {
        DitherPreviewRepresentable(
            configuration: model.configuration,
            isActive: model.isPreviewActive
        )
            .aspectRatio(DitherPreviewView.displayAspectRatio, contentMode: .fit)
            .frame(maxWidth: 460)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 14)
    }

    private var footer: some View {
        DitherFooter(model: model)
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
    }
}

private struct MotionSection: View {
    @ObservedObject var model: DitherOptionsModel

    var body: some View {
        DitherSection(title: "Motion", symbol: "waveform.path.ecg") {
            DitherSlider(model: model, title: "Wave speed", key: "waveSpeed", range: -1...1, fallback: 0.05)
            DitherSlider(model: model, title: "Wave frequency", key: "waveFrequency", range: 0.01...12, fallback: 3)
            DitherSlider(model: model, title: "Wave amplitude", key: "waveAmplitude", range: 0...1, fallback: 0.3)
            Toggle("Intro reveal", isOn: checkBinding(model, key: "intro"))
                .accessibilityIdentifier("intro")
        }
    }
}

private struct PatternSection: View {
    @ObservedObject var model: DitherOptionsModel
    private let titles = ["Bayer", "Bayer 4", "Bayer 2", "Halftone", "Lines", "Crosshatch", "Noise", "None"]

    var body: some View {
        DitherSection(title: "Pattern", symbol: "square.grid.3x3.fill") {
            Picker("Dither pattern", selection: $model.ditherMode) {
                ForEach(titles.indices, id: \.self) { index in
                    Text(titles[index]).tag(index)
                }
            }
            .accessibilityIdentifier("ditherMode")
            .onChange(of: model.ditherMode) { _ in model.publishForControlChange() }
            DitherSlider(model: model, title: "Color levels", key: "colorNum", range: 2...16, fallback: 4)
            DitherSlider(model: model, title: "Pixel size", key: "pixelSize", range: 1...64, fallback: 2)
            DitherSlider(model: model, title: "Grid gap", key: "gap", range: 0...0.45, fallback: 0)
            DitherSlider(model: model, title: "Corner radius", key: "cornerRadius", range: 0...0.5, fallback: 0)
            Text("Gap and corner radius are relative to each square's size.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ColorSection: View {
    @ObservedObject var model: DitherOptionsModel

    var body: some View {
        DitherSection(title: "Color", symbol: "paintpalette") {
            Toggle("Multicolor palette", isOn: Binding(
                get: { model.isMulticolor },
                set: { model.setMulticolor($0) }
            ))
            .accessibilityIdentifier("multicolor")
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 5), count: 7), spacing: 5) {
                ForEach(lumePalette.indices, id: \.self) { index in
                    Button {
                        model.selectColor(index)
                    } label: {
                        Image(systemName: model.selectedColors.contains(index) ? "circle.inset.filled" : "circle.fill")
                            .foregroundStyle(Color(nsColor: NSColor(hexString: lumePalette[index]) ?? .gray))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Palette color \(lumeNames[index])")
                    .accessibilityIdentifier("color-\(index)")
                    .accessibilityAddTraits(model.selectedColors.contains(index) ? .isSelected : [])
                }
            }
            Text("Select one color for the wave, or enable multicolor to select up to 8 colors in order.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text("Background")
                Spacer()
                backgroundButton(model, style: "black", title: "Black", symbol: "circle.fill")
                backgroundButton(model, style: "white", title: "White", symbol: "circle")
                backgroundButton(model, style: "dim", title: "Tinted", symbol: "circle.lefthalf.filled")
            }
        }
    }
}

private struct DitherSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.headline)
            content()
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct DitherSlider: View {
    @ObservedObject var model: DitherOptionsModel
    let title: String
    let key: String
    let range: ClosedRange<Double>
    let fallback: Double

    var body: some View {
        HStack {
            Text(title)
                .frame(width: 105, alignment: .leading)
            Slider(value: Binding(
                get: { Double(model.textValues[key] ?? "") ?? fallback },
                set: { model.setSlider($0, for: key) }
            ), in: range)
            TextField(title, text: Binding(
                get: { model.textValues[key] ?? "" },
                set: { model.setText($0, for: key) }
            )).textFieldStyle(.roundedBorder)
                .frame(width: 64)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(key)
    }
}

private struct DitherFooter: View {
    @ObservedObject var model: DitherOptionsModel

    var body: some View {
        HStack {
            Spacer()
            Button(role: .cancel) {
                model.onCancel?()
            } label: {
                Label("Cancel", systemImage: "xmark")
            }
            .accessibilityLabel("Cancel dither options")
            ConfirmButton {
                model.onSave?()
            }
        }
    }
}

private struct ConfirmButton: View {
    let action: () -> Void

    var body: some View {
        if #available(macOS 26, *) {
            Button(role: .confirm, action: action) {
                Label("Save", systemImage: "checkmark")
            }
            .buttonStyle(.glassProminent)
            .accessibilityLabel("Save dither options")
        } else {
            Button(action: action) {
                Label("Save", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Save dither options")
        }
    }
}

private func checkBinding(_ model: DitherOptionsModel, key: String) -> Binding<Bool> {
    Binding(
        get: { model.checks[key] == true },
        set: {
            model.checks[key] = $0
            model.publishForControlChange()
        }
    )
}

private func backgroundButton(_ model: DitherOptionsModel, style: String, title: String, symbol: String) -> some View {
    Button {
        model.setBackgroundStyle(style)
    } label: {
        Label(title, systemImage: symbol)
    }
    .buttonStyle(.bordered)
    .tint(model.backgroundStyle == style ? .accentColor : .secondary)
    .disabled(model.selectedColors.contains(0) && style != "white")
    .accessibilityLabel("\(title) background")
    .accessibilityIdentifier("background-\(style)")
}

private struct DitherPreviewRepresentable: NSViewRepresentable {
    let configuration: DitherConfiguration
    let isActive: Bool

    func makeNSView(context: Context) -> DitherPreviewView {
        DitherPreviewView(frame: .zero)
    }

    func updateNSView(_ nsView: DitherPreviewView, context: Context) {
        nsView.setConfiguration(configuration)
        nsView.setActive(isActive)
    }
}

private extension DitherOptionsModel {
    func publishForControlChange() {
        publishPreview()
    }
}

private extension NSColor {
    convenience init?(hexString: String) {
        let value = hexString.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard value.count == 6, let number = UInt32(value, radix: 16) else {
            return nil
        }
        self.init(
            srgbRed: CGFloat((number >> 16) & 255) / 255,
            green: CGFloat((number >> 8) & 255) / 255,
            blue: CGFloat(number & 255) / 255,
            alpha: 1
        )
    }

    var hexString: String {
        let color = usingColorSpace(.sRGB) ?? self
        let red = Int((color.redComponent * 255).rounded())
        let green = Int((color.greenComponent * 255).rounded())
        let blue = Int((color.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    func withBrightness(_ amount: CGFloat) -> NSColor {
        let color = usingColorSpace(.sRGB) ?? self
        return NSColor(
            srgbRed: color.redComponent * amount,
            green: color.greenComponent * amount,
            blue: color.blueComponent * amount,
            alpha: 1
        )
    }
}
