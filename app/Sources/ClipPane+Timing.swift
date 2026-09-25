import AppKit

extension ClipPane {
    // MARK: - Timing

    /// Where the clip sits on the ruler, and which way it runs.
    ///
    /// In and Out are the clip's own edges, typed as timecode and committed as
    /// `trim_start` / `trim_end` — the same two ops the edge drags and the two
    /// Trim to Playhead commands use, so a typed edge obeys the same rules.
    ///
    /// **Those rules CLAMP; they do not refuse** (`core/src/edit_clip.rs`, and
    /// the op table in `edit.rs` says so in one line each): `trim_start` pulls
    /// the new start back to the source head and no later than one frame
    /// before the end, `trim_end` pushes the new end to at least one frame of
    /// clip and no further than the source has left. **The core declines** —
    /// both arms beep from `applyEdit` and neither makes an undo step — when
    /// the clamped edge is where the edge already was or the two clamps cross
    /// (an IDENTITY: a clamp landing where the clip already is names no rule),
    /// and when the move breaks the overlap rule (a REFUSAL, in that rule's
    /// own sentence). So a typed value out of range does not beep: it lands
    /// clamped, and the field re-reads what the core committed. Nothing here
    /// clamps on the user's behalf, which keeps that one rule in one place.
    ///
    /// Duration is read-only because it has no op of its own: it is
    /// `end − start`, and §6 gives you the two edges instead.
    ///
    /// In, Out and Duration are one clip only. Two clips have two In points,
    /// and a field showing the first one's while writing to both would be a
    /// lie about what it edits — `reverseTimingSection()` is what a
    /// multi-clip selection gets instead.
    ///
    /// **It binds by clip ID, captured here, and reads fresh through it** —
    /// the rule every other by-id row in this panel follows
    /// (`VideoPane.transitionSection`, `DocumentPane.markerRow`), and the one
    /// place in the inspector where breaking it edits the WRONG CLIP rather
    /// than merely showing a stale number. These two fields commit on blur,
    /// and a blur can be caused by the rebuild itself: `rebuild()` removes
    /// every arranged subview, removing a field that is being typed into ends
    /// its editing session, and only then does `controlTextDidEndEditing`
    /// fire. Clicking another clip in the timeline takes that path — the
    /// timeline's content view refuses first responder, so the field keeps it
    /// while the selection changes underneath — and a `binding.primary` read
    /// inside the write closure would by then name the clip that was just
    /// clicked. `binding.snapshot.clip(id)` names the one the user typed into.
    /// Once that clip is GONE the reads fall back — 0 for the two edges, "—"
    /// for the duration — and a write still names the dead id, which the core
    /// rejects by name and `applyEdit` puts up as its message. That is loud
    /// for something rare (the clip has to be deleted while its field holds
    /// the field editor) but it is honest, and it is not the thing this rule
    /// exists to prevent, which is editing whichever clip was clicked next.
    ///
    /// The Reverse group under the edges is `reverseRows(over:mixed:)`, shared
    /// with the multi-clip section below.
    func timingSection(_ id: UInt32) -> InspectorSection {
        let binding = self.binding
        /// Read fresh on every call through the captured id, never captured
        /// itself: a trim REPLACES the clip snapshot, and the row is refreshed
        /// rather than rebuilt.
        func clip() -> ClipSnapshot? { binding.snapshot.clip(id) }
        func fps() -> Fps { binding.canvas.fps }
        func frames() -> Bool { binding.canvas.timecodeFrames }
        func duration() -> String {
            guard let clip = clip() else { return "—" }
            return ReelTime.format(clip.duration, fps: fps(), frames: frames())
        }
        let start = InspectorTimecodeField(
            read: { clip()?.start ?? 0 },
            write: { value in
                binding.apply("Trim Start", [.trimStart(clip: id, to: value)])
            },
            fps: fps, frames: frames,
            onEdit: { binding.edited() })
        start.toolTip = "Where the clip starts — trims its front edge"
        let end = InspectorTimecodeField(
            read: { clip()?.end ?? 0 },
            write: { value in
                binding.apply("Trim End", [.trimEnd(clip: id, to: value)])
            },
            fps: fps, frames: frames,
            onEdit: { binding.edited() })
        end.toolTip = "Where the clip ends — trims its back edge"

        var rows: [NSView] = [
            inspectorRow("In", [start]),
            inspectorRow("Out", [end]),
            inspectorRow("Duration", [inspectorReadout { duration() }]),
        ]
        // Reverse is a media-source op (`set_reversed`, §6); a text or shape
        // clip has no frames to turn around. The clip is re-filtered rather
        // than assumed because `allMedia` answered at BUILD time and the rows
        // read live: an empty list is no ops, which is a beep from `apply` and
        // the right answer for a clip that is no longer there. No mixed badge:
        // one clip cannot disagree with itself.
        if videoPane.allMedia {
            rows.append(
                contentsOf: reverseRows(
                    over: {
                        guard let clip = clip(), clip.source.hasSourceBound else { return [] }
                        return [clip]
                    },
                    mixed: nil))
        }
        return InspectorSection(
            id: "clip.timing", title: "Timing",
            summary: { duration() },
            defaultExpanded: false,
            rows: rows)
    }

