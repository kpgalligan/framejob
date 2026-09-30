import AppKit

/// The selected clip's obscure regions on the canvas (spec §4.2, §11 CI-16):
/// each one outlined through the layer's transform, with a move grip at its
/// centre and eight resize handles, outside any modal mode. The session is
/// `CanvasObscureSession` (one stored property on the frozen view,
/// `obscureDrag`); the frozen file carries only the wiring — a press arm, a
/// tick arm, a release arm, the cancel, one draw call and one cursor loop.
///
/// **Order.** The layer's own handles are hit first and a region grip is
/// tried only when the press found a body or nothing
/// (`CanvasHit.yieldsToObscureGrip`), so a grip under a layer handle is not
/// reachable there; a region's inside is not a grip, so a drag there still
/// moves the clip. The two modal modes' overlays sit above this whole view
/// and take every press while armed; the outlines stay drawn under them.
extension PreviewCanvasView {
    /// The box whose regions are drawn: the primary box, with exactly one
    /// clip selected, unlocked, outside crop mode and the text editor.
    var obscureBox: CanvasLayerBox? {
        guard selection.count == 1, !cropMode, editingClip == nil,
              let box = primaryBox, !box.locked
        else { return nil }
        return box
    }

    /// The list a drag replaces — `editTarget`'s start state for the clip —
    /// when it has as many entries as the list drawn (the recipe's, at the
    /// playhead); nil otherwise, and then no grip exists, because an index
    /// would name a different region.
    var obscureStartList: [ObscureProps]? {
        guard let box = obscureBox else { return nil }
        let list = editTarget.start(of: box.clip, in: project).video.obscure
        return list.count == box.video.obscure.count ? list : nil
    }

    /// The region grip under `point` (view space): the nearest within
    /// `handleGrab` by the larger axis distance; a tie goes to the higher
    /// index (the region drawn later), then to the earlier grip.
    func obscureHit(at point: CGPoint) -> ObscureRegionHit? {
        guard let box = obscureBox, !box.video.obscure.isEmpty, obscureStartList != nil else {
            return nil
        }
        var best: (hit: ObscureRegionHit, distance: CGFloat)?
        for (index, region) in box.video.obscure.enumerated() {
            for grip in ObscureGrip.all {
                let at = canvasToView(box.obscureGripPoint(grip, of: region))
                let distance = max(abs(at.x - point.x), abs(at.y - point.y))
                guard distance <= Self.handleGrab else { continue }
                if let found = best {
                    let closer = distance < found.distance
                    let later = distance == found.distance && index > found.hit.index
                    guard closer || later else { continue }
                }
                best = (ObscureRegionHit(clip: box.id, index: index, grip: grip), distance)
            }
        }
        return best?.hit
    }

    /// Mouse-down on a grip (view space). False when the grip no longer
    /// names an entry of the target's list, and the press falls through.
    func beginObscureDrag(_ hit: ObscureRegionHit, at point: CGPoint) -> Bool {
        guard let box = obscureBox, box.id == hit.clip, let list = obscureStartList else {
            return false
        }
        gestureTarget = editTarget
        guard let session = CanvasObscureSession(
            hit: hit, list: list, frame: box, press: viewToCanvas(point))
        else { return false }
        obscureDrag = session
        onLiveBegin?()
        return true
    }

    /// One tick (canvas space): one live op, the whole list.
    func continueObscureDrag(at point: CGPoint, flags: NSEvent.ModifierFlags) {
        guard var session = obscureDrag else { return }
        session.update(point: point, aboutCentre: flags.contains(.option))
        obscureDrag = session
        onLiveUpdate?([session.op(to: gestureTarget)])
    }

    // MARK: - Drawing

    /// Every region's outline — a dark backing stroke, then the marquee's
    /// dashed line — and, only while the grips exist, their handles and
    /// centre crosses.
    func drawObscureRegions() {
        guard let box = obscureBox else { return }
        let regions = box.video.obscure
        guard !regions.isEmpty else { return }
        let dash: [CGFloat] = [4, 3]
        for region in regions {
            let path = polygon(box.canvasQuad(ofSource: region.box))
            NSColor.black.withAlphaComponent(0.4).setStroke()
            path.lineWidth = 2
            path.stroke()
            path.setLineDash(dash, count: dash.count, phase: 0)
            path.lineWidth = 1
            DS.marquee.setStroke()
            path.stroke()
        }
        guard obscureStartList != nil else { return }
        for region in regions {
            drawObscureCentre(canvasToView(box.obscureGripPoint(.move, of: region)))
            drawHandles(
                CanvasHandle.allCases.map { box.obscureGripPoint(.resize($0), of: region) },
                fill: DS.marquee)
        }
    }

    /// The move grip: a 10 pt cross over a dark backing, so it reads on a
    /// white frame and a black one.
    private func drawObscureCentre(_ centre: CGPoint) {
        let arm: CGFloat = 5
        let cross = NSBezierPath()
        cross.move(to: CGPoint(x: centre.x - arm, y: centre.y))
        cross.line(to: CGPoint(x: centre.x + arm, y: centre.y))
        cross.move(to: CGPoint(x: centre.x, y: centre.y - arm))
        cross.line(to: CGPoint(x: centre.x, y: centre.y + arm))
        NSColor.black.withAlphaComponent(0.4).setStroke()
        cross.lineWidth = 3
        cross.stroke()
        DS.marquee.setStroke()
        cross.lineWidth = 1.5
        cross.stroke()
    }

    /// A `handleGrab` square at every grip (view space), empty while the
    /// grips do not exist.
    func obscureCursorRects() -> [(rect: CGRect, cursor: NSCursor)] {
        guard let box = obscureBox, !box.video.obscure.isEmpty, obscureStartList != nil else {
            return []
        }
        let grab = Self.handleGrab
        var rects: [(rect: CGRect, cursor: NSCursor)] = []
        for region in box.video.obscure {
            for grip in ObscureGrip.all {
                let centre = canvasToView(box.obscureGripPoint(grip, of: region))
                let rect = CGRect(
                    x: centre.x - grab / 2, y: centre.y - grab / 2, width: grab, height: grab)
                rects.append((rect, grip.cursor))
            }
        }
        return rects
    }
}
