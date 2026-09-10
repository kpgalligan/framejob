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
/// The duration readout is computed in Swift and is the ONE thing here the
/// core does not answer: `duration = source length / rate` is the op's own
/// definition (§6), and asking the core would mean applying the edit to find
/// out what it would do.
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

    /// §6 clamps the rate to ×0.1–×10; the field refuses outside it rather
    /// than letting the core silently clamp a number the user typed.
    static let rateRange = 0.1...10.0
    /// The rates the pull-down offers, a screencast editor's set.
    static let presets: [Double] = [0.25, 0.5, 1, 1.5, 2, 4]

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
            hint: "Faster clips get shorter and slower ones longer; the clips after them stay "
                + "where they are, so a speed change opens or leaves a gap.",
            content: content,
            buttonRow: makeButtonRow(
                cancel: cancelButton, apply: applyButton,
                leading: [sheetFootnote("×0.1 – ×10")]))
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

    /// "3 clips · 00:00:12:00 → 00:00:06:00". The source length is
    /// `duration × speed` (§5.2's speed is a rate, so the clip is that much
    /// shorter than its source), and the new length is that over the new rate
    /// — the op's own arithmetic, spelled once.
    private func syncReadout() {
        guard let snapshot = document?.editedProject.snapshot else {
            durationLabel.stringValue = ""
            return
        }
        var before: Ticks = 0
        var after: Ticks = 0
        let rate = self.rate
        for id in clips {
            guard let clip = snapshot.clip(id), clip.speed > 0 else { continue }
            let source = Double(clip.duration) * clip.speed
            before += clip.duration
            after += Ticks((source / rate).rounded())
        }
        let fps = snapshot.canvas.fps
        let count = clips.count == 1 ? "1 clip" : "\(clips.count) clips"
        durationLabel.stringValue =
            count + " · " + ReelTime.format(before, fps: fps, frames: true) + " → "
            + ReelTime.format(after, fps: fps, frames: true)
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
    @objc private func applyClicked(_ sender: Any?) {
        let rate = self.rate
        let keepPitch = self.keepPitch
        let document = self.document
        dismiss(self)
        guard ratesDiffer || rate != originalRate || keepPitch != originalKeepPitch else { return }
        guard let document = document, !clips.isEmpty else { return }
        document.applyEdit(
            "Set Speed",
            clips.map { .setSpeed(clip: $0, rate: rate, keepPitch: keepPitch) })
    }
}
