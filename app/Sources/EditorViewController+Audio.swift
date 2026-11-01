import AppKit

/// The Clip menu's sound commands: Normalize (road map 2 phase 5c), moved
/// here whole out of `EditorViewController.swift` with its validator arm, as
/// that body's own comment asked a second sound command to do, and
/// Synchronize Audio (road map "audio-sync", AS-1; spec §11 SY-1..SY-5), with
/// its Weak match sheet (road map "audio-sync-2", AS-3; SY-18, SY-19) and its
/// Synchronizing Audio sheet (AS-4; SY-22).
extension EditorViewController {

    /// Clip ▸ Normalize (road map 2 phase 5c) — the menu half of the Audio
    /// section's Normalize button. It follows the mode chosen there
    /// (`NormalizeChoice`, spec §11 AU-15): Peak, or Loudness at its target;
    /// the title stays "Normalize".
    ///
    /// **Not a line of the arithmetic is here**, which is the whole point of
    /// `AudioNormalize` being a value type: this reads no peaks and derives no
    /// gain, it calls the same `read` + `plan` pair (through `AudioMeasureDoor`)
    /// `AudioPane.normalize` and the agent's `normalize_clip` call, so the three cannot mean different
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
    ///
    /// The press is `AudioMeasureDoor.press` (spec §11 AU-64, AU-65), the
    /// button's body: Peak at once; Loudness at once when no clip has a stage
    /// the loudness cache leaves out, else under the Measuring Sound sheet.
    @objc func normalizeClips(_ sender: Any?) {
        guard let document = document else { return }
        let snapshot = document.editedProject.snapshot
        let ids = selectedClips.filter { AudioNormalize.canOffer($0, in: snapshot) }.map { $0.id }
        AudioMeasureDoor.press(.normalize, document: document, clips: ids, window: view.window)
    }

    /// Clip ▸ Enhance Voice (road map "audio" AP6, spec §11 AU-60, AU-65) —
    /// the menu half of the Volume section's Enhance Voice button, through
    /// the same `AudioMeasureDoor.press`: the clips `AudioNormalize.canOffer`
    /// passes, measured through their chosen settings under the Measuring
    /// Sound sheet (AU-64), committed at the Normalize row's Target as ONE
    /// undo step. Nothing to enhance and a second press beep, Normalize's two
    /// answers; the tool reports each skip by name.
    @objc func enhanceVoice(_ sender: Any?) {
        guard let document = document else { return }
        let snapshot = document.editedProject.snapshot
        let ids = selectedClips.filter { AudioNormalize.canOffer($0, in: snapshot) }.map { $0.id }
        AudioMeasureDoor.press(.enhanceVoice, document: document, clips: ids, window: view.window)
    }

    /// Clip ▸ Match Audio… (road map "audio" AP12, spec §11 AU-121, AU-128):
    /// the Match Audio sheet over the selected clips `AudioNormalize.canOffer`
    /// passes, then, from its hand-back, `AudioMeasureDoor.pressMatch` with
    /// the chosen reference and the other clips — the same `AudioMatch` read
    /// and plan and `AudioMatchRun` `match_audio` waits on. Under two clips,
    /// no window or a sheet already up beep.
    @objc func matchAudio(_ sender: Any?) {
        guard let document = document else { return }
        let snapshot = document.editedProject.snapshot
        let candidates = AudioMatchSheetController.candidates(selectedClips, in: snapshot)
        guard candidates.count >= 2, let window = view.window, window.attachedSheet == nil else {
            NSSound.beep()
            return
        }
        let ids = candidates.map(\.clip)
        presentAsSheet(
            AudioMatchSheetController(candidates: candidates) { [weak self, weak document] choice in
                guard let self, let document else { return }
                AudioMeasureDoor.pressMatch(
                    document: document, reference: choice.reference,
                    clips: ids.filter { $0 != choice.reference }, loudness: choice.loudness,
                    eq: choice.eq, window: self.view.window)
            })
    }

    /// Clip ▸ Synchronize Audio — the menu half of `sync_audio`. The same
    /// `AudioSync.read` + `plan` pair the tool calls; the anchor is SY-2's
    /// rule. The scope is the selection's clips `AudioNormalize.canOffer`
    /// passes, so a title or a nest picked alongside is not asked about. A
    /// refusal beeps and puts every reason at the inspector's foot (spec §11
    /// CI-10); a selection already in sync is no ops and beeps. A drift the
    /// plan corrects is applied here too, as the same `set_speed` in the same
    /// undo step (SY-6); the menu shows no drift figure — the inspector's
    /// speed is what changed. A plan with WEAK moves (SY-18,
    /// `AudioSync.weakMoves`, the tool's own test) is asked about first in
    /// the Weak match sheet (SY-19). `read` runs here, on the main thread;
    /// `plan` runs off it under the Synchronizing Audio sheet (SY-22), and
    /// its answer is applied in `finishSynchronizeAudio` only to the project
    /// and scope `read` took. With no window or a sheet already up it beeps.
    @objc func synchronizeAudio(_ sender: Any?) {
        guard let document = document else { return }
        let snapshot = document.editedProject.snapshot
        let ids = selectedClips.filter { AudioNormalize.canOffer($0, in: snapshot) }.map { $0.id }
        guard ids.count >= 2,
              let input = AudioSync.read(from: document, clips: ids, anchor: nil),
              let window = view.window, window.attachedSheet == nil
        else {
            NSSound.beep()
            return
        }
        let asked = document.project
        let scope = document.scope
        presentAsSheet(
            AudioSyncSheetController(input: input) { [weak self, weak document] plan in
                guard let self, let document else { return }
                self.finishSynchronizeAudio(plan, asked: asked, scope: scope, document: document)
            })
    }

