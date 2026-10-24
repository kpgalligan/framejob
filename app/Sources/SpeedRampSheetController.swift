import AppKit

/// Clip ▸ Speed Ramp…: a Ramp Up, Ramp Down, Speed Dip or Speed Burst on the
/// one selected media clip, in one step (spec §11 SR-24, #340) — the core's
/// `add_speed_ramp` (SR-23), which makes ordinary Speed actions.
///
/// **The span** is the timeline's in/out range when it lies inside the clip,
/// as clip time, and otherwise the clip's whole length (`span(of:range:)`).
///
/// **The readout is the CORE's answer, not a copy of it** (D4-6, D2-1), as the
/// Speed sheet's is: every change runs one trial `applying` of the op Apply
/// would send on the edited project and reads it back — the base rate from
/// `clip_state`'s `speed` before the edit, the target and the return from the
/// new actions' `end.speed`, the hold from their spans. A refusal or an error
/// prints the core's own sentence and disables Apply, so the sheet shows the
/// refusal before it applies. No rate is computed here.
final class SpeedRampSheetController: NSViewController, NSTextFieldDelegate {
    /// Weak, like every sheet's back-reference: the document must be free to
    /// close even with a dialog mid-air.
    private weak var document: ProjectDocument?
    /// The clip's id, not a snapshot: the document replaces its snapshot on
    /// every edit (`SpeedSheetController`'s reasoning).
    private let clip: UInt32
    /// CLIP time, or nil for the whole clip.
    private let span: (from: Ticks, to: Ticks)?

    private let shapePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let rateField = NSTextField(string: "")
    private let presetPopup = NSPopUpButton(frame: .zero, pullsDown: true)
    private let curvePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let holdPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let readoutLabel = NSTextField(wrappingLabelWithString: "")
    private var applyButton: NSButton?

    /// A dip's and a burst's hold choices, as fractions of the span: "None",
    /// "25%", "50%" (the default, the core's own) and "75%".
    static let holds: [Double] = [0, 0.25, 0.5, 0.75]
    /// The shape the sheet opens on: a dip fits a clip already playing its
    /// whole media, where a rise past the base rate would overrun.
    static let initialShape: SpeedRampShape = .speedDip
    static let initialHold: Double = 0.5

    init(document: ProjectDocument, clip: UInt32, span: (from: Ticks, to: Ticks)?) {
        self.document = document
        self.clip = clip
        self.span = span
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SpeedRampSheetController does not support NSCoder")
    }

    // MARK: - The sheet's arithmetic

    /// The rate a shape opens at: ×2 up and burst, ×0.5 down and dip.
    static func defaultRate(for shape: SpeedRampShape) -> Double {
        switch shape {
        case .rampUp, .speedBurst: return 2
        case .rampDown, .speedDip: return 0.5
        }
    }

    /// `range` as clip time when it lies inside `clip` (start at or after the
    /// clip's start, end at or before its end, end after start); nil — the
    /// whole clip — otherwise (SR-24 (b)).
    static func span(
        of clip: ClipSnapshot, range: (start: Ticks, end: Ticks)?
    ) -> (from: Ticks, to: Ticks)? {
        guard let range, range.end > range.start, range.start >= clip.start,
            range.end <= clip.end
        else { return nil }
        return (range.start - clip.start, range.end - clip.start)
    }

    /// The op Apply sends and the readout tries: `hold` only for a dip or a
    /// burst, `from`/`to` only for a span.
    static func op(
        clip: UInt32, shape: SpeedRampShape, rate: Double, curve: Curve, hold: Double,
        span: (from: Ticks, to: Ticks)?
    ) -> ReelOp {
        .addSpeedRamp(
            clip: clip, shape: shape, rate: rate, from: span?.from, to: span?.to, curve: curve,
            hold: shape.holds ? hold : nil)
    }

    struct Readout: Equatable {
        let lines: [String]
        let canApply: Bool
    }

