import AppKit

/// The track context menu: a right-click (or ⌃-click) on a track's header or
/// on the empty part of its lane. It carries the header's four toggles —
/// each with a checkmark, because a menu opened on ONE track can say that
/// track's state where the Track menu, acting on `currentTrack`, cannot —
/// and Remove Track, which is the only way to delete an EMPTY track that is
/// not the front-most one without selecting a clip on it first (and an empty
/// track has none to select).
///
/// A right-click on a clip, the ruler or the corner gets no menu: those hits
/// answer nil, which is what they answered before this file.
///
/// The toggles are the header buttons' own edits (`toggle(_:on:)`, which
/// `TimelineView.toggleHeader` also calls); Remove Track goes up through
/// `onRemoveTrack` to `EditorViewController.removeTrackCommand`, because a
/// track that still holds clips asks first and the alert is the
/// controller's. Every item names its track by id in `representedObject`
/// rather than by row, so a menu is never read against a row that moved.
extension TimelineView {
    /// The menu for `hit`, or nil when the hit is not a track's header or
    /// empty lane.
    func trackMenu(for hit: TimelineHit) -> NSMenu? {
        let row: Int
        switch hit {
        case .header(let r), .headerButton(let r, _), .lane(let r, _): row = r
        default: return nil
        }
        guard let track = track(atRow: row) else { return nil }

        let menu = NSMenu(title: track.name)
        // Enabled state is set per item below; autoenabling would ask the
        // responder chain, which knows nothing about the clicked track.
        menu.autoenablesItems = false
        func add(_ title: String, _ action: Selector, on: Bool) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: track.id)
            item.state = on ? .on : .off
            menu.addItem(item)
        }
        add("Hide Video", #selector(trackMenuToggleHidden(_:)), on: track.hidden)
        add("Mute Audio", #selector(trackMenuToggleMuted(_:)), on: track.muted)
        add("Lock Track", #selector(trackMenuToggleLocked(_:)), on: track.locked)
        add("Solo", #selector(trackMenuToggleSolo(_:)), on: track.solo)
        menu.addItem(.separator())
        add("Remove Track", #selector(trackMenuRemove(_:)), on: false)
        // The core refuses to remove the last track; say so before the click.
        menu.items.last?.isEnabled = snapshot.tracks.count > 1
        return menu
    }

    /// The four header toggles as edits — one `set_track` flipping one flag.
    func toggle(_ button: TimelineHeaderButton, on track: TrackSnapshot) {
        switch button {
        case .hidden:
            onEdit?("Hide Track", [.setTrack(track: track.id, hidden: !track.hidden)])
        case .muted:
            onEdit?("Mute Track", [.setTrack(track: track.id, muted: !track.muted)])
        case .locked:
            onEdit?("Lock Track", [.setTrack(track: track.id, locked: !track.locked)])
        case .solo:
            onEdit?("Solo Track", [.setTrack(track: track.id, solo: !track.solo)])
        }
    }

    private func menuTrack(_ sender: Any?) -> TrackSnapshot? {
        guard let id = ((sender as? NSMenuItem)?.representedObject as? NSNumber)?.uint32Value
        else { return nil }
        return snapshot.track(id)
    }

    private func toggleFromMenu(_ button: TimelineHeaderButton, _ sender: Any?) {
        guard let track = menuTrack(sender) else {
            NSSound.beep()
            return
        }
        toggle(button, on: track)
    }

    @objc func trackMenuToggleHidden(_ sender: Any?) { toggleFromMenu(.hidden, sender) }
    @objc func trackMenuToggleMuted(_ sender: Any?) { toggleFromMenu(.muted, sender) }
    @objc func trackMenuToggleLocked(_ sender: Any?) { toggleFromMenu(.locked, sender) }
    @objc func trackMenuToggleSolo(_ sender: Any?) { toggleFromMenu(.solo, sender) }

    @objc func trackMenuRemove(_ sender: Any?) {
        guard let track = menuTrack(sender) else {
            NSSound.beep()
            return
        }
        onRemoveTrack?(track.id)
    }
}
