import Cocoa

/// The main editor window. Single-instance: re-opening the editor with a
/// fresh image swaps the canvas contents rather than stacking windows.
///
/// Layout: canvas on top (fills), action bar at the bottom (Reset · Save).
/// Window is .titled + .resizable + .closable; the app stays an accessory
/// (LSUIElement), so showing the window calls NSApp.activate to bring it
/// forward without surfacing a Dock icon.
final class EditorWindow: NSWindowController {

    private static var instance: EditorWindow?

    private let canvas: EditorCanvas
    private var saveButton: NSButton!
    private var resetButton: NSButton!
    private var sourceLabel: NSTextField!

    private init(image: CGImage, sourceText: String) {
        self.canvas = EditorCanvas(image: image)

        let initialSize = NSSize(width: 1100, height: 720)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: initialSize),
                               styleMask: [.titled, .closable, .resizable, .miniaturizable],
                               backing: .buffered,
                               defer: false)
        window.title = "HawkEye"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 480, height: 360)

        super.init(window: window)

        installContentView(sourceText: sourceText)
        canvas.onStateChanged = { [weak self] in self?.refreshActions() }
        refreshActions()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func installContentView(sourceText: String) {
        guard let window = self.window else { return }

        let container = NSView(frame: window.contentLayoutRect)
        container.autoresizingMask = [.width, .height]

        canvas.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(canvas)

        // Action bar
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor(white: 0.13, alpha: 1).cgColor

        sourceLabel = NSTextField(labelWithString: sourceText)
        sourceLabel.translatesAutoresizingMaskIntoConstraints = false
        sourceLabel.textColor = NSColor(white: 0.7, alpha: 1)
        sourceLabel.font = .systemFont(ofSize: 11, weight: .medium)

        let hint = NSTextField(labelWithString:
            "Drag to select a source area · drag the callout to reposition · drag corners to resize")
        hint.translatesAutoresizingMaskIntoConstraints = false
        hint.textColor = NSColor(white: 0.55, alpha: 1)
        hint.font = .systemFont(ofSize: 11)
        hint.lineBreakMode = .byTruncatingMiddle

        resetButton = NSButton(title: "Reset", target: self, action: #selector(resetTapped))
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        resetButton.bezelStyle = .rounded
        resetButton.controlSize = .regular

        saveButton = NSButton(title: "Save Image…", target: self, action: #selector(saveTapped))
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.bezelStyle = .rounded
        saveButton.controlSize = .regular
        saveButton.keyEquivalent = "s"
        saveButton.keyEquivalentModifierMask = [.command]

        bar.addSubview(sourceLabel)
        bar.addSubview(hint)
        bar.addSubview(resetButton)
        bar.addSubview(saveButton)
        container.addSubview(bar)

        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: container.topAnchor),
            canvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: bar.topAnchor),

            bar.heightAnchor.constraint(equalToConstant: 48),
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            sourceLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16),
            sourceLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            hint.leadingAnchor.constraint(equalTo: sourceLabel.trailingAnchor, constant: 16),
            hint.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            hint.trailingAnchor.constraint(lessThanOrEqualTo: resetButton.leadingAnchor, constant: -16),

            saveButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16),
            saveButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            resetButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -8),
            resetButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])

        window.contentView = container
    }

    private func refreshActions() {
        saveButton.isEnabled = canvas.hasContent
        resetButton.isEnabled = canvas.hasContent || !canvas.selectionForUI.isNull
    }

    // MARK: - Actions

    @objc private func resetTapped() {
        canvas.reset()
    }

    @objc private func saveTapped() {
        guard let flat = canvas.renderFlattened(),
              let data = ImageSaver.pngData(from: flat)
        else {
            HUDWindow.show(text: "Couldn't render image")
            return
        }
        ImageSaver.presentSavePanel(default: nil, pngData: data) { url in
            if let url {
                HUDWindow.show(text: "Saved", subtext: url.lastPathComponent)
            }
        }
    }

    // MARK: - Single-instance entry

    static func show(image: CGImage, sourceLabel: String) {
        if let inst = instance {
            inst.canvas.setImage(image)
            inst.sourceLabel.stringValue = sourceLabel
            inst.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = EditorWindow(image: image, sourceText: sourceLabel)
        controller.window?.center()
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        instance = controller
    }
}

// Expose just enough state for the window controller to enable/disable
// the Reset button. Keeping `selection`/`callout` private on the canvas
// avoids the window scribbling on canvas state directly.
extension EditorCanvas {
    var selectionForUI: CGRect { selection }
}
