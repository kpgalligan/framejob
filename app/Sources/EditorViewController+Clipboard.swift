import AppKit

/// Edit ▸ Cut / Copy / Paste / Paste Attributes (⌘X, ⌘C, ⌘V, ⌥⌘V) — the
/// four menu items `EditorViewController.swift` forwards here — and the
/// fifth, Edit ▸ Paste Graphic Properties, whose action is this file's own.
///
/// The clipboard is one pasteboard type and two ops that read it. Copy writes
/// the selection as the `paste` op's payload (the module doc of
/// `core/src/edit_paste.rs` is its schema) under `com.kgalligan.reelcut.clips`;
/// Paste hands that payload straight back to the core, which does all the
/// deciding — fresh ids, media matched by path, the overlap rule, the frame
/// grid — and Paste Attributes and Paste Graphic Properties hand the SAME
/// payload to `paste_attributes`, which reads only its earliest clip's
/// property groups. Nothing about a clip is interpreted on this side.
///
/// **Every reader and writer takes its pasteboard as a parameter**, the
/// general one by default, so a probe can drive Copy and both pastes over a
/// private pasteboard and never touch the owner's clipboard.
///
/// Two decisions worth stating, because neither is forced:
///
/// **The payload is built from the core's own project JSON, not from
/// `ProjectSnapshot`.** The snapshot is a LENIENT read view (its `init(from:)`
/// falls back rather than failing), so re-encoding one would quietly drop
/// whatever this build does not know about and round every field through
/// Swift's idea of the schema. Copying the raw JSON objects means a pasted
/// clip is the clip that was copied, down to the keys nobody has written yet.
///
/// **A payload clip's `track` is rewritten to a DEPTH from the front of the
/// stack** (0 = front-most), because a track id means nothing in another
/// document — and pasting between documents is the case the private
/// pasteboard type exists for. Depth is the only thing about the source's
/// track stack worth carrying: it is what makes a two-lane selection paste
/// back onto two lanes.
extension EditorViewController {
    /// The private pasteboard type the payload travels under. Private on
    /// purpose: a Reelcut clip is not a flavour of anything else, and a paste
    /// from another app is a beep, not a guess.
    static let clipsPasteboardType = NSPasteboard.PasteboardType("com.kgalligan.reelcut.clips")

    // MARK: - Copy

    /// ⌘C. Writes the selection to the pasteboard (the general one, unless a
    /// probe names its own), with a short human summary as the plain-text
    /// fallback — pasting into a text editor should say what was copied, not
    /// spill a project.
    ///
    /// Returns whether anything was written, so Cut can stop before it deletes
    /// something it failed to copy.
    @discardableResult
    func copySelection(to pasteboard: NSPasteboard = .general) -> Bool {
        guard let document = document, !document.selection.isEmpty,
              let payload = clipboardPayload(for: document),
              JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(
                withJSONObject: payload, options: [.sortedKeys])
        else {
            NSSound.beep()
            return false
        }
        // `declareTypes` clears the pasteboard and takes ownership in one
        // call, which is the documented pairing for `setData(_:forType:)`.
        pasteboard.declareTypes([Self.clipsPasteboardType, .string], owner: nil)
        pasteboard.setData(data, forType: Self.clipsPasteboardType)
        pasteboard.setString(clipboardSummary(for: document), forType: .string)
        return true
    }

    /// The `paste` payload for the current selection: the selected clips
    /// verbatim out of `project.json` with each clip's `track` rewritten to
    /// its depth from the front, plus the media rows those clips name.
    ///
    /// nil when the project JSON cannot be read or the selection resolved to
    /// no clips at all — both of which mean there is nothing to put on the
    /// pasteboard, and the caller beeps.
    private func clipboardPayload(for document: ProjectDocument) -> [String: Any]? {
        // The EDITED project (road map 2's phase 9). Inside a nest the
        // selected clips are the NEST's, and they are the top level of this
        // JSON — so a Copy in a nest copies what was picked, and the `track`
        // depths it rewrites are counted against the nest's own stack, which
        // is what the paste on the other side will be measured against.
        guard let data = document.editedProject.json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let clips = root["clips"] as? [[String: Any]]
        else { return nil }
        let snapshot = document.editedProject.snapshot
        let front = snapshot.tracks.count - 1
        let selection = document.selection

        var payloadClips: [[String: Any]] = []
        var wanted: Set<UInt32> = []
        for clip in clips {
            guard let id = (clip["id"] as? NSNumber)?.uint32Value, selection.contains(id),
                  let track = (clip["track"] as? NSNumber)?.uint32Value,
                  let index = snapshot.trackIndex(of: track)
            else { continue }
            var copied = clip
            copied["track"] = front - index
            payloadClips.append(copied)
            wanted.formUnion(Self.payloadMediaIDs(clip))
        }
        guard !payloadClips.isEmpty else { return nil }

        // Only the rows the copied clips SHOW or look through: a media entry
        // nothing points at would arrive in the other document as a
        // Media-tab row the user cannot account for.
        let media = (root["media"] as? [[String: Any]] ?? []).filter { entry in
            guard let id = (entry["id"] as? NSNumber)?.uint32Value else { return false }
            return wanted.contains(id)
        }
        return ["clips": payloadClips, "media": media]
    }

