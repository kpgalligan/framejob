import AppKit

/// The document's title as a file STEM — what a save panel puts its own
/// extension after. Three panels want it (Export…, Save Frame…, Export
/// Captions…) and all three used to derive it with a bare
/// `deletingPathExtension` over `displayName`, which takes whatever follows
/// the last dot: an untitled document opened from `Board v1.2.mov` is titled
/// "Board v1.2" (`defaultDraftName()` strips the movie's extension and
/// nothing else) and was offered as `Board v1.mp4`, `Board v1 ….png` and
/// `Board v1.srt`. Measured: `("Board v1.2" as NSString).deletingPathExtension`
/// is "Board v1".
///
/// **The known set here is `{reelcut}` and nothing else** — not
/// `CaptionExporter.knownExtensions`' `{srt, vtt}` and not `FrameWriter`'s
/// image spellings, however alike the lines look. Those two strip a suffix
/// their own popup put on a name; this strips the DOCUMENT's own extension
/// off a title-bar name, and the only extension a title bar can carry is the
/// package's, shown or hidden as Finder's preference and the file's own flag
/// decide: a saved `Board v1.2.reelcut` reads as "Board v1.2.reelcut" or as
/// "Board v1.2" and must come back as "Board v1.2" from both. A caption set
/// here would turn the first into `Board v1.2.reelcut.srt`, and a document
/// somebody has literally named `talk.srt` keeps its suffix and is offered
/// `talk.srt.srt` — the honest answer for a pathological name, and the file
/// `AgentServer.captionDestinationURL` writes for that path (`srt` is replaceable
/// there, so over MCP it is `talk.srt`).
///
/// It is an extension in its own file because `ProjectDocument.swift` is over
/// the ~600-line cap and should not take on code, and a pure function because
/// a save panel is reachable by no proof this project can write —
/// `tools/proof/remaining_probe.py` compiles `app/Sources` and runs a table
/// of names through `displayStem(of:)` instead.
extension ProjectDocument {

    /// What the title bar says for a document with no name yet. It is
    /// `defaultDraftName()`'s own fallback spelled again, because
    /// `displayName` is declared implicitly unwrapped — AppKit's header
    /// leaves it unannotated, so Swift reads `String!` and a nil is possible
    /// in principle before AppKit has named the document — and every panel
    /// needs SOME stem to put an extension after. The two spellings must
    /// agree, and the literal stands in `ProjectDocument.swift` too rather
    /// than that file taking on a reference to this one; the probe reads
    /// both and pins them equal.
    static let untitledDisplayName = "Untitled Project"

    /// `name` with a trailing `.reelcut` removed, compared lower-cased —
    /// `destinationURL` compares its suffix lower-cased, and Finder lets a
    /// package be renamed `X.REELCUT` — and nothing else removed. Foundation
    /// reads no extension off a dot-leading name (`.reelcut` comes back as
    /// `.reelcut`, measured), so the empty-stem fallback below is reached by
    /// no input this session could construct; it stays because a stem of
    /// nothing is the one answer a panel cannot use.
    static func displayStem(of name: String) -> String {
        let suffix = (name as NSString).pathExtension.lowercased()
        guard suffix == projectFileExtension else { return name }
        let stem = (name as NSString).deletingPathExtension
        return stem.isEmpty ? name : stem
    }

    /// The stem of THIS document's title, over `displayName`'s fallback.
    var displayStem: String {
        Self.displayStem(of: displayName ?? Self.untitledDisplayName)
    }
}
