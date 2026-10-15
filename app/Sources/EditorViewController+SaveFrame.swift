import AppKit

/// File ▸ Save Frame… (⌥⌘E) — the frame under the playhead as a still image
/// (road map 2 phase 7a).
///
/// **What is here is the URL and the thread; the WRITE is `FrameWriter`'s.**
/// That split is the feature's whole point: `render_frame` calls the same
/// `FrameWriter.writeFrame`, which labels the frame BT.709 (spec §11 PR-11)
/// and writes it, so the two paths cannot produce different bytes for
/// one frame, and a proof script — which can drive the agent but can never
/// press a menu item or type into a save panel — is still measuring what this
/// command does. Anything about the picture that ends up in this file instead
/// of in `FrameWriter.swift` is a place the menu and the agent can drift.
///
/// **The picture is the EDITED project's, and so is the time it is asked
/// for** (road map 2's phase 9). Inside a nest `document.playhead` is measured
/// from the NEST's own zero — `setNestPath` subtracts the nest clip's start —
/// while `document.project` is still the timeline, so a command that spends
/// one in the other names a frame nobody asked for: the timeline at a tick
/// counted from somewhere inside it. Two ticks, two containers, no error.
/// Rendering `document.editedProject` at that same tick needs no mapping at
/// all, because the tick is already in that project's time base, and it
/// restores the identity this file was split for: `render_frame` renders
/// `editedProject` at `document.playhead` too (`AgentServer+Render.swift`),
/// so the menu item and the tool still write one frame's bytes and both write
/// the frame the canvas is showing. With no nest open the two handles are the
/// same object and nothing about this command changes.
///
/// That puts Save Frame on the `editedProject` side of the split
/// `ProjectDocument.editedProject` documents, where an EXPORT stays on the
/// `project` side, and the two are not in tension: an export's subject is the
/// FILE, which is always the whole timeline, and a frame grab's subject is
/// the PICTURE, which is whatever is on the canvas. The canvas is the thing a
/// person is looking at when they reach for ⌥⌘E.
///
/// **The render is off-main.** `Exporter.renderFrame` opens asset tracks and
/// decodes, and its own doc says to call it off the main thread;
/// `EditorViewController+Eyedropper.swift` is the seam this copies (:77-81 for
/// the queue, :187-194 for the hop out and back), down to the reason for a
/// queue of its own rather than the compositor's build queue — a grab must not
/// be stuck behind a preview rebuild, and a preview rebuild must not be stuck
/// behind a grab. It is a SECOND queue object rather than the eyedropper's
/// because that one is `private` to its file, and widening it would put two
/// unrelated commands in one line for no gain; both are named in
/// `app/CLAUDE.md`'s seam list.
///
/// **A frame showing a deep still or a deep VP9 track is saved deep** (spec
/// §11 PR-9, PR-12): a PNG or HEIC passes `keepsDepth`, the same expression
/// `render_frame` passes (`format.carriesDepth`), and `renderFrame` reads such
/// a frame through the reader, so the two still write one frame's bytes; a
/// JPEG never does.
///
/// The hop back does nothing on success: a save panel that has written the
/// file the person named has said everything it has to say. A failure gets an
/// alert naming the path, which is why `FrameWriter` throws rather than
/// answering a bare `false`.
///
/// **Save Frame passes NO timecode burn-in**, and the asymmetry is deliberate:
/// the export sheet and the `export` tool burn one in when asked, and
/// `render_frame` carries the option too (agent parity, and the only way a
/// script can photograph a burn-in), while this command never offers it —
/// a frame grab is a grab of the PICTURE, not of a review deliverable, and a
/// still somebody is about to put in a document should not arrive stamped.
/// It reaches that by calling `Exporter.renderFrame` WITHOUT its `options`
/// argument, whose default is `RecipeOptions.none`; if that default were ever
/// taken away this file would stop compiling, which is the right way for the
/// question to be asked again.
extension EditorViewController {

    /// One frame composed for one file is a decode, not a redraw — the
    /// eyedropper's argument for its own queue, and the same answer here.
    private static let frameGrabQueue = DispatchQueue(
        label: "com.kgalligan.framejob.saveframe", qos: .userInitiated)

    // MARK: - The command

    /// File ▸ Save Frame…. A selector declared `@objc` on an extension needs
    /// no forward in the frozen `EditorViewController.swift` (`pickChromaKey`
    /// is the precedent); only the validator arm is wired there, in one line.
    @objc func saveFrame(_ sender: Any?) { saveFrameCommand() }

