import AppKit
import SwiftUI
import Carbon.HIToolbox

// MARK: - HotkeyConfig + persistence

/// A keyboard-shortcut value: a keyCode + a set of NSEvent modifier
/// flags. Persisted to UserDefaults as JSON. Empty = unset.
struct HotkeyConfig: Codable, Equatable {
    var keyCode: UInt16
    var rawModifierFlags: UInt

    static let empty = HotkeyConfig(keyCode: 0, rawModifierFlags: 0)
    var isEmpty: Bool { keyCode == 0 && rawModifierFlags == 0 }

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: rawModifierFlags)
            .intersection(.deviceIndependentFlagsMask)
    }

    /// Hyper-H — the seed default: Cmd+Ctrl+Opt+Shift+H. "H" for HawkEye,
    /// and a deliberate departure from CopyLens's "\" so a user running
    /// both doesn't see one swallow the other.
    static let defaultCapture = HotkeyConfig(
        keyCode: UInt16(kVK_ANSI_H),
        rawModifierFlags: NSEvent.ModifierFlags([.command, .control, .option, .shift]).rawValue
    )
}

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

// MARK: - SwiftUI recorder field

struct HotkeyRecorderView: NSViewRepresentable {

    let storageKey: String
    let onChange: (HotkeyConfig) -> Void

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        HotkeyRecorderNSView(storageKey: storageKey, onChange: onChange)
    }

    func updateNSView(_ nsView: HotkeyRecorderNSView, context: Context) {
        nsView.refreshLabel()
    }
}

final class HotkeyRecorderNSView: NSView {

    private let storageKey: String
    private let onChange: (HotkeyConfig) -> Void
    private var label: NSTextField!
    private var clearButton: NSButton!
    private var monitor: Any?
    private var recording = false {
        didSet { refreshLabel() }
    }

    init(storageKey: String, onChange: @escaping (HotkeyConfig) -> Void) {
        self.storageKey = storageKey
        self.onChange = onChange
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.alignment = .center
        label.font = .systemFont(ofSize: 13)
        addSubview(label)

        clearButton = NSButton(title: "✕", target: self, action: #selector(clearShortcut))
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.bezelStyle = .accessoryBarAction
        clearButton.isBordered = false
        clearButton.font = .systemFont(ofSize: 11)
        addSubview(clearButton)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: clearButton.leadingAnchor, constant: -4),
        ])
        refreshLabel()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        if !recording { startRecording() }
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handle(event: event)
            return nil
        }
    }

    private func handle(event: NSEvent) {
        guard recording else { return }
        if event.type == .flagsChanged { return }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !mods.intersection([.command, .option, .control, .shift]).isEmpty else { return }
        let cfg = HotkeyConfig(keyCode: UInt16(event.keyCode), rawModifierFlags: mods.rawValue)
        HotkeyStore.write(storageKey, cfg)
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        onChange(cfg)
    }

    @objc private func clearShortcut() {
        HotkeyStore.write(storageKey, .empty)
        onChange(.empty)
        refreshLabel()
    }

    func refreshLabel() {
        if recording {
            label.stringValue = "Press a shortcut…"
            label.textColor = .secondaryLabelColor
        } else {
            let cfg = HotkeyStore.read(storageKey)
            if cfg.isEmpty {
                label.stringValue = "Click to set"
                label.textColor = .secondaryLabelColor
            } else {
                label.stringValue = HotkeyFormatter.glyphs(for: cfg)
                label.textColor = .labelColor
            }
        }
    }
}

// MARK: - Formatters

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

extension HotkeyConfig {
    var menuKeyEquivalent: (key: String, modifiers: NSEvent.ModifierFlags)? {
        guard !isEmpty else { return nil }
        guard let key = MenuKeyEquivalent.character(for: keyCode) else { return nil }
        return (key, modifierFlags)
    }
}

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
        default: return nil
        }
    }
}

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
