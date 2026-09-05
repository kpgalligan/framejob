import AppKit

/// Every timeline conversion — ticks ↔ points, tracks ↔ lane rows, clips ↔
/// rectangles — in one value.
///
/// `TimelineView` rebuilds one of these whenever the zoom, the track height,
/// the viewport or the project changes and hands the same copy to all three
/// drawing views. **Nothing else in the app does this arithmetic**: a hit
/// test and the bar it hit are then answering from one function, which is
/// the only way a drag can be trusted to grab what the user is looking at.
///
/// Coordinates are the content view's, which is FLIPPED (y grows down):
///
/// * the ruler band is `y ∈ [0, rulerHeight)`,
/// * the header column is `x ∈ [0, headerWidth)`,
/// * time zero therefore sits at `x == headerWidth`, so a clip at t = 0 is
///   flush against the header instead of hiding under it.
///
/// The header column and the ruler are *floating* (spec §4.4): they are
/// repositioned to the visible rectangle's origin on every scroll, so their
/// content-space origin is `pinnedX` / `pinnedY` rather than 0. Hit testing
/// against those two bands uses `TimelineView`'s pinned origins, not these
/// constants.
struct TimelineLayout {
    // MARK: - Fixed metrics

    /// Spec §4.4's 120 pt track-header column.
    static let headerWidth: CGFloat = 120
    static let rulerHeight: CGFloat = 26
    /// Gap between two lanes, and the gap above the first one.
    static let laneSpacing: CGFloat = 2
    static let lanesInset: CGFloat = 4
    /// Small / medium / large (View ▸ Timeline Track Height).
    static let trackHeights: [CGFloat] = [34, 56, 88]
    /// Empty time kept past the last clip so the end is reachable and a clip
    /// can be dragged past it.
    static let trailingPad: CGFloat = 260
    static let minZoom: CGFloat = 0.35
    static let maxZoom: CGFloat = 4000
    static let defaultZoom: CGFloat = 42
    /// Grab width of a clip's trim edge, in points.
    static let edgeGrab: CGFloat = 7
    /// Snap distance in POINTS; converted to ticks per zoom by
    /// `snapThreshold` so snapping feels the same at every zoom.
    static let snapSlop: CGFloat = 8
    static let clipRadius: CGFloat = 4
    /// Side of the fade-handle squares at the audio corners.
    static let fadeHandle: CGFloat = 8

    // MARK: - State

    var canvas = CanvasSnapshot()
    var trackCount = 0
    /// Index into `trackHeights`.
    var heightIndex = 1
    /// Points per second — the zoom.
    var zoom: CGFloat = defaultZoom
    var duration: Ticks = 0
    /// The scroll view's clip bounds, so the content is never smaller than
    /// what shows (an empty project still paints a full lane background).
    var viewport = CGSize.zero

    // MARK: - Vertical

    var trackHeight: CGFloat {
        Self.trackHeights[min(max(heightIndex, 0), Self.trackHeights.count - 1)]
    }

    /// Top of the first lane, below the ruler band.
    var lanesTop: CGFloat { Self.rulerHeight + Self.lanesInset }

    var rowPitch: CGFloat { trackHeight + Self.laneSpacing }

    var lanesHeight: CGFloat { CGFloat(max(trackCount, 0)) * rowPitch }

    var contentHeight: CGFloat {
        max(lanesTop + lanesHeight + Self.lanesInset, viewport.height)
    }

    /// Top of display row `row`. Row 0 is the TOP lane, which is the
    /// front-most track — `tracks.last` — because spec §4.4 puts the
    /// front-most track on top while the model stores index 0 at the back.
    func rowTop(_ row: Int) -> CGFloat { lanesTop + CGFloat(row) * rowPitch }

    func rowRect(_ row: Int, width: CGFloat) -> CGRect {
        CGRect(x: 0, y: rowTop(row), width: width, height: trackHeight)
    }

    /// The display row at `y`, unclamped: negative above the top lane and
    /// `>= trackCount` below the bottom one, which is exactly what a clip
    /// drag needs to decide it should create a track (spec §4.4).
    func unclampedRow(atY y: CGFloat) -> Int {
        Int(((y - lanesTop) / rowPitch).rounded(.down))
    }

    /// The display row at `y`, or nil when the point is outside the lanes.
    func row(atY y: CGFloat) -> Int? {
        let row = unclampedRow(atY: y)
        return (0..<max(trackCount, 0)).contains(row) ? row : nil
    }

    /// Display row → model index (`tracks[i]`, 0 = back) and back. Both
    /// directions are the same reflection; two names because reading
    /// `trackIndex(forRow:)` at a call site is the point.
    func trackIndex(forRow row: Int) -> Int { trackCount - 1 - row }
    func row(forTrackIndex index: Int) -> Int { trackCount - 1 - index }

