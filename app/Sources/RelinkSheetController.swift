import AppKit

/// The missing-media dialog (spec §5.6, §10 step 12): every media entry whose
/// file is gone, with a Locate… beside it, committed as one undo step.
///
/// A project ALWAYS opens, missing files or not — the clips stay, the
/// compositor draws a slate over them and the plan holds their time empty —
/// so this is an offer, never a gate. `EditorViewController+Export.swift`
/// puts it up once per document when a window with missing media appears; the
/// Media tab's per-row Relink… (`MediaPane.swift`) is the same op reached one
/// file at a time.
///
/// Picking one file also OFFERS its folder to the others: a moved shoot is
/// one folder with all of it in, and matching by file name there turns twenty
/// Locate… trips into one. Nothing is matched silently in a folder the user
/// did not just point at.
final class RelinkSheetController: NSViewController {
    /// Weak: a dialog must never keep a closing document alive.
    private weak var document: ProjectDocument?
    /// The missing entries as the sheet opened. The sheet blocks every edit
    /// while it is up, so this list cannot go stale under it.
    private let missing: [MediaSnapshot]
    /// media id → the file the user chose for it. Applied on Apply, not on
    /// pick, so Cancel really does leave the project untouched.
    private var replacements: [UInt32: URL] = [:]
    private var rows: [RelinkRowView] = []
    private var applyButton: NSButton!

    /// Documents this sheet has already been offered for. A WEAK set: an
    /// `ObjectIdentifier` of a closed document can be reused by the next one
    /// allocated at the same address, which would silently skip the offer for
    /// a project that needed it.
    private static let offered = NSHashTable<ProjectDocument>.weakObjects()

    /// True the first time it is asked about a document, false ever after —
    /// the automatic offer happens once per open, not on every window
    /// activation.
    static func markOffered(_ document: ProjectDocument) -> Bool {
        if offered.contains(document) { return false }
        offered.add(document)
        return true
    }

    /// Row height and the tallest the list grows before it scrolls.
    static let rowHeight: CGFloat = 46
    static let maxListHeight: CGFloat = 232

    init(document: ProjectDocument) {
        self.document = document
        self.missing = document.missingMedia
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("RelinkSheetController does not support NSCoder")
    }

    // MARK: - View

