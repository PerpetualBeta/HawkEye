import Cocoa

/// The drawing + interaction surface of the editor window.
///
/// Coordinate model:
///   - The view is `isFlipped = true` so view coordinates match image
///     coordinates (origin top-left, y-down). All persistent state
///     (selection rect, callout rect) is stored in **image** coordinates
///     — view-space conversion is just a uniform scale + a centring
///     offset, computed each layout from the image and bounds sizes.
///
/// Interaction model:
///   - Click on a callout corner → resize callout.
///   - Click inside the callout body → move callout.
///   - Click on a selection corner → resize selection (and the callout
///     re-magnifies the new region on the next redraw).
///   - Click inside the selection body → move selection.
///   - Click on empty image area → start a new rubber-band selection.
///     (Replaces any prior selection; the callout is repositioned by
///     `CalloutGeometry.initialCallout` if it didn't exist yet.)
final class EditorCanvas: NSView {

    // MARK: - State (image coordinates)

    private(set) var image: CGImage
    private(set) var selection: CGRect = .null
    private(set) var callout: CGRect = .null

    /// Notified after each interaction so the window can enable/disable
    /// the Save button.
    var onStateChanged: (() -> Void)?

    private let handleRadius: CGFloat = 6
    private let selectionLineDash: [CGFloat] = [6, 4]

    // MARK: - Drag tracking

    private enum DragMode {
        case newSelection(startImagePoint: CGPoint)
        case moveSelection(startImagePoint: CGPoint, originalRect: CGRect)
        case resizeSelection(corner: CalloutGeometry.Corner, originalRect: CGRect)
        case moveCallout(startImagePoint: CGPoint, originalRect: CGRect)
        case resizeCallout(corner: CalloutGeometry.Corner, originalRect: CGRect)
    }
    private var dragMode: DragMode?

    // MARK: - Init

