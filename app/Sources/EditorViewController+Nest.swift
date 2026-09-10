import AppKit

/// Clip ▸ Nest (⌘G) and Un-nest (⇧⌘G) — the two grouping commands
/// `EditorViewController.swift` forwards here (spec §4.4, §6).
///
/// Both are one op and one undo step, and every decision that could be the
/// core's is: which track the nest clip lands on, what span it covers, what
/// the nest's canvas is frozen at, where the contents come back to, and which
/// of the documented refusals applies. What is left on this side is the one
/// thing the core cannot answer — what should be SELECTED afterwards — and
/// the menu validation.
///
/// **Selection is read back, never predicted.** A nest replaces n clips with
/// one and an un-nest does the reverse, so in both cases the selection worth
/// having is "whatever is on the timeline now that was not there before": the
/// id-set difference `EditorViewController+AddClips.swift` and
/// `+Clipboard.swift` already use. Reading `next_id` first would work today
/// and would be a third place to be wrong the day the core mints ids
/// differently.
///
/// ## The way in is next door
///
/// The gesture this file looks like it should carry — double-click a nest
/// clip, the timeline and canvas show its contents, a breadcrumb leads back
/// out — is `EditorViewController+NestScope.swift`'s, and it exists (road map
/// 2's phase 9). It is worth reading what USED to be written here, because it
/// was true and it is what changed:
///
/// - **No op could address a clip inside a nest.** Every clip argument in the
///   op table resolves through `Project::clip`, which searches `self.clips`
///   and nothing else, and a nest's clips live in `Nest::clips`. So an inside
///   view could only ever have been READ-ONLY, which is worse than absent:
///   `TimelineView` builds its ops out of the snapshot it is handed, so every
///   drag, trim, split and delete would have emitted an op naming an id the
///   core refuses.
/// - What the feature needed first was a way to NAME a nested clip, and this
///   file said so: "an op-table decision (a path-valued `clip` argument, or a
///   `nest` scope on the envelope), not a new idea". It is the second of
///   those. `core/src/scope.rs` gives the ENVELOPE a `scope`, and the op is
///   applied to a view project whose top level is the nest — so
///   `Project::clip` kept its one meaning, no op gained a branch, and
///   `rc_project_scoped` hands the same view to the app to draw from.
///
/// The round trip — ⇧⌘G, edit, ⌘G — still works and is still the identity on
/// clip content. What it costs, and what going inside now saves, is the nest
/// CLIP's own transform, opacity, fades and volume: the group-level
/// properties, which an unnest throws away and a scope leaves alone.
///
/// Both commands here work INSIDE a nest, with no code of their own for it:
/// they read `document.editedProject` and their ops are stamped with the
/// scope by `ProjectDocument.applyEdit`, so ⌘G in a nest makes a nest in a
/// nest — a legal extra level, bounded by `MAX_NEST_DEPTH` on the merged
/// parent like any other.
extension EditorViewController {

    // MARK: - Nest

    /// ⌘G. Collapses the selection into one clip standing for the group, and
    /// selects it so it can be moved, faded or transformed straight away.
    ///
    /// No refusal beep of its own: `ProjectDocument.applyEdit` already beeps
    /// for the core's `Ok(None)` — an empty selection, a lone nest clip, or a
    /// nest clip the overlap rule will not have — and a second one here would
    /// double it. The only beep left is the guard below, which the menu
    /// validation makes unreachable from the menu but not from the key
    /// equivalent's own path.
    func nestSelection() {
        guard let document = document else { return }
        // `selectedClips` is ordered by start, so two runs over the same
        // selection build the same op JSON. `document.selection` is a Set and
        // would not.
        let clips = selectedClips.map { $0.id }
        guard !clips.isEmpty else {
            NSSound.beep()
            return
        }
        let before = Set(document.editedProject.snapshot.clips.map { $0.id })
        document.applyEdit("Nest", .nest(clips: clips))
        selectClipsAdded(since: before, in: document)
    }

    // MARK: - Un-nest

    /// ⇧⌘G. Opens every nest clip in the selection and selects everything
    /// that came out of them.
    ///
    /// All of them in ONE undo step: "open this group" is one intention
    /// whether the user picked one nest or four, and four steps to undo it
    /// would be four surprises. Building every op from the same before-state
    /// is safe because `unnest` only ever removes the clip it names and mints
    /// fresh ids for the rest — no id in the list can be invalidated by an
    /// earlier op in it, and the tracks an earlier op inserts shift indices,
    /// never ids.
    func unnestSelection() {
        guard let document = document else { return }
        let nests = selectedClips.filter { $0.source.nestID != nil }
        guard !nests.isEmpty else {
            NSSound.beep()
            return
        }
        let before = Set(document.editedProject.snapshot.clips.map { $0.id })
        document.applyEdit(
            nests.count == 1 ? "Un-nest" : "Un-nest Clips",
            nests.map { ReelOp.unnest(clip: $0.id) })
        selectClipsAdded(since: before, in: document)
    }

    // MARK: - Shared

    /// Selects whatever the edit put on the timeline that was not there
    /// before, and tells the views.
    ///
    /// Nothing added means the core refused — it has beeped already — so the
    /// selection is left as `ProjectDocument.clampViewState` left it, which
    /// for a refusal is untouched.
    private func selectClipsAdded(since before: Set<UInt32>, in document: ProjectDocument) {
        let added = document.editedProject.snapshot.clips.map { $0.id }
            .filter { !before.contains($0) }
        guard !added.isEmpty else { return }
        document.selection = Set(added)
        viewStateDidChange()
    }

    // MARK: - Validation

    /// The half of `validateUserInterfaceItem` this file owns. nil means "not
    /// mine" and leaves the base file's answer alone.
    ///
    /// Only the CHEAP halves of the core's refusals are mirrored. Menu
    /// validation runs on every event pass, and the third refusal — the nest
    /// clip would overlap something that was NOT selected — can only be
    /// answered by applying the op to a throwaway project, which is what
    /// `EditorViewController+AddClips.swift` does once per invocation and
    /// nothing should do once per keystroke. A live item that beeps is the
    /// right trade; a menu that stutters is not.
    func validateNestAction(_ action: Selector) -> Bool? {
        switch action {
        case #selector(nestClips(_:)):
            let clips = selectedClips
            // The core refuses a selection of one clip that is already a
            // nest: wrapping a group in a group changes nothing anyone can
            // see. Two of them, or a nest and something else, is a real edit.
            if clips.count == 1, clips[0].source.nestID != nil { return false }
            return !clips.isEmpty
        case #selector(unnestClips(_:)):
            return selectedClips.contains { $0.source.nestID != nil }
        default:
            return nil
        }
    }
}
