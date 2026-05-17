import Cocoa

final class StatusItem: NSObject, NSMenuDelegate {

    private let item: NSStatusItem
    private let onCapture: () -> Void
    private let onLoadImage: () -> Void
    private let onOpenSettings: () -> Void
    private let onOpenAbout: () -> Void
    private let onCheckForUpdates: () -> Void

    /// Held so `menuNeedsUpdate(_:)` can re-stamp the capture shortcut on
    /// every menu open — keeps the glyph in sync with whatever the user
    /// has configured in Settings without any cross-object coordination.
    private let captureItem: NSMenuItem

    init(onCapture: @escaping () -> Void,
         onLoadImage: @escaping () -> Void,
         onOpenSettings: @escaping () -> Void,
         onOpenAbout: @escaping () -> Void,
         onCheckForUpdates: @escaping () -> Void)
    {
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.onCapture = onCapture
        self.onLoadImage = onLoadImage
        self.onOpenSettings = onOpenSettings
        self.onOpenAbout = onOpenAbout
        self.onCheckForUpdates = onCheckForUpdates
        self.captureItem = NSMenuItem(title: "Capture Active Display",
                                       action: #selector(StatusItem.triggerCapture),
                                       keyEquivalent: "")
        super.init()

        if let button = item.button {
            // Template-style SF Symbol for the menu-bar glyph. The bundle
            // icon does the heavy artwork; the status item just needs a
            // small monochrome shape that adapts to light/dark menu bars.
            button.image = NSImage(systemSymbolName: "plus.magnifyingglass",
                                    accessibilityDescription: "HawkEye")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.delegate = self

        // Standard Jorvik menu order — About first, then app-specific
        // actions, then Settings, then Quit. Matches CopyLens, Rainy
        // Day, BrowserCommander, etc.
        let about = NSMenuItem(title: "About HawkEye",
                                action: #selector(openAbout),
                                keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(NSMenuItem.separator())

        captureItem.target = self
        menu.addItem(captureItem)

        let load = NSMenuItem(title: "Load Image…",
                               action: #selector(loadImage),
                               keyEquivalent: "o")
        load.target = self
        menu.addItem(load)

        menu.addItem(NSMenuItem.separator())

        let settings = NSMenuItem(title: "Settings…",
                                   action: #selector(openSettings),
                                   keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let updates = NSMenuItem(title: "Check for Updates…",
                                  action: #selector(checkForUpdates),
                                  keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit HawkEye",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")

        item.menu = menu
    }

    // MARK: - NSMenuDelegate

    /// Refresh the capture-shortcut glyph just before the menu opens.
    /// Reads the live hotkey config from UserDefaults so changes made
    /// in Settings show up immediately — no observer plumbing required.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let cfg = HotkeyStore.read(HotkeyKeys.capture)
        if let (key, mods) = cfg.menuKeyEquivalent {
            captureItem.keyEquivalent = key
            captureItem.keyEquivalentModifierMask = mods
        } else {
            captureItem.keyEquivalent = ""
            captureItem.keyEquivalentModifierMask = []
        }
    }

    @objc private func triggerCapture()   { onCapture() }
    @objc private func loadImage()        { onLoadImage() }
    @objc private func openSettings()     { onOpenSettings() }
    @objc private func openAbout()        { onOpenAbout() }
    @objc private func checkForUpdates()  { onCheckForUpdates() }
}
