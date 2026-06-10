import Cocoa

/// The main editor window. Single-instance: re-opening the editor with a
/// fresh image swaps the canvas contents rather than stacking windows.
///
/// Layout: canvas on top (fills), action bar at the bottom containing
/// the source label, arrow colour/thickness controls, and the Reset /
/// Save buttons. Window is `.titled + .resizable + .closable`; the app
/// stays an accessory (LSUIElement), so showing the window calls
/// `NSApp.activate` to bring it forward without surfacing a Dock icon.
final class EditorWindow: NSWindowController {

    private static var instance: EditorWindow?

    fileprivate let canvas: EditorCanvas
    private var saveButton: NSButton!
    private var resetButton: NSButton!
    private var sourceLabel: NSTextField!
    private var arrowColorWell: NSColorWell!
    private var arrowAutoColorCheckbox: NSButton!
    private var arrowThicknessSlider: NSSlider!

    // MARK: - UserDefaults keys + thickness range

    private enum Keys {
        static let arrowColor = "HawkEye.arrow.color"            // [Double] sRGB rgba
        static let arrowLineWidth = "HawkEye.arrow.lineWidth"    // Double, image-pixel units
        static let arrowAutoColor = "HawkEye.arrow.autoColor"    // Bool, default true
    }

    /// Slider range, in image-pixel units. Caps high enough for the
    /// arrow to read on large screenshots, low enough that thin strokes
    /// are still possible. Default 8 lines up with the prior "Medium".
    private static let arrowLineWidthRange: ClosedRange<CGFloat> = 2 ... 24
    private static let arrowLineWidthDefault: CGFloat = 8