    /// The panel, then the render, then the write.
    ///
    /// The refusals happen HERE, ahead of the panel, which is
    /// `removeSilencesCommand`'s rule: a save panel whose only possible answer
    /// is "there is nothing at the playhead to save" should not open at all.
    /// The test is the validator's — a zero-duration project is the one
    /// `Exporter.renderFrame` answers nil for — and it is asked of the project
    /// that will be RENDERED, which inside a nest is the nest: a person who
    /// has emptied the nest they are inside is looking at a blank canvas, and
    /// the timeline's own duration would open a panel for a frame that cannot
    /// be composed.
    func saveFrameCommand() {
        guard let document = document, let window = view.window,
              window.attachedSheet == nil, document.editedProject.duration > 0
        else {
            NSSound.beep()
            return
        }
        // The TIME is fixed here and nowhere else. It is the person's own
        // choice, it is spelled into the name they are about to edit, and a
        // frame grab whose file disagrees with its own filename is worse than
        // one taken a moment early — so unlike the project below, the playhead
        // is not re-read when the panel comes back. It is left exactly as the
        // document holds it, which inside a nest means the nest's own time
        // (see the type doc): the render below is handed the same container,
        // so there is nothing to map, and the timecode in the name is the one
        // the toolbar and the ruler were showing when ⌥⌘E was pressed.
        let time = max(0, document.playhead)
        // The canvas the time is MEASURED in, for the same reason. A nest
        // borrows the parent's `fps` and `timecode_frames` (`core/src/
        // scope.rs`'s table — only the width and height are the nest's), so
        // the two canvases spell a tick identically and this line changes no
        // name; it is written this way to say which container the tick came
        // from, so the next person to touch it does not have to work it out.
        //
        // The base is `displayStem`: the title with the package's own
        // extension off and NOTHING else off. A bare `deletingPathExtension`
        // stood here and offered "Board v1.2" as `Board v1 ….png` — the same
        // character the format popup below used to eat, fixed on the same
        // terms (`ProjectDocument+DisplayStem.swift`).
        let stem = frameStem(
            base: document.displayStem, at: time,
            canvas: document.editedProject.snapshot.canvas)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(stem).\(FrameWriter.Format.png.fileExtension)"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [FrameWriter.Format.png.contentType]
        panel.message = "Write the frame at the playhead as a still image."
        let options = SaveFrameOptions(panel: panel, stem: stem)
        panel.accessoryView = options.view
        // The completion is what keeps `options` alive: the panel retains the
        // accessory VIEW, not the object whose action the format popup calls,
        // and a deallocated target would leave a live popup that changes
        // nothing (`CaptionExportOptions`' note, and the same hazard).
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.renderAndWriteFrame(
                from: document, at: time, format: options.format, to: url, in: window)
        }
    }

    /// The suggested name: the document's, then the timecode of the frame
    /// being saved.
    ///
    /// A frame grab named after the project alone collides with the previous
    /// one every single time, and a save panel's answer to a collision is a
    /// replace-or-cancel alert — so the default name would train a person to
    /// retype it. The time is spelled by `ReelTime.format` under the canvas's
    /// own `timecode_frames`, because the toolbar and the ruler spell it that
    /// way and inventing a second spelling of a time is the thing that
    /// formatter exists to prevent.
    ///
    /// The colons come out. A colon is legal in a POSIX path and is exactly
    /// what a person would type, but the Finder renders one as `/` — so a file
    /// saved as `Talk 00:00:04:12.png` is listed as `Talk 00/00/04/12.png` and
    /// reads as four folders that are not there.
    private func frameStem(base: String, at t: Ticks, canvas: CanvasSnapshot) -> String {
        let time = ReelTime.format(t, fps: canvas.fps, frames: canvas.timecodeFrames)
        let safe = time.replacingOccurrences(of: ":", with: "-")
        return base.isEmpty ? safe : "\(base) \(safe)"
    }

    // MARK: - The render

    /// Reads the document on the main thread, composes off it, and comes back
    /// with a URL or an error.
    ///
    /// The PROJECT is read here rather than captured when the panel opened,
    /// which is `CaptionExporter`'s rule and holds for its reason: a save
    /// panel is window-modal, so nothing the person does can change the
    /// document under it, but an agent's edit can (MCP runs on the main
    /// thread and a sheet does not stop it), and what the project says NOW is
    /// what should land. The `t` it is asked about came the other way, from
    /// the command — see `saveFrameCommand`, where the reason is written down.
    ///
    /// It is the EDITED project, which is the whole of phase 9's correction
    /// here and is argued in the type doc: `time` is measured in whatever
    /// container is open, so this is the one handle it can be spent against.
    /// One seam is left open by that pairing and is named rather than
    /// guarded: an agent's `set_scope` between the panel opening and its OK
    /// would spend the old container's tick in the new container. It is the
    /// agent-only half of a race this method already documents for edits, the
    /// window-modal panel rules the person out, and the honest guard for it
    /// would be a second opinion here about which container a tick belongs
    /// to — which is `ProjectDocument`'s to hold, and holding it twice is
    /// what made this file wrong in the first place.
    private func renderAndWriteFrame(
        from document: ProjectDocument, at time: Ticks, format: FrameWriter.Format,
        to url: URL, in window: NSWindow
    ) {
        let project = document.editedProject
        let urls = document.mediaURLs()
        let graphics = GraphicRegistry.shared.snapshot(for: document.recipeKey)
        EditorViewController.frameGrabQueue.async { [weak self] in
            let result: Result<URL, Error>
            // `render_frame`'s expression, so the two stay one frame's bytes.
            if let image = Exporter.renderFrame(
                project: project, urls: urls, at: time, maxWidth: nil, graphics: graphics,
                keepsDepth: format.carriesDepth)
            {
                result = Result { try FrameWriter.writeFrame(image, as: format, to: url) }
            } else {
                result = .failure(SaveFrameError.noFrame)
            }
            DispatchQueue.main.async { self?.frameSaved(result, in: window) }
        }
    }

    /// Back on the main thread. Success is silent — the file is where the
    /// person put it — and a failure is an alert on the window that asked.
    /// The whole path mutates nothing, so there is no undo step to group and
    /// none of `performGroupedEdit`'s off-event machinery applies.
    func frameSaved(_ result: Result<URL, Error>, in window: NSWindow) {
        guard case .failure(let error) = result else { return }
        let alert = NSAlert(error: error)
        alert.beginSheetModal(for: window, completionHandler: nil)
    }

    // MARK: - Validation

    /// The half of `validateUserInterfaceItem` this file owns. `nil` means
    /// "not mine" and leaves the other answers alone — which is why the
    /// document is read INSIDE the arm rather than guarded ahead of the
    /// switch: an arm that answered `false` with no document would be
    /// answering for every other command in the chain as well.
    ///
    /// The arm is load-bearing, not decoration. Without it Save Frame… falls
    /// through to `validateUserInterfaceItem`'s closing `return true` and is
    /// live on an empty timeline, where it can only open a panel and then put
    /// up an alert. `duration > 0` is the honest test because it is exactly
    /// the question `Exporter.renderFrame` refuses on: a plan of zero length
    /// has no frame at any time. Nothing else about the timeline can be asked
    /// cheaply and answered correctly here — a project whose visible clips are
    /// all text, shapes or images DOES render (`CompositionBuilder` gives it a
    /// placeholder track), so a "has a video track" test would grey out a
    /// command that works.
    ///
    /// It asks the EDITED project, matching the command and the render: with
    /// a nest open the frame that would be written is the nest's, so an
    /// emptied nest inside a full timeline is exactly the case the arm exists
    /// for. `editedProject` is memoised per parent handle
    /// (`ProjectDocument`), so asking it from a validator — which runs on
    /// every menu update — costs a pointer comparison after the first call,
    /// and at the top level it IS `project`.
    func validateSaveFrameAction(_ action: Selector) -> Bool? {
        guard action == #selector(EditorViewController.saveFrame(_:)) else { return nil }
        return (document?.editedProject.duration ?? 0) > 0
    }
}

