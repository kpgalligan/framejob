import AppKit

/// The volume line on the timeline (road map "audio" AP8a, spec §11
/// AU-81…AU-84): every clip with sound draws its envelope — the plan's ramps
/// through `VolumeLines`, on `VolumeScale` — over its waveform; a press on it
/// drags the level in force, ⌥-press adds a point. The model is
/// `VolumeLine.swift`.
///
/// Extensions in a file of their own, as the speech duck's line is
/// (`TimelineView+DuckCurve.swift`): `TimelineView.swift` is frozen at wiring
/// and keeps one call in `hit(at:)` and one arm in each gesture phase.

/// One clip's line as drawn and hit: its rect, the scale on it, the ramps,
/// the polyline's vertices and the points (action ends naming the volume).
struct VolumeLineGeometry {
    let rect: CGRect
    let scale: VolumeScale
    let ramps: [PlanRamp]
    let vertices: [CGPoint]
    let points: [CGPoint]
}

extension TimelineContentView {
    /// The shortest line rect drawn (AU-81).
    static let volumeLineMinHeight: CGFloat = 12
    /// How far from the line a press still takes it (AU-84).
    static let volumeLineReach: CGFloat = 3

    /// The line on `clip` in lane rect `rect`: the audio region with its top
    /// raised to the action lane's bottom where they overlap, at least 12 pt
    /// tall, on a clip with sound that is not a nest clip and has an audio
    /// segment in the plan; nil otherwise. The drawing and the hit test both
    /// read this, so they cannot disagree.
    func volumeLineGeometry(
        _ clip: ClipSnapshot, rect: CGRect, owner: TimelineView
    ) -> VolumeLineGeometry? {
        guard clip.source.nestID == nil, owner.hasAudio(clip),
              let ramps = owner.volumeLines?.ramps(for: clip.id)
        else { return nil }
        let content = Self.contentRect(rect)
        var audio = Self.regions(in: content, hasVideo: owner.hasVideo(clip), hasAudio: true).audio
        let lane = Self.actionLane(content: content, sizeIndex: owner.trackHeightIndex)
        if lane.height > 0, lane.maxY > audio.minY, lane.minY < audio.maxY {
            audio = CGRect(
                x: audio.minX, y: lane.maxY, width: audio.width,
                height: max(audio.maxY - lane.maxY, 0))
        }
        guard audio.height >= Self.volumeLineMinHeight, audio.width > 1 else { return nil }
        let scale = VolumeScale(rect: audio.insetBy(dx: 0, dy: 1))
        let layout = owner.layout
        var vertices: [CGPoint] = []
        for ramp in ramps {
            vertices.append(CGPoint(x: layout.x(for: ramp.start), y: scale.y(gain: ramp.from)))
            vertices.append(CGPoint(
                x: layout.x(for: ramp.start + ramp.duration), y: scale.y(gain: ramp.to)))
        }
        var points: [CGPoint] = []
        for action in clip.actions
        where action.end.audio?.volume != nil && action.endTime <= clip.duration {
            let t = clip.start + action.endTime
            guard let gain = VolumeLines.gain(at: t, in: ramps) else { continue }
            points.append(CGPoint(x: layout.x(for: t), y: scale.y(gain: gain)))
        }
        return VolumeLineGeometry(
            rect: audio, scale: scale, ramps: ramps, vertices: vertices, points: points)
    }

