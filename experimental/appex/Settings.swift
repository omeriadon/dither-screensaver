import Foundation
import ScreenSaver
import simd

final class GeometryClockSettings: NSObject {
    static let shared = GeometryClockSettings()
    static let didChangeNotification = Notification.Name("local.geometry-clock.appex.settingsDidChange")

    private static let moduleIdentifier = "local.geometry-clock.appex"
    private let defaults: UserDefaults
    private var observing = false

    private let defaultsValues: [String: Any] = [
        "waveSpeed": 0.05, "waveFrequency": 3.0, "waveAmplitude": 0.3,
        "waveColor": "#808080", "backgroundColor": "#000000", "colorNum": 4.0,
        "pixelSize": 2.0, "disableAnimation": false, "ditherMode": 0,
        "palette": "", "scale": 1.0, "contrast": 1.0, "brightness": 0.0,
        "intro": true, "transparent": false, "dpr": 0.0, "gap": 0.0,
        "cornerRadius": 0.0, "backgroundStyle": "custom"
    ]

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? ScreenSaverDefaults(forModuleWithName: Self.moduleIdentifier) ?? UserDefaults.standard
        super.init()
        self.defaults.register(defaults: defaultsValues)
        for key in defaultsValues.keys {
            self.defaults.addObserver(self, forKeyPath: key, options: [.new], context: nil)
        }
        observing = true
    }

    deinit {
        if observing {
            for key in defaultsValues.keys {
                defaults.removeObserver(self, forKeyPath: key)
            }
        }
    }

    var configuration: DitherConfiguration {
        var result = DitherConfiguration()
        result.waveSpeed = number(for: "waveSpeed", fallback: result.waveSpeed)
        result.waveFrequency = max(0.01, number(for: "waveFrequency", fallback: result.waveFrequency))
        result.waveAmplitude = max(0, number(for: "waveAmplitude", fallback: result.waveAmplitude))
        result.waveColor = color(defaults.string(forKey: "waveColor"), fallback: result.waveColor)
        result.backgroundColor = color(defaults.string(forKey: "backgroundColor"), fallback: result.backgroundColor)
        switch defaults.string(forKey: "backgroundStyle") {
        case "black":
            result.backgroundColor = .zero
        case "white":
            result.backgroundColor = SIMD3<Float>(repeating: 1)
        case "dim":
            result.backgroundColor = result.waveColor * 0.2
        default:
            break
        }
        if result.waveColor == .zero {
            result.backgroundColor = SIMD3<Float>(repeating: 1)
        }
        result.colorNum = max(2, number(for: "colorNum", fallback: result.colorNum))
        result.pixelSize = min(4096, max(1, number(for: "pixelSize", fallback: result.pixelSize)))
        result.disableAnimation = defaults.bool(forKey: "disableAnimation")
        result.ditherMode = min(7, max(0, defaults.integer(forKey: "ditherMode")))
        result.palette = defaults.string(forKey: "palette")?
            .split(separator: ",")
            .compactMap { paletteColor(String($0).trimmingCharacters(in: .whitespaces)) } ?? []
        result.scale = max(0.05, number(for: "scale", fallback: result.scale))
        result.contrast = number(for: "contrast", fallback: result.contrast)
        result.brightness = number(for: "brightness", fallback: result.brightness)
        result.intro = defaults.bool(forKey: "intro")
        result.transparent = defaults.bool(forKey: "transparent")
        result.dpr = min(2, max(0, number(for: "dpr", fallback: result.dpr)))
        result.gap = min(0.45, max(0, number(for: "gap", fallback: result.gap)))
        result.cornerRadius = min(0.5, max(0, number(for: "cornerRadius", fallback: result.cornerRadius)))
        return result
    }

    func value(for key: String) -> Any {
        defaults.object(forKey: key) ?? ""
    }

    var values: [String: Any] {
        defaultsValues.keys.reduce(into: [:]) { result, key in
            result[key] = value(for: key)
        }
    }

    func set(_ value: Any, for key: String) {
        if let text = value as? String, defaultsValues[key] is Double {
            guard let number = Double(text), number.isFinite else {
                return
            }
            defaults.set(number, forKey: key)
        } else {
            defaults.set(value, forKey: key)
        }
        defaults.synchronize()
    }
    func reload() {
        defaults.synchronize()
    }

    private func number(for key: String, fallback: Float) -> Float {
        guard let value = defaults.object(forKey: key) as? NSNumber else {
            return fallback
        }
        let number = value.floatValue
        return number.isFinite ? number : fallback
    }

    private func color(_ value: String?, fallback: SIMD3<Float>) -> SIMD3<Float> {
        guard let value else {
            return fallback
        }
        let hex = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard hex.count == 6, let number = UInt32(hex, radix: 16) else {
            return fallback
        }
        return SIMD3<Float>(Float((number >> 16) & 255) / 255, Float((number >> 8) & 255) / 255, Float(number & 255) / 255)
    }

    private func paletteColor(_ value: String) -> SIMD3<Float>? {
        let hex = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard hex.count == 6, let number = UInt32(hex, radix: 16) else {
            return nil
        }
        return SIMD3<Float>(Float((number >> 16) & 255) / 255, Float((number >> 8) & 255) / 255, Float(number & 255) / 255)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard defaultsValues.keys.contains(keyPath ?? "") else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }
}