// MARK: - Failures this file owns

/// The one failure that is about the TIME rather than about the file, so it
/// does not belong in `FrameWriter` — which is handed an image and knows
/// nothing about playheads or plans.
private enum SaveFrameError: LocalizedError {
    /// `Exporter.renderFrame` answered nil, which it does for every reason at
    /// once and says nothing about which — no plan, a composition it could not
    /// build, a time past the end. It carries no payload for that reason: a
    /// tick count in an alert is noise to the person reading it, and there is
    /// nothing here that could turn one into the sentence that would help.
    case noFrame

    var errorDescription: String? {
        switch self {
        case .noFrame:
            return "There is no frame at the playhead. The time is past the end of the "
                + "timeline, the timeline is empty, or the media is missing."
        }
    }
}

// MARK: - The save panel's options

/// The one choice a frame grab has — which container — carried in the save
/// panel's accessory view rather than in a sheet of its own.
///
/// `CaptionExportOptions` is the pattern and its argument holds here too: a
/// sheet for one popup would be the heavier answer, and chaining a sheet out
/// of a sheet is what `ReverseProgressSheetController` records as not working
/// in this app. The line under the popup is not decoration either — it is what
/// each format does with alpha, said out loud at the moment the format is
/// chosen, which is the only place a person with a transparent canvas
/// (phase 7b) will read it before the JPEG has already flattened.
///
/// It owns nothing but its controls; the panel's completion holds it for as
/// long as the panel is up.
private final class SaveFrameOptions: NSObject {
    private weak var panel: NSSavePanel?
    private let stem: String
    private let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let hint = NSTextField(labelWithString: FrameWriter.Format.png.alphaNote)

