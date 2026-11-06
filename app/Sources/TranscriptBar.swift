import AppKit

/// The Transcript tab's bar (road map "creator-jobs" TX2b, spec §11 TX-24…
/// TX-27): pinned above the text as the pane's ONE `makeHeader()` instance,
/// so the controller hosts it above the scroll view as it hosts the Clip
/// tab's `ClipHeaderBlock`, and it never scrolls.
///
/// Top down: Words from and Language (an `InspectorRowLabel` at
/// `InspectorMetrics.labelWidth`, then an `OptionPopupControl` spanning the
/// rest of the row); the status row, its sentence wrapping, with Stop at its
/// right while the tab's waiter reads or Read when stopped; then the notes —
/// the same-speech notes, at most three "“name” (clip N) — reason" rows and
/// "…and N more clips with no words.", whose tooltip lists the rest. What is
/// empty collapses. Every value is the source's (`TranscriptTabSource`); the
/// bar stores none, and rebuilds a popup only when its titles change.
final class TranscriptBar: NSView, OptionControl {
    /// The no-words rows shown before "…and N more".
    static let noWordsShown = 3

    private weak var source: TranscriptTabSource?
    private let stack = NSStackView()
    private let wordsSlot = NSView()
    private let languageSlot = NSView()
    private let statusRow = NSStackView()
    private let statusLabel: InspectorNoteLabel
    private let status: Lines
    private var stopButton: OptionButtonControl!
    private var readButton: OptionButtonControl!
    private let notes = NSStackView()
    private var noteTexts: [String] = []
    private var wordsTitles: [String] = []
    private var languageTitles: [String] = []
    private var wordsPopup: OptionPopupControl?
    private var languagePopup: OptionPopupControl?
    /// The popups a rebuild replaced, held a generation: a pick lands inside
    /// the old popup's own menu callback.
    private var retired: [NSView] = []

