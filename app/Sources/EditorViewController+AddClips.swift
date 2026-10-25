import AppKit
import UniformTypeIdentifiers

/// The commands that put a clip on the timeline out of nothing rather than
/// out of a file already in the Media tab: Add Text (T), the Add Shape menu,
/// and — since road map 2's phase 6c — the two BACKGROUND commands.
///
/// Placement follows the spec §4.1 wording, "at the playhead": the clip goes on
/// the FRONT-MOST track if it fits there, and onto a new track above everything
/// if it does not. Trying the front track first is what keeps a title sequence
/// from growing a track per title; falling back to a new one is what keeps the
/// button from ever beeping at a playhead that happens to sit over a clip.
/// Both are one undo step either way, because `applyEdit` takes the whole op
/// list (`ProjectDocument`).
///
/// **The two background commands place nothing themselves.** A backdrop goes
/// on a NEW back-most track, which is a decision with a source window, a fill
/// scale and a `SCALE_MAX` clamp behind it, so the whole of it is one core op
/// — `add_background` and `add_blurred_background`, argued at length in
/// `core/src/edit_background.rs`'s module doc. What is left here is the menu,
/// the open panel, and the one thing the core cannot answer: what should be
/// SELECTED afterwards.
extension EditorViewController {

    /// T, the toolbar's Add Text button, and Clip > Add Text.
    @objc func addTextClipAtPlayhead(_ sender: Any?) {
        addGeneratedClip(named: "Add Text") { track, at in
            .addTextClip(track: track, at: at)
        }
    }

    /// One item of the Add Shape menu. The sender's tag indexes
    /// `ShapeKind.allCases` — the same tagging `showAddShapeMenu` writes, so
    /// the menu and the enum cannot drift.
    @objc func addShapeClipAtPlayhead(_ sender: Any?) {
        let kinds = ShapeKind.allCases
        let tag = (sender as? NSMenuItem)?.tag ?? 0
        let kind = tag >= 0 && tag < kinds.count ? kinds[tag] : .rectangle
        addGeneratedClip(named: "Add \(kind.displayName)") { track, at in
            .addShapeClip(track: track, at: at, shape: kind)
        }
    }

    /// The shared body: place `make` on the front track, and if the core
    /// refuses it there — the overlap rule (§6) is the only reason it can —
    /// insert a track above everything and place it there instead.
    ///
    /// The refusal is detected by applying the op PURELY first, against the
    /// document's own handle. That costs one throwaway project value and keeps
    /// the fallback out of the undo stack: nothing is registered until the
    /// version that works is the one applied.
    ///
    /// `grouped` is for a caller running OFF-EVENT (a panel's completion):
    /// the edit goes through `performGroupedEdit`, else `applyEdit`.
    func addGeneratedClip(
        named name: String, grouped: Bool = false, _ make: (UInt32, Ticks) -> ReelOp
    ) {
        guard let document = document else { return }
        // The EDITED project throughout, here and in every other command in
        // this file that places a clip: with a nest open the front track is
        // the NEST's front track, the overlap probe has to be run against the
        // nest, and the id set the selection is read back out of is the
        // nest's (road map 2's phase 9). `add_media` is the one exception and
        // is called out where it happens.
        let before = document.editedProject.snapshot
        let at = document.playhead

        var ops: [ReelOp] = []
        // `.project` on a `try?` collapses three answers into one nil: a
        // throw, an identity and a rule's refusal. Either way the front track
        // will not take this clip, so all of them take the new-track path.
        if let front = before.tracks.last?.id,
            (try? document.editedProject.applying(make(front, at))).project != nil
        {
            ops = [make(front, at)]
        } else {
            // The id of a newly added track is `next_id` from BEFORE the op —
            // the documented contract of the one JSON op entry point, since
            // `rc_project_apply` returns a project rather than an id.
            // Index 0 is the BACK of the stack (§6), so the count is the front.
            ops = [.addTrack(index: before.tracks.count), make(before.nextId, at)]
        }
        if grouped {
            document.performGroupedEdit(name, ops)
        } else {
            document.applyEdit(name, ops)
        }
        selectClips(addedSince: before, in: document)
    }

