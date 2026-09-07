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

// MARK: - Rows

/// One file in the list: thumbnail, name, the meta line, and the audio and
/// missing badges. Drawn rather than composed from controls — a row has no
/// editable field, and drawing keeps a list of dozens cheap.
///
/// The redesign's row is 52 pt with a 34 × 38 thumbnail (handoff README,
/// Part 2 §5). The old one was 56 pt around a 72-wide tile, which read as a
/// strip of filmstrip frames rather than as a list; the narrow portrait well
/// makes the NAME the thing you scan down.
final class MediaRowView: NSView, NSDraggingSource {
    static let height: CGFloat = 52

    private static let thumbSize = NSSize(width: 34, height: 38)
    private static let padding: CGFloat = 8
    /// Thumbnail to text, per the design's row.
    private static let gap: CGFloat = 9

    private let media: UInt32
    private weak var pane: MediaPane?
    private var thumbnail: CGImage?
    private var triedThumbnail = false
    private var mouseDownAt: CGPoint?
    private var hovered = false

    /// Whether this row is the document's selected media. Read rather than
    /// stored, because the pane is rebuilt whole whenever the media list
    /// changes and per-row state would not survive it.
    private var selected: Bool { pane?.binding.document?.selectedMedia == media }

    init(media: UInt32, pane: MediaPane) {
        self.media = media
        self.pane = pane
        super.init(frame: .zero)
        wantsLayer = true
        // The row is a drag source (§4.3) and nothing about it says so. The
        // list has no room for a line that does, so the row says it itself.
        toolTip =
            "Drag to a timeline track, or onto the canvas. Hold ⌥ to insert, ⇧⌥ to overwrite."
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MediaRowView does not support NSCoder")
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.height)
    }

    private var entry: MediaSnapshot? { pane?.binding.snapshot.media(media) }

    func invalidateThumbnail() {
        triedThumbnail = false
        thumbnail = nil
        needsDisplay = true
    }

    /// The cached first-second thumbnail, or a decoded still for an image
    /// file. Loaded once per row: `MediaImporter` posts when a cache lands and
    /// `invalidateThumbnail()` asks for it again.
    private func loadThumbnailIfNeeded() {
        guard !triedThumbnail else { return }
        triedThumbnail = true
        guard let pane = pane, let entry = entry else { return }
        if let cache = pane.binding.document?.cacheDirectory,
           let image = MediaImporter.loadThumbnail(for: media, index: 0, in: cache)
        {
            thumbnail = image
            return
        }
        guard entry.kind == .image, let url = mediaURL(for: entry) else { return }
        thumbnail = MediaImporter.decodeImage(url, maxPixelSize: 256)
    }

    // MARK: Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // ONLY this view's own areas. `toolTip` is implemented as a tracking
        // area owned by `NSToolTipManager`, and it is in `trackingAreas` like
        // any other: the usual `trackingAreas.forEach(removeTrackingArea)`
        // deletes it on the first layout pass — which in an autolayout stack
        // inside a scroll view is immediately — and nothing ever puts it back,
        // so the row's one statement that it is a drag source never appears.
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        // `.inVisibleRect` keeps the area right as the list scrolls under the
        // pointer; the rect argument is then ignored.
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let entry = entry else { return }
        loadThumbnailIfNeeded()
        let missing = mediaURL(for: entry) == nil

        // A row is an object now, not a band with a rule under it: one
        // hairline box on the list-row radius, and the hover fill inside the
        // same shape so the two never disagree by half a pixel.
        let box = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: DS.listRowRadius, yRadius: DS.listRowRadius)
        if selected {
            DS.accent.withAlphaComponent(0.14).setFill()
            box.fill()
        } else if hovered {
            DS.hoverFill.setFill()
            box.fill()
        }
        (selected ? DS.accent : DS.border).setStroke()
        box.stroke()

        let thumb = NSRect(
            x: Self.padding, y: ((bounds.height - Self.thumbSize.height) / 2).rounded(),
            width: Self.thumbSize.width, height: Self.thumbSize.height)
        let well = NSBezierPath(
            roundedRect: thumb, xRadius: DS.controlRadius, yRadius: DS.controlRadius)
        NSColor.controlBackgroundColor.setFill()
        well.fill()
        if let image = thumbnail {
            // Aspect FILL, clipped to the well: the well is portrait and most
            // footage is not, so fitting would leave a 34 × 19 stamp floating
            // in a box twice its height.
            NSGraphicsContext.current?.saveGraphicsState()
            well.addClip()
            let scale = max(
                thumb.width / CGFloat(image.width), thumb.height / CGFloat(image.height))
            let size = CGSize(
                width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            TimelineDraw.image(
                image,
                in: CGRect(
                    x: thumb.midX - size.width / 2, y: thumb.midY - size.height / 2,
                    width: size.width, height: size.height))
            NSGraphicsContext.current?.restoreGraphicsState()
        } else {
            TimelineDraw.symbol(
                entry.kind == .audio ? "waveform" : "photo", fallback: "▦", in: thumb,
                tint: DS.textFaint)
        }
        DS.border.setStroke()
        NSBezierPath(
            roundedRect: thumb.insetBy(dx: 0.5, dy: 0.5), xRadius: DS.controlRadius,
            yRadius: DS.controlRadius
        ).stroke()

        // The badges moved to the trailing edge: a 52 pt row has no third
        // line to hang them under, and "missing" is the one thing in this
        // list that must never be the part that got cropped.
        var trailing = bounds.maxX - Self.padding
        if missing {
            trailing = drawBadge("missing", endingAt: trailing, color: DS.coral)
        }
        if entry.hasAudio {
            trailing = drawBadge("audio", endingAt: trailing, color: DS.clipAudio)
        }

        let textX = thumb.maxX + Self.gap
        let width = max(trailing - textX, 10)
        // Truncating, not clipping: the meta line is longer than the space a
        // row with badges leaves ("00:00:21:00 · 1080×1920 · 25 fps" against
        // about 150 pt), and `TimelineDraw.label` would cut it mid-glyph — an
        // ellipsis at least says that something was left out.
        TimelineDraw.truncated(
            entry.name, in: CGRect(x: textX, y: 11, width: width, height: 16),
            font: DS.sans(12), color: DS.textStrong)
        TimelineDraw.truncated(
            metaLine(entry), in: CGRect(x: textX, y: 28, width: width, height: 13),
            font: DS.mono(10), color: DS.textMuted)
    }

    private func metaLine(_ entry: MediaSnapshot) -> String {
        var parts: [String] = []
        if entry.duration > 0 {
            parts.append(
                ReelTime.format(entry.duration, fps: entry.fps, frames: true))
        }
        if entry.width > 0, entry.height > 0 {
            parts.append("\(entry.width)×\(entry.height)")
        }
        if entry.hasVideo, entry.fps.double > 0 {
            parts.append("\(entry.fps.displayName) fps")
        }
        if parts.isEmpty { parts.append(entry.kind.displayName) }
        return parts.joined(separator: " · ")
    }

    /// One trailing badge, laid out right to left; returns the x the NEXT one
    /// should end at, so a row with both stacks them inward.
    @discardableResult
    private func drawBadge(_ text: String, endingAt x: CGFloat, color: NSColor) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: DS.mono(9), .foregroundColor: color,
        ]
        let size = text.size(withAttributes: attributes)
        let width = size.width + 10
        let rect = NSRect(x: x - width, y: bounds.midY - 6.5, width: width, height: 13)
        let path = NSBezierPath(
            roundedRect: rect, xRadius: DS.controlRadius, yRadius: DS.controlRadius)
        color.withAlphaComponent(0.16).setFill()
        path.fill()
        text.draw(
            at: NSPoint(x: rect.minX + 5, y: rect.midY - size.height / 2),
            withAttributes: attributes)
        return rect.minX - 5
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        mouseDownAt = convert(event.locationInWindow, from: nil)
        pane?.select(media)
    }

    /// A drag past the slop starts the row's drag session (§4.3: to a track,
    /// or onto the canvas).
    override func mouseDragged(with event: NSEvent) {
        guard let origin = mouseDownAt, let pane = pane else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard abs(point.x - origin.x) > 3 || abs(point.y - origin.y) > 3 else { return }
        mouseDownAt = nil

        let item = NSPasteboardItem()
        item.setString(String(media), forType: .reelcutMedia)
        let dragged = NSDraggingItem(pasteboardWriter: item)
        dragged.setDraggingFrame(bounds, contents: dragImage())
        // The session carries the id and the pane, so the destination views
        // stay ignorant of both the document and this row.
        MediaDragSession.current = MediaDragSession(
            media: media, source: self,
            drop: { [weak pane, media] destination, target in
                pane?.drop(media, on: destination, target: target) ?? false
            })
        beginDraggingSession(with: [dragged], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownAt = nil
    }

    private func dragImage() -> NSImage {
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        DS.chromeBackground.withAlphaComponent(0.9).setFill()
        NSBezierPath(
            roundedRect: NSRect(origin: .zero, size: bounds.size),
            xRadius: DS.listRowRadius, yRadius: DS.listRowRadius
        ).fill()
        if let entry = entry {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: DS.sans(12), .foregroundColor: DS.textStrong,
            ]
            entry.name.draw(at: NSPoint(x: 8, y: bounds.height / 2 - 8), withAttributes: attributes)
        }
        image.unlockFocus()
        return image
    }

    // MARK: Dragging source

    func draggingSession(
        _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(
        _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
    ) {
        MediaDragSession.current = nil
    }

    // MARK: Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        // Two groups: what to do with the file on the timeline, then what to
        // do with the file. The loop shape cannot express a separator, so the
        // groups are two loops with one between them.
        for (title, selector) in [
            ("Insert at Playhead", #selector(insertMedia(_:))),
            ("Overwrite at Playhead", #selector(overwriteMedia(_:))),
        ] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for (title, selector) in [
            ("Reveal in Finder", #selector(revealMedia(_:))),
            ("Relink…", #selector(relinkMedia(_:))),
            ("Remove", #selector(removeMedia(_:))),
        ] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    /// The row knows its own id, so these two place THIS file whatever the
    /// list's selection is — and they select it on the way, so the Edit menu
    /// and the row agree afterwards.
    @objc private func insertMedia(_ sender: Any?) { pane?.place(media, insert: true) }
    @objc private func overwriteMedia(_ sender: Any?) { pane?.place(media, insert: false) }

    @objc private func revealMedia(_ sender: Any?) { pane?.reveal(media) }
    @objc private func relinkMedia(_ sender: Any?) { pane?.relink(media) }
    @objc private func removeMedia(_ sender: Any?) { pane?.remove(media) }
}

// MARK: - Dragging a row out of the panel

extension NSPasteboard.PasteboardType {
    /// The private type a media row drags with. Deliberately NOT `.fileURL`:
    /// the editor's root view accepts file URLs and would open the file as a
    /// new document, which is not what dragging a row inside a project means.
    static let reelcutMedia = NSPasteboard.PasteboardType("com.kgalligan.reelcut.media")
}

/// What a drop onto a lane does about the room the clip needs (spec §6).
///
/// The modifiers are the timeline's own, read at the moment of the drop:
/// none places the clip and lets the overlap rule refuse it, ⌥ makes room
/// for it and ⇧⌥ takes the room it needs. ⌥ alone is free here — the
/// duplicate-drag it means elsewhere is a gesture on a CLIP, and this drag
/// starts in the media list.
enum MediaDropMode: Equatable {
    case add
    case insert
    case overwrite

    /// The mode the modifiers currently held describe.
    static func current(_ flags: NSEvent.ModifierFlags) -> MediaDropMode {
        guard flags.contains(.option) else { return .add }
        return flags.contains(.shift) ? .overwrite : .insert
    }
}

/// Where a dragged media row landed.
enum MediaDropTarget: Equatable {
    /// A timeline track, at the time under the cursor, and what to do about
    /// what is already there.
    case track(UInt32, Ticks, MediaDropMode)
    /// The preview canvas: a new top track at the playhead (§4.3).
    case canvas
}

/// The media drag in flight. AppKit runs one drag at a time, so one slot is
/// enough — and it is what lets the destination views stay ignorant of the
/// document: they report WHERE the row landed and the pane that started the
/// drag performs the edit.
final class MediaDragSession {
    static var current: MediaDragSession?

    let media: UInt32
    /// The row being dragged; the pane checks its window against the
    /// destination's, so a drag between two open projects cannot edit the
    /// wrong one.
    weak var source: NSView?
    let drop: (NSView, MediaDropTarget) -> Bool

    init(media: UInt32, source: NSView, drop: @escaping (NSView, MediaDropTarget) -> Bool) {
        self.media = media
        self.source = source
        self.drop = drop
    }
}

// MARK: - Drop targets

/// The timeline as a drop target for a media row (§4.3: "drops at the
/// cursor"). Registered by `EditorViewController+Inspector.installInspector`;
/// the arithmetic is `TimelineLayout`'s, as it is for every other point in
/// that view.
extension TimelineView {
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        MediaDragSession.current == nil ? [] : .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        MediaDragSession.current == nil ? [] : .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let session = MediaDragSession.current else { return false }
        let point = content.convert(sender.draggingLocation, from: nil)
        guard let row = layout.row(atY: point.y), let track = track(atRow: row)
        else { return false }
        // `NSDraggingInfo` carries no modifiers, so the flags are read live —
        // which is right anyway: what matters is what is held at the DROP.
        let mode = MediaDropMode.current(
            NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask))
        return session.drop(
            self, .track(track.id, max(layout.time(atX: point.x), 0), mode))
    }
}

/// The preview canvas as a drop target: a media row dropped here appends on a
/// new top track at the playhead (§4.3).
extension PreviewCanvasView {
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        MediaDragSession.current == nil ? [] : .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        MediaDragSession.current == nil ? [] : .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let session = MediaDragSession.current else { return false }
        return session.drop(self, .canvas)
    }
}
