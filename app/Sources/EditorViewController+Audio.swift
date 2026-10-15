import AppKit

/// The Clip menu's sound commands: Normalize (road map 2 phase 5c), moved
/// here whole out of `EditorViewController.swift` with its validator arm, as
/// that body's own comment asked a second sound command to do, and
/// Synchronize Audio (road map "audio-sync", AS-1; spec §11 SY-1..SY-5).
extension EditorViewController {

    /// Clip ▸ Normalize (road map 2 phase 5c) — the menu half of the Audio
    /// section's Normalize button.
    ///
    /// **Not a line of the arithmetic is here**, which is the whole point of
    /// `AudioNormalize` being a value type: this reads no peaks and derives no
    /// gain, it calls the same `read` + `plan` pair `AudioPane.normalize` and
    /// the agent's `normalize_clip` call, so the three cannot mean different
    /// things. What reaches the document is one ordinary `set_audio` per clip
    /// — each clip gets its own measured gain — committed as ONE undo step.
    ///
    /// The body sits in this file, beside every other sound command, rather
    /// than in `AudioNormalize.swift`, which is a pure value type with no
    /// `EditorViewController` extension in it.
    ///
    /// The scope is `AudioNormalize.canOffer` — `AudioPane.normalizable`'s
    /// scope exactly, and the same question the validator arm below asks — so a
    /// shape, a silent movie or a NEST picked alongside is simply not asked
    /// about instead of coming back as a refusal the user did not cause. It is
    /// `InspectorTab.hasAudio` and not that alone: a nest carrying anything
    /// audible has audio properties of its own, so `hasAudio` says yes about a
    /// clip the plan flattens and `read` can only refuse. `canOffer` is the one
    /// home of that rule, and the button, this command and this file's
    /// validator arm all ask it, or two of the three would disagree about one
    /// selection.
    ///
    /// Two different things beep, and both are correct. A selection nothing can
    /// be measured in produces no ops, and a second press on an
    /// already-normalised selection produces ops that change nothing: the first
    /// is an empty list and the second an identity edit, and `applyEdit` refuses
    /// both without registering an undo step. The menu is not the place that
    /// explains WHY a clip was skipped; `normalize_clip` reports each reason by
    /// name under `skipped`.
    @objc func normalizeClips(_ sender: Any?) {
        guard let document = document else { return }
        let snapshot = document.editedProject.snapshot
        let ids = selectedClips.filter { AudioNormalize.canOffer($0, in: snapshot) }.map { $0.id }
        guard !ids.isEmpty, let input = AudioNormalize.read(from: document, clips: ids) else {
            NSSound.beep()
            return
        }
        document.applyEdit("Normalize", AudioNormalize.plan(input).ops)
    }

    /// Clip ▸ Synchronize Audio — the menu half of `sync_audio`. The same
    /// `AudioSync.read` + `plan` pair the tool calls; the anchor is SY-2's
    /// rule. The scope is the selection's clips `AudioNormalize.canOffer`
    /// passes, so a title or a nest picked alongside is not asked about. A
    /// refusal beeps and puts every reason at the inspector's foot (spec §11
    /// CI-10); a selection already in sync is no ops and beeps. A drift the
    /// plan corrects is applied here too, as the same `set_speed` in the same
    /// undo step (SY-6); the menu shows no drift figure — the inspector's
    /// speed is what changed.
    @objc func synchronizeAudio(_ sender: Any?) {
        guard let document = document else { return }
        let snapshot = document.editedProject.snapshot
        let ids = selectedClips.filter { AudioNormalize.canOffer($0, in: snapshot) }.map { $0.id }
        guard ids.count >= 2,
              let input = AudioSync.read(from: document, clips: ids, anchor: nil)
        else {
            NSSound.beep()
            return
        }
        switch AudioSync.plan(input) {
        case .refused(let problems):
            NSSound.beep()
            let reason = problems.map { $0.description }.joined(separator: " ")
            NotificationCenter.default.post(
                name: .projectDocumentDidRefuse, object: document,
                userInfo: ["refusal": ReelRefusal(op: "sync_audio", reason: reason)])
        case .planned(_, _, let ops):
            guard !ops.isEmpty else {
                NSSound.beep()
                return
            }
            document.applyEdit("Synchronize Audio", ops)
        }
    }

    /// The menu arms, answered from `validateUserInterfaceItem`'s default
    /// case; nil for any other action.
    func validateAudioAction(_ action: Selector) -> Bool? {
        switch action {
        case #selector(normalizeClips(_:)):
            // Load-bearing: without it Clip ▸ Normalize falls through to the
            // closing `return true` and is live on a selection it could only
            // beep at.
            //
            // It asks the command's own question of the MEMOIZED snapshot, not
            // of the plan: a validator runs on every menu open, and
            // `ReelProject.plan` decodes JSON on every access. The plan is
            // still the honest answer to "does this clip make a sound", and
            // `AudioNormalize.read` asks it — a clip enabled here but with no
            // audio segment is reported under `skipped` rather than silently
            // dropped, which is the right side to be wrong on.
            //
            // `AudioNormalize.canOffer` and not `InspectorTab.hasAudio`: a
            // nest carrying anything audible has audio properties of its own,
            // so `hasAudio` says yes about the one clip `read` can ONLY refuse
            // (the plan flattens a nest, so the clip has no segment of its
            // own). The Audio pane's button asks the same function through
            // `AudioPane.normalizable`, which is what keeps a greyed button
            // and a live menu item from disagreeing about one selection.
            guard let snapshot = document?.editedProject.snapshot else { return false }
            return selectedClips.contains { AudioNormalize.canOffer($0, in: snapshot) }
        case #selector(synchronizeAudio(_:)):
            // Two clips that could play sound, asked of the snapshot for the
            // reason above; `read` and `plan` may still refuse, by name.
            guard let snapshot = document?.editedProject.snapshot else { return false }
            return AudioSync.canOffer(selectedClips, in: snapshot)
        default:
            return nil
        }
    }
}