    /// Select whatever appeared, so the inspector opens on the new clip's own
    /// sections and the canvas draws its handles. Comparing id sets rather
    /// than trusting an id we predicted keeps this correct even if the core
    /// ever allocates differently — and it is why every command in this file
    /// reads the snapshot BEFORE it edits.
    ///
    /// Nothing added means the core refused or answered an identity —
    /// `applyEdit` has already beeped — so the selection stays as
    /// `ProjectDocument.clampViewState` left it.
    func selectClips(addedSince before: ProjectSnapshot, in document: ProjectDocument) {
        let existing = Set(before.clips.map { $0.id })
        let added = document.editedProject.snapshot.clips.map { $0.id }
            .filter { !existing.contains($0) }
        guard !added.isEmpty else { return }
        document.selection = Set(added)
        viewStateDidChange()
    }

    // MARK: - Backgrounds (road map 2, phase 6c)

    /// Clip ▸ Add Background ▸ Solid Color.
    ///
    /// **No dialog, and no ellipsis in the title.** The op takes no arguments
    /// at all — a canvas-sized white rectangle on a new back-most track,
    /// running the timeline's length — and the plate is re-coloured afterwards
    /// in the Clip tab's existing Fill row, which is the row that already owns
    /// "what colour is this shape". Asking for the colour up front would put a
    /// second colour picker in front of the one the inspector already has, and
    /// it would leave the interesting case unreachable: a full-canvas GRADIENT
    /// is this same plate with a `shape.gradient` on it, so the road map's
    /// gradient background is Solid Color followed by the Gradient section and
    /// nothing else.
    ///
    /// White rather than black is the core's choice and its own doc argues it:
    /// the canvas is already black, so a black plate is a command that appears
    /// to do nothing.
    @objc func addSolidColorBackground(_ sender: Any?) {
        guard let document = document else {
            NSSound.beep()
            return
        }
        let before = document.editedProject.snapshot
        document.applyEdit("Add Background", [.addBackground()])
        selectClips(addedSince: before, in: document)
    }

    /// Clip ▸ Add Background ▸ Image… — a picture behind everything, at FILL
    /// scale and the timeline's length. Fill and not Fit, which is where
    /// `add_clip` would put it: a plate that leaves the canvas showing down
    /// one side has failed at the one thing a background is for, and it is
    /// the scale `add_blurred_background` gives its copy, so the two
    /// commands agree. The phase-6 review is what changed it.
    ///
    /// A standard `NSOpenPanel` over the image UTIs; `CaptionImporter.swift`
    /// is the pattern, down to the reason the edit that follows goes through
    /// `performGroupedEdit` rather than `applyEdit`: a panel's completion is
    /// OFF-EVENT, and an undo registration made outside an AppKit event lands
    /// in the implicit per-event group `NSUndoManager` never closes there,
    /// silently merging this edit into whatever came before it
    /// (app/CLAUDE.md's undo pitfall).
    @objc func addImageBackground(_ sender: Any?) {
        guard let document = document, let window = view.window else {
            NSSound.beep()
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        // The whole image family rather than `ProjectDocument.readableTypes`:
        // a movie behind the timeline is an ordinary clip on a track the user
        // puts where they want it, while a background is by definition the
        // thing that runs the WHOLE cut — and the op clamps a timed media to
        // its own file's length, so a five-second movie plate would stop where
        // its file does; only an image runs the whole timeline.
        panel.allowedContentTypes = [.image]
        panel.message = "Choose a picture to put behind everything."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.addImageBackground(from: url, into: document, in: window)
        }
    }

    /// The probe, then the placement. Probing is asynchronous and its answer
    /// arrives on the main thread (`MediaImporter.probe`, the seam that keeps
    /// `async` confined to that file), so an unreadable picture is reported in
    /// a sheet and nothing is placed.
    func addImageBackground(
        from url: URL, into document: ProjectDocument, in window: NSWindow
    ) {
        MediaImporter.probe(url: url, mayAsk: true) { [weak self] result in
            switch result {
            case .failure(let error):
                NSAlert(error: error).beginSheetModal(for: window, completionHandler: nil)
            case .success(let descriptor):
                self?.placeImageBackground(descriptor, into: document, in: window)
            }
        }
    }

