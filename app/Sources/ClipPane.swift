import AppKit

/// The Clip tab: a selection header, then every section the SELECTION has, in
/// one list (the chrome cleanup's Part 2 §5).
///
/// **It owns almost no controls.** The rows are the ones the Video, Audio,
/// Text and Shape panes have always built, so this pane holds one instance of
/// each — never added to any view hierarchy — and uses them purely as section
/// factories. That is safe because a pane holds no state of its own: it reads
/// and writes through the shared `InspectorBinding` this inspector handed it,
/// and the sections it makes are plain `NSView`s that keep working wherever
/// they are added. What this file adds is the header, the Timing section, and
/// `makeSections()` — the function from the selection's kind to the ordered
/// list of sections, which is what replaced the old tab-visibility juggling.
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
        ].joined(separator: "|")
    }

    override func makeHeader() -> (any OptionControl)? {
        ClipSelectionHeaderView(binding: binding)
    }

    // MARK: - Kind → sections

    /// The order the design asks for: what the layer IS, then what it is made
    /// of, then the effects over it, then when it plays, then how it sounds.
    /// A section that does not apply is absent rather than disabled — the pane
    /// is rebuilt when the selection's kinds change, so there is nothing stale
    /// to grey out.
    ///
    /// **Transform is "always" only for a clip that draws.** The design lists
    /// it unconditionally, but every control in it and in the effects group
    /// writes a `set_video` patch, and `InspectorBinding` addresses those to
    /// the clips with PIXELS: on a detached audio clip the patch would name no
    /// clip, so the whole group would be controls that answer a drag with a
    /// beep. `hasPixels` is the Video tab's old enabled-test, which is the
    /// same question asked once instead of six times.
    override func makeSections() -> [InspectorSection] {
        let hasPixels = !binding.videoClips.isEmpty
        var sections: [InspectorSection] = []
        if hasPixels {
            sections.append(videoPane.transformSection())
        }
        if textPane.allText {
            sections.append(contentsOf: [
                textPane.contentSection(), textPane.fontSection(), textPane.styleSection(),
                textPane.outlineSection(), textPane.backdropSection(), textPane.boxSection(),
                textPane.animationSection(), textPane.presetSection(),
            ])
        }
        if shapePane.allShape {
            sections.append(contentsOf: [
                shapePane.shapeSection(), shapePane.strokeSection(), shapePane.fillSection(),
                // Immediately after Fill, because a gradient REPLACES a fill
                // when it is set and the two rows are read together.
                shapePane.gradientSection(), shapePane.arrowSection(),
            ])
        }
        // `allSourcePixels` asks about the SOURCE KIND, so it says yes to an
        // audio-only file's clip too; `hasPixels` is what keeps a crop off a
        // clip that draws nothing.
        if hasPixels, videoPane.allSourcePixels {
            sections.append(contentsOf: [
                videoPane.cropSection(), videoPane.cornerSection(), videoPane.colorSection(),
                videoPane.chromaSection(),
            ])
        }
        // The effects group. Shadow is shared by all three drawing kinds, so
        // it appears once, here, rather than in the text and shape lists.
        if hasPixels {
            sections.append(contentsOf: [
                inspectorShadowSection(binding), videoPane.filtersSection(),
                videoPane.reflectionSection(), videoPane.spotlightSection(),
                videoPane.obscureSection(),
            ])
        }
        if videoPane.allMedia {
            sections.append(videoPane.speedSection())
        }
        if binding.isSingle, let clip = binding.primary {
            sections.append(timingSection(clip.id))
        } else if videoPane.allMedia {
            // The half of Timing a MULTI-clip selection can still answer for.
            // In, Out and Duration genuinely need one clip — two clips have
            // two In points — but Reverse is a per-clip op that fans out
            // happily, and it used to live in Speed, which is built for any
            // all-media selection. Dropping the whole section for two clips
            // took Reverse out of reach with it.
            sections.append(reverseTimingSection())
        }
        sections.append(videoPane.actionsSection())
        if binding.isSingle, let clip = binding.primary, videoPane.overlap(before: clip) != nil {
            sections.append(videoPane.transitionSection(clip.id))
        }
        if !binding.audioClips.isEmpty {
            sections.append(contentsOf: [
                audioPane.volumeSection(), audioPane.fadeSection(), audioPane.duckSection(),
                audioPane.noiseSection(), audioPane.compressorSection(), audioPane.mixSection(),
            ])
        }
        // Transform is the only section built open, so a selection that does
        // not get one — an audio-only clip, whose media has no video track —
        // would open the panel as nine shut headers and nothing to read. The
        // first section takes Transform's place there. `expandByDefault` still
        // defers to a section the user has closed themselves, so this is a
        // default and not an override — and it is offered to each section in
        // TURN for exactly that reason: the first one an audio-only clip gets
        // is `video.speed`, an id the Speed group shares, so a user who once
        // closed Speed on a video clip would otherwise be back to a panel of
        // nine shut headers. The first section with no stored preference opens.
        if !hasPixels, !sections.contains(where: { $0.isExpanded }) {
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
    /// clip and no further than the source has left. The core answers `None` —
    /// the refusal that beeps from `applyEdit` — only when the clamped edge is
    /// where the edge already was, when the two clamps cross (a source with
    /// almost nothing in front of it), or when the move would break the
    /// overlap rule. So a typed value out of range does not beep: it lands
    /// clamped, and the field re-reads whatever the core committed on the
    /// refresh that follows. Nothing here clamps on the user's behalf, which
    /// is what keeps that one rule in one place.
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

// MARK: - Selection header

/// The 44 pt block above the sections: the kind chip, the clip's name, and one
/// mono line of the facts a machine produced — how long it is, and where those
/// pixels came from.
///
/// It is the third view of the one selection model, the other two being the
/// timeline bar's block and the canvas's handles, so the chip and the kind word
/// come from `ClipKindStyle` and agree with them by construction. Drawn rather
/// than composed from controls — with ONE exception since format version 3:
/// for a single clip the name line is an `InspectorNameField`, because this
/// header is where the clip's OWN name is set and the only place it is cleared
/// (the strip's inline editor drops an empty commit — `TimelineView+Rename.swift`
/// says why). A multi-selection keeps the drawn "N clips selected". A label is
/// a 6 pt dot at the line's right end, the strip's dot, so the two views agree.
/// The field binds by clip ID and reads fresh through it (`timingSection`'s rule).
final class ClipSelectionHeaderView: NSView, OptionControl {
    static let height: CGFloat = 44
    /// The name line: 16 pt at y 8 drawn, a 20 pt field at y 6 typed into —
    /// both centred on y 16 — with the meta line under it. `DSField.style`
    /// pins a field at the panel's 26 pt, more than a 44 pt band with a meta
    /// line can give, so the field's is re-pinned (`installNameField`).
    private static let nameTop: CGFloat = 8
    private static let nameHeight: CGFloat = 16
    private static let fieldTop: CGFloat = 6
    private static let fieldHeight: CGFloat = 20
    private static let metaTop: CGFloat = 27
    private static let dotSize: CGFloat = 6
    private static let dotGap: CGFloat = 6

    private let binding: InspectorBinding
    private var nameField: InspectorNameField?
    /// The field's right edge, pulled in by the dot's room while a label is set.
    private var nameTrailing: NSLayoutConstraint?

    init(binding: InspectorBinding) {
        self.binding = binding
        super.init(frame: .zero)
        wantsLayer = true
        // Decided once: the pane, header included, is rebuilt whenever the
        // selected ids change (`structureSignature`).
        if binding.isSingle, let clip = binding.primary {
            installNameField(for: clip.id)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ClipSelectionHeaderView does not support NSCoder")
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.height)
    }

    /// Redraws only when what it SAYS changed. The panel refreshes on every
    /// playhead tick when the selected clip has actions
    /// (`EditorViewController+Inspector.swift`), and re-laying two truncating
    /// strings across a 44 pt band thirty times a second for a value that moves
    /// once per click is work for nothing. The field's own `refresh` is as
    /// cheap, and skips itself while it is typed into.
    func refresh() {
        nameField?.refresh()
        let label = self.label
        let trailing = -(InspectorMetrics.inset + (label == nil ? 0 : Self.dotSize + Self.dotGap))
        if let constraint = nameTrailing, constraint.constant != trailing {
            constraint.constant = trailing
        }
        let next = [name, meta, label ?? ""]
        guard next != lastDrawn else { return }
        lastDrawn = next
        needsDisplay = true
    }

    private var lastDrawn: [String] = []

    // MARK: The name field

    /// The single-clip name line, typed into. It shows what the strip shows
    /// (`name(of:)` — own name or fallback), so what you read is what you
    /// edit, and commits the clip's OWN name: the trimmed text, or `null` for
    /// an emptied field, which is how a name goes back to the fallback.
    /// Emptying a field that already showed the fallback has nothing to
    /// clear: no op is sent (the core's refusal would only beep). Either way
    /// the field re-reads the model as the commit ends — `InspectorNameField`
    /// sets itself directly there, because its `refresh` is skipped while
    /// the field editor is attached, which it still is at that point.
    private func installNameField(for id: UInt32) {
        let binding = self.binding
        /// Read fresh through the captured id, never captured itself: a
        /// rename REPLACES the clip snapshot, and the header is refreshed.
        func clip() -> ClipSnapshot? { binding.snapshot.clip(id) }
        let field = InspectorNameField(
            read: { clip().map { binding.snapshot.name(of: $0) } ?? "" },
            write: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty, clip()?.name == nil { return }
                let patch = ClipPatch(name: .some(trimmed.isEmpty ? nil : trimmed))
                binding.apply("Rename Clip", [.setClip(clips: [id], patch: patch)])
            },
            enabled: { clip() != nil },
            onEdit: { binding.edited() })
        field.font = DS.sans(12, weight: .semibold)
        field.toolTip = "The clip's own name — empty it to go back to what the clip shows"
        // `DSField.style` installed a 26 pt height on the field itself; the
        // one constraint is re-pinned rather than fought with a second.
        for constraint in field.constraints
        where constraint.firstItem === field && constraint.firstAttribute == .height {
            constraint.constant = Self.fieldHeight
        }
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)
        let trailing = field.trailingAnchor.constraint(
            equalTo: trailingAnchor, constant: -InspectorMetrics.inset)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.nameLeft),
            field.topAnchor.constraint(equalTo: topAnchor, constant: Self.fieldTop),
            trailing,
        ])
        nameTrailing = trailing
        nameField = field
    }

    // MARK: What it says

    /// The chip's ink: the kind's tint, or the neutral one when the selection
    /// holds more than one kind and no single tint would be true.
    private var chipColor: NSColor {
        let clips = binding.clips
        guard let first = clips.first else { return DS.borderStrong }
        let tint = ClipKindStyle.tint(for: first, in: binding.snapshot)
        let mixed = clips.dropFirst().contains {
            ClipKindStyle.tint(for: $0, in: binding.snapshot) != tint
        }
        return mixed ? DS.borderStrong : tint
    }

    private var name: String {
        let clips = binding.clips
        guard let first = clips.first else { return "No selection" }
        guard clips.count == 1 else { return "\(clips.count) clips selected" }
        return binding.snapshot.name(of: first)
    }

    /// The label the selection agrees on — nil when the clips disagree or
    /// none has one, so the dot never claims a colour for a clip that has
    /// another. An unknown name draws in the neutral ink, as on the strip.
    private var label: String? {
        let clips = binding.clips
        guard let first = clips.first?.label, !first.isEmpty,
              clips.allSatisfy({ $0.label?.lowercased() == first.lowercased() })
        else { return nil }
        return first
    }

    /// The meta line: the kind word, the duration in the DOCUMENT's timecode
    /// (never the source's), and the source's own facts where there are any.
    private var meta: String {
        let clips = binding.clips
        let canvas = binding.canvas
        guard let first = clips.first else { return "" }
        guard clips.count == 1 else {
            let total = clips.reduce(Ticks(0)) { $0 + $1.duration }
            return ReelTime.format(total, fps: canvas.fps, frames: canvas.timecodeFrames)
                + " total"
        }
        var parts = [ClipKindStyle.name(for: first, in: binding.snapshot)]
        parts.append(
            ReelTime.format(first.duration, fps: canvas.fps, frames: canvas.timecodeFrames))
        if let size = binding.snapshot.sourceSize(of: first), size.width > 0, size.height > 0 {
            parts.append("\(Int(size.width))×\(Int(size.height))")
        }
        // The source's own rate, not the canvas's: it is the one fact here
        // that says whether this clip is being conformed.
        if let media = binding.snapshot.media(for: first), media.hasVideo, media.fps.double > 0 {
            parts.append("\(media.fps.displayName) fps")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Drawing

    /// Where the name line starts: after the chip and its gap.
    private static var nameLeft: CGFloat { InspectorMetrics.inset + 8 + 8 }

    override func draw(_ dirtyRect: NSRect) {
        DS.border.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()

        let chip = NSRect(x: InspectorMetrics.inset, y: bounds.midY - 13, width: 8, height: 26)
        chipColor.setFill()
        NSBezierPath(roundedRect: chip, xRadius: 4, yRadius: 4).fill()

        let left = Self.nameLeft
        var nameRight = bounds.width - InspectorMetrics.inset
        if let label = label {
            // At the line's right end, centred on it, like the strip's.
            let dot = NSRect(
                x: nameRight - Self.dotSize,
                y: Self.nameTop + Self.nameHeight / 2 - Self.dotSize / 2,
                width: Self.dotSize, height: Self.dotSize)
            ClipLabel.color(named: label).setFill()
            NSBezierPath(ovalIn: dot).fill()
            nameRight = dot.minX - Self.dotGap
        }
        // The field paints its own line when there is one.
        if nameField == nil {
            let line = NSRect(
                x: left, y: Self.nameTop, width: max(nameRight - left, 10),
                height: Self.nameHeight)
            draw(name, in: line, font: DS.sans(12, weight: .semibold), color: DS.textStrong)
        }
        let width = max(bounds.width - left - InspectorMetrics.inset, 10)
        draw(meta, in: NSRect(x: left, y: Self.metaTop, width: width, height: 13),
             font: DS.mono(10), color: DS.textFaint)
    }

    /// One truncating line. `TimelineDraw.label` clips instead, which is right
    /// on a clip bar (the bar's edge says where it stopped) and wrong here,
    /// where a cut-off file name has nothing to say it was cut off.
    private func draw(_ text: String, in rect: NSRect, font: NSFont, color: NSColor) {
        guard !text.isEmpty, rect.width > 8 else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        text.draw(
            in: rect,
            withAttributes: [
                .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
            ])
    }
}
