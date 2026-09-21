import SwiftUI
import AppKit
import CoreGraphics

/// App-specific settings rows for HawkEye. Slotted into
/// `JorvikSettingsView` via its `appSettings` ViewBuilder above the
/// shared "General" section, so the layout matches the rest of the
/// Jorvik suite (Permissions → app-specific → General).
struct HawkEyeSettings: View {

    let onHotkeyChanged: (HotkeyConfig) -> Void

    /// Brings the app's Carbon hotkey down while the recorder is listening.
    /// Without it, pressing the shortcut already set fires the capture instead
    /// of being recorded, and the shortcut can never be changed.
    let onRecordingChanged: (Bool) -> Void

    @AppStorage("HawkEye.hudEnabled") private var hudEnabled: Bool = true

    /// Kept current by JorvikKit. Screen Recording has no system announcement, so unlike
    /// Accessibility it is the once-a-second re-read that does the work — see
    /// `JorvikPermissionWatcher`.
    @StateObject private var screenRecording = JorvikPermissionWatcher.screenRecording()

    var body: some View {
        Section("Permissions") {
            HStack {
                Text("Screen Recording")
                Spacer()
                if screenRecording.isGranted {
                    Label("Granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else {
                    Button("Grant Access") {
                        // First call surfaces the system TCC prompt; after
                        // a prior denial CG silently records a request and
                        // returns false, so also nudge the user toward
                        // the Settings pane where they'd actually flip it.
                        _ = CGRequestScreenCaptureAccess()
                        screenRecording.reread()
                        if !screenRecording.isGranted {
                            JorvikPermissionWatcher.openSettings(pane: .screenRecording)
                        }
                    }
                    .font(.caption)
                }
            }
            Text("Screen Recording is required for the hotkey-triggered capture of the active display. Loading an image from disk doesn't need this permission.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        MenuBarVisibilitySettings()

        Section("Capture") {
            JorvikHotkeyRow(label: "Hotkey",
                            storageKey: HotkeyKeys.capture,
                            onChange: onHotkeyChanged,
                            onRecordingChanged: onRecordingChanged)
        }

        Section("Behaviour") {
            Toggle("Show feedback HUD", isOn: $hudEnabled)
        }

        // Debug logging is a power-user knob, not for the Settings UI.
        // Enable with:
        //   defaults write cc.jorviksoftware.HawkEye HawkEye.debugLogging -bool YES
        // Then relaunch HawkEye. Output goes to /tmp/hawkeye.log.
    }
}
