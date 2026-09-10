import AppKit

// MARK: - What a press landed on

/// Which end of a clip a gesture grabbed.
enum TimelineEdge: Equatable {
    case start
    case end
}

/// The four toggles in a track header (spec §4.4): eye, speaker, lock, and
/// — since format version 3 — the headphones that solo the track's audio
/// (its text fallback is S, as H/M/L are the other three's).
enum TimelineHeaderButton: Equatable {
    case hidden
    case muted
    case locked
    case solo
}

/// What is under the pointer. `TimelineContentView` computes exactly one of
/// these from the layout and then hands it to the session that owns that
/// kind of drag — so "what did I grab" is decided once, in one function,
/// instead of being re-derived by every mouse handler.
enum TimelineHit: Equatable {
    /// Empty ruler: a scrub.
    case ruler(Ticks)
    case marker(UInt32)
    /// The square where the header column and the ruler cross — inert.
    case corner
    /// The same square while a nest is open, where it carries the breadcrumb
    /// out (road map 2's phase 9). A separate case rather than a flag on
    /// `corner`, so `beginGesture`'s `case .none, .corner: break` keeps
    /// meaning exactly what it says and the click is swallowed in the one
    /// state where there is nothing to go back to.
    case breadcrumb(level: Int)
    case header(row: Int)
    case headerButton(row: Int, button: TimelineHeaderButton)
    case clip(UInt32)
    case clipEdge(UInt32, TimelineEdge)
    case fade(UInt32, TimelineEdge)
    /// Empty lane: a marquee.
    case lane(row: Int, time: Ticks)
    /// Outside everything (below the last lane).
    case none
}

// MARK: - Snapping

/// Spec §4.4's snapping, as one value a gesture can consult.
///
/// Candidates are the core's (`ReelProject.snapCandidates(excluding:)` —
/// every other clip's edges and the markers) plus the playhead and the
/// in/out points, which the core does not know about because they are view
/// state. `enabled` folds together the N toggle and the ⌘ suppression, so a
/// session never has to look at modifier flags itself.
struct TimelineSnapper {
    let fps: Fps
    let candidates: [Ticks]
    /// Radius in ticks — `TimelineLayout.snapThreshold`, i.e. 8 points.
    let threshold: Ticks
    let enabled: Bool

    /// The time to actually use, and the guide to draw (nil when nothing
    /// was snapped). A candidate is already on the frame grid, so only the
    /// unsnapped case needs `snapToFrame` — but every tick that reaches an
    /// op leaves here on the grid either way (spec §6).
    func resolve(_ time: Ticks) -> (time: Ticks, guide: Ticks?) {
        guard enabled else { return (ReelTime.snapToFrame(time, fps: fps), nil) }
        let (resolved, snapped) = ReelSnap.resolve(candidates, time, threshold: threshold)
        if snapped { return (resolved, resolved) }
        return (ReelTime.snapToFrame(time, fps: fps), nil)
    }

    /// The candidate list for a gesture that must not snap to the very clips
    /// it is moving. `core` comes from `snapCandidates(excluding:)`.
    static func candidates(
        core: [Ticks], playhead: Ticks, range: (start: Ticks, end: Ticks)?
    ) -> [Ticks] {
        var all = core
        all.append(playhead)
        if let range = range {
            all.append(range.start)
            all.append(range.end)
        }
        return Array(Set(all)).sorted()
    }
}

// MARK: - Clip drag

/// Moving clips in time and across tracks (spec §4.4, §6 `move_clip`).
///
/// The preview *is* the edit: every tick calls `ProjectDocument.updateLiveEdit`
/// with `ops`, which re-applies to the handle the gesture started from, so
/// the bars the user drags are the core's own answer and a tick the core
/// refuses simply leaves the last good frame on screen (spec §7.6).
///
/// ⌥ duplicates. `duplicate` mints its copies inside the core, so the ids to
/// move are learned once at mouse-down by applying `duplicate` to the
/// current handle PURELY (`TimelineView.onProbe`) — a question, not an edit.
struct ClipDragSession {
    /// Every dragged clip, the anchor first is not required — `anchor` names
    /// it explicitly.
    let clips: [UInt32]
    let anchor: UInt32
    let anchorStart: Ticks
    let anchorRow: Int
    /// Time under the pointer at mouse-down, so the bar does not jump to
    /// centre itself on the cursor.
    let grabTime: Ticks
    /// Earliest start in the dragged set: the group's own origin, which is
    /// what snapping tests against a candidate.
    let spanStart: Ticks
    let trackCount: Int
    let duplicating: Bool
    /// Ids `duplicate` will mint, in the same order as `clips` sorted by
    /// start; empty when the probe failed and the drag falls back to a move.
    let copies: [UInt32]
    /// How far `duplicate` pushed the copies past the originals, so the move
    /// that follows lands them under the pointer and not past the span.
    let copyShift: Ticks
    /// Ids `add_track` will mint for a drop above the top lane / below the
    /// bottom one, probed with the same op PREFIX the drop will use so the
    /// core mints them in the same order. nil disables that end.
    let newTrackTop: UInt32?
    let newTrackBottom: UInt32?

