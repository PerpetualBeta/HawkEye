import Foundation

/// Diagnostic logging is gated behind the `HawkEye.debugLogging` UserDefault.
/// Release builds ship with the flag unset (default false) so nothing is
/// written to disk. Enable with:
///
///     defaults write cc.jorviksoftware.HawkEye HawkEye.debugLogging -bool YES
///
/// Then relaunch. The flag is read once at launch for speed; toggling at
/// runtime has no effect until the next process start.
private let debugLoggingEnabled: Bool = {
    UserDefaults.standard.bool(forKey: "HawkEye.debugLogging")
}()

private let logFile: FileHandle? = {
    guard debugLoggingEnabled else { return nil }
    let path = "/tmp/hawkeye.log"
    FileManager.default.createFile(atPath: path, contents: nil)
    return FileHandle(forWritingAtPath: path)
}()

private let timestampFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return f
}()

func clog(_ msg: String) {
    guard debugLoggingEnabled, let logFile else { return }
    let line = "\(timestampFormatter.string(from: Date()))  \(msg)\n"
    logFile.seekToEndOfFile()
    if let data = line.data(using: .utf8) {
        logFile.write(data)
    }
}