    /// Two ops in ONE undo step — `add_media` then `add_background {media}` —
    /// which needs the id the FIRST one mints, or the id it declined to mint.
    ///
    /// An op returns a project and never a value (spec §11: one FFI entry
    /// point for every op), so the id is learned by applying `add_media`
    /// PURELY, against the document's own handle, and reading it off the
    /// resulting snapshot: the core appends, so the last entry is the new one.
    /// `ProjectDocument.makeProject(around:)` has done exactly this since M1
    /// and this is the first use of the technique outside it, so the reason it
    /// is sound is worth writing down here as well: `next_id` is a single
    /// counter, so the same op applied to the same base mints the same id
    /// every time, and the throwaway project the probe applies to and the one
    /// the undo step applies to ARE the same base.
    ///
    /// **The precedent does not carry the whole way, and the review is what
    /// found the gap**: `makeProject(around:)` applies `add_media` to a
    /// project built empty two lines above it, where the file cannot already
    /// be in the list, and this call site is the case where it can be.
    /// `backgroundMedia(for:in:)` is that half.
    ///
    /// The alternative — `importMedia` and then a second edit — is two undo
    /// steps for one command, and a ⌘Z that leaves the picture in the media
    /// list is the kind of half-undone state this app does not have anywhere
    /// else.
    func placeImageBackground(
        _ descriptor: MediaDescriptor, into document: ProjectDocument, in window: NSWindow
    ) {
        let before = document.editedProject.snapshot
        let add = ReelOp.addMedia(descriptor: descriptor)
        let media: UInt32
        do {
            // The core's own message for a descriptor it refuses — a picture
            // past `MEDIA_DIMENSION_MAX`, a rate with a zero term — rather
            // than the sentence below, which would report "could not be
            // added" and name none of it. A `try?` here spent the one thing
            // the core said.
            // The DOCUMENT's handle, not the edited one: `add_media` is a
            // document-level op sent unscoped (`ReelOp.isDocumentLevel`), so
            // the probe that learns the id it will mint has to be run against
            // the same project the real op will land in.
            guard let id = try Self.backgroundMedia(for: descriptor, in: document.project) else {
                let alert = NSAlert()
                alert.messageText = "Could Not Add the Picture"
                alert.informativeText =
                    "“\(descriptor.path)” could not be added to this project's media list."
                alert.beginSheetModal(for: window, completionHandler: nil)
                return
            }
            media = id
        } catch {
            NSAlert(error: error).beginSheetModal(for: window, completionHandler: nil)
            return
        }
        // `add` stays in the list even when it is an identity: `applying(_
        // ops:)` runs every later op after an earlier one that changed
        // nothing, so one shape works for both cases and the undo step is
        // one either way.
        document.performGroupedEdit("Add Background", [add, .addBackground(media: media)])
        // The thumbnail the Media tab draws, and the filmstrip the timeline
        // draws: the import path generates them after every commit and this is
        // a commit like any other. Safe to call repeatedly — a cache whose
        // marker matches its file is not rebuilt, so a picture already in the
        // list costs the pass a stat and a marker read.
        document.generateCaches()
        selectClips(addedSince: before, in: document)
    }