    var delta: Ticks = 0
    var row: Int
    /// Non-nil while the drag is locked to a snap candidate.
    var guide: Ticks?
    /// False until the pointer actually leaves the press point — a click
    /// that merely selects must not register an undo step.
    var didMove = false

    /// True when the drop is past either end of the stack, which spec §4.4
    /// turns into a new track rather than a refusal.
    var needsNewTrack: Bool { row < 0 || row >= trackCount }

    /// Where `add_track` inserts it: model index `trackCount` (the front) for
    /// a drop above the top lane, 0 (the back) for one below the bottom.
    var newTrackIndex: Int { row < 0 ? trackCount : 0 }

    /// The anchor's proposed start — what the refusal check compares against
    /// once the core has had its say.
    var proposedStart: Ticks { anchorStart + delta }

    /// The ops for the current drag state, as ONE undo step.
    ///
    /// Order matters and is the order the probes assumed: `duplicate` first
    /// (so its copies take the low ids), then `add_track`, then the move.
    /// `destination` is the id of an EXISTING track to land on, or nil to
    /// leave every clip where it is vertically.
    func ops(destination: UInt32?) -> [ReelOp] {
        var ops: [ReelOp] = []
        let moved = duplicating && !copies.isEmpty ? copies : clips
        let shift = duplicating && !copies.isEmpty ? delta - copyShift : delta
        if duplicating, !copies.isEmpty {
            ops.append(.duplicate(clips: clips))
        }
        var target = destination
        if needsNewTrack, let created = row < 0 ? newTrackTop : newTrackBottom {
            ops.append(.addTrack(index: newTrackIndex))
            target = created
        }
        ops.append(.moveClip(clips: moved, delta: shift, track: target))
        return ops
    }

    /// Advances the drag. `time` is the time under the pointer and `row` the
    /// lane under it; snapping is applied to the GROUP's start so the whole
    /// selection clicks into place together.
    mutating func update(time: Ticks, row: Int, snapper: TimelineSnapper) {
        let raw = time - grabTime
        let resolved = snapper.resolve(spanStart + raw)
        delta = resolved.time - spanStart
        guide = resolved.guide
        // A clip can never start before zero (§6 clamps it); keeping the
        // preview honest about that stops the group sliding while the core
        // refuses to follow.
        if spanStart + delta < 0 { delta = -spanStart }
        self.row = row
        didMove = true
    }
}

// MARK: - Trim

/// Dragging a clip edge (spec §6 `trim_start` / `trim_end`), or with ⌥ a
/// rate stretch of the end.
///
/// **Pitfall:** `rate_stretch` only takes `to_end`, so ⌥ on the START edge
/// has nothing to express — it trims like a bare drag rather than pretending
/// to stretch and silently doing something else.
struct TrimSession {
    let clip: UInt32
    let edge: TimelineEdge
    let stretch: Bool
    let originalStart: Ticks
    let originalEnd: Ticks
    /// One frame of the document's grid: the minimum a clip may keep.
    let frame: Ticks

    var time: Ticks
    var guide: Ticks?
    var didMove = false

    /// True when ⌥ actually changes the op.
    var isRateStretch: Bool { stretch && edge == .end }

    var op: ReelOp {
        switch edge {
        case .start:
            return .trimStart(clip: clip, to: min(time, originalEnd - frame))
        case .end:
            let to = max(time, originalStart + frame)
            return isRateStretch
                ? .rateStretch(clip: clip, toEnd: to) : .trimEnd(clip: clip, to: to)
        }
    }

    mutating func update(time: Ticks, snapper: TimelineSnapper) {
        let resolved = snapper.resolve(time)
        // Clamped here as well as in the core: the preview must not show an
        // inverted bar for the ticks the core is busy refusing.
        switch edge {
        case .start:
            self.time = max(0, min(resolved.time, originalEnd - frame))
        case .end:
            self.time = max(resolved.time, originalStart + frame)
        }
        guide = resolved.guide
        didMove = true
    }
}

// MARK: - The edge moves

/// ⌥⇧-dragging a clip's BODY: the source slides under a fixed clip
/// (spec §6 `slip`).
///
/// The op's `delta` is the TOTAL travel since mouse-down, not this tick's
/// increment, because `updateLiveEdit` re-applies against the handle the
/// gesture started from. It is also deliberately unsnapped: the thing being
/// moved is inside the media, where the timeline's candidates — other
/// clips' edges, the markers, the playhead — mean nothing. The core rounds
/// it to the frame grid, so the film still steps a frame at a time.
struct SlipSession {
    let clip: UInt32
    /// Time under the pointer at mouse-down, so the film keeps pace with
    /// the cursor.
    let grabTime: Ticks

    var delta: Ticks = 0
    var didMove = false

    var op: ReelOp { .slip(clip: clip, delta: delta) }

    mutating func update(time: Ticks) {
        delta = time - grabTime
        didMove = true
    }
}