    /// The line, its points and — while it is dragged — the readout. Called
    /// after the speech duck's line, inside the clip body's clip.
    func drawVolumeLine(_ clip: ClipSnapshot, rect: CGRect, owner: TimelineView, visible: CGRect) {
        guard let geometry = volumeLineGeometry(clip, rect: rect, owner: owner),
              geometry.vertices.count >= 2
        else { return }
        let from = max(geometry.rect.minX, visible.minX) - 1
        let to = min(geometry.rect.maxX, visible.maxX) + 1
        guard to > from else { return }
        // Each ramp is one leg; a leg wholly off screen is skipped and the
        // next drawn one starts a new subpath, so a long clip costs only what
        // shows. Consecutive legs share their end and start points.
        let path = NSBezierPath()
        var open = false
        for leg in stride(from: 0, to: geometry.vertices.count - 1, by: 2) {
            let a = geometry.vertices[leg]
            let b = geometry.vertices[leg + 1]
            guard b.x >= from, a.x <= to else {
                open = false
                continue
            }
            if open { path.line(to: a) } else { path.move(to: a) }
            path.line(to: b)
            open = true
        }
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: geometry.rect).addClip()
        NSColor.white.withAlphaComponent(0.85).setStroke()
        path.lineWidth = 1
        path.stroke()
        DS.action.setFill()
        for point in geometry.points where point.x >= from && point.x <= to {
            NSRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5).fill()
        }
        NSGraphicsContext.current?.restoreGraphicsState()
        if let drag = owner.volumeDrag, drag.clip == clip.id {
            drawVolumeReadout(VolumeLine.readout(drag.volume), at: drag.point, in: geometry.rect)
        }
    }

    /// The dragged value beside the pointer, kept inside the line's rect
    /// where it fits.
    private func drawVolumeReadout(_ text: String, at point: CGPoint, in rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        var chip = CGRect(
            x: point.x + 8, y: point.y - size.height - 6, width: size.width + 8,
            height: size.height + 2)
        if chip.maxX > rect.maxX { chip.origin.x = point.x - 8 - chip.width }
        chip.origin.y = min(max(chip.minY, rect.minY), max(rect.maxY - chip.height, rect.minY))
        NSColor.black.withAlphaComponent(0.7).setFill()
        chip.fill()
        (text as NSString).draw(
            at: CGPoint(x: chip.minX + 4, y: chip.minY + 1), withAttributes: attributes)
    }

    /// AU-84: within the line's rect and 3 pt of the line at the pointer's x,
    /// the clip and the press's project time. `hit(at:)` asks after the fade
    /// handles, the action band and the edge grabs, and before the clip body.
    func volumeLineHit(_ clip: ClipSnapshot, rect: CGRect, at point: CGPoint) -> TimelineHit? {
        guard let owner = timeline,
              let geometry = volumeLineGeometry(clip, rect: rect, owner: owner),
              geometry.rect.contains(point)
        else { return nil }
        let time = owner.layout.time(atX: point.x)
        guard let gain = VolumeLines.gain(at: time, in: geometry.ramps),
              abs(point.y - geometry.scale.y(gain: gain)) <= Self.volumeLineReach
        else { return nil }
        return .volumeLine(clip.id, time)
    }
}

extension TimelineView {
    /// The `.volumeLine` arm, after the frozen file has selected the clip: a
    /// plain press drags the level in force (AU-82), ⌥ adds a point first
    /// (AU-83) — at once, so a click alone adds it — or beeps where one
    /// cannot go.
    func beginVolumeLine(_ id: UInt32, at point: CGPoint, time: Ticks, flags: NSEvent.ModifierFlags) {
        guard let clip = snapshot.clip(id),
              let index = snapshot.tracks.firstIndex(where: { $0.id == clip.track }),
              let geometry = content.volumeLineGeometry(
                  clip, rect: layout.clipRect(clip, row: layout.row(forTrackIndex: index)),
                  owner: self)
        else { return }
        let clipTime = min(max(time - clip.start, 0), max(clip.duration - 1, 0))
        if flags.contains(.option) {
            guard let project = volumeLines?.project,
                  let made = VolumeLine.point(
                      on: clip, at: clipTime, project: project, nextId: snapshot.nextId,
                      fps: snapshot.canvas.fps)
            else {
                NSSound.beep()
                return
            }
            let session = VolumeLineSession(
                clip: id, target: .end(action: made.action, volume: made.volume),
                prefix: made.prefix, pressY: point.y, scale: geometry.scale, volume: made.volume,
                point: point)
            volumeDrag = session
            onLiveBegin?()
            onLiveUpdate?(session.ops)
        } else {
            let target = VolumeLine.target(of: clip, at: clipTime)
            volumeDrag = VolumeLineSession(
                clip: id, target: target, prefix: [], pressY: point.y, scale: geometry.scale,
                volume: target.volume, point: point)
            onLiveBegin?()
        }
    }

    /// Vertical only: the pointer's y against the press's, on the scale the
    /// press found.
    func continueVolumeLine(at point: CGPoint) {
        guard var session = volumeDrag else { return }
        session.update(y: point.y)
        session.point = point
        volumeDrag = session
        onLiveUpdate?(session.ops)
    }

    /// One undo step, "Set Volume" or "Add Volume Point"; none when nothing
    /// changed (`ProjectDocument.endLiveEdit`).
    func endVolumeLine() {
        guard let session = volumeDrag else { return }
        volumeDrag = nil
        onLiveEnd?(session.undoName)
    }
}
