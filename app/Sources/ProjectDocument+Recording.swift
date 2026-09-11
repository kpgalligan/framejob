// app/Sources/ProjectDocument+Recording.swift — a recording as a new
// document (road map 3, phase R1b, the `.newProject` landing).
//
// An `extension ProjectDocument` in its own file, `+DisplayStem`'s shape: the
// base file is far over the ~600-line cap and takes no code it does not have
// to. What it HAD to take is `adoptImported(_:source:fps:)` — `project` and
// `importSourceURL` are `private(set)` and `clampViewState()` is private, so
// an extension in another file cannot build the untitled document itself —
// and that method is `readMediaFile`'s post-probe body moved whole, so a
// recording becomes a document by the ONE spelling File ▸ Open uses for a
// movie (road map 3, decision 1: a recording is ordinary media).

import AppKit

extension ProjectDocument {
    /// The untitled, dirty document a finished recording opens as — spec
    /// §1's opening flow for a movie, with two differences the recorder
    /// asks for. The CANVAS takes the recorder's rate (`choice.rate`, 30 or
    /// 60 — the grid the person chose) while the media record keeps the
    /// file's own, which for a ScreenCaptureKit file is whatever the screen
    /// did (R0 measured 25.58 fps at a 1/60 interval; decision 3). And a
    /// microphone file, when there is one, lands as a second clip on a new
    /// back track through `RecordingLanding.microphonePlacement`, as ONE
    /// grouped edit.
    ///
    /// **The order is a contract**, measured on the real class by the
    /// document scout and once more by the review, and each step leans on
    /// the one before:
    ///
    /// 1. `openUntitledDocumentAndDisplay(false)` — the controller ADDS the
    ///    document itself (no `addDocument`, or it is listed twice) and,
    ///    with `false`, makes no window yet.
    /// 2. `adoptImported` — BEFORE anything reads `displayName`: AppKit pins
    ///    the name on its first read, and the name is
    ///    `defaultDraftName()`, which is the recording's stem only once
    ///    `importSourceURL` is set. Nothing between 1 and 2 logs, summarises
    ///    or shows the document.
    /// 3. **The import count** — `fileModificationDate = nil` and
    ///    `countEditChange(.changeDone)`, the two lines `makeWindowControllers`
    ///    runs for an opened movie (`ProjectDocument.swift`, under its
    ///    `importSourceURL != nil, fileURL == nil, !isDocumentEdited` guard)
    ///    — run HERE, before the microphone's edit and with or without one.
    ///    The position is the fix for a defect the review measured on the
    ///    change count: counted the other way round, the microphone's edit
    ///    dirtied the document first, `makeWindowControllers`' guard found
    ///    it edited and skipped its own count, and ONE ⌘Z brought the count
    ///    back to zero — a recording's document that read CLEAN, which ⌘W
    ///    then closed without asking. Counted first, the microphone's edit
    ///    stacks a SECOND count and its undo leaves the first standing, so
    ///    the document is dirty with the voice or without it, as an opened
    ///    movie is. Without a microphone this is the same one count
    ///    `makeWindowControllers` would have made, one step earlier.
    /// 4. The microphone's grouped edit — named
    ///    `RecordingLanding.microphoneActionName`, "Add Microphone", and NOT
    ///    "Add Recording", because the step removes the voice and keeps the
    ///    picture and the Edit menu should say what ⌘Z will do — before the
    ///    window, so the `generateCaches()` inside `makeWindowControllers`
    ///    covers BOTH files and the editor's first composition is built
    ///    once, over the finished project, rather than rebuilt when the
    ///    second clip lands. Every op was trialled purely by
    ///    `microphonePlacement`, so the windowless commit cannot reach
    ///    `presentError`'s app-modal arm.
    /// 5. `makeWindowControllers()` — its own import count is guarded out by
    ///    step 3 (the guard counts only a document nothing has counted, which
    ///    is what makes the two orders equivalent for a movie and step 3
    ///    safe here); what it still does is run `generateCaches()` and
    ///    `ensureReversedMedia()` and add the editor window.
    /// 6. `showWindows()`.
    ///
    /// A throw after step 1 CLOSES the document it opened, or a failed
    /// landing would leave an invisible untitled draft in the controller
    /// with a blank project in it.
    ///
    /// Two limits, recorded. Without a microphone the document has NO undo
    /// step — its first project is what the document is, as for an opened
    /// movie — while with one, ⌘Z (Undo Add Microphone) removes the
    /// microphone's media and clip and leaves the picture, and the document
    /// STAYS dirty under it (step 3's count): the picture is the document,
    /// the voice is an edit to it. And the file stays on disk on either
    /// undo, as undoing Add Media… leaves the file (road map 3 §0). Main
    /// thread.
    static func untitled(around result: RecordingResult) throws -> ProjectDocument {
        assert(Thread.isMainThread)
        let controller = NSDocumentController.shared
        guard let document = try controller.openUntitledDocumentAndDisplay(false)
            as? ProjectDocument
        else {
            throw ReelCoreError(message: "The untitled document did not open as a Reelcut project.")
        }
        do {
            try document.adoptImported(
                result.descriptor, source: URL(fileURLWithPath: result.descriptor.path),
                fps: Fps(num: result.choice.rate, den: 1))
            // Step 3: the import count, BEFORE the microphone's edit — see
            // the doc comment for why the order is the fix.
            document.fileModificationDate = nil
            document.countEditChange(.changeDone)
            if let mic = try RecordingLanding.microphonePlacement(result, in: document) {
                document.performGroupedEdit(RecordingLanding.microphoneActionName, mic.ops)
            }
        } catch {
            document.close()
            throw error
        }
        document.makeWindowControllers()
        document.showWindows()
        return document
    }
}
