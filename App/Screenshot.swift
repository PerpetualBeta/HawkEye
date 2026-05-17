import Cocoa
import ScreenCaptureKit

/// Captures a full display via ScreenCaptureKit.
///
/// "Active display" is defined as the NSScreen currently hosting the mouse
/// pointer — matches the user's "the display I'm looking at right now"
/// mental model better than `NSScreen.main` (which is the screen with the
/// menu bar in mirrored setups, or last-key-window in others).
///
/// Returns the captured CGImage at native pixel density (Retina), or nil
/// if no display can be found, the user hasn't granted Screen Recording
/// permission, or the capture itself fails. Errors are logged.
enum Screenshot {

    /// Capture the display currently containing the mouse pointer.
    static func captureActiveDisplay() async -> CGImage? {
        let mouseLoc = NSEvent.mouseLocation
        let nsScreen = NSScreen.screens.first { $0.frame.contains(mouseLoc) }
            ?? NSScreen.main
        guard let nsScreen else {
            clog("Screenshot: no NSScreen for mouse=\(mouseLoc)")
            return nil
        }
        return await captureScreen(nsScreen)
    }

    private static func captureScreen(_ nsScreen: NSScreen) async -> CGImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                                onScreenWindowsOnly: true)

            let cgID = (nsScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            guard let display = content.displays.first(where: { $0.displayID == cgID }) else {
                clog("Screenshot: no SCDisplay for CGDirectDisplayID=\(cgID)")
                return nil
            }

            let config = SCStreamConfiguration()
            let scale = nsScreen.backingScaleFactor
            config.width = Int(nsScreen.frame.width * scale)
            config.height = Int(nsScreen.frame.height * scale)
            config.scalesToFit = false
            config.showsCursor = false

            let filter = SCContentFilter(display: display, excludingWindows: [])
            return try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                configuration: config)
        } catch {
            clog("Screenshot: capture failed — \(error)")
            return nil
        }
    }
}
