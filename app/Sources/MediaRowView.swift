import AppKit

/// One file in the list: thumbnail, name, the meta line, and the audio and
/// missing badges. Drawn rather than composed from controls — a row has no
/// editable field, and drawing keeps a list of dozens cheap.
///
/// The redesign's row is 52 pt with a 34 × 38 thumbnail (handoff README,
/// Part 2 §5). The old one was 56 pt around a 72-wide tile, which read as a
/// strip of filmstrip frames rather than as a list; the narrow portrait well
/// makes the NAME the thing you scan down.
///
/// **Why this is a file of its own.** `MediaPane.swift` stood at 822 lines
/// against app/CLAUDE.md's ~600 cap, and road map 2's phase 8 came to give
/// the Media tab a search field, a sort popup, an "unused only" filter and a
/// Reveal in Timeline context item — so the pane had to give something up
/// before it took any of them on. That is the payment
/// `LayerRenderersText.swift` made in phase 6 and `ExporterSettings.swift`
/// and `ExportSheetOptions.swift` made in phase 7, and it is worth noting
/// that phase 8's four additions landed on BOTH sides of this cut: the three
/// controls are the list's and the context item is a row's, so each half got
/// the room it needed. The room was not ENOUGH — phase 6's warning arriving
/// again, that a cut's estimate is worth about two thirds of the truth — so
/// phase 8c cut a second time, and the row commands the pane keeps are
/// `MediaPaneCommands.swift` now.
///
/// **The cut falls below the DRAG rather than under the row's closing
/// brace**, which is the one decision in it. A row is a drag source (§4.3),
/// and everything that followed it in the old file is there to serve that
/// drag: the private pasteboard type it writes, the two enums that name
/// where it may land, the session that carries it in flight, and the two
/// destination views that report a landing back. Cutting under the class
/// would have left the source in one file and the vocabulary it drags with
/// in another — a seam through the middle of one sentence. What the pane
/// keeps of the drag is the one part a row cannot do: `drop(_:on:target:)`
/// performs the edit, as `select`, `place`, `reveal`, `relink` and `remove`
/// do for the row menu, and every one of those goes through `binding`, which
/// is the pane's business and never a row's. The pane keeps the LIST — its
/// one section, its bands, and the Finder drop onto the panel.
///
/// **Nothing widened**, and that is measured rather than assumed. A type
/// carries its own scope, so every `private` member below keeps the privacy
/// it had — where splitting a TYPE across files costs each crossing member
/// its own, the toll `ExporterLoudness.swift` records and the two
/// `extension ExportSheetController` files pay. The row already reached the
/// pane through internal members and the pane already reached the row
/// through two (`init(media:pane:)` and `invalidateThumbnail()`), so the
/// file boundary changed no declaration at all. It is
/// `ExportProgressSheetController.swift`'s free cut a second time.
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
        // **The menu enables its own rows.** AppKit's automatic validation
        // would ask this view for `validateMenuItem(_:)`, and every row but
        // one is unconditionally live, so turning it off costs nothing and
        // buys a guarantee: a contextual menu is built at the moment of the
        // click, which is the moment the answer is wanted, so the enablement
        // below cannot go stale and does not depend on AppKit choosing to ask.
        // `SilenceSheetController`'s popup records the same rule for a
        // different reason — an enabled state set under `autoenablesItems` is
        // put straight back.
        menu.autoenablesItems = false
        // Two groups: what to do with the file on the timeline, then what to
        // do with the file. The loop shape cannot express a separator, so the
        // groups are two loops with one between them.
        //
        // Reveal in Timeline is DISABLED where the file's only users are
        // inside a nest: a nested clip has no id a selection can hold
        // (`MediaUsage.swift`), so the item would select nothing and scroll
        // nowhere. That case is exactly the one the pane's old top-level-only
        // usage test could not see.
        for (title, selector) in [
            ("Insert at Playhead", #selector(insertMedia(_:))),
            ("Overwrite at Playhead", #selector(overwriteMedia(_:))),
            ("Reveal in Timeline", #selector(revealInTimeline(_:))),
        ] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            if selector == #selector(revealInTimeline(_:)) {
                item.isEnabled = pane?.canRevealInTimeline(media) ?? false
            }
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

    /// Select the clips that show this file, and scroll the first one into
    /// view. The pane does both — it is the half that can reach the document
    /// and the editor — and it switches the panel to the Clip tab on the way,
    /// which is the panel's own rule for any changed selection.
    @objc private func revealInTimeline(_ sender: Any?) { pane?.revealInTimeline(media) }

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
