//  JorvikHotkeyRecorder.swift — canonical JorvikKit
//
//  The global-hotkey subsystem: a value type, its persistence, its display
//  formatting, the key-name tables, and the SwiftUI recorder field.
//
//  Promoted into JorvikKit on 2026-09-21. It had been hand-rolled four times —
//  ASCII Saver and Rainy Day shared one 206-line copy, HawkEye had 275 and
//  CopyLens 312, the latter two adding menu key equivalents. This is CopyLens's
//  version, which was the fullest and the best documented, with its app-specific
//  seed shortcut taken out. Each app keeps its own default; that is a product
//  decision, not shared infrastructure.
//
//  NOT to be confused with JorvikShortcutRecorder, which is a different and much
//  smaller thing: a recording *view* that hands the caller a shortcut and owns
//  no storage. Fourteen apps use that one and supply their own persistence. The
//  four that used this one get the whole subsystem instead, which is why they
//  were never migrated to the other.
//
//  Type names are deliberately unprefixed — HotkeyConfig, HotkeyStore,
//  HotkeyRecorderView — so that promoting the file changed no call site in any
//  of the four apps.

import AppKit
import SwiftUI
import Carbon.HIToolbox

// MARK: - HotkeyConfig + persistence

/// A keyboard-shortcut value: a keyCode + a set of NSEvent modifier
/// flags. Persisted to UserDefaults as JSON. Empty = unset (no hotkey
/// registered).
struct HotkeyConfig: Codable, Equatable {
    var keyCode: UInt16
    /// Stored as the raw `NSEvent.ModifierFlags` bitfield. Translated
    /// to Carbon flags by `HotkeyManager` at registration time.
    var rawModifierFlags: UInt

    static let empty = HotkeyConfig(keyCode: 0, rawModifierFlags: 0)
    var isEmpty: Bool { keyCode == 0 && rawModifierFlags == 0 }

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: rawModifierFlags)
            .intersection(.deviceIndependentFlagsMask)
    }

}