    // MARK: - Horizontal

    func x(for time: Ticks) -> CGFloat {
        Self.headerWidth + width(of: time)
    }

    func width(of duration: Ticks) -> CGFloat {
        CGFloat(duration) / CGFloat(ReelTime.perSecond) * zoom
    }

    func time(atX x: CGFloat) -> Ticks {
        ticks(of: x - Self.headerWidth)
    }

    /// A point *distance* as ticks — the conversion a drag delta needs.
    func ticks(of width: CGFloat) -> Ticks {
        guard zoom > 0 else { return 0 }
        return Self.ticks(fromSeconds: Double(width / zoom))
    }

    static func ticks(fromSeconds seconds: Double) -> Ticks {
        ticks(clamping: seconds * Double(ReelTime.perSecond))
    }

    /// `Ticks(_:)` traps on NaN and on anything past `Int64`, and a zoom of
    /// 0.35 pt/s over a wide window gets big fast — every Double → Ticks
    /// conversion in the timeline goes through here.
    static func ticks(clamping value: Double) -> Ticks {
        guard value.isFinite else { return 0 }
        return Ticks(min(max(value.rounded(), -4e17), 4e17))
    }

    var contentWidth: CGFloat {
        max(x(for: max(duration, 0)) + Self.trailingPad, viewport.width)
    }

    /// The snap radius in ticks: spec §4.4's 8 points, at this zoom.
    var snapThreshold: Ticks { max(ticks(of: Self.snapSlop), 1) }

    /// The zoom that fits `duration` (plus a breath) in `width` points.
    static func fitZoom(duration: Ticks, width: CGFloat) -> CGFloat {
        let seconds = Double(max(duration, ReelTime.perSecond)) / Double(ReelTime.perSecond)
        let usable = Double(max(width - headerWidth - 24, 80))
        return min(max(CGFloat(usable / seconds), minZoom), maxZoom)
    }

    // MARK: - Clips

    /// The bar for `clip` on display row `row`. Always at least 2 pt wide so
    /// a very short clip at a low zoom is still visible and still grabbable.
    func clipRect(_ clip: ClipSnapshot, row: Int) -> CGRect {
        let left = x(for: clip.start)
        let right = x(for: clip.end)
        return CGRect(
            x: left, y: rowTop(row), width: max(right - left, 2), height: trackHeight)
    }

    /// The tick range `rect` covers, clamped at zero — what the ruler and the
    /// clip loop iterate so a two-hour project draws only what shows.
    func visibleRange(_ rect: CGRect) -> (start: Ticks, end: Ticks) {
        let start = max(time(atX: rect.minX), 0)
        let end = max(time(atX: rect.maxX), start)
        return (start, end)
    }

    // MARK: - Ruler

    /// Tick spacing for the ruler, adaptive as spec §4.4 asks: frames while
    /// they are far enough apart to see, then seconds, 10 s and minutes.
    /// Minors need 6 pt of air, labelled majors 68 pt (a "MM:SS:FF" in 9 pt
    /// mono is about 48).
    func rulerSteps() -> (minor: Ticks, major: Ticks) {
        let ladder = Self.ladder(frame: canvas.fps.frameDuration)
        let minor = ladder.first { width(of: $0) >= 6 } ?? ladder[ladder.count - 1]
        let major = ladder.first { width(of: $0) >= 68 && $0 >= minor } ?? minor
        return (minor, max(major, minor))
    }

    /// Frames → seconds → minutes → hours, deduplicated and sorted. A
    /// degenerate frame duration (a 0-denominator rate) drops the frame rungs
    /// rather than dividing by zero.
    static func ladder(frame: Ticks) -> [Ticks] {
        let second = ReelTime.perSecond
        var steps: [Ticks] = []
        if frame > 0 {
            steps += [frame, frame * 2, frame * 5, frame * 10]
        }
        steps += [
            second, second * 2, second * 5, second * 10, second * 15, second * 30,
            second * 60, second * 120, second * 300, second * 600, second * 900,
            second * 1800, second * 3600,
        ]
        return Array(Set(steps.filter { $0 > 0 })).sorted()
    }

    /// A ruler label. Spelling is `ReelTime.format`'s — the core's — so the
    /// ruler, the toolbar and the agent never disagree about a time; the only
    /// liberty taken is dropping a leading `00:` hour when the whole project
    /// is under an hour, because an 11-glyph label does not fit at 68 pt.
    func rulerLabel(_ time: Ticks) -> String {
        let text = ReelTime.format(time, fps: canvas.fps, frames: canvas.timecodeFrames)
        guard duration < ReelTime.perSecond * 3600, text.hasPrefix("00:") else { return text }
        return String(text.dropFirst(3))
    }
}