    let view: NSView

    init(panel: NSSavePanel, stem: String) {
        self.panel = panel
        self.stem = stem

        for format in FrameWriter.Format.allCases {
            formatPopup.addItem(withTitle: format.displayName)
            // The row carries the FORMAT, never its position in the list.
            // `NSPopUpButton.addItem(withTitle:)` removes an existing row with
            // the same title before adding the new one, so a popup read by
            // `indexOfSelectedItem` is one duplicated title away from writing
            // a different format than the row named and reporting success —
            // phase 4's measured defect, in `app/CLAUDE.md`'s pitfall list.
            // These three titles are distinct; reading the object makes that
            // stop mattering.
            formatPopup.lastItem?.representedObject = format
        }
        formatPopup.font = DS.sans(13)
        formatPopup.selectItem(at: 0)

        hint.font = DS.sans(11)
        hint.textColor = DS.textMuted
        hint.isEditable = false

        let grid = NSGridView(views: [[fieldLabel("Format:"), formatPopup]])
        grid.rowSpacing = 8
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = 60
        grid.translatesAutoresizingMaskIntoConstraints = false
        hint.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(grid)
        container.addSubview(hint)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            grid.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            hint.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 6),
            hint.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            hint.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            container.widthAnchor.constraint(greaterThanOrEqualTo: grid.widthAnchor, constant: 32),
            container.widthAnchor.constraint(greaterThanOrEqualTo: hint.widthAnchor, constant: 32),
            // A floor wide enough for the longest of the three notes, so the
            // accessory view is one size for every format. Without it the
            // container shrinks to fit whichever line is showing and the
            // popup above it walks sideways each time the popup is used —
            // which reads as the panel twitching at the person's own click.
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 420),
        ])
        view = container

        super.init()
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged(_:))
        syncHint()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SaveFrameOptions does not support NSCoder")
    }

    var format: FrameWriter.Format {
        formatPopup.selectedItem?.representedObject as? FrameWriter.Format ?? .png
    }

    /// The panel's filter and its name field both name the container, so both
    /// move together — otherwise AppKit appends `.png` to a name the person
    /// just asked to be a `.jpg`.
    ///
    /// Only the EXTENSION is this method's to change. The stem is read back
    /// off the PANEL rather than from `stem`, which was fixed when the panel
    /// opened: somebody who typed "cover art" over the suggested name and then
    /// chose JPEG would otherwise watch the field silently revert to the
    /// project's name and save to a path they had already replaced. `stem`
    /// survives as the fallback for a field emptied to nothing.
    ///
    /// **The rewrite itself is `FrameWriter.renamed`**, which the review is
    /// what moved there: it strips a trailing suffix only when it is one of
    /// the three formats' own spellings, so `Board v1.2` no longer becomes
    /// `Board v1.jpg` when somebody picks JPEG, and — the reason it is a free
    /// function rather than four lines here — a rule inside a save panel's
    /// private method is a rule no proof can reach.
    @objc private func formatChanged(_ sender: Any?) {
        syncHint()
        guard let panel = panel else { return }
        let format = self.format
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = FrameWriter.renamed(
            panel.nameFieldStringValue, as: format, fallback: stem)
    }

    /// The note follows the popup. Every row has one, so the line never
    /// appears or disappears — `Format.alphaNote` argues why that is better
    /// than a warning that shows up only over JPEG, and a label whose height
    /// never changes is also what keeps the accessory view one size.
    private func syncHint() {
        hint.stringValue = format.alphaNote
    }
}
