import AppKit

/// `record_screen`'s LANDING (camera-recording CR3-0): `awaitGestureEnd`, the
/// wait for a target document's drag to end, and `land`, the two doors a
/// finished recording takes — a document through `editResult`, a new project
/// through `ProjectDocument.untitled(around:)`. A pure move out of
/// `AgentServer+Recording.swift` at the 400-line cap, landed alone before
/// camera + screen grows the tool; nothing in either body changed, and
/// `private` → internal is the whole cost, because a `private` extension
/// member reaches only its own file. What the answer and its refusals say is
/// `AgentServer+RecordingResult.swift` and `+RecordingSentences.swift`.
extension AgentServer {
    // MARK: - The landing

    /// SERVER THREAD. A target document mid-drag is not committed over the
    /// gesture's base handle (`RecordingLanding.placement` refuses by name);
    /// the panel retries from a half-second timer bounded at forty tries,
    /// and this polls `isLiveEditing` through `onMain` at that interval and
    /// bound BY NAME, so the two doors cannot drift. A gesture outlasting
    /// the bound still reaches `placement`'s refusal, which names the file;
    /// a `.newProject` target or a closed document has nothing to wait for.
    func awaitGestureEnd(_ destination: RecordingDestination) {
        for _ in 0..<RecorderPanelController.landingRetryLimit {
            let dragging = onMain { () -> Bool in
                guard case .document(let document) = RecordingLanding.resolve(destination)
                else { return false }
                return document.isLiveEditing
            }
            guard dragging else { return }
            Thread.sleep(forTimeInterval: RecorderPanelController.landingRetryInterval)
        }
    }

    /// MAIN. The two doors: a document through `editResult` (one undo step,
    /// the `created` ids, the scope landing); a new project through
    /// `ProjectDocument.untitled(around:)`, which does everything. Every
    /// throw past this point is `savedButNotAdded`'s: every segment's files
    /// exist. The result is `recordingFields` over the segments plus the ids
    /// each door knows them by (the placement's lists, predicted before the
    /// commit; the new project's snapshot, read by path), and `note` is the
    /// door's sentences in order: `place: false`, a closed target, what the
    /// landing could NOT place (each naming its file), then `resultNotes(result)`.
    /// Answers the document it landed in beside the answer, for
    /// `landAndEnhance`.
    func land(_ result: RecordingResult, place: Bool) throws
        -> (answer: String, document: ProjectDocument)
    {
        var fields: [String: Any]
        var notes: [String] = []
        switch RecordingLanding.resolve(result.choice.destination) {
        case .document(let document):
            let placement: RecordingLanding.Placement
            do {
                placement = try RecordingLanding.placement(result, in: document, place: place)
            } catch {
                throw Self.savedButNotAdded(result, error)
            }
            fields = Self.recordingFields(
                result, ids: Self.documentIds(result, placement: placement),
                leftOutIds: Self.documentLeftOutIds(result, placement: placement))
            fields["landed"] = "document"
            if !place {
                notes.append(
                    "The recording is in the project's media list but not on the timeline — "
                        + "place it with add_clip {track, media, at}.")
            }
            notes.append(contentsOf: placement.notes)
            notes.append(contentsOf: Self.resultNotes(result))
            if !notes.isEmpty { fields["note"] = notes.joined(separator: " ") }
            let answer: String
            do {
                answer = try editResult(document, RecordingLanding.actionName, placement.ops, fields)
            } catch {
                throw Self.savedButNotAdded(result, error)
            }
            // `editResult` commits and does not build caches; `importMedia`
            // calls this after its own commit for the same reason.
            document.generateCaches()
            return (answer, document)
        case .newProject:
            let document: ProjectDocument
            var landingNotes: [String] = []
            do {
                let landing = try ProjectDocument.untitled(around: result)
                document = landing.document
                landingNotes = landing.notes
            } catch {
                throw Self.savedButNotAdded(result, error)
            }
            fields = Self.recordingFields(
                result, ids: Self.newProjectIds(result, in: document),
                leftOutIds: Self.newProjectLeftOutIds(result, in: document))
            fields["landed"] = "new_project"
            if result.choice.destination != .newProject {
                notes.append(
                    "The target document closed while the recording ran, so it opened as a "
                        + "new project instead.")
            }
            if !place {
                notes.append(
                    "place: false has no meaning for a new project — the "
                        + (result.isVoiceOver ? "voice-over" : "picture") + " IS the "
                        + "document, so its clips are on the timeline, one per segment and "
                        + "the first at 0.")
            }
            notes.append(contentsOf: landingNotes)
            notes.append(contentsOf: Self.resultNotes(result))
            if !notes.isEmpty { fields["note"] = notes.joined(separator: " ") }
            fields["ok"] = true
            fields["project"] = summary(document)
            return (try jsonResult(fields), document)
        }
    }

    /// SERVER THREAD. `land` on main; then, when the choice asks for it,
    /// Enhance Voice over the recording's voice clips as its own step (spec
    /// §11 AU-68 (f)): `decide` polled through `onMain` every
    /// `RecordingEnhance.checkInterval`, then `enhance_voice`'s own body at
    /// its default target (a tool reads no `UserDefaults`). The answer is
    /// `land`'s with `enhance` (that body's answer) or `enhance_error`, and
    /// `project` read again.
    func landAndEnhance(_ result: RecordingResult, place: Bool) throws -> String {
        let stop = AgentLane.shared.callCancel
        let (answer, document) = try onMain { try self.land(result, place: place) }
        guard result.choice.enhanceMicrophone else { return answer }
        let (clips, scope) = onMain {
            (RecordingEnhance.voiceClips(of: result, in: document), document.scope)
        }
        let started = Date()
        var step = RecordingEnhance.Step.wait
        while step == .wait, stop?.isCancelled != true {
            step = onMain { () -> RecordingEnhance.Step in
                let present = RecordingEnhance.present(clips, in: document)
                return RecordingEnhance.decide(
                    clips: present, analysed: RecordingEnhance.isAnalysed(present, in: document),
                    busy: RecordingEnhance.isBusy(document, scope: scope),
                    elapsed: Date().timeIntervalSince(started))
            }
            if step == .wait { Thread.sleep(forTimeInterval: RecordingEnhance.checkInterval) }
        }
        var fields = Self.resultObject(answer) ?? [:]
        switch step {
        case .enhance(let ids):
            do {
                let enhanced = try enhanceVoice(
                    document: document, clips: ids, targetLUFS: AudioNormalize.defaultTargetLUFS)
                fields["enhance"] = Self.resultObject(enhanced) ?? enhanced
            } catch let error as ToolError {
                fields["enhance_error"] = error.message
            }
        case .drop:
            fields["enhance_error"] = RecordingEnhance.noVoiceSentence
        case .giveUp:
            fields["enhance_error"] = RecordingEnhance.notReadyToolSentence
        case .wait:
            fields["enhance_error"] =
                "record_screen was stopped while the microphone's sound was being analysed, so "
                + "Enhance Voice did not run."
        }
        fields["project"] = onMain { self.summary(document) }
        return try jsonResult(fields)
    }

    /// The object a `jsonResult` envelope's text holds, nil for anything else.
    private static func resultObject(_ envelope: String) -> [String: Any]? {
        guard
            let call = (try? JSONSerialization.jsonObject(with: Data(envelope.utf8)))
                as? [String: Any],
            let content = call["content"] as? [[String: Any]],
            let text = content.first?["text"] as? String
        else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }
}
