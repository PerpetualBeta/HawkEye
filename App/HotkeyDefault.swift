import AppKit
import Carbon.HIToolbox

// The seed shortcut this app ships with. Kept here rather than in
// JorvikKit: which shortcut an app claims is a product decision, not
// shared infrastructure, and two apps picking the same one would have
// them swallow each other.
extension HotkeyConfig {
    /// Hyper-H — the seed default: Cmd+Ctrl+Opt+Shift+H. "H" for HawkEye,
    /// and a deliberate departure from CopyLens's "\" so a user running
    /// both doesn't see one swallow the other.
    static let defaultCapture = HotkeyConfig(
        keyCode: UInt16(kVK_ANSI_H),
        rawModifierFlags: NSEvent.ModifierFlags([.command, .control, .option, .shift]).rawValue
    )
}
