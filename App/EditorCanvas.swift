import Cocoa

/// The drawing + interaction surface of the editor window.
///
/// Coordinate model:
///   - The view is `isFlipped = true` so view coordinates match image
///     coordinates (origin top-left, y-down). All persistent state
///     (selection rect, callout rect, arrowHeadAnchor) is stored in
///     image coordinates — view-space conversion is just a uniform
///     scale + a centring offset, computed each layout from the image
///     and bounds sizes.
///
/// Visual annotation style:
///   - Callout + pointer render as a single silhouette: a rounded
///     rectangle with a tapered triangular pointer growing out of the
///     edge facing the source area. One shape, one drop shadow, one
///     boundary — the pointer reads as part of the callout rather than
///     a separate arrow graphic.
///   - The pointer is filled in the user-chosen `arrowColor`; the
///     callout's interior is the cropped + magnified source content
///     (clipped to the rounded rect).
///   - Selection marquee: dashed rectangle in the same arrow colour so
///     the annotation reads as one coherent palette. Editor-only — not
///     rendered into the saved PNG.
///
/// Arrow head positioning:
///   - `arrowHeadAnchor` is the absolute image-space point the wedge
///     apex sits at. `nil` means auto-route to the midpoint of the
///     selection's facing edge. User-positioned anchors are cleared
///     when a fresh selection is committed or Reset is hit.
final class EditorCanvas: NSView {

    // MARK: - State (image coordinates)

    private(set) var image: CGImage
    private(set) var selection: CGRect = .null
    private(set) var callout: CGRect = .null

    /// User-positioned arrow head, in image coordinates. `nil` means
    /// the head auto-routes to the midpoint of the selection edge
    /// facing the callout (see `currentArrowEndpoints`).
    private(set) var arrowHeadAnchor: CGPoint?

    var arrowColor: NSColor = .systemRed {
        didSet { needsDisplay = true }
    }

    /// Arrow / wedge thickness in **image-pixel** units. Controls the
    /// wedge's base width via `baseHalfWidth = arrowLineWidth * 1.75`,
    /// driven by the slider in the editor's action bar. On-screen the
    /// computed image-pixel value gets converted to view points via
    /// `layout.scale`; the flatten pass uses it directly.
    var arrowLineWidth: CGFloat = 8 {
        didSet { needsDisplay = true }
    }

    /// When true, the pointer + border colour is auto-derived to make the
    /// callout stand out from the **background image it sits on** — a subtle
    /// accent that contrasts in luminance and complements the surrounding hue
    /// (see `suggestedArrowColor`). Recomputed whenever the selection or
    /// callout position changes. The user can switch this off and pick a
    /// colour manually; turning it back on recomputes immediately.
    var autoArrowColor: Bool = true {
        didSet {
            if autoArrowColor { recomputeAutoColor() }
            needsDisplay = true
        }
    }

    /// Fired when auto mode picks a new colour, so the window can reflect it
    /// in the colour well. Not persisted — auto colours are derived, not stored.
    var onArrowColorAutoUpdated: ((NSColor) -> Void)?

    /// Notified after each interaction so the window can enable/disable
    /// the Save button.
    var onStateChanged: (() -> Void)?

    // MARK: - Style constants (image-pixel space)

    private let calloutCornerRadius: CGFloat = 14
    private let calloutShadowOffset: CGFloat = 8
    private let calloutShadowBlur: CGFloat = 20

    /// Invisible grab margin (view-space points) around each corner for
    /// resize hit-testing. Replaces the old visible handle dots — resize is
    /// now signalled by the cursor (diagonal arrow on hover), not chrome.
    private let cornerGrabSlop: CGFloat = 11
    private let selectionLineDash: [CGFloat] = [4, 3]

    /// Half the wedge's base width, as a multiple of `arrowLineWidth`.
    /// 1.75× gives a base that reads as a proper pointer at the
    /// default thickness without overpowering the callout.
    private let wedgeBaseHalfWidthMultiplier: CGFloat = 1.75