    private init(image: CGImage, sourceText: String) {
        self.canvas = EditorCanvas(image: image)

        let initialSize = NSSize(width: 1100, height: 720)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: initialSize),
                               styleMask: [.titled, .closable, .resizable, .miniaturizable],
                               backing: .buffered,
                               defer: false)
        window.title = "HawkEye"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 600, height: 400)

        super.init(window: window)

        installContentView(sourceText: sourceText)
        applyPersistedArrowStyle()
        canvas.onStateChanged = { [weak self] in self?.refreshActions() }
        // Auto mode picks a colour from the content — mirror it in the well.
        canvas.onArrowColorAutoUpdated = { [weak self] color in
            self?.arrowColorWell.color = color
        }
        refreshActions()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func installContentView(sourceText: String) {
        guard let window = self.window else { return }

        let container = NSView(frame: window.contentLayoutRect)
        container.autoresizingMask = [.width, .height]

        canvas.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(canvas)

        // Action bar — uses the system "window background" material so
        // standard NSButtons stay legible in both light and dark mode.
        let bar = NSVisualEffectView()
        bar.material = .windowBackground
        bar.blendingMode = .behindWindow
        bar.state = .followsWindowActiveState
        bar.translatesAutoresizingMaskIntoConstraints = false

        sourceLabel = NSTextField(labelWithString: sourceText)
        sourceLabel.translatesAutoresizingMaskIntoConstraints = false
        sourceLabel.textColor = .secondaryLabelColor
        sourceLabel.font = .systemFont(ofSize: 11, weight: .medium)
        sourceLabel.setContentHuggingPriority(.required, for: .horizontal)

        let arrowLabel = NSTextField(labelWithString: "Arrow")
        arrowLabel.translatesAutoresizingMaskIntoConstraints = false
        arrowLabel.textColor = .secondaryLabelColor
        arrowLabel.font = .systemFont(ofSize: 11, weight: .medium)
        arrowLabel.setContentHuggingPriority(.required, for: .horizontal)

        arrowColorWell = NSColorWell()
        arrowColorWell.translatesAutoresizingMaskIntoConstraints = false
        arrowColorWell.isContinuous = true
        arrowColorWell.target = self
        arrowColorWell.action = #selector(arrowColorChanged)

        // "Auto" derives the pointer colour from the magnified content. On
        // by default; ticking it off enables the well for a manual override.
        arrowAutoColorCheckbox = NSButton(checkboxWithTitle: "Auto",
                                          target: self,
                                          action: #selector(autoColorToggled))
        arrowAutoColorCheckbox.translatesAutoresizingMaskIntoConstraints = false
        arrowAutoColorCheckbox.controlSize = .small
        arrowAutoColorCheckbox.font = .systemFont(ofSize: 11, weight: .medium)
        arrowAutoColorCheckbox.toolTip = "Match the pointer colour to the callout content"

        // Continuous slider — replaces the previous 3-option popup so
        // the user can dial in any thickness in the supported range.
        arrowThicknessSlider = NSSlider(value: Double(Self.arrowLineWidthDefault),
                                         minValue: Double(Self.arrowLineWidthRange.lowerBound),
                                         maxValue: Double(Self.arrowLineWidthRange.upperBound),
                                         target: self,
                                         action: #selector(arrowThicknessChanged))
        arrowThicknessSlider.translatesAutoresizingMaskIntoConstraints = false
        arrowThicknessSlider.isContinuous = true
        arrowThicknessSlider.controlSize = .small
        arrowThicknessSlider.toolTip = "Arrow thickness"

        resetButton = NSButton(title: "Reset", target: self, action: #selector(resetTapped))
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        resetButton.bezelStyle = .rounded
        resetButton.controlSize = .regular
        resetButton.toolTip = "Clear the selection and callout (⎋)"

        saveButton = NSButton(title: "Save Image…", target: self, action: #selector(saveTapped))
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.bezelStyle = .rounded
        saveButton.controlSize = .regular
        saveButton.keyEquivalent = "s"
        saveButton.keyEquivalentModifierMask = [.command]
        saveButton.bezelColor = .controlAccentColor

        bar.addSubview(sourceLabel)
        bar.addSubview(arrowLabel)
        bar.addSubview(arrowColorWell)
        bar.addSubview(arrowAutoColorCheckbox)
        bar.addSubview(arrowThicknessSlider)
        bar.addSubview(resetButton)
        bar.addSubview(saveButton)
        container.addSubview(bar)

        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: container.topAnchor),
            canvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: bar.topAnchor),

            bar.heightAnchor.constraint(equalToConstant: 52),
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            // Left cluster: source label
            sourceLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16),
            sourceLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            // Middle cluster: Arrow label · colour well · thickness popup
            arrowLabel.leadingAnchor.constraint(equalTo: sourceLabel.trailingAnchor, constant: 20),
            arrowLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            arrowColorWell.leadingAnchor.constraint(equalTo: arrowLabel.trailingAnchor, constant: 8),
            arrowColorWell.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            arrowColorWell.widthAnchor.constraint(equalToConstant: 36),
            arrowColorWell.heightAnchor.constraint(equalToConstant: 22),

            arrowAutoColorCheckbox.leadingAnchor.constraint(equalTo: arrowColorWell.trailingAnchor, constant: 8),
            arrowAutoColorCheckbox.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            arrowThicknessSlider.leadingAnchor.constraint(equalTo: arrowAutoColorCheckbox.trailingAnchor, constant: 12),
            arrowThicknessSlider.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            arrowThicknessSlider.widthAnchor.constraint(equalToConstant: 140),

            // Right cluster: Reset · Save (Save pinned, Reset to its left)
            saveButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16),
            saveButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            resetButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -8),
            resetButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            // Slider keeps clearance from the reset button; the gap
            // between is the flexible space.
            arrowThicknessSlider.trailingAnchor.constraint(lessThanOrEqualTo: resetButton.leadingAnchor, constant: -16),
        ])

        window.contentView = container
    }

    private func refreshActions() {
        saveButton.isEnabled = canvas.hasContent
        resetButton.isEnabled = canvas.hasContent || !canvas.selectionForUI.isNull
    }

    // MARK: - Arrow style persistence

    private static let defaultArrowColor: NSColor = .systemRed

    /// Read persisted colour + thickness (or fall back to defaults) and
    /// push both into the canvas + controls. Called once on init.
    private func applyPersistedArrowStyle() {
        let color = Self.loadArrowColor() ?? Self.defaultArrowColor
        let rawWidth = Self.loadArrowLineWidth() ?? Self.arrowLineWidthDefault
        let lineWidth = min(max(rawWidth, Self.arrowLineWidthRange.lowerBound),
                             Self.arrowLineWidthRange.upperBound)

        canvas.arrowColor = color
        canvas.arrowLineWidth = lineWidth

        arrowColorWell.color = color
        arrowThicknessSlider.doubleValue = Double(lineWidth)

        // Auto colour is on by default; the well is disabled while it's on
        // (it shows the derived colour) and enabled for a manual override.
        let auto = Self.loadArrowAutoColor()
        arrowAutoColorCheckbox.state = auto ? .on : .off
        arrowColorWell.isEnabled = !auto
        canvas.autoArrowColor = auto
    }

    private static func loadArrowColor() -> NSColor? {
        guard let arr = UserDefaults.standard.array(forKey: Keys.arrowColor) as? [Double],
              arr.count == 4
        else { return nil }
        return NSColor(srgbRed: CGFloat(arr[0]),
                       green: CGFloat(arr[1]),
                       blue: CGFloat(arr[2]),
                       alpha: CGFloat(arr[3]))
    }

    private static func saveArrowColor(_ color: NSColor) {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let arr: [Double] = [Double(rgb.redComponent),
                              Double(rgb.greenComponent),
                              Double(rgb.blueComponent),
                              Double(rgb.alphaComponent)]
        UserDefaults.standard.set(arr, forKey: Keys.arrowColor)
    }

    private static func loadArrowLineWidth() -> CGFloat? {
        guard UserDefaults.standard.object(forKey: Keys.arrowLineWidth) != nil else {
            return nil
        }
        return CGFloat(UserDefaults.standard.double(forKey: Keys.arrowLineWidth))
    }

    private static func saveArrowLineWidth(_ w: CGFloat) {
        UserDefaults.standard.set(Double(w), forKey: Keys.arrowLineWidth)
    }

    private static func loadArrowAutoColor() -> Bool {
        // Default true when never set.
        guard UserDefaults.standard.object(forKey: Keys.arrowAutoColor) != nil else { return true }
        return UserDefaults.standard.bool(forKey: Keys.arrowAutoColor)
    }

    private static func saveArrowAutoColor(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Keys.arrowAutoColor)
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

    @objc private func arrowColorChanged() {
        let color = arrowColorWell.color
        canvas.arrowColor = color
        Self.saveArrowColor(color)
    }

    @objc private func autoColorToggled() {
        let on = arrowAutoColorCheckbox.state == .on
        Self.saveArrowAutoColor(on)
        arrowColorWell.isEnabled = !on
        // Setting this recomputes from the current selection when turning on
        // (via the canvas didSet → onArrowColorAutoUpdated callback).
        canvas.autoArrowColor = on
        if !on {
            // Manual: fall back to the colour currently shown in the well.
            let color = arrowColorWell.color
            canvas.arrowColor = color
            Self.saveArrowColor(color)
        }
    }

    @objc private func arrowThicknessChanged() {
        let w = CGFloat(arrowThicknessSlider.doubleValue)
        canvas.arrowLineWidth = w
        Self.saveArrowLineWidth(w)
    }

    // MARK: - Single-instance entry

    static func show(image: CGImage, sourceLabel: String) {
        if let inst = instance {
            inst.canvas.setImage(image)
            inst.sourceLabel.stringValue = sourceLabel
            inst.window?.makeKeyAndOrderFront(nil)
            inst.window?.makeFirstResponder(inst.canvas)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = EditorWindow(image: image, sourceText: sourceLabel)
        controller.window?.center()
        controller.window?.makeKeyAndOrderFront(nil)
        controller.window?.makeFirstResponder(controller.canvas)
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
