import AppKit

/// Clip ▸ Speed…: the playback rate for the selected clips, whether pitch is
/// preserved, and the length that results (spec §6's `set_speed`).
///
/// Only `media` clips are offered. `set_speed` is an ERROR, not a refusal, on
/// any other source kind (§6), so a still or a text clip in the selection is
/// filtered out here rather than being sent and coming back as an alert —
/// `EditorViewController+Export.swift` refuses to open the sheet at all when
/// nothing in the selection qualifies.
///
/// **The duration readout is the CORE's answer, not a copy of it** (spec §11,
/// D4-6). It applies the sheet's own ops to the immutable handle and reads the
/// durations back: an edit is pure (§5.5), so asking costs a discarded handle
/// and needs no new export. A quotient in Swift could not say what `set_speed`
/// really writes — the duration is snapped to the nearest frame and then held
/// to what the FILE holds at the new rate (D4-3), and a clip slowed into its
/// neighbour is either APPLIED at its full new length, the neighbour gaining a
/// minted cross dissolve, or REFUSED by the overlap rule and left as it was.
/// `applying` runs past a refusal, so a mixed selection reads the applied
/// clips' new lengths beside the refused clips' old ones, which is exactly
/// what Apply will write.
final class SpeedSheetController: NSViewController, NSTextFieldDelegate {
    /// Weak, like every sheet's back-reference: the document must be free to
    /// close even with a dialog mid-air.
    private weak var document: ProjectDocument?
    /// Clip ids, not snapshots: a `ClipSnapshot` captured at open time would
    /// be a stale copy of a value the document replaces wholesale on every
    /// edit (the inspector rule, and the same reasoning applies here).
    private let clips: [UInt32]

    /// The rate the selection started at — 1 when the clips disagree — so
    /// "changed nothing" can be told from "set them all to what one of them
    /// already was".
    private let originalRate: Double
    private let originalKeepPitch: Bool
    /// True when the selection did not agree on a rate. Then ×1 IS a change —
    /// it normalises them — even though it equals `originalRate`.
    private let ratesDiffer: Bool

    private let rateField = NSTextField(string: "")
    private let presetPopup = NSPopUpButton(frame: .zero, pullsDown: true)
    private let pitchCheckbox = NSButton(
        checkboxWithTitle: "Preserve pitch", target: nil, action: nil)
    private let durationLabel = NSTextField(wrappingLabelWithString: "")

    /// §6 clamps the rate to the core's `ReelSpeed.limits`; the field refuses
    /// outside them rather than letting the core silently clamp a number the
    /// user typed.
    static let rateRange = ReelSpeed.limits.range
    /// The rates the pull-down offers: the common editing rates, then ×10 and ×100
    /// for a long recording (spec §11 #190).
    static let presets: [Double] = [0.25, 0.5, 1, 1.5, 2, 4, 10, 100]

    init(document: ProjectDocument, clips: [UInt32]) {
        self.document = document
        self.clips = clips
        // The EDITED project: this sheet is opened on the SELECTION, and with
        // a nest open the selection is the nest's clips (road map 2's phase
        // 9). At the top level it is `document.project` as before.
        let snapshot = document.editedProject.snapshot
        let speeds = clips.compactMap { snapshot.clip($0)?.speed }
        let first = speeds.first ?? 1
        let uniform = speeds.allSatisfy { $0 == first } && first > 0
        self.ratesDiffer = !uniform
        self.originalRate = uniform ? first : 1
        self.originalKeepPitch =
            clips.compactMap { snapshot.clip($0)?.audioProps.keepPitch }.first ?? true
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SpeedSheetController does not support NSCoder")
    }

    // MARK: - View

