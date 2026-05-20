# HawkEye

A macOS menu-bar utility that adds a magnifier callout to an image. Drag to pick a source rectangle and a rounded callout appears, showing that region magnified, joined to its source by a tapered pointer that grows out of the callout's edge as if it were part of the same shape. Save the result as a flat PNG.

## Two entry points

- **Hotkey** — by default `⌃⌥⇧⌘H` (Hyper-H). Grabs the active display (the one with the pointer on it) via ScreenCaptureKit and opens the editor.
- **Load Image…** — from the menu-bar pop-down (`⌘O` while the menu is open). Opens an existing PNG / JPEG / TIFF / HEIC and feeds it into the same editor.

## In the editor

- Drag on the image to define the source rectangle.
- A rounded, drop-shadowed callout is auto-placed next to it, showing the source area magnified.
- The callout's pointer is a tapered wedge that's part of the same silhouette — one shape, one drop shadow, no separate arrow graphic.
- Drag the callout body to reposition it; drag its corners to resize. The callout's aspect ratio is locked to the selection's, so the magnified content never distorts.
- Drag the source rectangle's body or corners to retarget — the callout re-magnifies, and its aspect snaps to match.
- Drag the **pointer tip** to retarget the wedge at any point in the image; the tail rotates automatically to exit the callout from whichever side faces the tip. The selection marquee + handles fade out while you're placing the tip so nothing obstructs your aim.
- Click in empty image space without dragging is a no-op — your existing annotation isn't destroyed. Drag with motion to start a fresh selection.
- Press **Escape** (or `⌘.`) to clear the current annotation and start over.
- **Save Image…** (`⌘S`) writes a flat PNG at the source image's native pixel resolution. The selection marquee is editor-only — it doesn't appear in the saved file.

## Editor controls

The action bar at the bottom of the editor window:

- **Arrow colour** — system colour picker. Drives the wedge fill, the selection marquee, and the resize-handle rings so the annotation reads as one palette. Live (continuous) update.
- **Thickness** — slider, 2–24 image-pixels. Controls the pointer's base width.
- **Reset** — clears selection, callout, and any user-positioned pointer tip.
- **Save Image…** (`⌘S`) — flatten and write.

Both the colour and the thickness are persisted to `UserDefaults`, so the next time you open the editor you start with the same arrow settings.

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
