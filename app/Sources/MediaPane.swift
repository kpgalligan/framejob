import AppKit
import UniformTypeIdentifiers

/// The Media tab (spec §4.3): every imported file with its thumbnail, name,
/// duration, dimensions, rate and badges; Add Media… (⇧⌘I); Finder drops onto
/// the panel; a drag from a row to a timeline track or onto the canvas; and
/// the row menu — Reveal in Finder, Relink…, Remove.
///
/// There is no left panel in this app (§11), so this list IS the library.
/// Files are referenced, never copied (path + bookmark, §11), which is why a
/// row can be "missing" and why Relink… lives here.
final class MediaPane: InspectorPaneView {
    override var tab: InspectorTab { .media }

    /// The Media tab always has something to show — including when there is
    /// nothing imported yet, which is when Add Media… matters most.
    override var emptyMessage: String? { nil }

    private var rows: [MediaRowView] = []

    override var structureSignature: String {
        let media = binding.snapshot.media.map { entry -> String in
            "\(entry.id):\(mediaURL(for: entry) == nil ? "missing" : "ok")"
        }
        return "media|" + media.joined(separator: ",")
    }

    override init(inspector: InspectorViewController) {
        super.init(inspector: inspector)
        // Finder drops land on the panel (§4.3). The editor's root view takes
        // file drops too, but it OPENS them as documents; a drop on this
        // panel means "add to this project", so the pane claims the type
        // first by being the deeper registered view.
        registerForDraggedTypes([.fileURL])
        NotificationCenter.default.addObserver(
            self, selector: #selector(cacheChanged(_:)), name: .mediaCacheDidChange, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MediaPane does not support NSCoder")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Sections

    /// The redesign makes this tab a real LIST rather than a stack of button
    /// rows (handoff README, Part 2 §5): a 38 pt action row, the rows 3 pt
    /// apart, and a 40 pt footer carrying Consolidate… and one line saying
    /// what it does. It is still ONE `InspectorSection`, because the panel's
    /// shell builds every pane from sections and this one has no business
    /// forking that.
    override func makeSections() -> [InspectorSection] {
        rows = []
        var content: [NSView] = [actionRow()]
        if binding.snapshot.media.isEmpty {
            content.append(
                inspectorRow(nil, [InspectorRowLabel("Drop files here, or use Add Media….")]))
        } else {
            content.append(listView())
        }
        content.append(footerRow())
        return [InspectorSection(id: "media.files", title: "Media", rows: content)]
    }

    /// Add Media…, its ⇧⌘I hint, and the item count at the trailing edge.
    ///
    /// The count is a plain label rather than an `OptionControl`: it changes
    /// only when the media list does, and the list is part of
    /// `structureSignature`, so the whole pane is rebuilt around it.
    private func actionRow() -> NSView {
        let add = OptionButtonControl(
            title: "Add Media…",
            action: { [weak self] in
                self?.inspector?.onCommand?(#selector(EditorViewController.addMediaFiles(_:)))
            },
            enabled: { true }, onEdit: {})
        add.toolTip = "Import files into this project (⇧⌘I)"

        let count = binding.snapshot.media.count
        let tally: String
        switch count {
        case 0: tally = "No media"
        case 1: tally = "1 item"
        default: tally = "\(count) items"
        }
        return MediaPane.bar(
            height: 38, border: .bottom,
            views: [
                add, MediaPane.caption("⇧⌘I"), MediaPane.spacer(), MediaPane.caption(tally),
            ])
    }

    /// The rows themselves, in their own stack so they sit 3 pt apart — the
    /// section's own row spacing is 6 and is shared with every other pane.
    private func listView() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        for media in binding.snapshot.media {
            let row = MediaRowView(media: media.id, pane: self)
            rows.append(row)
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    /// Consolidate belongs beside the list it acts on: this pane is where the
    /// "files are referenced, never copied" rule is visible (a row can be
    /// missing, and Relink… lives here), so it is where the one command that
    /// ends the rule should be reachable. The menu item is the same action;
    /// both validate through the editor.
    ///
    /// The design puts it in a footer with a line saying what it does, so the
    /// one command in the app that copies gigabytes is never a mystery
    /// button. The line is the SHORT one; the sentence is the tooltip on both
    /// halves of the row.
    private func footerRow() -> NSView {
        let binding = self.binding
        let consolidate = OptionButtonControl(
            title: "Consolidate…",
            action: { [weak self] in
                self?.inspector?.onCommand?(#selector(EditorViewController.consolidateMedia(_:)))
            },
            enabled: { !binding.snapshot.media.isEmpty }, onEdit: {})
        consolidate.toolTip = MediaPane.consolidateNote

        let note = MediaPane.caption(MediaPane.consolidateLine, font: DS.sans(11))
        note.toolTip = MediaPane.consolidateNote
        note.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        return MediaPane.bar(height: 40, border: .top, views: [consolidate, note])
    }

    /// The line the footer SHOWS — the mock's own wording.
    ///
    /// **Pitfall:** the sentence below measures 251.2 pt in `DS.sans(11)`,
    /// against the 192 pt left beside the 84 pt Consolidate… button in the
    /// 304 pt panel and 168 pt at the 280 pt minimum (all measured) — so it
    /// truncated at the default width and at every width below it, and only
    /// came out whole past about 363 pt, which nobody but a user who has
    /// dragged the panel nearly to its 440 pt maximum ever sees. A
    /// half-sentence is a poor description of the one command that copies
    /// gigabytes. This line is 146.7 pt and fits the whole range.
    private static let consolidateLine = "Copies sources into the package"

    /// The whole sentence, kept as the tooltip on the button and on the line
    /// so the short version is never the only thing said.
    private static let consolidateNote = "Copies every referenced file into this project's package."

    /// A machine-face caption — the ⇧⌘I hint, the item count, the footer's
    /// one-liner. `InspectorRowLabel` is the shared label; only its face
    /// changes, so the pane does not grow a label class of its own.
    private static func caption(_ text: String, font: NSFont = DS.mono(10)) -> InspectorRowLabel {
        let label = InspectorRowLabel(text)
        label.font = font
        label.textColor = DS.textFaint
        return label
    }

    /// The stretchy gap that pushes a bar's trailing cluster out — the same
    /// low-hugging filler `inspectorRow` uses.
    private static func spacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        view.setContentCompressionResistancePriority(
            NSLayoutConstraint.Priority(1), for: .horizontal)
        return view
    }

    /// One of the pane's two chrome bands, drawn EDGE TO EDGE.
    ///
    /// **Pitfall:** a `BarView` fills `DS.chromeBackground`, which is exactly
    /// what `InspectorViewController` paints the panel with — so the band
    /// itself is invisible and its 1 pt hairline is the whole of it. And a
    /// section's rows are inset by `InspectorMetrics.inset`, so that hairline
    /// stopped 10 pt short at each end and read as a floating stub rather than
    /// a rule; the 38 pt action row and the 40 pt footer were structurally
    /// there and visually absent.
    ///
    /// The fix keeps `BarView` and overhangs the inset instead: the bar is a
    /// subview of the section row pinned 10 pt PAST each side, and the content
    /// stack takes those 10 pt back as padding, so the rule spans the panel
    /// while the controls stay on the panel's gutter — the mock's own
    /// arrangement (a band with `padding: 0 10px`). The alternative was to
    /// inset the section's rows less, and the section shell is shared with
    /// every other pane, so it is not this one's to change.
    ///
    /// The overhang is legal because nothing between the row and the pane
    /// clips to its bounds — measured by rendering the same hierarchy
    /// offscreen (layer-backed root → scroll view → pane stack → section
    /// stack → row), where the bar paints the full panel width.
    private static func bar(height: CGFloat, border: BarView.Border, views: [NSView]) -> NSView {
        let row = NSView()
        let bar = BarView(border: border)
        bar.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(bar)
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)
        let inset = InspectorMetrics.inset
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: height),
            bar.topAnchor.constraint(equalTo: row.topAnchor),
            bar.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            bar.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: -inset),
            bar.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: inset),
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -inset),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        return row
    }

    /// Thumbnails and waveforms land after the import returns
    /// (`MediaImporter` posts repeatedly as they arrive), so this only marks
    /// the rows dirty — never a rebuild.
    @objc private func cacheChanged(_ note: Notification) {
        for row in rows { row.invalidateThumbnail() }
    }

    // MARK: - Finder drops

    private func droppedURLs(_ sender: any NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options)
        return (urls as? [URL]) ?? []
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        droppedURLs(sender).isEmpty ? [] : .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        droppedURLs(sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = droppedURLs(sender)
        guard !urls.isEmpty else { return false }
        inspector?.onImportFiles?(urls)
        return true
    }

    // MARK: - Row commands

    /// Where a dragged row landed. Returns false when the drop is refused, so
    /// the drag springs back rather than silently doing nothing.
    func drop(_ media: UInt32, on destination: NSView, target: MediaDropTarget) -> Bool {
        // A drag started in ANOTHER document's panel must not edit this one:
        // the session carries the source row, and the two windows differ.
        guard destination.window === window, window != nil else { return false }
        guard binding.snapshot.media(media) != nil else { return false }
        let fps = binding.canvas.fps
        switch target {
        case .track(let track, let at, let mode):
            let when = ReelTime.snapToFrame(max(at, 0), fps: fps)
            switch mode {
            case .add:
                binding.apply("Add Clip", [.addClip(track: track, media: media, at: when)])
            case .insert:
                binding.apply("Insert", [.insertClip(track: track, media: media, at: when)])
            case .overwrite:
                binding.apply(
                    "Overwrite", [.overwriteClip(track: track, media: media, at: when)])
            }
        case .canvas:
            let at = ReelTime.snapToFrame(max(binding.playhead, 0), fps: fps)
            let index = binding.snapshot.tracks.count
            // `add_track` returns a project, not an id (§11's one entry
            // point), so the id is learned from a PURE trial application
            // before the real edit runs.
            let existing = Set(binding.snapshot.tracks.map { $0.id })
            let probed = inspector?.onProbe?([.addTrack(index: index)])
            guard let track = probed?.tracks.first(where: { !existing.contains($0.id) })?.id else {
                guard let top = binding.snapshot.tracks.last?.id else { return false }
                binding.apply("Add Clip", [.addClip(track: top, media: media, at: at)])
                return true
            }
            binding.apply(
                "Add Clip",
                [.addTrack(index: index), .addClip(track: track, media: media, at: at)])
        }
        return true
    }

    /// A row was clicked: it becomes the document's selected media, which is
    /// what Edit ▸ Insert / Overwrite at Playhead act on. View state, so it
    /// neither dirties the document nor registers an undo step.
    func select(_ media: UInt32) {
        guard let document = binding.document, document.selectedMedia != media else { return }
        document.selectedMedia = media
        // Only the rows draw the selection, and the Edit menu asks for it
        // when it validates, so a redraw is the whole of the update.
        rows.forEach { $0.needsDisplay = true }
    }

    /// The row menu's Insert / Overwrite at Playhead. The same two ops the
    /// Edit menu runs, on the row that was right-clicked.
    func place(_ media: UInt32, insert: Bool) {
        select(media)
        guard binding.snapshot.media(media) != nil,
              let track = binding.document?.targetTrack
        else {
            NSSound.beep()
            return
        }
        let at = ReelTime.snapToFrame(max(binding.playhead, 0), fps: binding.canvas.fps)
        binding.apply(
            insert ? "Insert" : "Overwrite",
            [
                insert
                    ? .insertClip(track: track, media: media, at: at)
                    : .overwriteClip(track: track, media: media, at: at)
            ])
    }

    /// The row menu's Reveal in Finder.
    func reveal(_ media: UInt32) {
        guard let entry = binding.snapshot.media(media), let url = mediaURL(for: entry) else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Relink… — the offer a project whose media has moved opens with (§5.6).
    func relink(_ media: UInt32) {
        guard let entry = binding.snapshot.media(media), let window = window else {
            NSSound.beep()
            return
        }
        let binding = self.binding
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose the file for “\(entry.name)”."
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            // A sheet's completion is not an AppKit event: the grouped entry
            // point is mandatory here (app/CLAUDE.md's undo pitfall).
            binding.applyGrouped(
                "Relink Media",
                [
                    .relinkMedia(
                        media: media, path: url.path, bookmark: bookmarkString(for: url))
                ])
        }
    }

    /// Remove — refused while the media is in use, with the "and its clips"
    /// offer §4.3 asks for.
    func remove(_ media: UInt32) {
        guard let entry = binding.snapshot.media(media) else {
            NSSound.beep()
            return
        }
        let users = binding.snapshot.clips.filter { $0.source.mediaID == media }
        guard !users.isEmpty else {
            binding.apply("Remove Media", [.removeMedia(media: media)])
            return
        }
        guard let window = window else {
            NSSound.beep()
            return
        }
        let binding = self.binding
        let alert = NSAlert()
        alert.messageText = "Remove “\(entry.name)”?"
        alert.informativeText =
            users.count == 1
            ? "It is used by 1 clip, which will be removed with it."
            : "It is used by \(users.count) clips, which will be removed with it."
        alert.addButton(withTitle: "Remove and Delete Clips")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            binding.applyGrouped(
                "Remove Media", [.removeMedia(media: media, withClips: true)])
        }
    }
}
