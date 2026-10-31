import AppKit

/// The Match Audio sheet (road map "audio" AP12, spec §11 AU-121): Clip ▸
/// Match Audio… puts it up over two or more selected clips that could play
/// sound, to choose the reference the others are matched to and what is
/// matched.
///
/// "Match to" lists the clips in timeline order (start, then track order),
/// the first chosen. Each row is an `NSMenuItem` carrying its CLIP ID in
/// `representedObject`, added through the menu and read back from the
/// selected item, never by its index or title: `addItem(withTitle:)` drops a
/// row whose title is already there (`CaptionExporter`'s measured reason),
/// and the titles carry the track and the id besides. Loudness and EQ start
/// on every time (not remembered); Match is disabled with both off.
///
/// **The hand-back is the Measuring Sound sheet's**: Match stores the choice
/// and dismisses; `chosen` is called once, on the main queue's next turn
/// after `viewDidDisappear` (while it runs the window still reports this
/// sheet as attached), and never after Cancel. Only then does the editor
/// press `AudioMeasureDoor.pressMatch`, which puts up its own sheet.
///
/// **The dev accept** (`-RCDevMatchAudioAccept YES`, dev tools only): the
/// sheet presses its own Match once it is up, so a proof can drive the menu
/// item to its edit (AU-128).
final class AudioMatchSheetController: NSViewController {
    /// The dev-only launch default that presses Match.
    static let devAcceptKey = "RCDevMatchAudioAccept"

    /// What Match hands back.
    struct Choice: Equatable {
        let reference: UInt32
        let loudness: Bool
        let eq: Bool
    }

    /// One row of "Match to".
    struct Candidate: Equatable {
        let clip: UInt32
        let title: String
    }

    private let candidates: [Candidate]
    private let chosen: (Choice) -> Void

    private let referencePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let loudnessCheckbox = NSButton(
        checkboxWithTitle: "Loudness", target: nil, action: nil)
    private let eqCheckbox = NSButton(checkboxWithTitle: "EQ", target: nil, action: nil)
    /// Set in `loadView`; implicitly unwrapped for exactly that reason
    /// (app/CLAUDE.md).
    private var matchButton: NSButton!

    private var choice: Choice?
    private var answered = false

    init(candidates: [Candidate], chosen: @escaping (Choice) -> Void) {
        self.candidates = candidates
        self.chosen = chosen
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("AudioMatchSheetController does not support NSCoder")
    }

    /// The clips `canOffer` passes, in timeline order: start, then track
    /// order. Each titled `<clip name> — <track name> — m:ss (clip <id>)`.
    static func candidates(_ clips: [ClipSnapshot], in snapshot: ProjectSnapshot) -> [Candidate] {
        let order = clips.filter { AudioNormalize.canOffer($0, in: snapshot) }.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            return (snapshot.trackIndex(of: $0.track) ?? 0) < (snapshot.trackIndex(of: $1.track) ?? 0)
        }
        return order.map { clip in
            let index = snapshot.trackIndex(of: clip.track) ?? 0
            let named = snapshot.track(clip.track)?.name ?? ""
            let track = named.isEmpty ? "Track \(index + 1)" : named
            let seconds = max(0, Int(clip.start / ReelTime.perSecond))
            let time = String(format: "%d:%02d", seconds / 60, seconds % 60)
            return Candidate(
                clip: clip.id,
                title: "\(snapshot.name(of: clip)) — \(track) — \(time) (clip \(clip.id))")
        }
    }

    override func loadView() {
        for candidate in candidates {
            let item = NSMenuItem(title: candidate.title, action: nil, keyEquivalent: "")
            item.representedObject = NSNumber(value: candidate.clip)
            referencePopup.menu?.addItem(item)
        }
        referencePopup.font = DS.sans(13)
        referencePopup.selectItem(at: 0)

        for box in [loudnessCheckbox, eqCheckbox] {
            box.state = .on
            box.font = DS.sans(13)
            box.target = self
            box.action = #selector(partChanged(_:))
        }
        loudnessCheckbox.toolTip =
            "Each other clip's volume set so it plays as loud as the reference (and the "
            + "limiter, when its peaks need it)."
        eqCheckbox.toolTip =
            "Each other clip's EQ shelves and bands set so its voice has the reference's "
            + "tone; its high- and low-pass are kept."

        let grid = makeSheetGrid([
            [fieldLabel("Match to:"), referencePopup],
            [NSGridCell.emptyContentView, loudnessCheckbox],
            [NSGridCell.emptyContentView, eqCheckbox],
        ])

        let cancelButton = sheetCancelButton(target: self, action: #selector(cancelClicked(_:)))
        matchButton = StickerButton(
            title: "Match", style: .primary, target: self, action: #selector(matchClicked(_:)))
        view = makeSheetView(
            title: "Match Audio",
            hint: "The other selected clips take the reference's loudness and its speech's "
                + "tone, written as their own Volume, Limiter and EQ settings in one undo "
                + "step. Each clip is measured as it plays, which takes a moment on a long "
                + "clip.",
            content: sheetColumn([grid]),
            buttonRow: makeButtonRow(cancel: cancelButton, apply: matchButton))
        syncMatch()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        #if FRAMEJOB_DEV_TOOLS
        if UserDefaults.standard.bool(forKey: Self.devAcceptKey) {
            DispatchQueue.main.async { [weak self] in self?.matchClicked(nil) }
        }
        #endif
    }

    /// The one hand-back: once, with the choice, and never after Cancel.
    override func viewDidDisappear() {
        super.viewDidDisappear()
        guard !answered, let choice else { return }
        answered = true
        let chosen = self.chosen
        DispatchQueue.main.async { chosen(choice) }
    }

    private func syncMatch() {
        matchButton.isEnabled = loudnessCheckbox.state == .on || eqCheckbox.state == .on
    }

    @objc private func partChanged(_ sender: Any?) {
        syncMatch()
    }

    @objc private func cancelClicked(_ sender: Any?) {
        dismiss(self)
    }

    @objc private func matchClicked(_ sender: Any?) {
        let loudness = loudnessCheckbox.state == .on
        let eq = eqCheckbox.state == .on
        guard choice == nil, loudness || eq,
            let reference = (referencePopup.selectedItem?.representedObject as? NSNumber)?
                .uint32Value
        else { return NSSound.beep() }
        choice = Choice(reference: reference, loudness: loudness, eq: eq)
        dismiss(self)
    }
}