    /// Timing for a MULTI-clip media selection: the Reverse group, and nothing
    /// else, because In, Out and Duration each describe one edge of one clip.
    ///
    /// The same section id as the single-clip Timing, so the group the user
    /// opened stays open as the selection grows and shrinks, and the same
    /// summary in the header's own vocabulary — the total of what is selected,
    /// spelled the way `ClipSelectionHeaderView` spells it.
    func reverseTimingSection() -> InspectorSection {
        let binding = self.binding
        /// Live, not captured: the rows survive a refresh, and `allMedia`
        /// answered for the selection this build saw.
        func clips() -> [ClipSnapshot] { binding.clips.filter { $0.source.hasSourceBound } }
        func total() -> String {
            let sum = clips().reduce(Ticks(0)) { $0 + $1.duration }
            let canvas = binding.canvas
            return ReelTime.format(sum, fps: canvas.fps, frames: canvas.timecodeFrames) + " total"
        }
        return InspectorSection(
            id: "clip.timing", title: "Timing",
            summary: { total() },
            defaultExpanded: false,
            rows: reverseRows(
                over: clips,
                mixed: { binding.mixed(clips()) { $0.source.isReversed } }))
    }

    /// The Reverse group — the box, the state readout and the retry button —
    /// over whatever clips the section speaks for: the one clip of a
    /// single-clip Timing, every media clip of a multi-clip one. One op per
    /// clip, all in one `apply`, so the fan-out is a single undo step.
    ///
    /// **Reverse carries a state readout that no other control here needs.**
    /// AVFoundation cannot play a clip backwards, so ticking the box does not
    /// change the picture by itself: it makes the app pre-render the frames
    /// (spec §11), and until they exist the clip draws a slate rather than
    /// lying about which way it is going. The readout says which of those the
    /// clip is in, and the button is what restarts a render the user stopped —
    /// the one path back from `ReverseStatus.stopped`, since nothing retries
    /// on its own.
    func reverseRows(
        over clips: @escaping () -> [ClipSnapshot], mixed: (() -> Bool)?
    ) -> [NSView] {
        let binding = self.binding
        /// One line for what may be several clips. Stopped outranks pending
        /// deliberately: it is the state with something to do about it, and a
        /// "Rendering…" that hid a stopped clip behind a rendering one would
        /// grey out the only button that could fix it.
        func status() -> ReverseStatus {
            guard let document = binding.document else { return .off }
            let states = clips().map { document.reverseStatus(of: $0) }
            for state in [ReverseStatus.stopped, .pending, .unavailable, .ready]
            where states.contains(state) {
                return state
            }
            return .off
        }
        let render = OptionButtonControl(
            title: "Render Reverse",
            action: {
                guard let document = binding.document else { return }
                guard let next = clips().first(where: {
                    document.reverseStatus(of: $0) == .stopped
                })
                else { return }
                // **Pitfall:** one press starts ONE media.
                // `ensureReversedMedia` refuses to open a second sheet while
                // one is up, so un-refusing every stopped clip here would
                // leave all but the first reading "Rendering…" with nothing
                // rendering. Retried one at a time, the readout keeps saying
                // "Not rendered" while any remain, and the next press takes
                // the next one.
                document.retryReversedMedia(for: next)
            },
            enabled: { status() == .stopped },
            onEdit: {})
        render.toolTip = "Render the reversed frames these clips need"
        return [
            inspectorCheckRow(
                "Reverse", binding, name: "Reverse",
                read: { clips().first?.source.isReversed ?? false },
                ops: { value in
                    clips().map { ReelOp.setReversed(clip: $0.id, reversed: value) }
                },
                mixed: mixed, resets: false),
            inspectorRow("Reversed frames", [inspectorReadout { status().summary }]),
            inspectorButtonRow([render]),
        ]
    }
}
