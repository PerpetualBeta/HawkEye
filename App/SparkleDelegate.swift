import Cocoa
import Sparkle

/// Sparkle 2.x bootstrap. Held by AppDelegate so the SPUStandardUpdater
/// stays alive for the lifetime of the process. Feed URL and the shared
/// Jorvik EdDSA public key live in Info.plist — same key as the rest of
/// the suite, signed by the private half that lives in the user keychain.
final class SparkleDelegate: NSObject {

    private var updater: SPUStandardUpdaterController?

    func start() {
        updater = SPUStandardUpdaterController(startingUpdater: true,
                                                updaterDelegate: nil,
                                                userDriverDelegate: nil)
        clog("SparkleDelegate: SPUStandardUpdater started")
    }

    func checkForUpdates() {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        updater?.checkForUpdates(nil)
    }
}
