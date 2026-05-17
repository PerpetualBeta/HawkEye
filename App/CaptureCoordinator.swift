import Cocoa

/// Routes the two entry points (hotkey screen-capture and "Load Image…")
/// into the same destination: an `EditorWindow` showing the image, ready
/// for the user to draw a source rectangle and reposition the callout.
///
/// Re-entrancy: a second hotkey press while a capture is in flight is a
/// no-op. The editor window itself is single-instance — re-opening with
/// a fresh image replaces the contents rather than stacking windows.
final class CaptureCoordinator {

    private var inFlight = false

    func captureActiveDisplay() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !inFlight else {
            clog("CaptureCoordinator: ignoring re-entrant capture")
            return
        }
        inFlight = true

        Task { @MainActor in
            defer { self.inFlight = false }
            // Brief delay so any visible HawkEye UI (menu, settings) has
            // a chance to dismiss before the shutter — otherwise the
            // open menu appears in the screenshot. 100ms is enough on
            // typical hardware and imperceptible to users.
            try? await Task.sleep(nanoseconds: 100_000_000)

            guard let image = await Screenshot.captureActiveDisplay() else {
                HUDWindow.show(text: "Capture failed",
                               subtext: "Check Screen Recording permission")
                return
            }
            clog("CaptureCoordinator: captured \(image.width)×\(image.height) — opening editor")
            EditorWindow.show(image: image, sourceLabel: "Screen Capture")
        }
    }

    func loadImage() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let image = ImageLoader.presentOpenPanel() else { return }
        clog("CaptureCoordinator: loaded \(image.width)×\(image.height) — opening editor")
        EditorWindow.show(image: image, sourceLabel: "Loaded Image")
    }
}
