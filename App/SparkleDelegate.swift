import Cocoa
import Sparkle

/// Sparkle 2.x bootstrap. Held by AppDelegate so the SPUStandardUpdater
/// stays alive for the lifetime of the process. Feed URL and the shared
/// Jorvik EdDSA public key live in Info.plist — same key as the rest of
/// the suite, signed by the private half that lives in the user keychain.
final class SparkleDelegate: NSObject {

    private var updater: SPUStandardUpdaterController?
    private let userDriverDelegate = HawkEyeUserDriverDelegate()

    func start() {
        updater = SPUStandardUpdaterController(startingUpdater: true,
                                                updaterDelegate: nil,
                                                userDriverDelegate: userDriverDelegate)
        clog("SparkleDelegate: SPUStandardUpdater started")
    }

    func checkForUpdates() {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        updater?.checkForUpdates(nil)
    }
}

/// Keeps Sparkle's UI in front for the whole update session — canonical
/// Jorvik pattern (KB `conventions-sparkle-integration` §6, validated on
/// ClipMan). Three legs: modern activation API, window-level elevation to
/// `.floating` for the session, and a key-window observer to catch the
/// download/install status sheet, which has no dedicated Sparkle hook.
final class HawkEyeUserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    private var sessionObserver: NSObjectProtocol?
    private var elevatedWindows: [(window: NSWindow, originalLevel: NSWindow.Level)] = []

    func standardUserDriverWillShowModalAlert() {
        bringForward()
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        startFocusGuard()
        bringForward()
    }

    func standardUserDriverWillFinishUpdateSession() {
        stopFocusGuard()
    }

    private func bringForward() {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        elevateAllWindows()
    }

    private func startFocusGuard() {
        guard sessionObserver == nil else { return }
        sessionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.bringForward()
        }
    }

    private func stopFocusGuard() {
        if let obs = sessionObserver {
            NotificationCenter.default.removeObserver(obs)
            sessionObserver = nil
        }
        for entry in elevatedWindows {
            entry.window.level = entry.originalLevel
        }
        elevatedWindows.removeAll()
    }

    /// Promote every visible window in this process to `.floating`. Any
    /// new Sparkle window that opens during the session is caught by
    /// the key-notification observer above and elevated then.
    private func elevateAllWindows() {
        for window in NSApp.windows where window.isVisible && window.level == .normal {
            elevatedWindows.append((window, window.level))
            window.level = .floating
        }
    }
}