    /// The media id `add_background` is to be handed for `descriptor` — the
    /// one `add_media` is about to mint, or the one the project already holds
    /// for that path.
    ///
    /// **A file already in the media list is not a failure.** `add_media`
    /// deduplicates by path and answers the documented identity (which
    /// `ReelProject.applying` answers as `.identity`, with no handle) rather
    /// than an error, and its own doc says what a caller does with that
    /// answer: "The caller that gets it looks the path up to find the id that
    /// is already there" (`core/src/edit_track.rs`). Reading the absent
    /// handle as "could not be added" refused two entirely ordinary sequences
    /// — Add Background ▸ Image… twice with one picture, and using a picture
    /// that is already in the Media tab — with a sentence that is not true,
    /// and placed nothing. `commitImport`
    /// has absorbed the same identity silently since M1; a duplicate drop into
    /// the Media tab is a no-op, and this command owes the file the same
    /// reading.
    ///
    /// The lookup compares against the TRIMMED path, because that is the
    /// string the core stored: `add_media` trims before it deduplicates and
    /// before it writes `record.path`.
    ///
    /// Throws the core's own message for a descriptor it refuses; nil only for
    /// the case that cannot happen — an identity whose path is in no entry.
    static func backgroundMedia(for descriptor: MediaDescriptor, in project: ReelProject) throws
        -> UInt32?
    {
        if let probed = try project.applying(.addMedia(descriptor: descriptor)).project {
            return probed.snapshot.media.last?.id
        }
        let path = descriptor.path.trimmingCharacters(in: .whitespacesAndNewlines)
        return project.snapshot.media.first { $0.path == path }?.id
    }

    /// Clip ▸ Add Blurred Background — the screencast backdrop: the selected
    /// clip copied onto a new back-most track, blown up to FILL the canvas and
    /// blurred at full strength.
    ///
    /// One clip, never a selection: the copy is made of that clip's own pixels
    /// and plays its own frames, so two selected clips would either have to be
    /// chosen between or produce two backdrops, one of which hides the other.
    /// The menu item is validated on that, so the beep below is reachable only
    /// from a path that skips validation.
    ///
    /// Everything else is the op's: the dropped audio switch (a copy that kept
    /// it would play one recording twice, at roughly +6 dB, and no still frame
    /// could see it), the dropped transition, the dropped actions, and the
    /// fill scale.
    @objc func addBlurredBackground(_ sender: Any?) {
        guard let document = document, selectedClips.count == 1,
            let clip = selectedClips.first
        else {
            NSSound.beep()
            return
        }
        let before = document.editedProject.snapshot
        document.applyEdit("Add Blurred Background", [.addBlurredBackground(clip: clip.id)])
        // The backdrop, not the clip it was made from: what a person does next
        // is dial its blur or its scale, and the foreground clip is one click
        // away on the timeline. It is also this file's standing rule — every
        // command here selects what it created.
        selectClips(addedSince: before, in: document)
    }

    /// The menu arms for the three, answered from `validateUserInterfaceItem`'s
    /// default case. Each asks the cheap snapshot question its command's own
    /// guard asks, so the menu and the command can never disagree — and
    /// without an arm an item falls through to that method's closing
    /// `return true` and is live on a timeline where it could only beep.
    func validateBackgroundAction(_ action: Selector) -> Bool? {
        switch action {
        case #selector(addSolidColorBackground(_:)), #selector(addImageBackground(_:)):
            // A plate needs a canvas and nothing else. It lands on a track of
            // its own, so there is no selection to have and no overlap to
            // refuse; the document's existence is all there is to check, and
            // `validateUserInterfaceItem` has checked it already.
            return true
        case #selector(addBlurredBackground(_:)):
            guard let snapshot = document?.editedProject.snapshot, selectedClips.count == 1,
                let clip = selectedClips.first
            else { return false }
            // The op's own refusals, asked here so the item DIMS rather than
            // raising a sheet.
            //
            // A NEST first, and it is the one a reader will not expect:
            // `sourceSize(of:)` answers for a nest with its frozen canvas, so
            // the size test below would wave it through. The op refuses it all
            // the same, because a nest clip never becomes a layer — only its
            // PLACEMENT folds down, through `Frame::enter` — so the blur the
            // copy would carry reaches nothing, and the backdrop comes out
            // SHARP at fill scale, at double the render cost, reported as
            // success. Refusing there and dimming here are one decision;
            // `edit_background.rs`'s module doc argues it.
            if case .nest = clip.source { return false }
            // Then a source with no pixel size — a text clip, an audio-only
            // one — which has nothing to scale to the canvas.
            guard let size = snapshot.sourceSize(of: clip), size.width > 0, size.height > 0
            else { return false }
            return true
        default:
            return nil
        }
    }
}
