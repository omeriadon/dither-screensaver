import AppKit
import simd

@main
enum OptionsViewCheck {
    static func main() {
        let model = DitherOptionsModel()
        model.loadValues([
            "waveSpeed": 0.05,
            "waveDirection": 405.0,
            "waveFrequency": 3.0,
            "waveAmplitude": 0.3,
            "waveColor": "#808080",
            "backgroundColor": "#000000",
            "colorNum": 4.0,
            "ditherStrength": 0.75,
            "pixelSize": 2.0,
            "palette": "#FFFFFF, #000000",
            "gap": 0.2,
            "cornerRadius": 0.35,
            "joinAdjacentSquares": true,
            "intro": true,
            "transparent": false,
            "ditherMode": 0,
            "backgroundStyle": "black"
        ])

        let values = try! model.values()
        assert(model.colorPlacement == "squares")
        assert(values.textFields["waveSpeed"] == "0.05")
        assert(values.textFields["waveDirection"] == "45.0")
        assert(abs(model.configuration.waveDirection - 45) < 0.0001)
        assert(values.textFields["palette"] == "#FFFFFF, #000000")
        assert(values.textFields["gap"] == "0.2")
        assert(values.textFields["cornerRadius"] == "0.35")
        assert(values.textFields["ditherStrength"] == "0.75")
        assert(abs(model.configuration.ditherStrength - 0.75) < 0.0001)
        assert(model.configuration.intro == false)
        assert(model.configuration.joinAdjacentSquares)

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
        model.setBackgroundStyle("black")
        assert(model.backgroundStyle == "black")
        assert(model.configuration.backgroundColor == .zero)
        assert(model.configuration.palette.count == 3)

        model.setColorPlacement("background")
        model.setSquareStyle("black")
        assert(abs(model.configuration.backgroundColor.x - 1) < 0.0001)
        assert(abs(model.configuration.backgroundColor.y - (38.0 / 255.0)) < 0.0001)
        assert(model.configuration.waveColor == .zero)
        assert(model.configuration.palette.isEmpty)
        model.selectColor(3)
        assert(model.isColorSelected(3))
        assert(!model.isColorSelected(1))
        assert(abs(model.configuration.backgroundColor.x - (187.0 / 255.0)) < 0.0001)
        assert(model.textValues["palette"] == "#FF2600, #FF9300, #000000")
        model.setSquareStyle("white")
        assert(model.configuration.waveColor == SIMD3<Float>(repeating: 1))
        let savedBackgroundValues = try! model.values()
        assert(savedBackgroundValues.textFields["colorPlacement"] == "background")
        assert(savedBackgroundValues.textFields["squareStyle"] == "white")
        assert(model.textValues["palette"] == "#FF2600, #FF9300, #000000")
        let reloaded = DitherOptionsModel()
        var saved: [String: Any] = savedBackgroundValues.textFields
        saved["ditherMode"] = savedBackgroundValues.ditherMode
        reloaded.loadValues(saved)
        assert(reloaded.colorPlacement == "background")
        assert(reloaded.isColorSelected(3))
        assert(reloaded.configuration.backgroundColor == model.configuration.backgroundColor)
        assert(reloaded.configuration.waveColor == model.configuration.waveColor)
        assert(reloaded.configuration.palette.isEmpty)
        model.setColorPlacement("squares")
        assert(model.configuration.backgroundColor == .zero)
        assert(model.configuration.palette.count == 3)
        assert(model.textValues["waveColor"] == "#FF2600")

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

        model.setText("0.05", for: "waveSpeed")
        model.setText("inf", for: "waveDirection")
        do {
            _ = try model.values()
            assertionFailure("Nonfinite direction input must not be saved")
        } catch {
            assert(error.localizedDescription.contains("Wave direction"))
        }

        model.setSlider(90, for: "waveDirection")
        assert(abs(model.configuration.waveDirection - 90) < 0.0001)
        assert(abs(DitherConfiguration.waveDirectionVector(for: 0).x) < 0.0001)
        assert(abs(DitherConfiguration.waveDirectionVector(for: 90).y) < 0.0001)
        let directionValues = try! model.values()
        let directionReload = DitherOptionsModel()
        directionReload.loadValues(directionValues.textFields)
        assert(abs(directionReload.configuration.waveDirection - 90) < 0.0001)

        model.setSlider(0, for: "ditherStrength")
        for mode in 0...7 {
            model.ditherMode = mode
            assert(model.configuration.ditherStrength == 0)
        }
        let migratedReload = DitherOptionsModel()
        migratedReload.loadValues([
            "waveSpeed": -0.25,
            "waveDirection": 0.0,
            "ditherStrength": 1.0
        ])
        assert(migratedReload.configuration.waveSpeed == 0.25)
        assert(migratedReload.configuration.waveDirection == 180)

        model.setSlider(0.2, for: "gap")
        let gapConfiguration = model.configuration
        assert(gapConfiguration.joinAdjacentSquares)
        model.setSlider(0, for: "gap")
        assert(model.configuration.joinAdjacentSquares)

        print("OptionsViewCheck passed")
    }
}
