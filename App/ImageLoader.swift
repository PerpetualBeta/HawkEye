import AppKit
import UniformTypeIdentifiers

/// Wraps `NSOpenPanel` for "Load Image…". Returns a loaded `CGImage` (so
/// the editor canvas can sample pixels directly when rendering the
/// magnified callout) or nil if the user cancels.
enum ImageLoader {

    static func presentOpenPanel() -> CGImage? {
        let panel = NSOpenPanel()
        panel.title = "Load Image"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic, .image]

        // Force the panel to the front so it appears even though we run
        // as an accessory (LSUIElement) — otherwise it can hide behind
        // whatever was previously frontmost.
        NSApp.activate(ignoringOtherApps: true)

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return load(from: url)
    }

    static func load(from url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            clog("ImageLoader: CGImageSource failed for \(url.path)")
            return nil
        }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
