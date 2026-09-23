import AppKit

/// The Clip tab: a pinned block — the selection header, the action lane and
/// the sub-tabs (spec §11 CI-5) — over the sections of the ACTIVE sub-tab.
///
/// **It owns almost no controls.** The rows are the ones the Video, Audio,
/// Text and Shape panes have always built, so this pane holds one instance of
/// each — never added to any view hierarchy — and uses them purely as section
/// factories. That is safe because a pane holds no state of its own: it reads
/// and writes through the shared `InspectorBinding` this inspector handed it,
/// and the sections it makes are plain `NSView`s that keep working wherever
/// they are added. What this file adds is the header, the Timing section, and
/// `makeSections()` — the function from the selection's kind and the active
/// sub-tab to the ordered list of sections.
///
/// **Why the sections are the ones that already existed.** The handoff's table
/// draws five groups (TRANSFORM · VIDEO · AUDIO · EFFECTS · TIMING) of four or
/// five rows each, but the same document says the pane contents move "into
/// sections largely as-is" and that the work is "the shell and the
/// kind-to-sections function, not the rows". Those two readings disagree, and
/// this is the one that loses nothing: today's twenty-odd sections each carry
/// their own Reset button and their own evaluated-action note ("Editing action
/// 2's end state"), both of which are per-section by construction
/// (`InspectorSection`), and folding five of them into one VIDEO group would
/// have to throw away four Resets and four notes. So the existing sections
/// stay the unit, the Clip tab lists them all, and the section SUMMARY the
/// design asks for — plus Transform open and the rest closed — is what keeps
/// the panel readable at that length.
final class ClipPane: InspectorPaneView {
    /// The four factories. Constructed once and kept: their sections capture
    /// them (a Reset closure holds `binding`, a button holds `inspector`), and
    /// they are cheap — an `NSView` with a stack view nobody ever lays out.
    private let videoPane: VideoPane
    private let audioPane: AudioPane
    private let textPane: TextPane
    private let shapePane: ShapePane
    /// The sub-tab picked by hand, if any. Forgotten by the CONTROLLER when
    /// the selection's ids change (`forgetSubTab()`), never here.
    private var chosen: ClipSubTab?

    override init(inspector: InspectorViewController) {
        videoPane = VideoPane(inspector: inspector)
        audioPane = AudioPane(inspector: inspector)
        textPane = TextPane(inspector: inspector)
        shapePane = ShapePane(inspector: inspector)
        super.init(inspector: inspector)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ClipPane does not support NSCoder")
    }

    // MARK: - Shape of the panel

    /// The four panes' signatures, composed. Each of them knows something this
    /// one cannot see — a filter added, a text family changed, a shape kind
    /// switched — and a signature that missed any of it would leave the pane
    /// refreshed but not rebuilt, which shows up as controls that never
    /// appear.
    ///
    /// The two halves are added on top of them all, because whether the
    /// selection has PIXELS and whether it has AUDIO each add or remove a
    /// whole group of sections while every clip id stays exactly as it was.
    /// The audio half is the one that moves under an edit: `hasAudio` reads
    /// `clip.enabled.audio`, so Detach Audio and the clip menu's toggle change
    /// it (`set_enabled`, §6). The video half does NOT track that flag —
    /// `hasPixels` asks the MEDIA whether it has a video track, not the clip
    /// whether its video is on — so what moves it is a relink or a consolidate
    /// that puts different media under the clip. Both are cheap to ask and
    /// neither is visible in the four panes' own signatures.
    override var structureSignature: String {
        [
            super.structureSignature,
            videoPane.structureSignature,
            textPane.structureSignature,
            shapePane.structureSignature,
            audioPane.structureSignature,
            (binding.videoClips.isEmpty ? "-" : "px") + (binding.audioClips.isEmpty ? "-" : "au"),
            activeSubTab.rawValue, subTabs.map(\.rawValue).joined(separator: ","),
        ].joined(separator: "|")
    }

    override func makeHeader() -> (any OptionControl)? {
        let binding = self.binding
        let strip = ClipSubTabsView(
            tabs: subTabs, active: activeSubTab,
            badge: { tab in binding.selectedAction.map { tab.keyedCount(in: $0.end) } ?? 0 },
            onSelect: { [weak inspector] in inspector?.selectClipSubTab($0) })
        return ClipHeaderBlock(binding: binding, inspector: inspector, subTabs: strip)
    }

    // MARK: - Sub-tabs

