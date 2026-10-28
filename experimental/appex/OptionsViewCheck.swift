import AppKit
import simd

@main
enum OptionsViewCheck {
    static func main() {
        let model = DitherOptionsModel()
        model.loadValues([
            "waveSpeed": 0.05,
            "waveFrequency": 3.0,
            "waveAmplitude": 0.3,
            "waveColor": "#808080",
            "backgroundColor": "#000000",
            "colorNum": 4.0,
            "pixelSize": 2.0,
            "palette": "#FFFFFF, #000000",
            "gap": 0.2,
            "cornerRadius": 0.35,
            "intro": true,
            "transparent": false,
            "ditherMode": 0,
            "backgroundStyle": "black"
        ])

        let values = try! model.values()
        assert(values.textFields["waveSpeed"] == "0.05")
        assert(values.textFields["palette"] == "#FFFFFF, #000000")
        assert(values.textFields["gap"] == "0.2")
        assert(values.textFields["cornerRadius"] == "0.35")
        assert(model.configuration.intro == false)

        var previewConfiguration: DitherConfiguration?
        model.onPreviewChanged = { previewConfiguration = $0 }
        model.setMulticolor(false)
        model.selectColor(1)
        model.setMulticolor(true)
        model.selectColor(2)
        assert(model.textValues["palette"] == "#FF2600, #FF9300")
        assert(model.configuration.waveColor.x == 1)
        assert(model.configuration.backgroundColor == .zero)
        assert(previewConfiguration?.palette.count == 2)

        model.selectColor(0)
        assert(model.textValues["palette"] == "#FF2600, #FF9300, #000000")
        assert(model.backgroundStyle == "white")
        assert(model.configuration.backgroundColor == SIMD3<Float>(repeating: 1))

        model.setMulticolor(false)
        assert(model.textValues["palette"] == "")
        assert(model.textValues["waveColor"] == "#FF2600")

        model.setText("not a number", for: "waveSpeed")
        do {
            _ = try model.values()
            assertionFailure("Invalid input must not be saved")
        } catch {
            assert(error.localizedDescription.contains("Wave speed"))
        }

        print("OptionsViewCheck passed")
    }
}