    /// How far the wedge's base extends INTO the callout from the
    /// chosen edge midpoint. Anti-aliasing gap insurance — keeps the
    /// pointer/callout join seamless. Scales with thickness so very
    /// thin pointers don't push deep into the magnified content.
    private let wedgeInsetMultiplier: CGFloat = 0.5

    /// Width of the manual-mode bubble outline, in image-pixel units. Tied
    /// loosely to the pointer thickness so the frame stays proportionate to
    /// the wedge it continues from (~2px at the default thickness).
    private var calloutBorderWidthImage: CGFloat { max(2, arrowLineWidth * 0.25) }

    // MARK: - Drag tracking

    private enum DragMode {
        /// Empty-image-space drag. `committed` flips true once the
        /// pointer has moved far enough to count as a real rubber-band
        /// drag — until then, a bare click here is a no-op so the
        /// user's existing selection/callout aren't destroyed by a
        /// stray click.
        case newSelection(startImagePoint: CGPoint, committed: Bool)
        case moveSelection(startImagePoint: CGPoint, originalRect: CGRect)
        case resizeSelection(corner: CalloutGeometry.Corner, originalRect: CGRect)
        case moveCallout(startImagePoint: CGPoint, originalRect: CGRect)
        case resizeCallout(corner: CalloutGeometry.Corner, originalRect: CGRect)
        case dragArrowHead
    }
    private var dragMode: DragMode?

    private let newSelectionCommitThreshold: CGFloat = 4

    /// True while the pointer is hovering over the (committed) source
    /// selection at rest. Brings the marquee back so the user can see and
    /// grab the source region without it cluttering the view the rest of
    /// the time.
    private var isHoveringSelection = false {
        didSet { if isHoveringSelection != oldValue { needsDisplay = true } }
    }

    /// The rubber-band rectangle while a *new* selection is being dragged.
    /// Kept separate from the committed `selection`/`callout` so dragging (or
    /// a stray click) in empty space doesn't destroy an existing callout —
    /// the existing annotation is only replaced once a valid new selection is
    /// committed on mouse-up. `nil` when not drawing a new selection.
    private var draftSelection: CGRect?

    /// True while the user is actively dragging the arrow head. The
    /// editor hides selection chrome (marquee + corner handles) during
    /// this drag so the user can place the tip precisely.
    private var isDraggingArrowHead: Bool {
        if case .dragArrowHead = dragMode { return true }
        return false
    }

    /// True only while the user is actively drawing, moving, or resizing the
    /// source selection. The dashed marquee is drawn only then — at rest the
    /// editor shows just the callout + pointer (and the marquee never appears
    /// in the saved image regardless).
    private var isManipulatingSelection: Bool {
        switch dragMode {
        case .moveSelection, .resizeSelection: return true
        default: return false
        }
    }

    // MARK: - Init