    /// The selection's tabs, in display order: Text or Shape first for those
    /// kinds, Picture for clips that draw, Sound for clips with audio, and
    /// Clip always, last.
    var subTabs: [ClipSubTab] {
        var tabs: [ClipSubTab] = []
        if textPane.allText { tabs.append(.text) }
        if shapePane.allShape { tabs.append(.shape) }
        if !binding.videoClips.isEmpty { tabs.append(.picture) }
        if !binding.audioClips.isEmpty { tabs.append(.sound) }
        tabs.append(.clip)
        return tabs
    }

    /// The tab picked by hand while the selection has it, else the first.
    var activeSubTab: ClipSubTab {
        let tabs = subTabs
        if let chosen, tabs.contains(chosen) { return chosen }
        return tabs.first ?? .clip
    }

    /// Records a pick; triggers nothing (`selectClipSubTab` refreshes).
    func choose(_ tab: ClipSubTab) { chosen = tab }

    /// Back to the default tab; triggers nothing. The controller calls it
    /// when the selection's ids change.
    func forgetSubTab() { chosen = nil }

    // MARK: - Kind → sections

    /// The active sub-tab's sections, in the handoff's order. A section that
    /// does not apply is absent rather than disabled — the pane is rebuilt
    /// when the selection's kinds or the tab change, so there is nothing
    /// stale to grey out.
    ///
    /// Picture exists only for a selection with PIXELS: every control in it
    /// writes a `set_video` patch, and `InspectorBinding` addresses those to
    /// the clips that draw.
    override func makeSections() -> [InspectorSection] {
        let hasPixels = !binding.videoClips.isEmpty
        var sections: [InspectorSection] = []
        switch activeSubTab {
        case .text:
            sections = [
                textPane.contentSection(), textPane.fontSection(), textPane.styleSection(),
                textPane.outlineSection(), textPane.backdropSection(), textPane.boxSection(),
                textPane.animationSection(), textPane.presetSection(),
            ]
        case .shape:
            sections = [
                shapePane.shapeSection(), shapePane.strokeSection(), shapePane.fillSection(),
                // Immediately after Fill, because a gradient REPLACES a fill
                // when it is set and the two rows are read together.
                shapePane.gradientSection(), shapePane.arrowSection(),
            ]
        case .picture:
            sections = [videoPane.transformSection()]
            // `allSourcePixels` asks about the SOURCE KIND, so it says yes to
            // an audio-only file's clip too; the tab itself is what keeps a
            // crop off a clip that draws nothing.
            if videoPane.allSourcePixels {
                sections += [
                    videoPane.cropSection(), videoPane.cornerSection(), videoPane.colorSection(),
                    videoPane.chromaSection(),
                ]
            }
            // Shadow is shared by all three drawing kinds, so it is here once.
            sections += [
                inspectorShadowSection(binding), videoPane.filtersSection(),
                videoPane.reflectionSection(), videoPane.spotlightSection(),
                videoPane.obscureSection(),
            ]
        case .sound:
            sections = [
                audioPane.volumeSection(), audioPane.fadeSection(), audioPane.duckSection(),
                audioPane.noiseSection(), audioPane.compressorSection(), audioPane.mixSection(),
            ]
        case .clip:
            if binding.isSingle, let clip = binding.primary {
                sections.append(timingSection(clip.id))
            } else if videoPane.allMedia {
                // The half of Timing a MULTI-clip selection can still answer
                // for: Reverse is a per-clip op that fans out happily, where
                // In, Out and Duration genuinely need one clip.
                sections.append(reverseTimingSection())
            }
            if videoPane.allMedia {
                sections.append(videoPane.speedSection())
            }
            if binding.isSingle, let clip = binding.primary,
               videoPane.overlap(before: clip) != nil {
                sections.append(videoPane.transitionSection(clip.id))
            }
            if hasPixels {
                sections.append(videoPane.motionSection())
            }
        }
        // A tab that would open as a column of shut headers opens its first
        // section with no stored preference instead. `expandByDefault` defers
        // to a section the user has closed themselves, so this is a default
        // and not an override — and it is offered to each section in TURN
        // because an id can be shared (`video.speed`, `clip.timing`), and a
        // group closed once elsewhere would otherwise leave the tab shut.
        if !sections.contains(where: { $0.isExpanded }) {
            for section in sections {
                if section.expandByDefault() { break }
            }
        }
        return sections
    }

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
    private func timingSection(_ id: UInt32) -> InspectorSection {
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
    private func reverseTimingSection() -> InspectorSection {
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
    private func reverseRows(
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
                mixed: mixed),
            inspectorRow("Reversed frames", [inspectorReadout { status().summary }]),
            inspectorButtonRow([render]),
        ]
    }
}
