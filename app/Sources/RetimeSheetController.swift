import AppKit

/// Clip ▸ Retime Range… (road map "creator-jobs" CU9a, spec §11 CU-90 (d)):
/// the In–Out range played faster or slower on every unlocked track, and
/// everything after it moved to stay in step — one `retime_range`, one undo
/// step "Retime Range".
///
/// Rate starts at ×2 with the Speed sheet's field, presets and footnote
/// (`SpeedRateControls`); Preserve pitch starts at the Keep pitch of the first
/// media clip on an unlocked track that overlaps the range, on when there is
/// none. Apply at ×1 only closes the sheet. Otherwise it commits through
/// `SpeedAudioDrop.commit`, always sending `keep_pitch`, so a rate that takes
/// a clip with sound above the audio ceiling asks first, on this sheet's
/// window: Set Speed closes the sheet and applies, Cancel leaves it up with
/// nothing applied. What the core refuses comes back as `applyEdit`'s strip.
///
/// **The dev accept** (`-RCDevRetimeAccept YES`, dev tools only): the sheet
/// presses its own Apply once it is up, so a proof can drive the menu item to
/// its edit (AU-128's precedent).
final class RetimeSheetController: NSViewController, NSTextFieldDelegate {
    /// The dev-only launch default that presses Apply.
    static let devAcceptKey = "RCDevRetimeAccept"
    /// The rate the sheet opens at.
    static let initialRate: Double = 2

    /// Weak, like every sheet's back-reference: the document must be free to
    /// close even with a dialog mid-air.
    private weak var document: ProjectDocument?
    private let range: (from: Ticks, to: Ticks)
    private let originalKeepPitch: Bool

    private let rateField = NSTextField(string: "")
    private let presetPopup = NSPopUpButton(frame: .zero, pullsDown: true)
    private let pitchCheckbox = NSButton(
        checkboxWithTitle: "Preserve pitch", target: nil, action: nil)

    init(document: ProjectDocument, range: (from: Ticks, to: Ticks)) {
        self.document = document
        self.range = range
        // The EDITED project: inside a nest the range is the nest's.
        self.originalKeepPitch = Self.initialKeepPitch(
            in: document.editedProject.snapshot, from: range.from, to: range.to)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("RetimeSheetController does not support NSCoder")
    }

    // MARK: - View

    override func loadView() {
        SpeedRateControls.styleRateField(rateField, initial: Self.initialRate, delegate: self)
        SpeedRateControls.fillPresets(
            presetPopup, target: self, action: #selector(presetChosen(_:)))

        pitchCheckbox.state = originalKeepPitch ? .on : .off
        pitchCheckbox.font = DS.sans(13)

        let grid = makeSheetGrid([
            [fieldLabel("Rate:"), SpeedRateControls.rateRow(field: rateField, presets: presetPopup)],
            [NSGridCell.emptyContentView, pitchCheckbox],
        ])

        let cancelButton = sheetCancelButton(target: self, action: #selector(cancelClicked(_:)))
        let applyButton = sheetApplyButton(target: self, action: #selector(applyClicked(_:)))
        view = makeSheetView(
            title: "Retime Range",
            hint: "Every unlocked track between In and Out plays faster or slower, and "
                + "everything after Out moves to stay in step. One undo step.",
            content: sheetColumn([grid]),
            buttonRow: makeButtonRow(
                cancel: cancelButton, apply: applyButton,
                leading: [SpeedRateControls.rangeFootnote()]))
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        #if FRAMEJOB_DEV_TOOLS
        if UserDefaults.standard.bool(forKey: Self.devAcceptKey) {
            DispatchQueue.main.async { [weak self] in self?.applyClicked(nil) }
        }
        #endif
    }

    // MARK: - Values

    /// The ops Apply sends: one `retime_range` over the range.
    static func ops(from: Ticks, to: Ticks, rate: Double, keepPitch: Bool) -> [ReelOp] {
        [.retimeRange(from: from, to: to, rate: rate, keepPitch: keepPitch)]
    }

    /// Preserve pitch's first state: the Keep pitch of the first media clip,
    /// in snapshot order, on an unlocked track and overlapping `[from, to)`;
    /// on when there is none.
    static func initialKeepPitch(in snapshot: ProjectSnapshot, from: Ticks, to: Ticks) -> Bool {
        let unlocked = Set(snapshot.tracks.filter { !$0.locked }.map(\.id))
        let first = snapshot.clips.first { clip in
            guard case .media = clip.source else { return false }
            return unlocked.contains(clip.track) && clip.start < to && clip.end > from
        }
        return first?.audioProps.keepPitch ?? true
    }

    /// The rate the controls describe, always inside the core's clamp.
    private var rate: Double {
        SpeedRateControls.clamp(rateField.doubleValue)
    }

    private var keepPitch: Bool { pitchCheckbox.state == .on }

    // MARK: - Controls

    @objc private func presetChosen(_ sender: Any?) {
        guard let preset = SpeedRateControls.preset(of: presetPopup) else { return }
        rateField.doubleValue = preset
        // The pull-down always shows its own title, so put it back.
        presetPopup.selectItem(at: 0)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        rateField.doubleValue = rate
    }

    // MARK: - Commit

    @objc private func cancelClicked(_ sender: Any?) {
        dismiss(self)
    }

    /// ×1 is no edit: the core answers an identity and `applyEdit` would beep
    /// at a dialog the person just confirmed, so the sheet only closes.
    @objc private func applyClicked(_ sender: Any?) {
        let rate = self.rate
        guard rate != 1, let document = self.document else {
            dismiss(self)
            return
        }
        SpeedAudioDrop.commit(
            "Retime Range",
            Self.ops(from: range.from, to: range.to, rate: rate, keepPitch: keepPitch),
            to: document, asking: view.window,
            before: { [weak self] in if let self { self.dismiss(self) } })
    }
}