    /// Line 1 names the shape and the span in timeline timecode; line 2 is
    /// the trial's rates (and a dip's or a burst's hold), or the core's
    /// sentence with Apply disabled.
    static func readout(
        of op: ReelOp, clip: UInt32, shape: SpeedRampShape, span: (from: Ticks, to: Ticks)?,
        in project: ReelProject
    ) -> Readout {
        let snapshot = project.snapshot
        guard let target = snapshot.clip(clip) else { return Readout(lines: [], canApply: false) }
        let fps = snapshot.canvas.fps
        let from = target.start + (span?.from ?? 0)
        let to = span.map { target.start + $0.to } ?? target.end
        let place = span == nil ? "the whole clip" : "the range"
        let head =
            "\(shape.displayName) · \(place) " + ReelTime.format(from, fps: fps, frames: true)
            + " – " + ReelTime.format(to, fps: fps, frames: true)
        let trial: ReelEdit
        do {
            trial = try project.applying(op)
        } catch {
            let message = (error as? ReelCoreError)?.message ?? error.localizedDescription
            return Readout(lines: [head, message], canApply: false)
        }
        switch trial {
        case .identity:
            return Readout(lines: [head], canApply: false)
        case .refused(let refusal):
            return Readout(lines: [head, refusal.reason], canApply: false)
        case .applied(let after):
            let before = Set(target.actions.map(\.id))
            let added = (after.snapshot.clip(clip)?.actions ?? [])
                .filter { !before.contains($0.id) }
                .sorted { $0.start < $1.start }
            let base = project.clipState(clip, at: from)?["speed"] as? Double
            func rate(_ value: Double?) -> String {
                value.map { "×" + String(format: "%g", $0) } ?? "×?"
            }
            var line = rate(base) + " → " + rate(added.first?.end.speed)
            if added.count == 2 {
                let held = added[1].start - (added[0].start + added[0].duration)
                line += ", held " + String(format: "%.2f", ReelTime.seconds(held)) + " s, → "
                    + rate(added[1].end.speed)
            }
            return Readout(lines: [head, line], canApply: true)
        }
    }

    // MARK: - View

