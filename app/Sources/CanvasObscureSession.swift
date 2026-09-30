import AppKit

/// A stored obscure region's grips on the canvas and the drag that moves or
/// resizes it (spec §4.2, §11 CI-16). Pure values: the drawing, the hit test
/// and the wiring are `PreviewCanvasView+Obscure.swift`'s.
///
/// A region lives in the layer's own SOURCE-pixel frame, measured from the
/// centre of its cropped rect (`CanvasLayerBox.sourcePoint`, spec §5.3's Q),
/// so a grip is a point in that frame taken to the canvas through
/// `canvasPoint(source:)`, and a drag's travel is the pointer taken back
/// through `sourcePoint` — the same reading the region band makes, which is
/// what keeps a turned, scaled or cropped clip free of special cases here.

// MARK: - Grips

/// One grip of a region: its centre, or one of its box's eight handles,
/// named in the region's own (layer) axes.
enum ObscureGrip: Equatable {
    case move
    case resize(CanvasHandle)

    /// The order a hit test walks them in: the centre, then the handles.
    static let all: [ObscureGrip] = [.move] + CanvasHandle.allCases.map { .resize($0) }

    var cursor: NSCursor {
        switch self {
        case .move: return .openHand
        case .resize(let handle): return handle.cursor
        }
    }
}

/// A press on a region's grip: the clip, the entry's index in its list, and
/// which grip.
struct ObscureRegionHit: Equatable {
    let clip: UInt32
    let index: Int
    let grip: ObscureGrip
}

extension CanvasHit {
    /// Whether a region grip under the pointer may take the press instead:
    /// only a body or nothing. The rotation grip, the endpoints and the
    /// eight scale handles outrank every region grip (CI-16).
    var yieldsToObscureGrip: Bool {
        switch self {
        case .body, .empty: return true
        case .handle, .rotation, .cropHandle, .endpoint: return false
        }
    }
}

extension CanvasLayerBox {
    /// `grip` of `region`, in canvas space: the region's centre, or one of
    /// its box's handles, taken through `canvasPoint(source:)`.
    func obscureGripPoint(_ grip: ObscureGrip, of region: ObscureProps) -> CGPoint {
        switch grip {
        case .move: return canvasPoint(source: CGPoint(x: region.x, y: region.y))
        case .resize(let handle): return canvasPoint(source: handle.point(in: region.box))
        }
    }
}

// MARK: - The drag

/// Dragging one region's grip. The write is the WHOLE list with one entry
/// replaced — never a different length — through the target captured at
/// mouse-down (CI-13), so a list the target does not hold at this length is
/// never gripped (`PreviewCanvasView.obscureStartList`).
struct CanvasObscureSession {
    let clip: UInt32
    let index: Int
    let grip: ObscureGrip
    /// The list the write replaces: the target's start state.
    let list: [ObscureProps]
    /// The box ON SCREEN at mouse-down; the pointer's travel is measured
    /// through it, as the region band measures a band.
    let frame: CanvasLayerBox
    /// The press, in source pixels.
    let grab: CGPoint
    /// The entry's box, then as dragged; source pixels.
    var box: CGRect

    /// Each side of a region stays within these, source pixels.
    static let minSide = 1.0
    static let maxSide = 20000.0

    /// Nil when `list` has no entry at `hit.index`.
    init?(hit: ObscureRegionHit, list: [ObscureProps], frame: CanvasLayerBox, press: CGPoint) {
        guard list.indices.contains(hit.index) else { return nil }
        clip = hit.clip
        index = hit.index
        grip = hit.grip
        self.list = list
        self.frame = frame
        grab = frame.sourcePoint(press)
        box = list[hit.index].box
    }

    var undoName: String {
        switch grip {
        case .move: return "Move Region"
        case .resize: return "Resize Region"
        }
    }

    /// `list` with the entry at `index` placed at `box`: the centre taken
    /// from the unrounded rect, then everything rounded the way every canvas
    /// gesture rounds (`ZoomRegionSession.region`'s order). The entry's
    /// shape, feather, kind and amount are kept.
    var regions: [ObscureProps] {
        var out = list
        let old = list[index]
        out[index] = ObscureProps(
            shape: old.shape, x: canvasRound(Double(box.midX)), y: canvasRound(Double(box.midY)),
            width: canvasRound(Double(box.width)), height: canvasRound(Double(box.height)),
            feather: old.feather, kind: old.kind, amount: old.amount)
        return out
    }

    func op(to target: CanvasEditTarget) -> ReelOp {
        target.op(video: VideoPatch(obscure: regions), clip: clip)
    }

    /// `point` is a canvas point; `aboutCentre` is ⌥. The centre grip moves
    /// the box by the travel. A handle moves the edge it drives by the
    /// travel's component on that axis, the far edge pinned (a side never
    /// flips, and never falls under `minSide`), or with ⌥ the centre pinned
    /// and both edges moving; an axis it does not drive keeps its extent.
    mutating func update(point: CGPoint, aboutCentre: Bool) {
        let at = frame.sourcePoint(point)
        let d = CGPoint(x: at.x - grab.x, y: at.y - grab.y)
        let start = list[index].box
        switch grip {
        case .move:
            box = start.offsetBy(dx: d.x, dy: d.y)
        case .resize(let handle):
            let x = Self.span(
                start.minX, start.maxX, unit: handle.unit.x, travel: d.x, aboutCentre: aboutCentre)
            let y = Self.span(
                start.minY, start.maxY, unit: handle.unit.y, travel: d.y, aboutCentre: aboutCentre)
            box = CGRect(x: x.min, y: y.min, width: x.max - x.min, height: y.max - y.min)
        }
    }

    /// One axis of a resize: `unit` is the handle's -1, 0 or +1 on it.
    private static func span(
        _ low: CGFloat, _ high: CGFloat, unit: CGFloat, travel: CGFloat, aboutCentre: Bool
    ) -> (min: CGFloat, max: CGFloat) {
        guard unit != 0 else { return (low, high) }
        let lower = CGFloat(minSide)
        let upper = CGFloat(maxSide)
        if aboutCentre {
            let centre = (low + high) / 2
            let side = min(max((high - low) + 2 * unit * travel, lower), upper)
            return (centre - side / 2, centre + side / 2)
        }
        if unit > 0 {
            let side = min(max(high + travel - low, lower), upper)
            return (low, low + side)
        }
        let side = min(max(high - (low + travel), lower), upper)
        return (high - side, high)
    }
}
