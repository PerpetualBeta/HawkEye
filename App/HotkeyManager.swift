import AppKit
import Carbon.HIToolbox

/// Registers global hotkeys via Carbon's `RegisterEventHotKey`. Carbon
/// is the only path on macOS to install a system-wide hotkey from an
/// app that isn't a login item or accessibility client.
///
/// Single instance owned by AppDelegate. Call `register(_:slot:handler:)`
/// to install a hotkey for an internal slot id; calling again with the
/// same slot replaces the prior binding cleanly. Pass `.empty` to remove.
final class HotkeyManager {

    enum Slot: UInt32 {
        case capture = 1
    }

    private struct Registered {
        let ref: EventHotKeyRef
        let handler: () -> Void
    }
    private var slots: [Slot: Registered] = [:]
    private var eventHandler: EventHandlerRef?

    init() {
        installEventHandler()
    }

    deinit {
        if let h = eventHandler { RemoveEventHandler(h) }
        for (_, r) in slots { UnregisterEventHotKey(r.ref) }
    }

    func register(_ cfg: HotkeyConfig, slot: Slot, handler: @escaping () -> Void) {
        if let prev = slots.removeValue(forKey: slot) {
            UnregisterEventHotKey(prev.ref)
        }
        guard !cfg.isEmpty else {
            clog("HotkeyManager: slot=\(slot.rawValue) cleared (no hotkey)")
            return
        }

        let modifiers = carbonModifiers(from: cfg.modifierFlags)
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x48574B45),  // 'HWKE'
                                      id: slot.rawValue)
        let status = RegisterEventHotKey(UInt32(cfg.keyCode),
                                          modifiers,
                                          hotKeyID,
                                          GetEventDispatcherTarget(),
                                          0,
                                          &hotKeyRef)
        guard status == noErr, let ref = hotKeyRef else {
            clog("HotkeyManager: register failed status=\(status) slot=\(slot.rawValue)")
            return
        }
        slots[slot] = Registered(ref: ref, handler: handler)
        clog("HotkeyManager: registered slot=\(slot.rawValue) — \(HotkeyFormatter.glyphs(for: cfg))")
    }

    private func installEventHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(),
                            { (_: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) in
                                guard let event = event, let userData = userData else { return noErr }
                                let me = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                                var hkID = EventHotKeyID()
                                GetEventParameter(event,
                                                  EventParamName(kEventParamDirectObject),
                                                  EventParamType(typeEventHotKeyID),
                                                  nil,
                                                  MemoryLayout<EventHotKeyID>.size,
                                                  nil,
                                                  &hkID)
                                if let slot = Slot(rawValue: hkID.id),
                                   let reg = me.slots[slot] {
                                    DispatchQueue.main.async { reg.handler() }
                                }
                                return noErr
                            },
                            1,
                            &spec,
                            context,
                            &eventHandler)
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option)  { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift)   { m |= UInt32(shiftKey) }
        return m
    }
}

/// Single place for UserDefaults key names so the Settings UI and the
/// hotkey loader can't drift apart.
enum HotkeyKeys {
    static let capture = "HawkEye.hotkey.capture"
}