    /// The Synchronizing Audio sheet's answer (SY-22): refused, with a beep
    /// and a sentence at the inspector's foot, when the document's project or
    /// scope is no longer the one `read` took (the weak sheet's own test);
    /// otherwise what the menu did before the plan moved off main, with
    /// `performGroupedEdit` for `applyEdit` — a queue's completion is not an
    /// AppKit event (app/CLAUDE.md's undo pitfall).
    private func finishSynchronizeAudio(
        _ plan: AudioSync.Plan, asked: ReelProject, scope: UInt32?, document: ProjectDocument
    ) {
        guard document.project === asked, document.scope == scope else {
            NSSound.beep()
            NotificationCenter.default.post(
                name: .projectDocumentDidRefuse, object: document,
                userInfo: [
                    "refusal": ReelRefusal(
                        op: "sync_audio",
                        reason: "the project changed while Synchronize Audio was matching, so "
                            + "nothing moved. Choose Synchronize Audio again.")
                ])
            return
        }
        switch plan {
        case .refused(let problems):
            NSSound.beep()
            let reason = problems.map { $0.description }.joined(separator: " ")
            NotificationCenter.default.post(
                name: .projectDocumentDidRefuse, object: document,
                userInfo: ["refusal": ReelRefusal(op: "sync_audio", reason: reason)])
        case .planned(let anchor, let synced, let ops):
            guard !ops.isEmpty else {
                NSSound.beep()
                return
            }
            let weak = AudioSync.weakMoves(synced)
            guard !weak.isEmpty else {
                document.performGroupedEdit("Synchronize Audio", ops)
                return
            }
            guard let window = view.window, window.attachedSheet == nil else {
                NSSound.beep()
                return
            }
            askToApplyWeakMatch(weak, anchor: anchor, ops: ops, document: document, on: window)
        }
    }

    /// The Weak match sheet (SY-19): Apply (the default) commits `ops` as one
    /// grouped step — a sheet's completion is not an AppKit event
    /// (app/CLAUDE.md's undo pitfall) — but only on the project handle and
    /// scope it was asked about; anything else beeps and says so at the
    /// inspector's foot. Cancel (Escape) changes nothing.
    private func askToApplyWeakMatch(
        _ weak: [AudioSync.Synced], anchor: UInt32, ops: [ReelOp],
        document: ProjectDocument, on window: NSWindow
    ) {
        let snapshot = document.editedProject.snapshot
        var names: [UInt32: String] = [:]
        for id in [anchor] + weak.map(\.clip) {
            if let clip = snapshot.clip(id) { names[id] = snapshot.name(of: clip) }
        }
        let text = AudioSync.weakQuestion(weak, anchor: anchor, names: names)
        let asked = document.project
        let scope = document.scope
        let alert = NSAlert()
        alert.messageText = text.message
        alert.informativeText = text.detail
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak document] response in
            guard response == .alertFirstButtonReturn, let document else { return }
            guard document.project === asked, document.scope == scope else {
                NSSound.beep()
                NotificationCenter.default.post(
                    name: .projectDocumentDidRefuse, object: document,
                    userInfo: [
                        "refusal": ReelRefusal(
                            op: "sync_audio",
                            reason: "the project changed while the weak match was being asked "
                                + "about, so nothing moved. Choose Synchronize Audio again.")
                    ])
                return
            }
            document.performGroupedEdit("Synchronize Audio", ops)
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
        case #selector(enhanceVoice(_:)):
            // Normalize's question, for Normalize's reasons (AU-60): the
            // button asks it through `AudioPane.normalizable`.
            guard let snapshot = document?.editedProject.snapshot else { return false }
            return selectedClips.contains { AudioNormalize.canOffer($0, in: snapshot) }
        case #selector(matchAudio(_:)):
            // Two clips Normalize could measure (AU-121): one the reference.
            guard let snapshot = document?.editedProject.snapshot else { return false }
            return selectedClips.filter { AudioNormalize.canOffer($0, in: snapshot) }.count >= 2
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