    init(image: CGImage) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.10, alpha: 1).cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    // MARK: - Image swap

    /// Replace the displayed image and reset overlays. Used when the
    /// editor window is reused across captures/loads.
    func setImage(_ image: CGImage) {
        self.image = image
        self.selection = .null
        self.callout = .null
        needsDisplay = true
        onStateChanged?()
    }

    // MARK: - Coordinate conversion

    /// View → image: scale factor + image origin in view space.
    /// Letterbox: image is centred and uniformly scaled to fit.
    private struct Layout {
        let scale: CGFloat
        let imageOriginInView: CGPoint
        let imageSizeInView: CGSize
    }

    private func currentLayout() -> Layout {
        let imageSize = CGSize(width: image.width, height: image.height)
        let viewSize = bounds.size
        let scale = min(viewSize.width / imageSize.width,
                         viewSize.height / imageSize.height)
        let drawnW = imageSize.width * scale
        let drawnH = imageSize.height * scale
        let originX = (viewSize.width  - drawnW) / 2
        let originY = (viewSize.height - drawnH) / 2
        return Layout(scale: scale,
                      imageOriginInView: CGPoint(x: originX, y: originY),
                      imageSizeInView: CGSize(width: drawnW, height: drawnH))
    }

    private func imageToView(_ rect: CGRect, layout l: Layout) -> CGRect {
        CGRect(x: l.imageOriginInView.x + rect.minX * l.scale,
               y: l.imageOriginInView.y + rect.minY * l.scale,
               width:  rect.width  * l.scale,
               height: rect.height * l.scale)
    }

    private func imageToView(_ point: CGPoint, layout l: Layout) -> CGPoint {
        CGPoint(x: l.imageOriginInView.x + point.x * l.scale,
                y: l.imageOriginInView.y + point.y * l.scale)
    }

    private func viewToImage(_ point: CGPoint, layout l: Layout) -> CGPoint {
        CGPoint(x: (point.x - l.imageOriginInView.x) / l.scale,
                y: (point.y - l.imageOriginInView.y) / l.scale)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let l = currentLayout()
        let imageSize = CGSize(width: image.width, height: image.height)
        let imageRectInView = CGRect(origin: l.imageOriginInView, size: l.imageSizeInView)

        // Draw the image (flipped view + CGContext draw → need to flip
        // back so the image isn't upside-down).
        ctx.saveGState()
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        let flippedRect = CGRect(x: imageRectInView.minX,
                                  y: bounds.height - imageRectInView.maxY,
                                  width: imageRectInView.width,
                                  height: imageRectInView.height)
        ctx.draw(image, in: flippedRect)
        ctx.restoreGState()

        // Drop a subtle 1px outline so the image extent is visible against
        // the dark canvas — useful when the image has white edges.
        ctx.setStrokeColor(NSColor(white: 1, alpha: 0.10).cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(imageRectInView)

        let hasSelection = !selection.isNull && selection.width > 0 && selection.height > 0
        let hasCallout   = !callout.isNull   && callout.width   > 0 && callout.height   > 0

        // Arrow first so the callout border draws over the head — cleaner
        // visual termination than the arrow tip floating outside the box.
        if hasSelection && hasCallout {
            drawArrow(in: ctx, layout: l, imageSize: imageSize)
        }

        if hasSelection {
            drawSelection(in: ctx, layout: l)
        }
        if hasCallout {
            drawCallout(in: ctx, layout: l)
        }
    }

    private func drawSelection(in ctx: CGContext, layout l: Layout) {
        let viewRect = imageToView(selection, layout: l)

        // Dashed white border, no fill. The fill would obscure the very
        // pixels the user is trying to call attention to.
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(2)
        ctx.setLineDash(phase: 0, lengths: selectionLineDash)
        ctx.stroke(viewRect)
        ctx.setLineDash(phase: 0, lengths: [])

        drawHandles(rect: viewRect, in: ctx, fill: .white)
    }

    private func drawCallout(in ctx: CGContext, layout l: Layout) {
        let viewRect = imageToView(callout, layout: l)

        // Clip to the callout, draw the cropped + zoomed source content
        // inside it. If selection isn't set yet, fill grey as a placeholder.
        ctx.saveGState()
        ctx.addRect(viewRect)
        ctx.clip()
        if !selection.isNull, selection.width > 0, selection.height > 0,
           let crop = image.cropping(to: integralCrop(selection))
        {
            // Flip back so the cropped image renders right-way-up under
            // the flipped view (same trick as the main image draw).
            ctx.saveGState()
            ctx.translateBy(x: 0, y: bounds.height)
            ctx.scaleBy(x: 1, y: -1)
            let flipped = CGRect(x: viewRect.minX,
                                  y: bounds.height - viewRect.maxY,
                                  width: viewRect.width,
                                  height: viewRect.height)
            ctx.interpolationQuality = .high
            ctx.draw(crop, in: flipped)
            ctx.restoreGState()
        } else {
            ctx.setFillColor(NSColor(white: 0.6, alpha: 0.4).cgColor)
            ctx.fill(viewRect)
        }
        ctx.restoreGState()

        // Bold white border so the callout reads clearly above the source
        // image even when the underlying content is white-on-light.
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(3)
        ctx.stroke(viewRect)

        drawHandles(rect: viewRect, in: ctx, fill: .white)
    }

    private func drawArrow(in ctx: CGContext, layout l: Layout, imageSize: CGSize) {
        let (tail, head, _, _) = CalloutGeometry.arrow(from: selection, to: callout)
        let vTail = imageToView(tail, layout: l)
        let vHead = imageToView(head, layout: l)

        // Two-layer stroke for high contrast on arbitrary backgrounds:
        // a fat white pill behind a thinner navy stroke. Same recipe as
        // CleanShot/Snagit — visible on light, dark, and busy backgrounds.
        let outerWidth: CGFloat = 8
        let innerWidth: CGFloat = 4
        ctx.setLineCap(.round)

        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(outerWidth)
        ctx.beginPath()
        ctx.move(to: vTail)
        ctx.addLine(to: vHead)
        ctx.strokePath()

        let brandBlue = NSColor(red: 0x00/255.0, green: 0x40/255.0, blue: 0x80/255.0, alpha: 1.0)
        ctx.setStrokeColor(brandBlue.cgColor)
        ctx.setLineWidth(innerWidth)
        ctx.beginPath()
        ctx.move(to: vTail)
        ctx.addLine(to: vHead)
        ctx.strokePath()

        // Arrowhead (solid, white outlined by navy for the same contrast).
        let angle = atan2(vHead.y - vTail.y, vHead.x - vTail.x)
        let len: CGFloat = 16
        let spread: CGFloat = .pi / 6
        let l1 = CGPoint(x: vHead.x - cos(angle - spread) * len,
                          y: vHead.y - sin(angle - spread) * len)
        let l2 = CGPoint(x: vHead.x - cos(angle + spread) * len,
                          y: vHead.y - sin(angle + spread) * len)
        let path = CGMutablePath()
        path.move(to: vHead)
        path.addLine(to: l1)
        path.addLine(to: l2)
        path.closeSubpath()

        ctx.setLineJoin(.round)
        ctx.setLineWidth(4)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.addPath(path)
        ctx.strokePath()

        ctx.setFillColor(brandBlue.cgColor)
        ctx.addPath(path)
        ctx.fillPath()
    }

    private func drawHandles(rect: CGRect, in ctx: CGContext, fill: NSColor) {
        let r = handleRadius
        for p in CalloutGeometry.handlePoints(of: rect).values {
            let dot = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            ctx.setFillColor(fill.cgColor)
            ctx.fillEllipse(in: dot)
            ctx.setStrokeColor(NSColor(white: 0, alpha: 0.6).cgColor)
            ctx.setLineWidth(1)
            ctx.strokeEllipse(in: dot)
        }
    }

    // MARK: - Hit testing

    /// Returns the corner whose handle (in view space) contains `point`,
    /// or nil. View-space hit-test so the handles stay the same physical
    /// size regardless of zoom.
    private func corner(of rect: CGRect, atView point: CGPoint, layout l: Layout)
        -> CalloutGeometry.Corner?
    {
        let viewRect = imageToView(rect, layout: l)
        let slop = handleRadius + 2
        for (corner, p) in CalloutGeometry.handlePoints(of: viewRect) {
            if abs(p.x - point.x) <= slop && abs(p.y - point.y) <= slop {
                return corner
            }
        }
        return nil
    }

    // MARK: - Mouse events

    override func mouseDown(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let l = currentLayout()
        let imagePoint = viewToImage(viewPoint, layout: l)

        // Priority: callout handles → callout body → selection handles →
        // selection body → new selection.
        if !callout.isNull {
            if let c = corner(of: callout, atView: viewPoint, layout: l) {
                dragMode = .resizeCallout(corner: c, originalRect: callout)
                return
            }
            if callout.contains(imagePoint) {
                dragMode = .moveCallout(startImagePoint: imagePoint, originalRect: callout)
                return
            }
        }
        if !selection.isNull {
            if let c = corner(of: selection, atView: viewPoint, layout: l) {
                dragMode = .resizeSelection(corner: c, originalRect: selection)
                return
            }
            if selection.contains(imagePoint) {
                dragMode = .moveSelection(startImagePoint: imagePoint, originalRect: selection)
                return
            }
        }

        // Empty space → start new selection (only if click landed on the
        // image, not on the letterbox).
        let imageRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        if imageRect.contains(imagePoint) {
            selection = CGRect(origin: imagePoint, size: .zero)
            dragMode = .newSelection(startImagePoint: imagePoint)
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mode = dragMode else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let l = currentLayout()
        let imagePoint = viewToImage(viewPoint, layout: l)
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)

        switch mode {
        case .newSelection(let start):
            // Drag rubber-band; clamp to image extent.
            let clamped = clampPoint(imagePoint, to: imageBounds)
            selection = CGRect(x: min(start.x, clamped.x),
                                y: min(start.y, clamped.y),
                                width: abs(clamped.x - start.x),
                                height: abs(clamped.y - start.y))

        case .moveSelection(let start, let orig):
            let dx = imagePoint.x - start.x
            let dy = imagePoint.y - start.y
            selection = orig.offsetBy(dx: dx, dy: dy)
            selection = clampRect(selection, to: imageBounds)

        case .resizeSelection(let corner, let orig):
            selection = CalloutGeometry.resize(orig, corner: corner, to: imagePoint)
            selection = clampRect(selection, to: imageBounds)

        case .moveCallout(let start, let orig):
            let dx = imagePoint.x - start.x
            let dy = imagePoint.y - start.y
            callout = orig.offsetBy(dx: dx, dy: dy)
            callout = clampRect(callout, to: imageBounds)

        case .resizeCallout(let corner, let orig):
            callout = CalloutGeometry.resize(orig, corner: corner, to: imagePoint)
            callout = clampRect(callout, to: imageBounds)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragMode = nil
            onStateChanged?()
        }
        guard let mode = dragMode else { return }
        if case .newSelection = mode {
            // Auto-place the callout if this is the first time and the
            // user drew something non-trivial. Don't clobber an existing
            // callout — the user might have intentionally re-selected.
            if callout.isNull && selection.width > 6 && selection.height > 6 {
                callout = CalloutGeometry.initialCallout(for: selection,
                                                          in: CGSize(width: image.width,
                                                                     height: image.height))
            } else if selection.width <= 6 || selection.height <= 6 {
                // Treat tiny drag as cancel — accidental click.
                selection = .null
            }
            needsDisplay = true
        }
    }

    override func resetCursorRects() {
        // Useful future hook for resize cursors on handles. Left empty
        // for now — the default pointer is acceptable while we shake
        // the interaction down.
    }

    // MARK: - Helpers

    private func clampPoint(_ p: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(x: min(max(p.x, bounds.minX), bounds.maxX),
                y: min(max(p.y, bounds.minY), bounds.maxY))
    }

    private func clampRect(_ r: CGRect, to bounds: CGRect) -> CGRect {
        var r = r
        if r.width > bounds.width { r.size.width = bounds.width }
        if r.height > bounds.height { r.size.height = bounds.height }
        if r.minX < bounds.minX { r.origin.x = bounds.minX }
        if r.minY < bounds.minY { r.origin.y = bounds.minY }
        if r.maxX > bounds.maxX { r.origin.x = bounds.maxX - r.width }
        if r.maxY > bounds.maxY { r.origin.y = bounds.maxY - r.height }
        return r
    }

    /// CGImage.cropping(to:) wants integer pixel rect.
    private func integralCrop(_ r: CGRect) -> CGRect {
        var r = r.integral
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        if r.maxX > w { r.size.width = w - r.minX }
        if r.maxY > h { r.size.height = h - r.minY }
        if r.minX < 0 { r.origin.x = 0 }
        if r.minY < 0 { r.origin.y = 0 }
        return r
    }

    // MARK: - Public actions

    /// Reset overlays to no-selection, no-callout. Image stays.
    func reset() {
        selection = .null
        callout = .null
        needsDisplay = true
        onStateChanged?()
    }

    /// True when the canvas has something worth saving — an image plus
    /// at least a callout. (The arrow only draws when both selection and
    /// callout exist, but the user can choose to save just the callout.)
    var hasContent: Bool {
        !callout.isNull && callout.width > 0 && callout.height > 0
    }

    /// Render the flattened result at the image's native pixel resolution.
    /// Off-screen render: no view-coordinate concerns — everything stays
    /// in image space, which is exactly how the persistent state is held.
    func renderFlattened() -> CGImage? {
        let w = image.width
        let h = image.height
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil,
                                   width: w,
                                   height: h,
                                   bitsPerComponent: 8,
                                   bytesPerRow: 0,
                                   space: cs,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            return nil
        }

        // CG default is bottom-left y-up. Our state is top-left y-down.
        // Flip the context so we can use image coords directly.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)

        // Image
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        let hasSelection = !selection.isNull && selection.width > 0 && selection.height > 0
        let hasCallout   = !callout.isNull   && callout.width   > 0 && callout.height   > 0

        if hasSelection && hasCallout {
            drawArrowFlattened(in: ctx, imageHeight: CGFloat(h))
        }
        if hasSelection {
            drawSelectionFlattened(in: ctx)
        }
        if hasCallout {
            drawCalloutFlattened(in: ctx)
        }
        return ctx.makeImage()
    }

    // Render variants used during flattening. Same shapes as the on-screen
    // versions, but in image coordinates (no view-space scale).
    private func drawSelectionFlattened(in ctx: CGContext) {
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(max(2, CGFloat(image.width) * 0.002))
        ctx.setLineDash(phase: 0, lengths: [10, 6])
        ctx.stroke(selection)
        ctx.setLineDash(phase: 0, lengths: [])
    }

    private func drawCalloutFlattened(in ctx: CGContext) {
        ctx.saveGState()
        ctx.addRect(callout)
        ctx.clip()
        if !selection.isNull, selection.width > 0, selection.height > 0,
           let crop = image.cropping(to: integralCrop(selection))
        {
            ctx.interpolationQuality = .high
            ctx.draw(crop, in: callout)
        } else {
            ctx.setFillColor(NSColor(white: 0.6, alpha: 0.4).cgColor)
            ctx.fill(callout)
        }
        ctx.restoreGState()

        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(max(3, CGFloat(image.width) * 0.003))
        ctx.stroke(callout)
    }

    private func drawArrowFlattened(in ctx: CGContext, imageHeight: CGFloat) {
        let (tail, head, _, _) = CalloutGeometry.arrow(from: selection, to: callout)

        let outer = max(8, CGFloat(image.width) * 0.008)
        let inner = max(4, CGFloat(image.width) * 0.004)
        let brandBlue = NSColor(red: 0x00/255.0, green: 0x40/255.0, blue: 0x80/255.0, alpha: 1.0)

        ctx.setLineCap(.round)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(outer)
        ctx.beginPath()
        ctx.move(to: tail)
        ctx.addLine(to: head)
        ctx.strokePath()

        ctx.setStrokeColor(brandBlue.cgColor)
        ctx.setLineWidth(inner)
        ctx.beginPath()
        ctx.move(to: tail)
        ctx.addLine(to: head)
        ctx.strokePath()

        let angle = atan2(head.y - tail.y, head.x - tail.x)
        let len = max(16, CGFloat(image.width) * 0.016)
        let spread: CGFloat = .pi / 6
        let l1 = CGPoint(x: head.x - cos(angle - spread) * len,
                          y: head.y - sin(angle - spread) * len)
        let l2 = CGPoint(x: head.x - cos(angle + spread) * len,
                          y: head.y - sin(angle + spread) * len)
        let path = CGMutablePath()
        path.move(to: head)
        path.addLine(to: l1)
        path.addLine(to: l2)
        path.closeSubpath()

        ctx.setLineJoin(.round)
        ctx.setLineWidth(max(4, CGFloat(image.width) * 0.004))
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.addPath(path)
        ctx.strokePath()

        ctx.setFillColor(brandBlue.cgColor)
        ctx.addPath(path)
        ctx.fillPath()
    }
}
