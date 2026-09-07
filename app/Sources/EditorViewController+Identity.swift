import AppKit

/// Clip identity (spec §5.2, format version 3): Clip ▸ Rename… (⇧⌘R), the
/// Clip ▸ Label ▸ submenu, and the Track ▸ Solo item's validation — the menu
/// halves of what the timeline does in place (`TimelineView+Rename.swift`,
/// the header column's S) and what the Clip tab's header field does
/// (`ClipSelectionHeaderView` in `ClipPane.swift`).
///
/// Solo's BODY is `toggleTrack(.solo)` in `EditorViewController+Timeline.swift`,
/// beside its three siblings; only the checkmark lives here, because
/// `validateTimelineAction` takes no item to put one on. Edit ▸ Paste
/// Attributes (⌥⌘V) is in `EditorViewController+Clipboard.swift`, beside the
/// pasteboard it reads.
extension EditorViewController {

    // MARK: - Rename

    /// ⇧⌘R. The timeline opens its inline field over the first selected clip
    /// — no dialog, so the name is typed where it will be read. The
    /// timeline's selection is the document's (`refreshTimeline` pushes it),
    /// so asking the view is asking the model.
    func renameClipCommand() {
        guard let document = document, !document.selection.isEmpty, let timeline = timeline
        else {
            NSSound.beep()
            return
        }
        timeline.renameSelectedClip()
    }

    // MARK: - Label

    /// Clip ▸ Label ▸ — the sender's tag indexes `ClipLabel.allCases` and −1
    /// is None, the `setTransitionKindCommand` idiom. One `set_clip` over the
    /// whole selection, so labelling three clips is one undo step; a colour
    /// every selected clip already carries is the core's refusal, and beeps.
    func setClipLabelCommand(_ sender: Any?) {
        guard let document = document, let tag = (sender as? NSMenuItem)?.tag,
              !document.selection.isEmpty
        else {
            NSSound.beep()
            return
        }
        let labels = ClipLabel.allCases
        guard tag < 0 || labels.indices.contains(tag) else {
            NSSound.beep()
            return
        }
        let name: String? = tag < 0 ? nil : labels[tag].rawValue
        document.applyEdit(
            "Label Clip",
            .setClip(clips: Array(document.selection), patch: ClipPatch(label: .some(name))))
    }

    /// The label the selection agrees on: `.some(name)` when every selected
    /// clip carries that one, `.some(nil)` when none carries any, and nil
    /// when they disagree — so the submenu's checkmark can be on Blue, on
    /// None, or on nothing, and never on a colour only some of them have.
    /// Compared lower-cased, as `ClipLabel.color(named:)` reads a name.
    private var sharedClipLabel: String?? {
        let labels = selectedClips.map { clip -> String? in
            guard let label = clip.label, !label.isEmpty else { return nil }
            return label.lowercased()
        }
        guard let first = labels.first, labels.allSatisfy({ $0 == first }) else { return nil }
        return .some(first)
    }

    // MARK: - Validation

    /// The half of `validateUserInterfaceItem` this file owns. nil means "not
    /// mine" and leaves the other answers alone.
    func validateIdentityAction(
        _ action: Selector, item: any NSValidatedUserInterfaceItem
    ) -> Bool? {
        guard let document = document else { return false }
        switch action {
        case #selector(renameClip(_:)):
            return !document.selection.isEmpty
        case #selector(setClipLabel(_:)):
            if let menuItem = item as? NSMenuItem {
                let labels = ClipLabel.allCases
                let tagged: String? =
                    labels.indices.contains(menuItem.tag) ? labels[menuItem.tag].rawValue : nil
                menuItem.state = sharedClipLabel == .some(tagged) ? .on : .off
            }
            return !document.selection.isEmpty
        case #selector(toggleTrackSolo(_:)):
            // A checkmark, unlike its three siblings: solo is a mixing state
            // the ear cannot always confirm — a soloed track with nothing on
            // it still silences the rest — so the menu says which it is.
            let track = currentTrack
            (item as? NSMenuItem)?.state = track?.solo == true ? .on : .off
            return track != nil
        default:
            return nil
        }
    }
}
