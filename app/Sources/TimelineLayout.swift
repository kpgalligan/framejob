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

    /// Spec §4.4's track-header column and its ruler band. The numbers are
    /// `DS`'s — the redesign widened the column to 132 and shortened the ruler
    /// to 22 — but the NAMES stay here, because every call site in the
    /// timeline spells them `TimelineLayout.headerWidth` and that is the
    /// vocabulary of this file.
    static let headerWidth = DS.trackHeaderWidth
    static let rulerHeight = DS.rulerHeight
    /// Gap between two lanes, and the gap above the first one.
    static let laneSpacing: CGFloat = 2
    static let lanesInset: CGFloat = 4
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
    static let clipRadius = DS.clipRadius
    /// Side of the fade-handle squares at the audio corners.
    static let fadeHandle: CGFloat = 8

    // MARK: - Track kinds

    /// What a track holds, which is the only thing that decides how tall its
    /// lane is. The raw values index `DS.trackHeights`' inner array, so the
    /// enum and the token table can never drift apart.
    enum TrackKind: Int {
        case text = 0
        case video = 1
        case audio = 2
    }

    /// A track's kind, from the clips on it: text when it holds nothing but
    /// text and shapes, audio when every clip sings and none of them draws,
    /// and video for everything else — an EMPTY track included, because a
    /// fresh track is where footage is about to land.
    ///
    /// Not a method on the layout: the layout is a pure value that never
    /// touches a snapshot, so this runs once where the layout is built and
    /// only the resulting heights go in.
    ///
    /// **Do not call this in a loop over the tracks.** It builds a whole
    /// `SnapshotIndex` per call, which is the very O(tracks × clips) the
    /// sizing path was rewritten to avoid; `rowHeights` and `trackHeights`
    /// build one index and classify every track against it. This overload
    /// exists for a one-off question about a single track.
    static func trackKind(of clips: [ClipSnapshot], in snapshot: ProjectSnapshot) -> TrackKind {
        trackKind(of: clips, index: SnapshotIndex(snapshot))
    }

    private static func trackKind(of clips: [ClipSnapshot], index: SnapshotIndex) -> TrackKind {
        guard !clips.isEmpty else { return .video }
        if clips.allSatisfy({ clip in
            if case .text = clip.source { return true }
            if case .shape = clip.source { return true }
            return false
        }) {
            return .text
        }
        if clips.allSatisfy({ carriesAudio($0, index: index) && !carriesVideo($0, index: index) }) {
            return .audio
        }
        return .video
    }

    /// The snapshot's clips bucketed by track and its media keyed by id, built
    /// ONCE per height calculation.
    ///
    /// `TimelineView.rebuildLayout()` calls `rowHeights` on every tick of a
    /// live gesture — thirty times a second through a whole drag — and the
    /// obvious spelling of it is quadratic: `snapshot.clips(onTrack:)` filters
    /// the whole clip array (and sorts it) once per TRACK, and
    /// `snapshot.media(for:)` scans the whole media array once per CLIP. On a
    /// long timeline that is the drag's frame budget.
    ///
    /// **The buckets are UNSORTED**, unlike `ProjectSnapshot.clips(onTrack:)`.
    /// That is safe for exactly one reason: classification asks a bucket only
    /// `isEmpty` and `allSatisfy`, neither of which can see an order. Anything
    /// order-sensitive — an overlap rule, a transition lookup — must keep
    /// using the snapshot's sorted accessor.
    private struct SnapshotIndex {
        private var clipsByTrack: [UInt32: [ClipSnapshot]] = [:]
        private var mediaByID: [UInt32: MediaSnapshot] = [:]

        init(_ snapshot: ProjectSnapshot) {
            for clip in snapshot.clips {
                clipsByTrack[clip.track, default: []].append(clip)
            }
            for item in snapshot.media {
                mediaByID[item.id] = item
            }
        }

        func clips(onTrack id: UInt32) -> [ClipSnapshot] { clipsByTrack[id] ?? [] }

        func media(for clip: ClipSnapshot) -> MediaSnapshot? {
            clip.source.mediaID.flatMap { mediaByID[$0] }
        }
    }

    /// True when the clip contributes samples. Deliberately the same test
    /// `TimelineView.hasAudio` makes — a nest sings when the core gave it
    /// audio props — so a lane is called audio for exactly the reason its
    /// clips draw waveforms.
    private static func carriesAudio(_ clip: ClipSnapshot, index: SnapshotIndex) -> Bool {
        guard clip.enabled.audio else { return false }
        if case .nest = clip.source { return clip.audio != nil }
        return index.media(for: clip)?.hasAudio ?? false
    }

    /// True when the clip draws pixels. Wider than `TimelineView.hasVideo`,
    /// which answers "is there a filmstrip": a text, shape or nest clip has no
    /// thumbnails but is unquestionably picture, and a lane of them must not
    /// be sized as if it were sound.
    private static func carriesVideo(_ clip: ClipSnapshot, index: SnapshotIndex) -> Bool {
        guard clip.enabled.video else { return false }
        switch clip.source {
        case .media, .still, .image: return index.media(for: clip)?.hasVideo ?? false
        case .text, .shape, .nest: return true
        }
    }

    /// The lane height of every DISPLAY ROW, top row first — the array
    /// `rowHeights` wants. Row 0 is the front-most track (`tracks.last`), so
    /// the model order is reversed here and nowhere else.
    ///
    /// `frozen` overrides the classification for the tracks it names. A clip
    /// drag previews its own ops, and the clip under the pointer may be the
    /// very one that made its track an audio track — a lane that resized
    /// mid-drag would move the drop target the user is aiming at, so the
    /// gesture freezes what it started with and a track the preview INVENTED
    /// (an `add_track` under the pointer) still gets classified fresh.
    static func rowHeights(
        for snapshot: ProjectSnapshot, sizeIndex: Int, frozen: [UInt32: CGFloat] = [:]
    ) -> [CGFloat] {
        let sizes = sizeRow(sizeIndex)
        let index = SnapshotIndex(snapshot)
        // `??` takes its right side as an autoclosure, so a frozen track is
        // still never classified — the freeze is what keeps a lane from
        // resizing under the pointer mid-drag.
        return snapshot.tracks.reversed().map { track in
            frozen[track.id] ?? height(of: track, index: index, sizes: sizes)
        }
    }

    /// The same heights keyed by TRACK id — what a gesture freezes, because a
    /// preview can restack the rows under it but never renumber a track.
    static func trackHeights(for snapshot: ProjectSnapshot, sizeIndex: Int) -> [UInt32: CGFloat] {
        let sizes = sizeRow(sizeIndex)
        let index = SnapshotIndex(snapshot)
        var table: [UInt32: CGFloat] = [:]
        for track in snapshot.tracks {
            table[track.id] = height(of: track, index: index, sizes: sizes)
        }
        return table
    }

    private static func sizeRow(_ sizeIndex: Int) -> [CGFloat] {
        DS.trackHeights[min(max(sizeIndex, 0), DS.trackHeights.count - 1)]
    }

    private static func height(
        of track: TrackSnapshot, index: SnapshotIndex, sizes: [CGFloat]
    ) -> CGFloat {
        let kind = trackKind(of: index.clips(onTrack: track.id), index: index)
        guard sizes.indices.contains(kind.rawValue) else { return 84 }
        return sizes[kind.rawValue]
    }

    /// The height a row outside `rowHeights` is worth: the size's VIDEO lane.
    /// `unclampedRow` extrapolates with it above and below the stack, so a
    /// drag past either end still counts rows at a believable pitch. The 84
    /// is the medium video lane, and is reachable only if `DS.trackHeights`
    /// is ever reshaped to fewer than three columns.
    static func fallbackHeight(sizeIndex: Int) -> CGFloat {
        let sizes = sizeRow(sizeIndex)
        guard sizes.indices.contains(TrackKind.video.rawValue) else { return 84 }
        return sizes[TrackKind.video.rawValue]
    }

    // MARK: - State

    var canvas = CanvasSnapshot()
    var trackCount = 0
    /// Index into `DS.trackHeights` — the S/M/L control.
    var heightIndex = 1
    /// Lane height per DISPLAY ROW, row 0 first, from
    /// `rowHeights(for:sizeIndex:)`. Empty is legal and every row then falls
    /// back to the size's video height.
    var rowHeights: [CGFloat] = []
    /// Points per second — the zoom.
    var zoom: CGFloat = defaultZoom
    var duration: Ticks = 0
    /// The scroll view's clip bounds, so the content is never smaller than
    /// what shows (an empty project still paints a full lane background).
    var viewport = CGSize.zero

    // MARK: - Vertical

    /// The height of one lane. Every row has its own since the redesign: a
    /// text lane is 30/44/58, a video lane 54/84/116 and an audio lane
    /// 40/60/82 (`DS.trackHeights`).
    func trackHeight(row: Int) -> CGFloat {
        rowHeights.indices.contains(row)
            ? rowHeights[row] : Self.fallbackHeight(sizeIndex: heightIndex)
    }

    /// Top of the first lane, below the ruler band.
    var lanesTop: CGFloat { Self.rulerHeight + Self.lanesInset }

    /// One row's height plus the gap under it.
    func rowPitch(_ row: Int) -> CGFloat { trackHeight(row: row) + Self.laneSpacing }

    var lanesHeight: CGFloat { rowTop(max(trackCount, 0)) - lanesTop }

    var contentHeight: CGFloat {
        max(lanesTop + lanesHeight + Self.lanesInset, viewport.height)
    }

    /// Top of display row `row`, as a prefix sum over `rowHeights`. Row 0 is
    /// the TOP lane, which is the front-most track — `tracks.last` — because
    /// spec §4.4 puts the front-most track on top while the model stores index
    /// 0 at the back. A negative row is above the stack and is extrapolated at
    /// the fallback pitch, which is what keeps `unclampedRow` invertible there.
    func rowTop(_ row: Int) -> CGFloat {
        guard row > 0 else {
            let pitch = Self.fallbackHeight(sizeIndex: heightIndex) + Self.laneSpacing
            return lanesTop + CGFloat(row) * pitch
        }
        var y = lanesTop
        for index in 0..<row {
            y += rowPitch(index)
        }
        return y
    }

    func rowRect(_ row: Int, width: CGFloat) -> CGRect {
        CGRect(x: 0, y: rowTop(row), width: width, height: trackHeight(row: row))
    }

    /// The display row at `y`, unclamped: negative above the top lane and
    /// `>= trackCount` below the bottom one, which is exactly what a clip
    /// drag needs to decide it should create a track (spec §4.4). Rows have
    /// different heights now, so this walks them rather than dividing — and
    /// past either end it falls back to a constant pitch so "two rows below
    /// the bottom" still means something.
    func unclampedRow(atY y: CGFloat) -> Int {
        let pitch = Self.fallbackHeight(sizeIndex: heightIndex) + Self.laneSpacing
        guard y >= lanesTop else { return Int(((y - lanesTop) / pitch).rounded(.down)) }
        var top = lanesTop
        for row in 0..<max(trackCount, 0) {
            let bottom = top + rowPitch(row)
            if y < bottom { return row }
            top = bottom
        }
        return max(trackCount, 0) + Int(((y - top) / pitch).rounded(.down))
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
            x: left, y: rowTop(row), width: max(right - left, 2), height: trackHeight(row: row))
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