    init(source: TranscriptTabSource) {
        self.source = source
        let status = Lines()
        self.status = status
        statusLabel = InspectorNoteLabel(wraps: true) {
            status.lines.isEmpty ? nil : status.lines.joined(separator: "\n")
        }
        super.init(frame: .zero)
        stopButton = OptionButtonControl(
            title: "Stop", action: { [weak self] in self?.pressStop() }, enabled: { true }, onEdit: {})
        stopButton.setAccessibilityIdentifier("transcript.stop")
        stopButton.toolTip = "Stop reading on this Mac. A tool call's reading goes on."
        readButton = OptionButtonControl(
            title: "Read", action: { [weak self] in self?.pressRead() }, enabled: { true }, onEdit: {})
        readButton.setAccessibilityIdentifier("transcript.read")
        readButton.toolTip = "Read the files left on this Mac."

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = InspectorMetrics.rowSpacing
        stack.edgeInsets = NSEdgeInsets(
            top: 8, left: InspectorMetrics.inset, bottom: 6, right: InspectorMetrics.inset)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        statusRow.orientation = .horizontal
        statusRow.alignment = .top
        statusRow.spacing = 8
        statusRow.distribution = .fill
        statusRow.addArrangedSubview(statusLabel)
        statusRow.addArrangedSubview(stopButton)
        statusRow.addArrangedSubview(readButton)
        // The sentence takes the row; the button keeps its own width.
        statusLabel.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        for button in [stopButton!, readButton!] {
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        notes.orientation = .vertical
        notes.alignment = .leading
        notes.spacing = 4

        let rows: [NSView] = [
            row("Words from", wordsSlot), row("Language", languageSlot), statusRow, notes,
        ]
        for view in rows {
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(
                equalTo: stack.widthAnchor, constant: -2 * InspectorMetrics.inset
            ).isActive = true
        }
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TranscriptBar does not support NSCoder")
    }

    override var isFlipped: Bool { true }

    /// The status sentences the status label reads.
    private final class Lines {
        var lines: [String] = []
    }

    /// A label at `labelWidth`, then `slot` to the row's end.
    private func row(_ title: String, _ slot: NSView) -> NSView {
        let box = NSView()
        let label = InspectorRowLabel(title)
        for view in [label, slot] {
            view.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(view)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            label.widthAnchor.constraint(equalToConstant: InspectorMetrics.labelWidth),
            label.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            slot.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 6),
            slot.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            slot.topAnchor.constraint(equalTo: box.topAnchor),
            slot.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            slot.heightAnchor.constraint(equalToConstant: DS.controlHeight),
        ])
        return box
    }

    /// `popup` in `slot`, spanning it.
    private func install(_ popup: OptionPopupControl, in slot: NSView) {
        let old = slot.subviews
        retired += old
        for view in old { view.removeFromSuperview() }
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        popup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        slot.addSubview(popup)
        NSLayoutConstraint.activate([
            popup.leadingAnchor.constraint(equalTo: slot.leadingAnchor),
            popup.trailingAnchor.constraint(equalTo: slot.trailingAnchor),
            popup.topAnchor.constraint(equalTo: slot.topAnchor),
            popup.bottomAnchor.constraint(equalTo: slot.bottomAnchor),
        ])
    }

    // MARK: - Refresh

    func refresh() {
        guard let source else { return }
        retired = []
        var moved = refreshPopups(source)
        status.lines = Self.statusText(source.status) ?? []
        statusLabel.refresh()
        let before = [stopButton.isHidden, readButton.isHidden, statusRow.isHidden]
        stopButton.isHidden = !stopShown
        readButton.isHidden = !readShown
        statusRow.isHidden = status.lines.isEmpty && !stopShown && !readShown
        moved = moved || before != [stopButton.isHidden, readButton.isHidden, statusRow.isHidden]
        moved = refreshNotes(source) || moved
        // A view coming or going lands at a zero frame until the next layout
        // pass: lay the window out now, so nothing reads it before then.
        if moved { window?.contentView?.layoutSubtreeIfNeeded() }
    }

    /// Rebuilds a popup whose titles changed, which it answers.
    private func refreshPopups(_ source: TranscriptTabSource) -> Bool {
        var rebuilt = false
        let trackChoices: [(title: String, value: UInt32?)] =
            [("All tracks", nil)] + source.tracks.map { ($0.name, Optional($0.id)) }
        let titles = trackChoices.map(\.title)
        if titles != wordsTitles || wordsPopup == nil {
            wordsTitles = titles
            let popup = OptionPopupControl(
                width: InspectorMetrics.popupWidth, choices: trackChoices,
                read: { [weak source] in source?.wordsFrom },
                write: { [weak self] in self?.chooseWordsFrom($0) },
                enabled: { true }, onEdit: {})
            popup.setAccessibilityIdentifier("transcript.words-from")
            wordsPopup = popup
            install(popup, in: wordsSlot)
            rebuilt = true
        } else {
            wordsPopup?.refresh()
        }

        let installed = source.languages ?? []
        // The default's identifier, not its name: "Automatic (English (United
        // States))" runs past the popup's chevron at the inspector's 280 pt.
        let automatic = Transcriber.defaultLanguage(in: installed).map {
            "Automatic (\($0.identifier))"
        } ?? "Automatic"
        let languageChoices: [(title: String, value: String?)] =
            [(automatic, nil)] + installed.map { ($0.displayName, Optional($0.identifier)) }
        let names = languageChoices.map(\.title)
        if names != languageTitles || languagePopup == nil {
            languageTitles = names
            let popup = OptionPopupControl(
                width: InspectorMetrics.popupWidth, choices: languageChoices,
                read: { [weak source] in source?.language },
                write: { [weak self] in self?.chooseLanguage($0) },
                enabled: { [weak source] in !(source?.languages ?? []).isEmpty }, onEdit: {})
            popup.setAccessibilityIdentifier("transcript.language")
            languagePopup = popup
            install(popup, in: languageSlot)
            rebuilt = true
        } else {
            languagePopup?.refresh()
        }
        return rebuilt
    }

    /// The same-speech notes, then at most `noWordsShown` clips with no
    /// words and one line for the rest; rebuilt only when the text changes,
    /// which it answers.
    private func refreshNotes(_ source: TranscriptTabSource) -> Bool {
        let rows = source.noWords.map(\.row)
        var texts = source.notes + rows.prefix(Self.noWordsShown)
        let rest = Array(rows.dropFirst(Self.noWordsShown))
        if !rest.isEmpty {
            texts.append("…and \(rest.count) more clip\(rest.count == 1 ? "" : "s") with no words.")
        }
        let hidden = notes.isHidden
        notes.isHidden = texts.isEmpty
        guard texts != noteTexts else { return hidden != notes.isHidden }
        noteTexts = texts
        for view in notes.arrangedSubviews { view.removeFromSuperview() }
        for (index, text) in texts.enumerated() {
            let label = InspectorNoteLabel(wraps: true) { text }
            if !rest.isEmpty, index == texts.count - 1 {
                label.toolTip = rest.joined(separator: "\n")
            }
            notes.addArrangedSubview(label)
            label.widthAnchor.constraint(equalTo: notes.widthAnchor).isActive = true
        }
        return true
    }

    /// The status line's sentences (TX-22, TX-26); nil when it says nothing.
    static func statusText(_ status: TranscriptTabSource.Status) -> [String]? {
        switch status {
        case .idle, .loading:
            return nil
        case .reading(let name, let fraction, let index, let of):
            return ["Reading “\(name)” on this Mac… \(Int((fraction * 100).rounded(.down))) % (\(index) of \(of))"]
        case .noModel:
            return [
                "This Mac has no speech model installed. Choose File ▸ Generate Captions…, pick "
                    + "a language and press Download."
            ]
        case .failed(let sentences):
            return sentences
        case .stopped(let remaining):
            return ["Stopped. \(remaining) file\(remaining == 1 ? "" : "s") not read on this Mac."]
        }
    }

    // MARK: - The controls' own paths (the dev tool presses these too)

    var stopShown: Bool { source?.canStop ?? false }

    var readShown: Bool {
        if case .stopped = source?.status { return true }
        return false
    }

    func chooseWordsFrom(_ track: UInt32?) {
        source?.setWordsFrom(track)
        refresh()
    }

    func chooseLanguage(_ identifier: String?) {
        source?.setLanguage(identifier)
        refresh()
    }

    func pressStop() {
        guard stopShown else { return }
        source?.stop()
        refresh()
    }

    func pressRead() {
        guard readShown else { return }
        source?.resume()
        refresh()
    }
}
