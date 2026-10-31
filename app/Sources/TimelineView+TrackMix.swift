import AppKit

/// The track mix popover (spec §11 AU-105): a track's Volume and Pan,
/// anchored on its header's fifth switch. The switch, the context menu's
/// Volume and Pan… and Track ▸ Volume and Pan… (on the current track) all
/// open it through `showTrackMix(_:)`; `set_track {volume, pan}` is the MCP
/// mirror (`AgentServer+Tracks.swift`).
///
/// **One per timeline.** Opening it on another track closes the first. It
/// edits through the timeline's own `onLiveBegin`/`onLiveUpdate`/`onLiveEnd`
/// (a drag) and `onEdit` (a field commit or Reset), so its undo steps are the
/// header toggles' kind. It refreshes on its document's
/// `.projectDocumentDidChange`, a turn of the main queue later so the
/// timeline's snapshot has been pushed, and closes when its track is gone —
/// removed, undone away, or out of scope when a nest is entered or left.
extension TimelineView {
    /// The open popover per timeline, keyed by the view's identity: the view
    /// is frozen (wiring only), so the state lives here, dropped on close.
    private static var trackMixes: [ObjectIdentifier: TrackMixPopover] = [:]

    func showTrackMix(_ track: TrackSnapshot) {
        let key = ObjectIdentifier(self)
        Self.trackMixes[key]?.close()
        guard let index = snapshot.trackIndex(of: track.id) else {
            NSSound.beep()
            return
        }
        let row = layout.row(forTrackIndex: index)
        let height = layout.trackHeight(row: row)
        var anchor = TimelineHeaderView.buttonRect(4, height: height)
        anchor.origin.y += layout.rowTop(row) - TimelineLayout.rulerHeight
        let edits = TrackMixEdits(
            liveBegin: { [weak self] in self?.onLiveBegin?() },
            liveUpdate: { [weak self] ops in self?.onLiveUpdate?(ops) },
            liveEnd: { [weak self] name in self?.onLiveEnd?(name) },
            edit: { [weak self] name, ops in self?.onEdit?(name, ops) })
        let mix = TrackMixPopover(
            track: track, edits: edits, timeline: self,
            document: window?.windowController?.document as? ProjectDocument
        ) { gone in
            // Only its own entry: a popover closed for a newer one must not
            // drop the newer one.
            if Self.trackMixes[key] === gone { Self.trackMixes[key] = nil }
        }
        Self.trackMixes[key] = mix
        mix.show(relativeTo: anchor, of: headers)
    }
}

/// The popover and its observation, alive while it is shown.
final class TrackMixPopover: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let content: TrackMixViewController
    private weak var timeline: TimelineView?
    private var observer: NSObjectProtocol?
    private let closed: (TrackMixPopover) -> Void

    init(
        track: TrackSnapshot, edits: TrackMixEdits, timeline: TimelineView,
        document: ProjectDocument?, closed: @escaping (TrackMixPopover) -> Void
    ) {
        content = TrackMixViewController(track: track, edits: edits)
        self.timeline = timeline
        self.closed = closed
        super.init()
        popover.behavior = .transient
        popover.contentViewController = content
        popover.delegate = self
        observer = NotificationCenter.default.addObserver(
            forName: .projectDocumentDidChange, object: document, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    func show(relativeTo rect: NSRect, of view: NSView) {
        popover.show(relativeTo: rect, of: view, preferredEdge: .maxX)
    }

    func close() {
        popover.close()
    }

    private func refresh() {
        guard let timeline, let track = timeline.snapshot.track(content.track.id) else {
            close()
            return
        }
        content.update(track)
    }

    func popoverDidClose(_ notification: Notification) {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        closed(self)
    }
}