    override func loadView() {
        for shape in SpeedRampShape.allCases {
            shapePopup.menu?.addItem(menuItem(shape.displayName, shape.rawValue))
        }
        select(shapePopup, SpeedRampSheetController.initialShape.rawValue)
        shapePopup.font = DS.sans(13)
        shapePopup.target = self
        shapePopup.action = #selector(shapeChosen(_:))

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.allowsFloats = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        formatter.minimum = NSNumber(value: SpeedSheetController.rateRange.lowerBound)
        formatter.maximum = NSNumber(value: SpeedSheetController.rateRange.upperBound)
        rateField.formatter = formatter
        rateField.delegate = self
        rateField.alignment = .right
        rateField.doubleValue = Self.defaultRate(for: Self.initialShape)
        rateField.widthAnchor.constraint(equalToConstant: 80).isActive = true
        DSField.style(rateField)

        // A pull-down's first item is its title and is never chosen.
        presetPopup.menu?.addItem(menuItem("Presets", nil))
        for preset in SpeedSheetController.presets {
            presetPopup.menu?.addItem(
                menuItem(SpeedSheetController.title(for: preset), NSNumber(value: preset)))
        }
        presetPopup.font = DS.sans(13)
        presetPopup.target = self
        presetPopup.action = #selector(presetChosen(_:))
        presetPopup.widthAnchor.constraint(equalToConstant: 96).isActive = true

        for curve in [Curve.easeInOut, Curve.linear] {
            curvePopup.menu?.addItem(menuItem(curve.displayName, curve.rawValue))
        }
        select(curvePopup, Curve.easeInOut.rawValue)
        curvePopup.font = DS.sans(13)
        curvePopup.target = self
        curvePopup.action = #selector(controlChanged(_:))

        for hold in Self.holds {
            let title = hold == 0 ? "None" : String(format: "%.0f%%", hold * 100)
            holdPopup.menu?.addItem(menuItem(title, NSNumber(value: hold)))
        }
        if let item = holdPopup.itemArray.first(where: {
            ($0.representedObject as? NSNumber)?.doubleValue == Self.initialHold
        }) {
            holdPopup.select(item)
        }
        holdPopup.font = DS.sans(13)
        holdPopup.target = self
        holdPopup.action = #selector(controlChanged(_:))

        readoutLabel.font = DS.mono(11)
        readoutLabel.textColor = DS.textMuted
        readoutLabel.preferredMaxLayoutWidth = sheetWidth - sheetInset * 2

        let times = NSTextField(labelWithString: "×")
        times.font = DS.sans(13)
        times.textColor = DS.textMuted
        let rateRow = NSStackView(views: [rateField, times, presetPopup])
        rateRow.orientation = .horizontal
        rateRow.alignment = .centerY
        rateRow.spacing = 6

        let grid = NSGridView(views: [
            [fieldLabel("Shape:"), shapePopup],
            [fieldLabel("Rate:"), rateRow],
            [fieldLabel("Curve:"), curvePopup],
            [fieldLabel("Hold:"), holdPopup],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = 106

        let content = NSStackView(views: [grid, readoutLabel])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10

        let cancelButton = sheetCancelButton(target: self, action: #selector(cancelClicked(_:)))
        let apply = sheetApplyButton(target: self, action: #selector(applyClicked(_:)))
        applyButton = apply
        let range = SpeedSheetController.rateRange
        view = makeSheetView(
            title: "Speed Ramp",
            hint: "Up and Burst rise above the clip's rate where the ramp starts; Down and Dip "
                + "fall below it. Dip and Burst return to it, holding the rate between. The "
                + "clip keeps its place and length, and plays more or less of its media.",
            content: content,
            buttonRow: makeButtonRow(
                cancel: cancelButton, apply: apply,
                leading: [
                    sheetFootnote(
                        String(format: "×%g – ×%g", range.lowerBound, range.upperBound))
                ]))
        syncControls()
    }

    private func menuItem(_ title: String, _ value: Any?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.representedObject = value
        return item
    }

    private func select(_ popup: NSPopUpButton, _ raw: String) {
        if let item = popup.itemArray.first(where: { $0.representedObject as? String == raw }) {
            popup.select(item)
        }
    }

    // MARK: - Values

    private var shape: SpeedRampShape {
        (shapePopup.selectedItem?.representedObject as? String)
            .flatMap(SpeedRampShape.init(rawValue:)) ?? Self.initialShape
    }

    private var rate: Double {
        let range = SpeedSheetController.rateRange
        return min(max(rateField.doubleValue, range.lowerBound), range.upperBound)
    }

    private var curve: Curve {
        (curvePopup.selectedItem?.representedObject as? String)
            .flatMap(Curve.init(rawValue:)) ?? .easeInOut
    }

    private var hold: Double {
        (holdPopup.selectedItem?.representedObject as? NSNumber)?.doubleValue ?? Self.initialHold
    }

    private var currentOp: ReelOp {
        Self.op(clip: clip, shape: shape, rate: rate, curve: curve, hold: hold, span: span)
    }

    private func syncControls() {
        holdPopup.isEnabled = shape.holds
        guard let project = document?.editedProject else {
            readoutLabel.stringValue = ""
            applyButton?.isEnabled = false
            return
        }
        let readout = Self.readout(
            of: currentOp, clip: clip, shape: shape, span: span, in: project)
        readoutLabel.stringValue = readout.lines.joined(separator: "\n")
        applyButton?.isEnabled = readout.canApply
    }

    // MARK: - Controls

    @objc private func shapeChosen(_ sender: Any?) {
        rateField.doubleValue = Self.defaultRate(for: shape)
        syncControls()
    }

    @objc private func presetChosen(_ sender: Any?) {
        if let preset = (presetPopup.selectedItem?.representedObject as? NSNumber)?.doubleValue {
            rateField.doubleValue = preset
        }
        // The pull-down always shows its own title, so put it back.
        presetPopup.selectItem(at: 0)
        syncControls()
    }

    @objc private func controlChanged(_ sender: Any?) {
        syncControls()
    }

    /// The readout and Apply follow every keystroke (SR-24 (d)): Apply does
    /// not end the field's editing, and `rate` reads the typed value.
    func controlTextDidChange(_ obj: Notification) {
        syncControls()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        rateField.doubleValue = rate
        syncControls()
    }

    // MARK: - Commit

    @objc private func cancelClicked(_ sender: Any?) {
        dismiss(self)
    }

    /// One `add_speed_ramp`, one undo step named for the shape. A preset that
    /// takes a clip with sound above the audio ceiling asks once first
    /// (`SpeedAudioDrop`, SR-21 (e)), on this sheet's window: Set Speed closes
    /// the sheet and applies, Cancel leaves the sheet up with nothing applied.
    @objc private func applyClicked(_ sender: Any?) {
        guard let document = self.document else {
            dismiss(self)
            return
        }
        let ops = [currentOp]
        let name = shape.displayName
        let crossing = SpeedAudioDrop.crossing(applying: ops, to: document.editedProject)
        guard !crossing.isEmpty else {
            dismiss(self)
            document.applyEdit(name, ops)
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
            document?.performGroupedEdit(name, ops)
        }
    }
}
