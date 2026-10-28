import AppKit
import ScreenSaver
import SwiftUI

@objc(DitherConfigurationViewController)
final class DitherConfigurationViewController: ScreenSaverConfigurationViewController {
    private let settings = DitherSettings.shared
    private let optionsModel = DitherOptionsModel()
    private lazy var optionsView = NSHostingView(rootView: DitherOptionsView(model: optionsModel))

    override func loadView() {
        optionsModel.onCancel = { [weak self] in
            self?.optionsModel.endPreview()
            self?.configureSheetDidEnd()
        }
        optionsModel.onSave = { [weak self] in
            self?.saveOptions()
        }
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 700))
        optionsView.frame = container.bounds
        optionsView.autoresizingMask = [.width, .height]
        container.addSubview(optionsView)
        view = container
        preferredContentSize = NSSize(width: 460, height: 700)
    }

    override func configureSheetWillPresent() {
        super.configureSheetWillPresent()
        settings.reload()
        optionsModel.loadValues(settings.values, configuration: settings.configuration)
        optionsModel.scrollToTop()
        optionsModel.beginPreview()
    }

    private func saveOptions() {
        do {
            let values = try optionsModel.values()
            for (key, value) in values.textFields {
                settings.set(value, for: key)
            }
            for (key, value) in values.checks {
                settings.set(value, for: key)
            }
            settings.set(values.ditherMode, for: "ditherMode")
            optionsModel.endPreview()
            configureSheetDidEnd()
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Check the dither options"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