/// UserDefaults persistence for `HotkeyConfig`. Each hotkey slot has its
/// own key. Returns `.empty` when the key isn't present so the caller can
/// substitute a default.
enum HotkeyStore {
    static func read(_ key: String) -> HotkeyConfig {
        guard let data = UserDefaults.standard.data(forKey: key),
              let cfg  = try? JSONDecoder().decode(HotkeyConfig.self, from: data)
        else { return .empty }
        return cfg
    }
    static func write(_ key: String, _ cfg: HotkeyConfig) {
        if cfg.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(cfg) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - The shortcut row

/// The estate's shortcut row, backed by `HotkeyStore`.
///
/// `JorvikShortcutRecorder` is the single recorder UI across every Jorvik app,
/// and it is storage-agnostic: it binds a `keyCode`/`modifiers` pair. Apps that
/// keep a `HotkeyConfig` under a storage key use this adapter rather than a
/// second recorder, so all of them draw the same row.
///
/// This replaced `HotkeyRecorderView`, an `NSViewRepresentable` click-to-record
/// field that four apps used while the other eight used `JorvikShortcutRecorder`
/// — two components doing one job. The field's one capability the row lacked was
/// clearing a shortcut, so `JorvikShortcutRecorder` gained an optional `onClear`
/// and nothing was lost.
struct JorvikHotkeyRow: View {

    let label: String
    let storageKey: String
    var onChange: ((HotkeyConfig) -> Void)?

    /// Forwarded to `JorvikShortcutRecorder`. Apps registering a Carbon hotkey
    /// must unregister it while recording, or the shortcut already set fires the
    /// action instead of being recorded.
    var onRecordingChanged: ((Bool) -> Void)?

    @State private var config: HotkeyConfig = .empty

    var body: some View {
        JorvikShortcutRecorder(
            label: label,
            // Written separately by the recorder, so neither setter persists —
            // `onChanged` fires once after both and is where the write happens.
            keyCode: Binding(
                get: { config.keyCode },
                set: { config.keyCode = $0 }
            ),
            modifiers: Binding(
                get: { config.modifierFlags },
                set: { config.rawModifierFlags = $0.rawValue }
            ),
            // Empty string rather than a placeholder: the row hides its Clear
            // button when there is no text, which is the behaviour wanted when
            // there is no shortcut to clear.
            displayString: { config.isEmpty ? "" : HotkeyFormatter.glyphs(for: config) },
            onChanged: { persist() },
            onClear: {
                config = .empty
                persist()
            },
            onRecordingChanged: { onRecordingChanged?($0) }
        )
        .onAppear { config = HotkeyStore.read(storageKey) }
    }

    private func persist() {
        HotkeyStore.write(storageKey, config)
        onChange?(config)
    }
}


// MARK: - Formatters

/// Formats a HotkeyConfig as the standard glyph string (⌃⌥⇧⌘K).
enum HotkeyFormatter {
    static func glyphs(for cfg: HotkeyConfig) -> String {
        var s = ""
        let m = cfg.modifierFlags
        if m.contains(.control) { s += "⌃" }
        if m.contains(.option)  { s += "⌥" }
        if m.contains(.shift)   { s += "⇧" }
        if m.contains(.command) { s += "⌘" }
        s += KeyCodeNames.name(for: cfg.keyCode)
        return s
    }
}

// MARK: - NSMenuItem key-equivalent mapping

extension HotkeyConfig {
    /// `(keyEquivalent, modifierMask)` suitable for an `NSMenuItem`, or
    /// `nil` if the config is empty or the keyCode has no displayable
    /// character (e.g. Caps Lock). The menu item draws the standard
    /// "⌃⌥⇧⌘x" glyph string on the right edge from these values.
    ///
    /// Status-item menus only intercept their key-equivalents while the
    /// menu is open, so this is purely cosmetic — the global Carbon
    /// hotkey is what actually fires the capture.
    var menuKeyEquivalent: (key: String, modifiers: NSEvent.ModifierFlags)? {
        guard !isEmpty else { return nil }
        guard let key = MenuKeyEquivalent.character(for: keyCode) else { return nil }
        return (key, modifierFlags)
    }
}

/// Virtual keyCode → string suitable for `NSMenuItem.keyEquivalent`.
/// Returns nil for keyCodes that have no sensible menu representation.
///
/// Distinct from `KeyCodeNames` because the menu wants the *character*
/// (lowercase letters, the actual punctuation symbol, or the Unicode
/// scalar that AppKit reserves for arrows/function keys), not the
/// human-display name. Kept narrow on purpose: the recorder already
/// rejects keystrokes without a modifier, so the keyCodes that reach
/// here are the same set users actually pick for shortcuts.
enum MenuKeyEquivalent {
    static func character(for keyCode: UInt16) -> String? {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "a"; case kVK_ANSI_B: return "b"; case kVK_ANSI_C: return "c"
        case kVK_ANSI_D: return "d"; case kVK_ANSI_E: return "e"; case kVK_ANSI_F: return "f"
        case kVK_ANSI_G: return "g"; case kVK_ANSI_H: return "h"; case kVK_ANSI_I: return "i"
        case kVK_ANSI_J: return "j"; case kVK_ANSI_K: return "k"; case kVK_ANSI_L: return "l"
        case kVK_ANSI_M: return "m"; case kVK_ANSI_N: return "n"; case kVK_ANSI_O: return "o"
        case kVK_ANSI_P: return "p"; case kVK_ANSI_Q: return "q"; case kVK_ANSI_R: return "r"
        case kVK_ANSI_S: return "s"; case kVK_ANSI_T: return "t"; case kVK_ANSI_U: return "u"
        case kVK_ANSI_V: return "v"; case kVK_ANSI_W: return "w"; case kVK_ANSI_X: return "x"
        case kVK_ANSI_Y: return "y"; case kVK_ANSI_Z: return "z"
        case kVK_ANSI_0: return "0"; case kVK_ANSI_1: return "1"; case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"; case kVK_ANSI_4: return "4"; case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"; case kVK_ANSI_7: return "7"; case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_Backslash:    return "\\"
        case kVK_ANSI_Slash:        return "/"
        case kVK_ANSI_Period:       return "."
        case kVK_ANSI_Comma:        return ","
        case kVK_ANSI_Semicolon:    return ";"
        case kVK_ANSI_Quote:        return "'"
        case kVK_ANSI_LeftBracket:  return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Minus:        return "-"
        case kVK_ANSI_Equal:        return "="
        case kVK_ANSI_Grave:        return "`"
        case kVK_Space:  return " "
        case kVK_Return: return "\r"
        case kVK_Tab:    return "\t"
        case kVK_Escape: return "\u{1B}"
        case kVK_Delete: return "\u{08}"
        case kVK_UpArrow:    return String(format: "%C", NSUpArrowFunctionKey)
        case kVK_DownArrow:  return String(format: "%C", NSDownArrowFunctionKey)
        case kVK_LeftArrow:  return String(format: "%C", NSLeftArrowFunctionKey)
        case kVK_RightArrow: return String(format: "%C", NSRightArrowFunctionKey)
        case kVK_F1:  return String(format: "%C", NSF1FunctionKey)
        case kVK_F2:  return String(format: "%C", NSF2FunctionKey)
        case kVK_F3:  return String(format: "%C", NSF3FunctionKey)
        case kVK_F4:  return String(format: "%C", NSF4FunctionKey)
        case kVK_F5:  return String(format: "%C", NSF5FunctionKey)
        case kVK_F6:  return String(format: "%C", NSF6FunctionKey)
        case kVK_F7:  return String(format: "%C", NSF7FunctionKey)
        case kVK_F8:  return String(format: "%C", NSF8FunctionKey)
        case kVK_F9:  return String(format: "%C", NSF9FunctionKey)
        case kVK_F10: return String(format: "%C", NSF10FunctionKey)
        case kVK_F11: return String(format: "%C", NSF11FunctionKey)
        case kVK_F12: return String(format: "%C", NSF12FunctionKey)
        case kVK_F13: return String(format: "%C", NSF13FunctionKey)
        case kVK_F14: return String(format: "%C", NSF14FunctionKey)
        case kVK_F15: return String(format: "%C", NSF15FunctionKey)
        case kVK_F16: return String(format: "%C", NSF16FunctionKey)
        case kVK_F17: return String(format: "%C", NSF17FunctionKey)
        case kVK_F18: return String(format: "%C", NSF18FunctionKey)
        case kVK_F19: return String(format: "%C", NSF19FunctionKey)
        case kVK_F20: return String(format: "%C", NSF20FunctionKey)
        default: return nil
        }
    }
}

/// Best-effort mapping from virtual key codes to display strings.
/// Covers the keys most people will pick for shortcuts; falls back
/// to "Key N" for anything obscure.
enum KeyCodeNames {
    static func name(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"; case kVK_ANSI_B: return "B"; case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"; case kVK_ANSI_E: return "E"; case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"; case kVK_ANSI_H: return "H"; case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"; case kVK_ANSI_K: return "K"; case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"; case kVK_ANSI_N: return "N"; case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"; case kVK_ANSI_Q: return "Q"; case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"; case kVK_ANSI_T: return "T"; case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"; case kVK_ANSI_W: return "W"; case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"; case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"; case kVK_ANSI_1: return "1"; case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"; case kVK_ANSI_4: return "4"; case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"; case kVK_ANSI_7: return "7"; case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_Grave: return "`"
        case kVK_F1: return "F1"; case kVK_F2: return "F2"; case kVK_F3: return "F3"
        case kVK_F4: return "F4"; case kVK_F5: return "F5"; case kVK_F6: return "F6"
        case kVK_F7: return "F7"; case kVK_F8: return "F8"; case kVK_F9: return "F9"
        case kVK_F10: return "F10"; case kVK_F11: return "F11"; case kVK_F12: return "F12"
        // F13 to F20 can be recorded on their own, with no modifier, so they
        // must have names. Without these they drew as "Key 105" and similar.
        case kVK_F13: return "F13"; case kVK_F14: return "F14"; case kVK_F15: return "F15"
        case kVK_F16: return "F16"; case kVK_F17: return "F17"; case kVK_F18: return "F18"
        case kVK_F19: return "F19"; case kVK_F20: return "F20"
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Escape: return "⎋"
        case kVK_Delete: return "⌫"
        case kVK_LeftArrow: return "←"; case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"; case kVK_DownArrow: return "↓"
        default: return "Key \(keyCode)"
        }
    }
}