    override func loadView() {
        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 0
        list.translatesAutoresizingMaskIntoConstraints = false
        for media in missing {
            let row = RelinkRowView(media: media, sheet: self)
            rows.append(row)
            list.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        }

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = list
        let width = sheetWidth - sheetInset * 2
        let height = min(
            Self.maxListHeight, max(Self.rowHeight, CGFloat(missing.count) * Self.rowHeight))
        NSLayoutConstraint.activate([
            scroll.widthAnchor.constraint(equalToConstant: width),
            scroll.heightAnchor.constraint(equalToConstant: height),
            list.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            list.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
        ])

        let cancelButton = sheetCancelButton(target: self, action: #selector(cancelClicked(_:)))
        applyButton = StickerButton(
            title: "Relink", style: .primary, target: self, action: #selector(applyClicked(_:)))
        let count = missing.count == 1 ? "1 file" : "\(missing.count) files"
        view = makeSheetView(
            title: "Missing media",
            hint: "The project opened without these files: their clips keep their place on the "
                + "timeline and show a slate until the files are found.",
            content: scroll,
            buttonRow: makeButtonRow(
                cancel: cancelButton, apply: applyButton, leading: [sheetFootnote(count)]))
        syncApply()
    }

    private func syncApply() {
        applyButton?.isEnabled = !replacements.isEmpty
    }

    // MARK: - Locating

    /// The Locate… panel for one row. Presented on the SHEET's window, so the
    /// dialog the user is answering stays put behind it.
    func locate(_ media: UInt32) {
        guard let entry = missing.first(where: { $0.id == media }), let window = view.window
        else {
            NSSound.beep()
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose the file for “\(entry.name)”."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self = self else { return }
            self.chose(url, for: media)
        }
    }

    /// Records one choice and offers the rest of the folder to the entries
    /// still unmatched. Only a file that exists AND is not already spoken for
    /// is taken.
    private func chose(_ url: URL, for media: UInt32) {
        replacements[media] = url
        let folder = url.deletingLastPathComponent()
        for entry in missing where entry.id != media && replacements[entry.id] == nil {
            let candidate = folder.appendingPathComponent(entry.name)
            guard FileManager.default.fileExists(atPath: candidate.path) else { continue }
            replacements[entry.id] = candidate
        }
        for row in rows {
            row.update(replacements[row.media])
        }
        syncApply()
    }

    // MARK: - Commit

    @objc private func cancelClicked(_ sender: Any?) {
        dismiss(self)
    }

    /// Every chosen file, in id order, through `ProjectDocument.relinkMedia`
    /// (spec §11, #63): each is probed as import probes it, so an entry takes
    /// its file's duration, size, rate and flags and a clip past a shorter
    /// file's end is held to it; every probed relink is ONE undo step, and a
    /// cache pass follows — a different file rebuilds, the same file moved
    /// elsewhere is skipped (the stamp has no path), and so is every other
    /// media whose marker still matches. A file of another kind is refused
    /// in the core's sentence, which the grouped edit drops when another
    /// relink in it applied (#88's fold).
    @objc private func applyClicked(_ sender: Any?) {
        let replacements = self.replacements
        let document = self.document
        dismiss(self)
        guard let document = document, !replacements.isEmpty else { return }
        let choices = replacements.keys.sorted().compactMap { id -> (media: UInt32, url: URL)? in
            guard let url = replacements[id] else { return nil }
            return (media: id, url: url)
        }
        document.relinkMedia(choices)
    }
}

// MARK: - One row

/// One missing file: its name, where it was, and a Locate… button that turns
/// into the chosen path once a file has been picked.
///
/// It knows only its media id and asks the sheet to do everything — the
/// pattern every list row in this app follows (`MediaRowView`), so a row can
/// never hold a stale copy of a value the document owns.
final class RelinkRowView: NSView {
    let media: UInt32
    private weak var sheet: RelinkSheetController?
    private let nameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let locateButton: NSButton

    init(media: MediaSnapshot, sheet: RelinkSheetController) {
        self.media = media.id
        self.sheet = sheet
        // Target and action are set below: `self` does not exist yet here.
        self.locateButton = StickerButton(
            title: "Locate…", style: .secondary, target: nil, action: nil)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        nameLabel.stringValue = media.name
        nameLabel.font = DS.sans(13, weight: .semibold)
        nameLabel.textColor = DS.textStrong
        nameLabel.lineBreakMode = .byTruncatingMiddle

        pathLabel.stringValue = media.path
        pathLabel.font = DS.mono(10)
        pathLabel.textColor = DS.textFaint
        pathLabel.lineBreakMode = .byTruncatingHead
        // A label resists compression by default, which would push the
        // Locate… button off the card instead of shortening the path.
        for label in [nameLabel, pathLabel] {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }

        locateButton.target = self
        locateButton.action = #selector(locateClicked(_:))

        let text = NSStackView(views: [nameLabel, pathLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        text.translatesAutoresizingMaskIntoConstraints = false
        locateButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)
        addSubview(locateButton)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: RelinkSheetController.rowHeight),
            text.leadingAnchor.constraint(equalTo: leadingAnchor),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.trailingAnchor.constraint(
                lessThanOrEqualTo: locateButton.leadingAnchor, constant: -10),
            locateButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            locateButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("RelinkRowView does not support NSCoder")
    }

    /// Repaints from the sheet's decision: the chosen path in the strong ink,
    /// the old one faint. Called on EVERY row after any pick, because one
    /// pick can match several rows at once.
    func update(_ replacement: URL?) {
        guard let replacement = replacement else { return }
        pathLabel.stringValue = replacement.path
        pathLabel.textColor = DS.textMuted
        locateButton.title = "Change…"
    }

    override func draw(_ dirtyRect: NSRect) {
        DS.border.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }

    @objc private func locateClicked(_ sender: Any?) {
        sheet?.locate(media)
    }
}