    /// The media ids one copied clip (its `project.json` object) names: its
    /// source's, its base look's and each action end's look's (spec §11 GR-8),
    /// in that order without repeats — the rows a paste into another project
    /// needs. An end may name a LUT that is gone; its row is simply not found.
    static func payloadMediaIDs(_ clip: [String: Any]) -> [UInt32] {
        func lookMedia(_ video: Any?) -> UInt32? {
            guard let video = video as? [String: Any], let look = video["look"] as? [String: Any]
            else { return nil }
            return (look["media"] as? NSNumber)?.uint32Value
        }
        var found: [UInt32?] = [
            ((clip["source"] as? [String: Any])?["media"] as? NSNumber)?.uint32Value,
            lookMedia(clip["video"]),
        ]
        for action in clip["actions"] as? [[String: Any]] ?? [] {
            found.append(lookMedia((action["end"] as? [String: Any])?["video"]))
        }
        var ids: [UInt32] = []
        for id in found.compactMap({ $0 }) where !ids.contains(id) { ids.append(id) }
        return ids
    }

    /// The plain-text fallback: what was copied and the span it covered, in
    /// the document's own timecode (`ReelTime.format`, as everywhere else).
    private func clipboardSummary(for document: ProjectDocument) -> String {
        let clips = selectedClips
        let canvas = document.editedProject.snapshot.canvas
        let frames = canvas.timecodeFrames
        let start = clips.first?.start ?? 0
        let end = clips.map { $0.end }.max() ?? start
        let count = clips.count == 1 ? "1 clip" : "\(clips.count) clips"
        return "Reelcut — \(count), "
            + ReelTime.format(start, fps: canvas.fps, frames: frames) + " to "
            + ReelTime.format(end, fps: canvas.fps, frames: frames)
    }

    // MARK: - Cut

    /// ⌘X. Copy, then exactly the edit ⌫ performs — ONE undo step, because
    /// the copy touches no model state and the delete is a single op.
    func cutSelection() {
        guard let document = document, !document.selection.isEmpty else {
            NSSound.beep()
            return
        }
        guard copySelection() else { return }
        document.applyEdit("Cut", .delete(clips: Array(document.selection)))
    }

    // MARK: - Paste

    /// ⌘V. The payload lands at the playhead and whatever appeared is
    /// selected, so the paste can be dragged or styled straight away.
    ///
    /// Placement is entirely the core's: `paste` puts a clip the overlap rule
    /// refuses on a new track in front rather than refusing the edit, so the
    /// only beeps here are an empty pasteboard and a payload the core reports
    /// as invalid (through `applyEdit`, which presents the message).
    func pasteClips() {
        guard let document = document, let payload = pasteboardPayload() else {
            NSSound.beep()
            return
        }
        let before = Set(document.editedProject.snapshot.clips.map { $0.id })
        document.applyEdit("Paste", .paste(at: document.playhead, payload: payload))

        // Comparing id sets rather than trusting ids we predicted: the core
        // mints them, and this stays correct if it ever mints them
        // differently (`EditorViewController+AddClips.swift` does the same).
        let added = document.editedProject.snapshot.clips.map { $0.id }
            .filter { !before.contains($0) }
        guard !added.isEmpty else { return }
        document.selection = Set(added)
        viewStateDidChange()
    }

    // MARK: - Paste Attributes

