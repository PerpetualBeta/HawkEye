import Foundation
import CoreGraphics

/// Geometry helpers for the magnifier callout: arrow routing, initial
/// callout placement, resize-handle hit-testing.
enum CalloutGeometry {

    /// Side of a rectangle that an arrow exits.
    enum Side {
        case top, bottom, left, right
    }

    /// Compute the endpoints of the connector arrow between the source
    /// rectangle and the callout. Tail sits on the edge of `source`,
    /// head sits on the edge of `callout`, both on the sides facing each
    /// other. Falls back to the nearest edges if the rectangles overlap.
    static func arrow(from source: CGRect, to callout: CGRect)
        -> (tail: CGPoint, head: CGPoint, tailSide: Side, headSide: Side)
    {
        let srcCenter = CGPoint(x: source.midX, y: source.midY)
        let dstCenter = CGPoint(x: callout.midX, y: callout.midY)

        let tailSide = side(of: source, towards: dstCenter)
        let headSide = side(of: callout, towards: srcCenter)

        let tail = edgePoint(on: source, side: tailSide, towards: dstCenter)
        let head = edgePoint(on: callout, side: headSide, towards: srcCenter)
        return (tail, head, tailSide, headSide)
    }

    /// Pick the side of `rect` that faces `target`.
    private static func side(of rect: CGRect, towards target: CGPoint) -> Side {
        let dx = target.x - rect.midX
        let dy = target.y - rect.midY
        // Compare absolute deltas scaled by half-width/half-height so a
        // tall thin rect prefers its long sides correctly.
        let nx = abs(dx) / max(rect.width / 2, 1)
        let ny = abs(dy) / max(rect.height / 2, 1)
        if nx > ny {
            return dx > 0 ? .right : .left
        } else {
            return dy > 0 ? .bottom : .top
        }
    }

    /// Point on the chosen side of `rect`, x/y clamped to the projection
    /// of `target` along the chosen edge.
    private static func edgePoint(on rect: CGRect, side: Side, towards target: CGPoint) -> CGPoint {
        switch side {
        case .top:
            let x = min(max(target.x, rect.minX), rect.maxX)
            return CGPoint(x: x, y: rect.minY)
        case .bottom:
            let x = min(max(target.x, rect.minX), rect.maxX)
            return CGPoint(x: x, y: rect.maxY)
        case .left:
            let y = min(max(target.y, rect.minY), rect.maxY)
            return CGPoint(x: rect.minX, y: y)
        case .right:
            let y = min(max(target.y, rect.minY), rect.maxY)
            return CGPoint(x: rect.maxX, y: y)
        }
    }

    /// Initial callout placement next to a freshly-drawn source rectangle.
    /// Picks whichever side of `source` has the most room inside `image`,
    /// sizes the callout at `zoom`× the source (capped to fit), and pads
    /// it away from the source by `padding`.
    static func initialCallout(for source: CGRect,
                                in imageSize: CGSize,
                                zoom: CGFloat = 2.5,
                                padding: CGFloat = 24) -> CGRect
    {
        let imageRect = CGRect(origin: .zero, size: imageSize)
        let target = CGSize(width: max(source.width  * zoom, 120),
                            height: max(source.height * zoom, 90))

        // Space available on each side
        let leftRoom   = source.minX
        let rightRoom  = imageRect.maxX - source.maxX
        let topRoom    = source.minY
        let bottomRoom = imageRect.maxY - source.maxY

        // Pick side with the most room that can also fit the target dim
        // along the *parallel* axis (width for top/bottom, height for
        // left/right). Fall back to the largest absolute room.
        struct Candidate { let side: Side; let room: CGFloat; let fits: Bool }
        let candidates: [Candidate] = [
            .init(side: .left,   room: leftRoom,   fits: leftRoom   >= target.width  + padding),
            .init(side: .right,  room: rightRoom,  fits: rightRoom  >= target.width  + padding),
            .init(side: .top,    room: topRoom,    fits: topRoom    >= target.height + padding),
            .init(side: .bottom, room: bottomRoom, fits: bottomRoom >= target.height + padding),
        ]
        let fitting = candidates.filter { $0.fits }
        let chosen = (fitting.max { $0.room < $1.room } ?? candidates.max { $0.room < $1.room })!

        // Cap callout size so it stays inside the image after placement
        let w = min(target.width,  imageRect.width  - 2 * padding)
        let h = min(target.height, imageRect.height - 2 * padding)
        let cx = source.midX
        let cy = source.midY
        var origin: CGPoint
        switch chosen.side {
        case .right:
            origin = CGPoint(x: source.maxX + padding,
                             y: cy - h / 2)
        case .left:
            origin = CGPoint(x: source.minX - padding - w,
                             y: cy - h / 2)
        case .bottom:
            origin = CGPoint(x: cx - w / 2,
                             y: source.maxY + padding)
        case .top:
            origin = CGPoint(x: cx - w / 2,
                             y: source.minY - padding - h)
        }
        // Clamp into image bounds
        origin.x = min(max(origin.x, imageRect.minX + 4), imageRect.maxX - w - 4)
        origin.y = min(max(origin.y, imageRect.minY + 4), imageRect.maxY - h - 4)
        return CGRect(x: origin.x, y: origin.y, width: w, height: h)
    }

    /// Corner kinds used for resize-handle hit-testing.
    enum Corner { case topLeft, topRight, bottomLeft, bottomRight }

    /// Locations of the four corner handles on `rect`, indexed by Corner.
    static func handlePoints(of rect: CGRect) -> [Corner: CGPoint] {
        [
            .topLeft:     CGPoint(x: rect.minX, y: rect.minY),
            .topRight:    CGPoint(x: rect.maxX, y: rect.minY),
            .bottomLeft:  CGPoint(x: rect.minX, y: rect.maxY),
            .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY),
        ]
    }

    /// Resize `rect` by moving the named corner to `point`. Maintains a
    /// minimum size of `minSide` × `minSide` so the user can't collapse
    /// the rectangle to nothing.
    static func resize(_ rect: CGRect, corner: Corner, to point: CGPoint,
                        minSide: CGFloat = 20) -> CGRect
    {
        var x = rect.minX
        var y = rect.minY
        var w = rect.width
        var h = rect.height
        switch corner {
        case .topLeft:
            w = (rect.maxX - point.x)
            h = (rect.maxY - point.y)
            x = point.x
            y = point.y
        case .topRight:
            w = point.x - rect.minX
            h = rect.maxY - point.y
            y = point.y
        case .bottomLeft:
            w = rect.maxX - point.x
            h = point.y - rect.minY
            x = point.x
        case .bottomRight:
            w = point.x - rect.minX
            h = point.y - rect.minY
        }
        // Floor at minSide. If the user drags through, the corner "sticks"
        // at min size rather than flipping the rectangle inside-out.
        if w < minSide {
            switch corner {
            case .topLeft, .bottomLeft: x = rect.maxX - minSide
            default: break
            }
            w = minSide
        }
        if h < minSide {
            switch corner {
            case .topLeft, .topRight: y = rect.maxY - minSide
            default: break
            }
            h = minSide
        }
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
