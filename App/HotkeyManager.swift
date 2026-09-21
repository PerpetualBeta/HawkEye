import AppKit
import Carbon.HIToolbox

/// HawkEye's hotkey slots, and a storage-aware convenience over the shared
/// `JorvikHotkeyManager`.
///
/// The Carbon plumbing used to live here, and in four other apps, as five
/// hand-maintained copies of the same file. It now lives in JorvikKit; what
/// stays here is the part that is genuinely this app's: which slots exist, the
/// four-character signature that keeps its registrations distinct from its
/// siblings', and the fact that it stores shortcuts as a `HotkeyConfig`.
extension JorvikHotkeyManager {

    /// Internal slot identifiers; keep stable so re-registrations supersede
    /// previous installs cleanly.
    enum Slot: UInt32 {
        case capture    = 1
    }

    static let hawkEyeSignature = OSType(0x48574B45)

    /// Registers from a stored config. Pass `.empty` to remove.
    func register(_ cfg: HotkeyConfig, slot: Slot, handler: @escaping () -> Void) {
        register(keyCode: cfg.keyCode,
                 modifiers: cfg.modifierFlags,
                 slot: slot.rawValue,
                 handler: handler)
    }
}

/// UserDefaults keys for this app's hotkey slots. Kept alongside the slots
/// they belong to; the shared manager knows nothing about storage.
enum HotkeyKeys {
    static let capture = "HawkEye.hotkey.capture"
}
