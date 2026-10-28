import Foundation

@main
enum SettingsCheck {
    static func main() {
        let suiteName = "local.dither.settings-check.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = DitherSettings(defaults: defaults)

        assert(settings.configuration.pixelSize == 2)
        assert(settings.configuration.gap == 0)
        assert(settings.configuration.cornerRadius == 0)
        defaults.set(true, forKey: "transparent")
        assert(!settings.configuration.transparent)
        assert(String(describing: settings.value(for: "waveSpeed")) == "0.05")
        settings.set(6, for: "ditherMode")
        assert(settings.configuration.ditherMode == 6)
        settings.set("0.25", for: "waveSpeed")
        assert(settings.configuration.waveSpeed == 0.25)
        settings.set("not a number", for: "waveSpeed")
        assert(settings.configuration.waveSpeed == 0.25)

        settings.set("#FF2600", for: "waveColor")
        settings.set("dim", for: "backgroundStyle")
        let dim = settings.configuration
        assert(abs(dim.backgroundColor.x - dim.waveColor.x * 0.2) < 0.0001)
        settings.set("#46E1FC", for: "waveColor")
        let changed = settings.configuration
        assert(abs(changed.backgroundColor.y - changed.waveColor.y * 0.2) < 0.0001)
        settings.set("white", for: "backgroundStyle")
        assert(settings.configuration.backgroundColor.x == 1)
        settings.set("#000000", for: "waveColor")
        settings.set("black", for: "backgroundStyle")
        assert(settings.configuration.backgroundColor == SIMD3<Float>(repeating: 1))
        settings.set("0.2", for: "gap")
        settings.set("0.35", for: "cornerRadius")
        assert(settings.configuration.gap == 0.2)
        assert(settings.configuration.cornerRadius == 0.35)

        defaults.removePersistentDomain(forName: suiteName)
        print("SettingsCheck passed")
    }
}