    /// ⌥⌘V. The payload's EARLIEST clip's LOOK — its video, audio, text and
    /// shape groups, the earliest by start, then the front-most track, then
    /// the lower id — onto every selected clip, leaving `groups` to the core's
    /// default (every group both sides have, spec §6). Nothing that makes the
    /// clip THIS clip travels: not its place, speed, actions, transition, name
    /// or label, and not a text clip's words or a shape's geometry.
    ///
    /// Whole selection, one op, one undo step. An IDENTITY — the payload's
    /// clip and the targets share no group, or the look is already theirs —
    /// is `applyEdit`'s beep, and an out-of-range payload is its error,
    /// presented. There is no group picker here: the default rule is what
    /// ⌥⌘V has always meant in a cutting room, and the agent's tool
    /// (`paste_attributes`) takes `groups` for anyone who needs the choice.
    func pasteAttributes(from pasteboard: NSPasteboard = .general) {
        guard let document = document, !document.selection.isEmpty,
              let payload = pasteboardPayload(on: pasteboard)
        else {
            NSSound.beep()
            return
        }
        document.applyEdit(
            "Paste Attributes",
            .pasteAttributes(clips: Array(document.selection), payload: payload))
    }

    // MARK: - Paste Graphic Properties

    /// Edit ▸ Paste Graphic Properties (spec §11 G-32), which has no key. A
    /// menu sends its `NSMenuItem`, so the app reads the general pasteboard;
    /// a probe sends this action a private pasteboard as its sender, which
    /// is how the line below is measured and not only typechecked.
    @objc func pasteGraphicProperties(_ sender: Any?) {
        pasteGraphicProps(from: sender as? NSPasteboard ?? .general)
    }

    /// The copied graphic's props — all of them, its words included — onto
    /// every selected clip drawn by the SAME graphic; each keeps its own
    /// size, in point and length. ONE op, and nothing about the payload is
    /// read here: `groups: ["graphic"]` names the group ⌥⌘V never carries,
    /// and `skipMissing` makes the core skip a selected clip that cannot take
    /// it rather than refuse the paste. So when the copied clip is not a
    /// graphic, or no selected clip is drawn by the same one, the answer is
    /// an identity — `applyEdit`'s beep — and copied props the core will not
    /// store, onto a clip that takes them, are its sentence in an alert.
    func pasteGraphicProps(from pasteboard: NSPasteboard = .general) {
        guard let document = document, !document.selection.isEmpty,
              let payload = pasteboardPayload(on: pasteboard)
        else {
            NSSound.beep()
            return
        }
        document.applyEdit(
            "Paste Graphic Properties",
            .pasteAttributes(
                clips: Array(document.selection), payload: payload,
                groups: ["graphic"], skipMissing: true))
    }

    /// The payload on the pasteboard, or nil when there is nothing of ours
    /// there to paste — an empty pasteboard, another app's content, or a
    /// payload with no clips in it.
    private func pasteboardPayload(on pasteboard: NSPasteboard = .general) -> [String: Any]? {
        guard let data = pasteboard.data(forType: Self.clipsPasteboardType),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let clips = payload["clips"] as? [Any], !clips.isEmpty
        else { return nil }
        return payload
    }

    /// Whether ⌘V has anything to do. Only the TYPE is inspected, not the
    /// bytes: this runs on every menu validation, and reading a pasteboard's
    /// available types is cheap where decoding its data is not.
    func canPasteClips(on pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.availableType(from: [Self.clipsPasteboardType]) != nil
    }

    // MARK: - Validation

    /// The half of `validateUserInterfaceItem` this file owns. nil means "not
    /// mine" and leaves the base file's answer alone.
    func validateClipboardAction(
        _ action: Selector, pasteboard: NSPasteboard = .general
    ) -> Bool? {
        guard let document = document else { return false }
        switch action {
        case #selector(cut(_:)), #selector(copy(_:)):
            return !document.selection.isEmpty
        case #selector(paste(_:)):
            return canPasteClips(on: pasteboard)
        case #selector(pasteAttributes(_:)):
            // Paste needs no selection (the clips land at the playhead);
            // Paste Attributes needs something to paste ONTO.
            return canPasteClips(on: pasteboard) && !document.selection.isEmpty
        case #selector(pasteGraphicProperties(_:)):
            // Something of ours to read and a graphic to paste onto. WHAT was
            // copied is not read here (the bytes, on every menu validation):
            // a copied clip that is not a graphic is the item's beep (G-32).
            return canPasteClips(on: pasteboard)
                && selectedClips.contains { $0.source == .graphic && $0.graphic != nil }
        default:
            return nil
        }
    }
}
