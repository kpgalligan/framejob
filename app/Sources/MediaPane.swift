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

    override func makeSections() -> [InspectorSection] {
        let binding = self.binding
        rows = []
        var content: [NSView] = []

        let add = OptionButtonControl(
            title: "Add Media…",
            action: { [weak self] in
                self?.inspector?.onCommand?(#selector(EditorViewController.addMediaFiles(_:)))
            },
            enabled: { true }, onEdit: {})
        add.toolTip = "Import files into this project (⇧⌘I)"
        content.append(inspectorButtonRow([add, InspectorRowLabel("⇧⌘I")]))

        for media in binding.snapshot.media {
            let row = MediaRowView(media: media.id, pane: self)
            rows.append(row)
            content.append(row)
        }
        if binding.snapshot.media.isEmpty {
            content.append(
                inspectorRow(nil, [InspectorRowLabel("Drop files here, or use Add Media….")]))
        } else {
            content.append(
                inspectorRow(
                    nil, [InspectorRowLabel("Drag a row to a track, or onto the canvas.")]))
        }
        return [InspectorSection(id: "media.files", title: "Media", rows: content)]
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
        case .track(let track, let at):
            binding.apply(
                "Add Clip",
                [
                    .addClip(
                        track: track, media: media,
                        at: ReelTime.snapToFrame(max(at, 0), fps: fps))
                ])
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
final class MediaRowView: NSView, NSDraggingSource {
    static let height: CGFloat = 56

    private let media: UInt32
    private weak var pane: MediaPane?
    private var thumbnail: CGImage?
    private var triedThumbnail = false
    private var mouseDownAt: CGPoint?

    init(media: UInt32, pane: MediaPane) {
        self.media = media
        self.pane = pane
        super.init(frame: .zero)
        wantsLayer = true
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

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let entry = entry else { return }
        loadThumbnailIfNeeded()
        let missing = mediaURL(for: entry) == nil

        let thumb = NSRect(x: 0, y: 6, width: 72, height: Self.height - 16)
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: thumb, xRadius: 3, yRadius: 3).fill()
        if let image = thumbnail {
            let scale = min(
                thumb.width / CGFloat(image.width), thumb.height / CGFloat(image.height))
            let size = CGSize(
                width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            TimelineDraw.image(
                image,
                in: CGRect(
                    x: thumb.midX - size.width / 2, y: thumb.midY - size.height / 2,
                    width: size.width, height: size.height))
        } else {
            TimelineDraw.symbol(
                entry.kind == .audio ? "waveform" : "photo", fallback: "▦", in: thumb,
                tint: DS.textFaint)
        }
        DS.border.setStroke()
        NSBezierPath(roundedRect: thumb.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3).stroke()

        let textX = thumb.maxX + 8
        let width = max(bounds.width - textX, 10)
        TimelineDraw.label(
            entry.name, in: CGRect(x: textX, y: 8, width: width, height: 15),
            font: DS.sans(12), color: DS.textStrong)
        TimelineDraw.label(
            metaLine(entry), in: CGRect(x: textX, y: 24, width: width, height: 13),
            font: DS.mono(10), color: DS.textMuted)

        var badgeX = textX
        if entry.hasAudio {
            badgeX = drawBadge("audio", at: badgeX, color: DS.clipAudio)
        }
        if missing {
            badgeX = drawBadge("missing", at: badgeX, color: DS.coral)
        }
        _ = badgeX

        DS.border.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
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

    @discardableResult
    private func drawBadge(_ text: String, at x: CGFloat, color: NSColor) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: DS.mono(9), .foregroundColor: color,
        ]
        let size = text.size(withAttributes: attributes)
        let rect = NSRect(x: x, y: 39, width: size.width + 10, height: 13)
        let path = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        color.withAlphaComponent(0.16).setFill()
        path.fill()
        text.draw(
            at: NSPoint(x: rect.minX + 5, y: rect.midY - size.height / 2),
            withAttributes: attributes)
        return rect.maxX + 5
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        mouseDownAt = convert(event.locationInWindow, from: nil)
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
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: bounds.size), xRadius: 4, yRadius: 4)
            .fill()
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

/// Where a dragged media row landed.
enum MediaDropTarget: Equatable {
    /// A timeline track, at the time under the cursor.
    case track(UInt32, Ticks)
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
        return session.drop(self, .track(track.id, max(layout.time(atX: point.x), 0)))
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