    init(image: CGImage) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.10, alpha: 1).cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override var acceptsFirstResponder: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        dragMode = nil
        reset()
    }

    // MARK: - Image swap

    func setImage(_ image: CGImage) {
        self.image = image
        self.selection = .null
        self.callout = .null
        self.arrowHeadAnchor = nil
        self.draftSelection = nil
        needsDisplay = true
        onStateChanged?()
    }

    // MARK: - Coordinate conversion

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

    // MARK: - Arrow endpoints + wedge geometry

    /// Tail + head image-space points for the current annotation state,
    /// or `nil` if either rectangle is unset.
    private func currentArrowEndpoints() -> (tail: CGPoint, head: CGPoint)? {
        guard !selection.isNull, selection.width > 0, selection.height > 0,
              !callout.isNull, callout.width > 0, callout.height > 0
        else { return nil }
        if let anchor = arrowHeadAnchor {
            let tail = CalloutGeometry.calloutAnchor(of: callout, towards: anchor)
            return (tail, anchor)
        } else {
            let (t, h, _, _) = CalloutGeometry.arrow(from: callout, to: selection)
            return (t, h)
        }
    }

    /// The three image-space points of the wedge pointer:
    /// `(baseLeft, apex, baseRight)`. `nil` if there's no valid pointer
    /// (no selection/callout, or the head sits inside the callout —
    /// where the pointer would become a degenerate inward-pointing
    /// triangle).
    private func wedgePointsInImageSpace() -> (baseLeft: CGPoint, apex: CGPoint, baseRight: CGPoint)? {
        guard let (_, head) = currentArrowEndpoints() else { return nil }

        // Refuse a wedge pointing into the callout's own interior.
        // Small inset so a head right on the boundary still draws.
        if callout.insetBy(dx: -2, dy: -2).contains(head) { return nil }

        let chosenSide = CalloutGeometry.side(of: callout, towards: head)
        let edgeMid = CalloutGeometry.edgeMidpoint(on: callout, side: chosenSide)
        let (perp, inward) = baseAxes(for: chosenSide)

        let baseHalfWidth = arrowLineWidth * wedgeBaseHalfWidthMultiplier
        let inset = max(1, arrowLineWidth * wedgeInsetMultiplier)

        // Inset the base into the callout so it overlaps the rounded
        // rect at the join. Hides any anti-aliasing seam between the
        // wedge's base edge and the callout's edge.
        let baseCenter = CGPoint(x: edgeMid.x + inward.x * inset,
                                  y: edgeMid.y + inward.y * inset)
        let baseLeft = CGPoint(x: baseCenter.x + perp.x * baseHalfWidth,
                                y: baseCenter.y + perp.y * baseHalfWidth)
        let baseRight = CGPoint(x: baseCenter.x - perp.x * baseHalfWidth,
                                 y: baseCenter.y - perp.y * baseHalfWidth)
        return (baseLeft, head, baseRight)
    }

    /// Unit vectors for the named side, in image-space (top-left
    /// origin, y-down). `perp` is parallel to the edge (drives the
    /// wedge base width); `inward` points into the rectangle (drives
    /// the wedge's inset for a seamless join with the callout).
    private func baseAxes(for side: CalloutGeometry.Side) -> (perp: CGPoint, inward: CGPoint) {
        switch side {
        case .top:    return (CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1))
        case .bottom: return (CGPoint(x: 1, y: 0), CGPoint(x: 0, y: -1))
        case .left:   return (CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 0))
        case .right:  return (CGPoint(x: 0, y: 1), CGPoint(x: -1, y: 0))
        }
    }

    // MARK: - Drawing (on-screen)

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let l = currentLayout()
        let imageRectInView = CGRect(origin: l.imageOriginInView, size: l.imageSizeInView)

        // Draw the source image — locally flip the CTM so the bitmap
        // renders right-way-up under the y-down view.
        ctx.saveGState()
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        let flippedRect = CGRect(x: imageRectInView.minX,
                                  y: bounds.height - imageRectInView.maxY,
                                  width: imageRectInView.width,
                                  height: imageRectInView.height)
        ctx.draw(image, in: flippedRect)
        ctx.restoreGState()

        let hasSelection = !selection.isNull && selection.width > 0 && selection.height > 0
        let hasCallout   = !callout.isNull   && callout.width   > 0 && callout.height   > 0

        // Selection marquee first so the callout's silhouette
        // overlays any stray crossing — though `initialCallout`
        // places the callout outside the selection so they shouldn't
        // typically intersect.
        if let draft = draftSelection {
            // Drawing a new selection: show the rubber-band; the existing
            // callout (if any) is hidden for the duration and restored if the
            // draft turns out too small to commit.
            drawMarquee(draft, in: ctx, layout: l)
        } else if hasSelection && (isManipulatingSelection || isHoveringSelection) {
            drawMarquee(selection, in: ctx, layout: l)
        }
        if hasCallout && draftSelection == nil {
            drawCalloutWithPointer(in: ctx, layout: l)
        }
    }

    private func drawMarquee(_ imageRect: CGRect, in ctx: CGContext, layout l: Layout) {
        let viewRect = imageToView(imageRect, layout: l)

        // A fine, fixed hairline — deliberately decoupled from arrowLineWidth
        // so a thick pointer doesn't drag a heavy marquee along with it.
        ctx.setStrokeColor(arrowColor.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: selectionLineDash)
        ctx.stroke(viewRect)
        ctx.setLineDash(phase: 0, lengths: [])
    }

    private func drawCalloutWithPointer(in ctx: CGContext, layout l: Layout) {
        let viewRect = imageToView(callout, layout: l)
        let radius = calloutCornerRadius * l.scale
        let roundedPath = CGPath(roundedRect: viewRect,
                                  cornerWidth: radius,
                                  cornerHeight: radius,
                                  transform: nil)

        // Build the wedge path in view-space, if applicable.
        let wedgePath: CGPath? = {
            guard let pts = wedgePointsInImageSpace() else { return nil }
            let p = CGMutablePath()
            p.move(to: imageToView(pts.baseLeft, layout: l))
            p.addLine(to: imageToView(pts.apex, layout: l))
            p.addLine(to: imageToView(pts.baseRight, layout: l))
            p.closeSubpath()
            return p
        }()

        // Step 1 — combined silhouette + shadow. Filling rounded rect
        // and wedge as a single path-with-subpaths casts one unified
        // shadow under both. The white fill is mostly covered by the
        // wedge fill (step 2) and the magnified content (step 3); the
        // only place white actually shows is at sub-pixel anti-alias
        // edges, where it's the correct neutral.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: calloutShadowOffset * l.scale),
                       blur: calloutShadowBlur * l.scale,
                       color: NSColor(white: 0, alpha: 0.45).cgColor)
        ctx.setFillColor(NSColor.white.cgColor)
        let silhouette = CGMutablePath()
        silhouette.addPath(roundedPath)
        if let w = wedgePath { silhouette.addPath(w) }
        ctx.addPath(silhouette)
        ctx.fillPath()
        ctx.restoreGState()

        // Step 2 — wedge fill in arrowColor. Covers the white from
        // step 1 inside the wedge triangle.
        if let w = wedgePath {
            ctx.saveGState()
            ctx.setFillColor(arrowColor.cgColor)
            ctx.addPath(w)
            ctx.fillPath()
            ctx.restoreGState()
        }

        // Step 3 — clip to the rounded rect, draw cropped + zoomed
        // source content. Covers any wedge color that extended into
        // the callout's interior via the inset.
        ctx.saveGState()
        ctx.addPath(roundedPath)
        ctx.clip()
        if !selection.isNull, selection.width > 0, selection.height > 0,
           let crop = image.cropping(to: integralCrop(selection))
        {
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

        // Step 4 — outline the bubble in arrowColor so the same-coloured wedge
        // reads as one shape with it. The segment of this outline under the
        // wedge base is the wedge's own colour, so the join stays seamless.
        // Drawn in both modes: the auto colour now contrasts with the
        // background, so the border helps delineate the callout from the scene.
        ctx.saveGState()
        ctx.addPath(roundedPath)
        ctx.setStrokeColor(arrowColor.cgColor)
        ctx.setLineWidth(max(1.5, calloutBorderWidthImage * l.scale))
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Hit testing

    private func corner(of rect: CGRect, atView point: CGPoint, layout l: Layout)
        -> CalloutGeometry.Corner?
    {
        let viewRect = imageToView(rect, layout: l)
        let slop = cornerGrabSlop
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

        // Arrow-head drag has highest priority — let the user grab it
        // even when it overlaps the selection rect or sits near a
        // callout corner.
        if let (_, head) = currentArrowEndpoints() {
            let viewHead = imageToView(head, layout: l)
            let dx = viewPoint.x - viewHead.x
            let dy = viewPoint.y - viewHead.y
            let viewLineWidth = max(2, arrowLineWidth * l.scale)
            let hitRadius = max(12, viewLineWidth * 2)
            if sqrt(dx * dx + dy * dy) <= hitRadius {
                dragMode = .dragArrowHead
                return
            }
        }

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

        let imageRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        if imageRect.contains(imagePoint) {
            dragMode = .newSelection(startImagePoint: imagePoint, committed: false)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mode = dragMode else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let l = currentLayout()
        let imagePoint = viewToImage(viewPoint, layout: l)
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)

        switch mode {
        case .newSelection(let start, let committed):
            let dxImg = imagePoint.x - start.x
            let dyImg = imagePoint.y - start.y
            let viewDistance = sqrt(dxImg * dxImg + dyImg * dyImg) * l.scale
            if !committed {
                if viewDistance < newSelectionCommitThreshold { return }
                dragMode = .newSelection(startImagePoint: start, committed: true)
            }
            let clamped = clampPoint(imagePoint, to: imageBounds)
            draftSelection = CGRect(x: min(start.x, clamped.x),
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
            reconformCalloutAspect(bounds: imageBounds)

        case .moveCallout(let start, let orig):
            let dx = imagePoint.x - start.x
            let dy = imagePoint.y - start.y
            callout = orig.offsetBy(dx: dx, dy: dy)
            callout = clampRect(callout, to: imageBounds)

        case .resizeCallout(let corner, let orig):
            if !selection.isNull, selection.width > 0, selection.height > 0 {
                let aspect = selection.width / selection.height
                callout = CalloutGeometry.aspectLockedResize(orig, corner: corner,
                                                              to: imagePoint, aspect: aspect)
            } else {
                callout = CalloutGeometry.resize(orig, corner: corner, to: imagePoint)
            }
            callout = clampRect(callout, to: imageBounds)

        case .dragArrowHead:
            arrowHeadAnchor = clampPoint(imagePoint, to: imageBounds)
        }
        dragCursor(for: mode).set()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragMode = nil
            if autoArrowColor { recomputeAutoColor() }
            needsDisplay = true
            onStateChanged?()
            // Restore the hover cursor for wherever the pointer ended up.
            NSCursor.arrow.set()
            hoverCursor(atView: convert(event.locationInWindow, from: nil)).set()
        }
        guard let mode = dragMode else { return }
        if case .newSelection(_, let committed) = mode {
            // Only replace the existing annotation if a real new rectangle was
            // drawn. A bare click or a tiny accidental drag leaves the current
            // selection + callout untouched.
            if committed, let draft = draftSelection, draft.width > 6, draft.height > 6 {
                selection = draft
                callout = CalloutGeometry.initialCallout(for: selection,
                                                          in: CGSize(width: image.width,
                                                                     height: image.height))
                arrowHeadAnchor = nil
            }
            draftSelection = nil
            needsDisplay = true
        }
    }

    override func resetCursorRects() { }

    // MARK: - Cursor hints
    //
    // Resize/move is discoverable via the cursor rather than visible
    // handles: a diagonal resize arrow at the corners, an open hand over a
    // draggable body or the arrow head, the arrow elsewhere. The editor
    // window is active and key, so manual cursor management (a .mouseMoved
    // tracking area + NSCursor.set) is reliable here.

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseMoved(with event: NSEvent) {
        guard dragMode == nil else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        hoverCursor(atView: viewPoint).set()

        // Reveal the marquee when the pointer is over the source region or
        // one of its corners.
        let l = currentLayout()
        let overBody = !selection.isNull && selection.contains(viewToImage(viewPoint, layout: l))
        let overCorner = !selection.isNull && corner(of: selection, atView: viewPoint, layout: l) != nil
        isHoveringSelection = overBody || overCorner
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
        isHoveringSelection = false
    }

    /// The cursor to show when hovering (no drag in progress), mirroring the
    /// hit-test priority used in `mouseDown`.
    private func hoverCursor(atView viewPoint: CGPoint) -> NSCursor {
        let l = currentLayout()

        if let (_, head) = currentArrowEndpoints() {
            let viewHead = imageToView(head, layout: l)
            let dx = viewPoint.x - viewHead.x
            let dy = viewPoint.y - viewHead.y
            let viewLineWidth = max(2, arrowLineWidth * l.scale)
            let hitRadius = max(12, viewLineWidth * 2)
            if sqrt(dx * dx + dy * dy) <= hitRadius { return .openHand }
        }
        if !callout.isNull {
            if let c = corner(of: callout, atView: viewPoint, layout: l) { return diagonalCursor(for: c) }
            if callout.contains(viewToImage(viewPoint, layout: l)) { return .openHand }
        }
        if !selection.isNull {
            if let c = corner(of: selection, atView: viewPoint, layout: l) { return diagonalCursor(for: c) }
            if selection.contains(viewToImage(viewPoint, layout: l)) { return .openHand }
        }
        return .arrow
    }

    private func dragCursor(for mode: DragMode) -> NSCursor {
        switch mode {
        case .resizeSelection(let c, _), .resizeCallout(let c, _): return diagonalCursor(for: c)
        case .newSelection: return .crosshair
        default: return .closedHand
        }
    }

    private func diagonalCursor(for corner: CalloutGeometry.Corner) -> NSCursor {
        switch corner {
        case .topLeft, .bottomRight: return .resizeDiagonalNWSE
        case .topRight, .bottomLeft: return .resizeDiagonalNESW
        }
    }

    // MARK: - Auto pointer colour

    /// Recompute and apply the auto pointer colour for the current
    /// selection, notifying the window so the colour well reflects it.
    /// No-op when there's no usable selection.
    private func recomputeAutoColor() {
        guard autoArrowColor, let c = suggestedArrowColor() else { return }
        arrowColor = c
        onArrowColorAutoUpdated?(c)
    }

    /// Derive a pointer + border colour that makes the callout stand out from
    /// the **background image it sits on** — a subtle accent that contrasts in
    /// luminance and complements the surrounding hue, rather than echoing the
    /// callout's own (potentially camouflaging) content. `nil` when there's no
    /// usable callout to sample around.
    func suggestedArrowColor() -> NSColor? {
        guard !callout.isNull, callout.width >= 2, callout.height >= 2,
              let background = backgroundContextColor() else { return nil }
        return Self.contrastingPointerColor(against: background)
    }

    /// Average colour of the background ring immediately surrounding the
    /// callout — the slice of the scene the annotation has to read against.
    /// Samples the four bands just outside the callout edges (clamped to the
    /// image) and means them; falls back to the whole image if the callout
    /// fills it (no ring to sample).
    private func backgroundContextColor() -> NSColor? {
        let margin = max(24, min(callout.width, callout.height) * 0.35)
        let imageRect = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
        let bands = [
            CGRect(x: callout.minX - margin, y: callout.minY - margin, width: callout.width + 2 * margin, height: margin), // above
            CGRect(x: callout.minX - margin, y: callout.maxY,          width: callout.width + 2 * margin, height: margin), // below
            CGRect(x: callout.minX - margin, y: callout.minY,          width: margin, height: callout.height),             // left
            CGRect(x: callout.maxX,          y: callout.minY,          width: margin, height: callout.height),             // right
        ]
        var samples: [NSColor] = []
        for band in bands {
            let clipped = band.intersection(imageRect)
            guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1,
                  let crop = image.cropping(to: integralCrop(clipped)),
                  let avg = Self.averageColor(of: crop) else { continue }
            samples.append(avg)
        }
        if samples.isEmpty {
            guard let crop = image.cropping(to: integralCrop(imageRect)) else { return nil }
            return Self.averageColor(of: crop)
        }
        return Self.meanColor(samples)
    }

    /// Box-average an image by rendering it into a 1×1 sRGB context.
    /// Deterministic and fast — the single pixel is the area average.
    private static func averageColor(of image: CGImage) -> NSColor? {
        var px: [UInt8] = [0, 0, 0, 0]
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8,
                                  bytesPerRow: 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let a = CGFloat(px[3]) / 255
        guard a > 0 else { return nil }
        // Un-premultiply.
        return NSColor(srgbRed: CGFloat(px[0]) / 255 / a,
                       green: CGFloat(px[1]) / 255 / a,
                       blue: CGFloat(px[2]) / 255 / a,
                       alpha: 1)
    }

    /// Mean of several sampled colours, in sRGB.
    private static func meanColor(_ colors: [NSColor]) -> NSColor? {
        guard !colors.isEmpty else { return nil }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        for colour in colors {
            let s = colour.usingColorSpace(.sRGB) ?? colour
            r += s.redComponent; g += s.greenComponent; b += s.blueComponent
        }
        let n = CGFloat(colors.count)
        return NSColor(srgbRed: r / n, green: g / n, blue: b / n, alpha: 1)
    }

    /// Calm blue accent used when the background has no hue of its own (the
    /// common grey/white UI-screenshot case) — so the callout still gets a
    /// discernible colour instead of melting into the chrome.
    private static let neutralAccentHue: CGFloat = 0.58

    /// Pick a subtle accent the callout (wedge + border) reads clearly against
    /// `background`. Luminance does the heavy lifting — a light accent on dark
    /// scenes, a deeper one on light scenes — with a complementary hue when the
    /// background is chromatic. Saturation stays moderate: discernible, never
    /// gaudy. These four constants are the taste dials.
    private static func contrastingPointerColor(against background: NSColor) -> NSColor {
        let c = background.usingColorSpace(.sRGB) ?? background
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let luminance = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent

        // Complement the background's hue when it has one; otherwise a calm
        // default accent for neutral scenes.
        let hue = s > 0.15 ? (h + 0.5).truncatingRemainder(dividingBy: 1.0) : neutralAccentHue
        // Light backgrounds get a deeper, slightly richer accent; dark
        // backgrounds get a brighter, lighter one. Moderate saturation either way.
        let onLight = luminance >= 0.5
        let saturation: CGFloat = onLight ? 0.60 : 0.50
        let brightness: CGFloat = onLight ? 0.55 : 0.92
        return NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
    }

    // MARK: - Helpers

    private func reconformCalloutAspect(bounds: CGRect) {
        guard !selection.isNull, selection.width > 0, selection.height > 0,
              !callout.isNull,   callout.width   > 0, callout.height   > 0
        else { return }
        let aspect = selection.width / selection.height
        let currentAspect = callout.width / callout.height
        if abs(aspect - currentAspect) < 0.001 { return }
        let centre = CGPoint(x: callout.midX, y: callout.midY)
        let newHeight = callout.width / aspect
        callout = CGRect(x: centre.x - callout.width / 2,
                         y: centre.y - newHeight / 2,
                         width: callout.width,
                         height: newHeight)
        callout = clampRect(callout, to: bounds)
    }

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

    func reset() {
        selection = .null
        callout = .null
        arrowHeadAnchor = nil
        draftSelection = nil
        needsDisplay = true
        onStateChanged?()
    }

    var hasContent: Bool {
        !callout.isNull && callout.width > 0 && callout.height > 0
    }

    // MARK: - Flatten

    /// Render the flattened result at the image's native pixel
    /// resolution. CG context stays in default y-up orientation so the
    /// source bitmap draws right-side-up; image-space coordinates are
    /// converted to CG-space via the local `cgRect`/`cgPoint` closures
    /// per shape.
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

        let H = CGFloat(h)
        let cgRect: (CGRect) -> CGRect = { r in
            CGRect(x: r.minX, y: H - r.maxY, width: r.width, height: r.height)
        }
        let cgPoint: (CGPoint) -> CGPoint = { p in
            CGPoint(x: p.x, y: H - p.y)
        }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        let hasCallout = !callout.isNull && callout.width > 0 && callout.height > 0

        // Selection marquee is editor-only — never appears in the
        // saved file. Only the callout + pointer + magnified content
        // make it through.
        if hasCallout {
            drawCalloutWithPointerFlattened(in: ctx, cgRect: cgRect, cgPoint: cgPoint)
        }
        return ctx.makeImage()
    }

    private func drawCalloutWithPointerFlattened(in ctx: CGContext,
                                                  cgRect: (CGRect) -> CGRect,
                                                  cgPoint: (CGPoint) -> CGPoint)
    {
        let cgCallout = cgRect(callout)
        let roundedPath = CGPath(roundedRect: cgCallout,
                                  cornerWidth: calloutCornerRadius,
                                  cornerHeight: calloutCornerRadius,
                                  transform: nil)

        let wedgePath: CGPath? = {
            guard let pts = wedgePointsInImageSpace() else { return nil }
            let p = CGMutablePath()
            p.move(to: cgPoint(pts.baseLeft))
            p.addLine(to: cgPoint(pts.apex))
            p.addLine(to: cgPoint(pts.baseRight))
            p.closeSubpath()
            return p
        }()

        // Step 1 — combined silhouette + shadow. y-up CG, so negate
        // the offset to cast the shadow downward in screen terms.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -calloutShadowOffset),
                       blur: calloutShadowBlur,
                       color: NSColor(white: 0, alpha: 0.45).cgColor)
        ctx.setFillColor(NSColor.white.cgColor)
        let silhouette = CGMutablePath()
        silhouette.addPath(roundedPath)
        if let w = wedgePath { silhouette.addPath(w) }
        ctx.addPath(silhouette)
        ctx.fillPath()
        ctx.restoreGState()

        // Step 2 — wedge fill
        if let w = wedgePath {
            ctx.saveGState()
            ctx.setFillColor(arrowColor.cgColor)
            ctx.addPath(w)
            ctx.fillPath()
            ctx.restoreGState()
        }

        // Step 3 — clip to rounded rect, draw magnified content
        ctx.saveGState()
        ctx.addPath(roundedPath)
        ctx.clip()
        if !selection.isNull, selection.width > 0, selection.height > 0,
           let crop = image.cropping(to: integralCrop(selection))
        {
            ctx.interpolationQuality = .high
            ctx.draw(crop, in: cgCallout)
        } else {
            ctx.setFillColor(NSColor(white: 0.6, alpha: 0.4).cgColor)
            ctx.fill(cgCallout)
        }
        ctx.restoreGState()

        // Step 4 — bubble outline, matching the on-screen render. See the note
        // there. Drawn in both modes so the saved PNG carries the same border.
        ctx.saveGState()
        ctx.addPath(roundedPath)
        ctx.setStrokeColor(arrowColor.cgColor)
        ctx.setLineWidth(calloutBorderWidthImage)
        ctx.strokePath()
        ctx.restoreGState()
    }
}

// MARK: - Diagonal resize cursors
//
// macOS ships no *public* diagonal-resize cursor, but AppKit has long
// carried private ones (the same arrows Finder and Preview use on window
// and shape corners). We reach them by selector behind a guard, falling
// back to the crosshair if a future macOS ever drops them — so the worst
// case is a less-pretty but still-functional hint, never a crash.
private extension NSCursor {
    static var resizeDiagonalNWSE: NSCursor { diagonalCursor("_windowResizeNorthWestSouthEastCursor") }
    static var resizeDiagonalNESW: NSCursor { diagonalCursor("_windowResizeNorthEastSouthWestCursor") }

    static func diagonalCursor(_ selectorName: String) -> NSCursor {
        let selector = NSSelectorFromString(selectorName)
        if NSCursor.responds(to: selector),
           let cursor = NSCursor.perform(selector)?.takeUnretainedValue() as? NSCursor {
            return cursor
        }
        return .crosshair
    }
}