/// ⌥⇧-dragging a clip's EDGE: the hard cut moves and nothing else does
/// (spec §6 `roll`).
///
/// Either edge rolls, but they roll DIFFERENT cuts, and the op only ever
/// names the clip on the cut's right: grabbing the start edge rolls this
/// clip against its predecessor, and grabbing the end edge rolls the
/// SUCCESSOR against this one. `clip` is resolved at mouse-down, so the
/// session itself has one job.
///
/// Clamped in the preview as well as in the core, for `TrimSession`'s
/// reason: the bar must not be drawn inverted for the ticks the core is
/// busy refusing. The bounds here are the frame minimums only — the source
/// clamps need the media, which the core has and the view does not — so a
/// drag past those still looks live and lands where the core allows.
struct RollSession {
    let clip: UInt32
    let earliest: Ticks
    let latest: Ticks

    var time: Ticks
    var guide: Ticks?
    var didMove = false

    var op: ReelOp { .roll(clip: clip, to: time) }

    mutating func update(time: Ticks, snapper: TimelineSnapper) {
        let resolved = snapper.resolve(time)
        self.time = max(earliest, min(resolved.time, latest))
        guide = resolved.guide
        didMove = true
    }
}

// MARK: - Marquee

/// Rubber-band selection on an empty lane. ⇧ adds to what was already
/// selected; a bare drag replaces it.
struct RangeSession {
    let origin: CGPoint
    let additive: Bool
    let base: Set<UInt32>
    var current: CGPoint

    var rect: CGRect {
        CGRect(
            x: min(origin.x, current.x), y: min(origin.y, current.y),
            width: abs(current.x - origin.x), height: abs(current.y - origin.y))
    }

    /// Every clip whose bar intersects the band, unioned with `base` when ⇧
    /// was held. Locked tracks are skipped: a marquee that selects clips no
    /// edit can touch is a trap.
    func selection(in snapshot: ProjectSnapshot, layout: TimelineLayout) -> Set<UInt32> {
        var hit = additive ? base : []
        let band = rect
        for (index, track) in snapshot.tracks.enumerated() where !track.locked {
            let row = layout.row(forTrackIndex: index)
            for clip in snapshot.clips(onTrack: track.id)
            where layout.clipRect(clip, row: row).intersects(band) {
                hit.insert(clip.id)
            }
        }
        return hit
    }
}

// MARK: - Playhead

/// Scrubbing from the ruler. Playback stops for the duration of the drag —
/// seeking under a running player fights the rate observer — and the time is
/// pushed straight at the controller, never at an op: the playhead is view
/// state (spec §5.2).
struct PlayheadSession {
    var time: Ticks
    let wasPlaying: Bool

    mutating func update(time: Ticks, snapper: TimelineSnapper) {
        self.time = max(0, snapper.resolve(time).time)
    }
}

// MARK: - Marker drag

/// Dragging a marker flag along the ruler (spec §6 `set_marker`). Two
/// markers may not share a time, so a drag onto another one is refused by
/// the core and the flag stays where it was.
struct MarkerDragSession {
    let marker: UInt32
    let original: Ticks
    var time: Ticks
    var guide: Ticks?
    var didMove = false

    var op: ReelOp { .setMarker(marker: marker, time: max(0, time)) }

    mutating func update(time: Ticks, snapper: TimelineSnapper) {
        let resolved = snapper.resolve(time)
        self.time = max(0, resolved.time)
        guide = resolved.guide
        didMove = true
    }
}

// MARK: - Fade handles

/// The small squares at the audio corners, dragged inward to set
/// `audio.fade_in` / `audio.fade_out` (spec §4.4). The length is a duration,
/// not a time, so it never snaps to a clip edge — it clamps to the clip.
struct FadeHandleSession {
    let clip: UInt32
    let edge: TimelineEdge
    let clipStart: Ticks
    let clipEnd: Ticks
    var length: Ticks
    var didMove = false

    var op: ReelOp {
        var patch = AudioPatch()
        switch edge {
        case .start: patch.fadeIn = length
        case .end: patch.fadeOut = length
        }
        return .setAudio(clips: [clip], patch: patch)
    }

    /// `time` is the pointer's time; the fade is the distance from the
    /// matching edge, capped at the clip's own length.
    mutating func update(time: Ticks, fps: Fps) {
        let span = max(clipEnd - clipStart, 0)
        let raw: Ticks
        switch edge {
        case .start: raw = time - clipStart
        case .end: raw = clipEnd - time
        }
        length = ReelTime.snapToFrame(max(0, min(raw, span)), fps: fps)
        didMove = true
    }
}

// MARK: - Track reorder

/// Dragging a track header to restack it (spec §4.4). The drag is in display
/// rows (0 = top = front-most); `op` converts back to the model's index,
/// where 0 is the BACK of the stack.
struct TrackDragSession {
    let track: UInt32
    let originalRow: Int
    let trackCount: Int
    var row: Int
    var didMove = false

    var op: ReelOp? {
        guard row != originalRow, (0..<trackCount).contains(row) else { return nil }
        return .moveTrack(track: track, index: trackCount - 1 - row)
    }

    mutating func update(row: Int) {
        self.row = min(max(row, 0), max(trackCount - 1, 0))
        didMove = true
    }
}
