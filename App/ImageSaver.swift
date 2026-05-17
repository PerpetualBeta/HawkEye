import AppKit
import UniformTypeIdentifiers

/// Wraps `NSSavePanel` + PNG encoding. Default filename includes a
/// timestamp so saving multiple annotations of the same source doesn't
/// silently overwrite.
enum ImageSaver {

    static func presentSavePanel(default suggestedName: String? = nil,
                                  pngData: Data,
                                  completion: ((URL?) -> Void)? = nil)
    {
        let panel = NSSavePanel()
        panel.title = "Save Annotated Image"
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd-HHmmss"
        let defaultName = suggestedName ?? "HawkEye-\(stamp.string(from: Date())).png"
        panel.nameFieldStringValue = defaultName

        NSApp.activate(ignoringOtherApps: true)

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else {
            completion?(nil)
            return
        }
        do {
            try pngData.write(to: url)
            completion?(url)
        } catch {
            clog("ImageSaver: write failed — \(error)")
            let alert = NSAlert()
            alert.messageText = "Couldn't save image"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            completion?(nil)
        }
    }

    /// Encode a CGImage to PNG data via NSBitmapImageRep.
    static func pngData(from cgImage: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }
}