    override func loadView() {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.allowsFloats = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        formatter.minimum = NSNumber(value: Self.rateRange.lowerBound)
        formatter.maximum = NSNumber(value: Self.rateRange.upperBound)
        rateField.formatter = formatter
        rateField.delegate = self
        rateField.alignment = .right
        rateField.doubleValue = originalRate
        rateField.widthAnchor.constraint(equalToConstant: 80).isActive = true
        DSField.style(rateField)

        // A pull-down's first item is its title and is never chosen, so the
        // presets start at index 1 and `applyPreset` subtracts it.
        presetPopup.addItem(withTitle: "Presets")
        for preset in Self.presets {
            presetPopup.addItem(withTitle: Self.title(for: preset))
        }
        presetPopup.font = DS.sans(13)
        presetPopup.target = self
        presetPopup.action = #selector(presetChosen(_:))
        presetPopup.widthAnchor.constraint(equalToConstant: 96).isActive = true

        pitchCheckbox.state = originalKeepPitch ? .on : .off
        pitchCheckbox.font = DS.sans(13)
        pitchCheckbox.target = self
        pitchCheckbox.action = #selector(pitchChanged(_:))

        durationLabel.font = DS.mono(11)
        durationLabel.textColor = DS.textMuted
        durationLabel.preferredMaxLayoutWidth = sheetWidth - sheetInset * 2

        let times = NSTextField(labelWithString: "×")
        times.font = DS.sans(13)
        times.textColor = DS.textMuted
        let rateRow = NSStackView(views: [rateField, times, presetPopup])
        rateRow.orientation = .horizontal
        rateRow.alignment = .centerY
        rateRow.spacing = 6

        let grid = NSGridView(views: [
            [fieldLabel("Rate:"), rateRow],
            [NSGridCell.emptyContentView, pitchCheckbox],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = 106

        let content = NSStackView(views: [grid, durationLabel])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10

        let cancelButton = sheetCancelButton(target: self, action: #selector(cancelClicked(_:)))
        let applyButton = sheetApplyButton(target: self, action: #selector(applyClicked(_:)))
        view = makeSheetView(
            title: "Speed",
            hint: "Faster clips can leave gaps; slower clips can overlap. Later clips stay in "
                + "place. A clip an allowed overlap reaches gains a transition, named below. "
                + "If an overlap is not allowed, that clip stays unchanged; other selected "
                + "clips can still change.",
            content: content,
            buttonRow: makeButtonRow(
                cancel: cancelButton, apply: applyButton,
                leading: [
                    sheetFootnote(
                        String(
                            format: "×%g – ×%g", Self.rateRange.lowerBound,
                            Self.rateRange.upperBound))
                ]))
        syncReadout()
    }

    static func title(for rate: Double) -> String {
        String(format: rate < 1 ? "%.2f×" : "%g×", rate)
    }

    // MARK: - Values

    /// The rate the controls describe, always inside §6's clamp.
    private var rate: Double {
        min(max(rateField.doubleValue, Self.rateRange.lowerBound), Self.rateRange.upperBound)
    }

    private var keepPitch: Bool { pitchCheckbox.state == .on }

    /// The ops Apply sends — one `set_speed` per clip, in the selection's own
    /// order — so what the readout asks about and what Apply writes are one
    /// list and cannot drift. `applyClicked` calls it.
    static func ops(for clips: [UInt32], rate: Double, keepPitch: Bool) -> [ReelOp] {
        clips.map { .setSpeed(clip: $0, rate: rate, keepPitch: keepPitch) }
    }

    /// A clip whose transition a trial makes play (#109), or makes longer or
    /// shorter (#184), and that transition's length after the trial.
    struct TransitionChange: Equatable {
        enum Change: Equatable { case gains, grows, shrinks }
        let clip: UInt32
        let kind: TransitionKind
        let change: Change
        /// The overlap with its predecessor after the trial.
        let duration: Ticks
    }

    /// The project once the sheet's ops have run — the ONE `applying` every
    /// line of the readout is read off. A refusal still answers the project
    /// with the refused clips as they were.
    static func trial(
        of clips: [UInt32], rate: Double, keepPitch: Bool, in project: ReelProject
    ) -> ProjectSnapshot {
        let ops = Self.ops(for: clips, rate: rate, keepPitch: keepPitch)
        return ((try? project.applying(ops)).project ?? project).snapshot
    }

    /// What the selection measures now, and what it measures once those ops
    /// have run — the two numbers the readout prints, both read off a project.
    ///
    /// `after` is summed from the handle the ops make, not from arithmetic
    /// here, which is the whole of the type doc's claim. A clip the core
    /// refused is absent from nothing — it is still in the applied snapshot,
    /// at the length it had — so a refusal reads as "no change" for that clip
    /// and the rest of the selection still counts.
    static func lengths(
        of clips: [UInt32], rate: Double, keepPitch: Bool, in project: ReelProject
    ) -> (before: Ticks, after: Ticks) {
        lengths(
            of: clips, before: project.snapshot,
            after: trial(of: clips, rate: rate, keepPitch: keepPitch, in: project))
    }

    static func lengths(
        of clips: [UInt32], before snapshot: ProjectSnapshot, after applied: ProjectSnapshot
    ) -> (before: Ticks, after: Ticks) {
        var before: Ticks = 0
        var after: Ticks = 0
        for id in clips {
            guard let clip = snapshot.clip(id), clip.speed > 0 else { continue }
            before += clip.duration
            after += applied.clip(id)?.duration ?? clip.duration
        }
        return (before, after)
    }

    /// Every clip, on a track holding one of `clips`, whose transition plays
    /// in `after` and either did not in `before` (`.gains` — a minted cross
    /// dissolve, or a transition set earlier that an overlap now reaches) or
    /// did at a smaller or larger overlap (`.grows`, `.shrinks`). A transition
    /// plays when the clip has one and overlaps its predecessor
    /// (`VideoPane.overlap(before:)`'s idiom). One that plays in both at the
    /// same overlap is absent. Ordered by start, then id.
    static func transitionChanges(
        of clips: [UInt32], before: ProjectSnapshot, after: ProjectSnapshot
    ) -> [TransitionChange] {
        func overlap(_ id: UInt32, in snapshot: ProjectSnapshot) -> Ticks {
            guard let clip = snapshot.clip(id) else { return 0 }
            let earlier = snapshot.clips(onTrack: clip.track).filter { $0.start < clip.start }
            guard let previous = earlier.last else { return 0 }
            return previous.end - clip.start
        }
        func effective(_ id: UInt32, in snapshot: ProjectSnapshot) -> Bool {
            snapshot.clip(id)?.transitionIn != nil && overlap(id, in: snapshot) > 0
        }
        let tracks = Set(clips.compactMap { before.clip($0)?.track })
        var changes: [(start: Ticks, change: TransitionChange)] = []
        for clip in after.clips where tracks.contains(clip.track) {
            let id = clip.id
            let had = effective(id, in: before)
            guard effective(id, in: after), let kind = clip.transitionIn?.kind else { continue }
            let now = overlap(id, in: after)
            let was = overlap(id, in: before)
            guard !had || now != was else { continue }
            let change: TransitionChange.Change = !had ? .gains : now > was ? .grows : .shrinks
            changes.append(
                (clip.start, TransitionChange(clip: id, kind: kind, change: change, duration: now)))
        }
        return changes.sorted { ($0.start, $0.change.clip) < ($1.start, $1.change.clip) }
            .map(\.change)
    }

    /// "clip 7 gains a 0.67 s cross dissolve", "clip 7's cross dissolve grows
    /// to 1.50 s", "clip 7's cross dissolve shrinks to 0.67 s".
    static func changeLine(_ change: TransitionChange) -> String {
        let seconds = String(format: "%.2f", ReelTime.seconds(change.duration))
        let kind = change.kind.displayName.lowercased()
        switch change.change {
        case .gains: return "clip \(change.clip) gains a \(seconds) s \(kind)"
        case .grows: return "clip \(change.clip)'s \(kind) grows to \(seconds) s"
        case .shrinks: return "clip \(change.clip)'s \(kind) shrinks to \(seconds) s"
        }
    }

    /// The readout's last line when a selected clip ramps its speed: Apply
    /// sets the base rate and scales the ramp with it (rule L, spec §11
    /// SR-19 (a), SR-21 (f)).
    static let rampLine =
        "Each speed ramp keeps its shape: the rates it names scale with the base rate."

    /// "3 clips · 00:00:12:00 → 00:00:06:00", then one `changeLine` per clip
    /// whose transition the trial makes play, grow or shrink — every line
    /// read off one trial handle — then `rampLine` when a selected clip is
    /// ramped (the core's `sourceMap`).
    static func readout(
        of clips: [UInt32], rate: Double, keepPitch: Bool, in project: ReelProject
    ) -> String {
        let before = project.snapshot
        let after = trial(of: clips, rate: rate, keepPitch: keepPitch, in: project)
        let (from, to) = lengths(of: clips, before: before, after: after)
        let fps = before.canvas.fps
        let count = clips.count == 1 ? "1 clip" : "\(clips.count) clips"
        let summary =
            count + " · " + ReelTime.format(from, fps: fps, frames: true) + " → "
            + ReelTime.format(to, fps: fps, frames: true)
        let changes = transitionChanges(of: clips, before: before, after: after)
        let ramp = clips.contains { project.sourceMap($0)?.ramped == true } ? [rampLine] : []
        return ([summary] + changes.map(changeLine) + ramp).joined(separator: "\n")
    }

    private func syncReadout() {
        guard let project = document?.editedProject else {
            durationLabel.stringValue = ""
            return
        }
        durationLabel.stringValue = Self.readout(
            of: clips, rate: rate, keepPitch: keepPitch, in: project)
    }

    // MARK: - Controls

    @objc private func presetChosen(_ sender: Any?) {
        let index = presetPopup.indexOfSelectedItem - 1
        guard index >= 0, index < Self.presets.count else { return }
        rateField.doubleValue = Self.presets[index]
        // The pull-down always shows its own title, so put it back.
        presetPopup.selectItem(at: 0)
        syncReadout()
    }

    @objc private func pitchChanged(_ sender: Any?) {
        syncReadout()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        rateField.doubleValue = rate
        syncReadout()
    }

    // MARK: - Commit

    @objc private func cancelClicked(_ sender: Any?) {
        dismiss(self)
    }

    /// One `set_speed` per clip, committed as ONE undo step. A rate that is
    /// already what every clip has is not an edit — the core would return
    /// identity and `applyEdit` would beep at a dialog the user just
    /// confirmed, which reads as a refusal rather than as "nothing to do".
    ///
    /// A rate that takes a clip with sound above the audio ceiling asks first
    /// (`SpeedAudioDrop`, #212), on this sheet's own window: Set Speed closes
    /// the sheet and applies, Cancel leaves the sheet up with nothing applied.
    @objc private func applyClicked(_ sender: Any?) {
        let rate = self.rate
        let keepPitch = self.keepPitch
        guard ratesDiffer || rate != originalRate || keepPitch != originalKeepPitch else {
            dismiss(self)
            return
        }
        guard let document = self.document, !clips.isEmpty else {
            dismiss(self)
            return
        }
        let ops = Self.ops(for: clips, rate: rate, keepPitch: keepPitch)
        let crossing = SpeedAudioDrop.crossing(applying: ops, to: document.editedProject)
        guard !crossing.isEmpty else {
            dismiss(self)
            document.applyEdit("Set Speed", ops)
            return
        }
        guard let window = view.window else {
            NSSound.beep()
            return
        }
        SpeedAudioDrop.ask(crossing, on: window) { [weak self, weak document] confirmed in
            guard confirmed else { return }
            if let self { self.dismiss(self) }
            // A sheet's completion is not an AppKit event: the grouped entry
            // point is mandatory here (app/CLAUDE.md's undo pitfall).
            document?.performGroupedEdit("Set Speed", ops)
        }
    }
}
