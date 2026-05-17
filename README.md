# HawkEye

A macOS menu-bar utility that adds a magnifier callout to an image. Drag to pick a source rectangle, drag the callout box to reposition it, drag the corners to resize. A high-contrast arrow keeps the callout visually anchored to its source. Save the result as a flat PNG.

## Two entry points

- **Hotkey** — by default `⌃⌥⇧⌘H` (Hyper-H). Grabs the active display (the one with the pointer on it) via ScreenCaptureKit and opens the editor.
- **Load Image…** — from the menu-bar pop-down (`⌘O` while the menu is open). Opens an existing PNG / JPEG / TIFF / HEIC and feeds it into the same editor.

## In the editor

- Drag on the image to define the source rectangle.
- A callout box is auto-placed next to it, showing a magnified copy of the source area.
- Drag the callout body to reposition it, drag its corners to resize it.
- Drag the source rectangle's body or corners to retarget — the callout re-magnifies automatically.
- Click empty image area to start a fresh selection.
- **Save Image…** (`⌘S`) writes a flat PNG at the source image's native pixel resolution.

## Menu

About · Capture Active Display · Load Image… · Settings… · Check for Updates… · Quit. Standard Jorvik suite order.

## Settings

- **Screen Recording** — required for the hotkey capture path. Loading from disk doesn't need it.
- **Capture hotkey** — recorder field; defaults to Hyper-H. Cleared with the ✕ button.
- **Show feedback HUD** — toggles the post-save toast.
- **Launch at Login** — standard `SMAppService` toggle.

## Privacy

No network. No telemetry. Screen Recording (when used) hits a single display via `ScreenCaptureKit`; nothing is written off-disk except the PNG you choose to save.

## Build

```
make dev-build   # arm64, Developer ID signed, Sparkle embedded
make run         # build, kill any running instance, open the bundle
make icon        # regenerate Resources/AppIcon.icns from generate_icon.swift
```

Requires the shared [`jorvik-release`](https://github.com/PerpetualBeta/jorvik-release) Make include at `../jorvik-release/release.mk`.

## Requirements

macOS 14 (Sonoma) or later.

## License

Public domain. No rights reserved.
