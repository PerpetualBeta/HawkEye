import SwiftUI
import AppKit
import CoreGraphics

/// App-specific settings rows for HawkEye. Slotted into
/// `JorvikSettingsView` via its `appSettings` ViewBuilder above the
/// shared "General" section, so the layout matches the rest of the
/// Jorvik suite (Permissions → app-specific → General).
struct HawkEyeSettings: View {

    let onHotkeyChanged: (HotkeyConfig) -> Void

    @AppStorage("HawkEye.hudEnabled") private var hudEnabled: Bool = true

    /// CGPreflightScreenCaptureAccess flips immediately when the user
    /// grants Screen Recording in System Settings, but SwiftUI doesn't
    /// see the change without a redraw trigger. Re-poll on appear so
    /// returning to the Settings window after granting refreshes the
    /// indicator without a relaunch.
    @State private var screenRecordingGranted: Bool = CGPreflightScreenCaptureAccess()

    var body: some View {
        Section("Permissions") {
            HStack {
                Text("Screen Recording")
                Spacer()
                if screenRecordingGranted {
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
                        screenRecordingGranted = CGPreflightScreenCaptureAccess()
                        if !screenRecordingGranted {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                    .font(.caption)
                }
            }
            Text("Screen Recording is required for the hotkey-triggered capture of the active display. Loading an image from disk doesn't need this permission.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Capture") {
            HStack {
                Text("Hotkey")
                Spacer()
                HotkeyRecorderView(storageKey: HotkeyKeys.capture,
                                    onChange: onHotkeyChanged)
                    .frame(width: 180, height: 24)
            }
        }

        Section("Behaviour") {
            Toggle("Show feedback HUD", isOn: $hudEnabled)
        }
        .onAppear {
            screenRecordingGranted = CGPreflightScreenCaptureAccess()
        }

        // Debug logging is a power-user knob, not for the Settings UI.
        // Enable with:
        //   defaults write cc.jorviksoftware.HawkEye HawkEye.debugLogging -bool YES
        // Then relaunch HawkEye. Output goes to /tmp/hawkeye.log.
    }
}
