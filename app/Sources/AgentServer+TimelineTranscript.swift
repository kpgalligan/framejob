import Foundation

/// `get_timeline_transcript` (road map "creator-jobs" TX1, spec §11 TX-10…
/// TX-13): every heard word of the edited container in timeline order,
/// nested instances included, each with its clip, track, editability and a
/// stable identity, read on this Mac once per media and kept
/// (`TranscriptFill`, TX-12).
///
/// An APP-STATE read, `get_transcript`'s posture: nothing is edited, no undo
/// step, never the network, so no AI-7 row and no key (TX-14). **It runs on
/// the SERVER thread** (`creatorOffMainTools`): the fill blocks for seconds
/// to minutes. The document, the plan, the snapshot, the arguments and each
/// heard media's cached transcript are read in ONE main-thread hop; the
/// assistant's Stop withdraws this call's want from the fill
/// (`AgentLane.shared.callCancel`, AI-16), which cancels a run no other owner
/// wants.
extension AgentServer {

    /// What the main-thread hop read.
    private struct TimelineTranscriptContext {
        let document: ProjectDocument
        let snapshot: ProjectSnapshot
        let window: TranscriptReader.Window?
        let tracks: Set<UInt32>?
        let instances: [TimelineTranscript.Instance]
        let noWords: [TimelineTranscript.NoWords]
        let cloud: [UInt32: TimelineTranscript.MediaWords]
        let records: [UInt32: MediaSnapshot]
        let urls: [UInt32: URL]
        let cacheDir: URL?
        let playhead: Ticks
        let fill: TranscriptFill
    }

    /// `get_timeline_transcript {from?, to?, tracks?, language?}`. Refused,
    /// in order: the window (TR-13's `.empty`, then outside the timeline), an
    /// unknown track by name, the language's spelling, then — only when a
    /// heard media needs this Mac's words — the installed model, and a
    /// failed or cancelled fill with the recogniser's sentence.
    func getTimelineTranscript(_ a: [String: Any]) throws -> String {
        let stop = AgentLane.shared.callCancel  // the assistant's Stop (spec §11 AI-16, TX-13)
        guard !Thread.isMainThread else {
            throw ToolError(
                message: "get_timeline_transcript must run on the server thread — its name is "
                    + "missing from AgentServer.creatorOffMainTools.")
        }
        let context = try onMain { try self.timelineTranscriptContext(a) }
        let wanted = try stringArg(a, "language")
        try Self.checkSpelling(of: wanted)

        // The media the window needs: the playhead's first, then by first start.
        let window = context.window
        let needed = TimelineTranscript.neededMedia(
            context.instances, window: window, playhead: context.playhead)

        var media = context.cloud.filter { needed.contains($0.key) }
        let device = needed.filter { context.cloud[$0] == nil }
        if !device.isEmpty {
            let language = try Self.transcriptionLanguage(wanted)
            media.merge(
                try deviceWords(device, language: language, context: context, stop: stop),
                uniquingKeysWith: { first, _ in first })
        }

        let all = TimelineTranscript.words(
            context.instances, media: media, snapshot: context.snapshot)
        let windowed = window.map { TimelineTranscript.overlapping(all, in: $0) } ?? all
        var notes = TimelineTranscript.sameSpeech(windowed, instances: context.instances)
        let kept = context.tracks.map { tracks in windowed.filter { tracks.contains($0.track) } }
            ?? windowed
        let page = TimelineTranscript.page(kept, fps: context.snapshot.canvas.fps)
        if needed.contains(where: { media[$0]?.fillersReported == false }) {
            notes.append(
                "These words were not transcribed with filler words, so a filler missing here "
                    + "may still be in the audio.")
        }

        var result: [String: Any] = [
            "ok": true,
            "count": page.words.count,
            "words": page.words.map(Self.wordRow),
            "media": needed.compactMap { media[$0] }.map { heard -> [String: Any] in
                var row: [String: Any] = [
                    "media": Int(heard.media), "engine": heard.engine.rawValue,
                    "fillers_reported": heard.fillersReported,
                ]
                if let language = heard.language { row["language"] = language }
                return row
            },
            "no_words": context.noWords.map {
                [
                    "clip": Int($0.clip), "nest_path": $0.nestPath.map { Int($0) },
                    "tag": $0.tag, "reason": $0.reason,
                ] as [String: Any]
            },
            "notes": notes,
        ]
        if let window {
            result["from"] = window.from
            result["to"] = window.to
        }
        if let next = page.nextFrom {
            result["truncated"] = true
            result["next_from"] = next
        }
        return try onMain {
            result["project"] = self.summary(context.document)
            return try self.jsonResult(result)
        }
    }

    /// The one main-thread hop: the document, the edited container's plan
    /// and snapshot, the window and `tracks`, the instances, the clips with
    /// no words and each heard media's cached transcript.
    private func timelineTranscriptContext(_ a: [String: Any]) throws -> TimelineTranscriptContext {
        let document = try target(a)
        let edited = document.editedProject
        let snapshot = edited.snapshot
        let window: TranscriptReader.Window?
        do {
            window = try TimelineTranscript.window(
                from: try optionalTimeArg(a, "from", document),
                to: try optionalTimeArg(a, "to", document), duration: snapshot.duration)
        } catch let error as TranscriptReader.WindowError {
            throw ToolError(message: error.localizedDescription)
        } catch let error as TimelineTranscript.WindowError {
            throw ToolError(message: error.localizedDescription)
        }
        var tracks: Set<UInt32>?
        if let ids = try intsArg(a, "tracks") {
            let scope = try idScope(document)
            tracks = []
            for id in ids {
                guard let track = UInt32(exactly: id), scope.tracks.contains(where: { $0.id == track })
                else {
                    throw ToolError(message: scope.noSuchId("track", UInt32(clamping: id)))
                }
                tracks?.insert(track)
            }
        }
        guard let read = TimelineTranscript.read(document: document) else {
            throw ToolError(message: "The timeline's composition plan could not be read.")
        }
        var cloud: [UInt32: TimelineTranscript.MediaWords] = [:]
        if let cacheDir = read.cacheDir {
            for instance in read.instances {
                let id = instance.job.media
                guard cloud[id] == nil, let record = read.records[id],
                    let words = TimelineTranscript.cloudWords(
                        record, url: instance.job.source, cacheDir: cacheDir)
                else { continue }
                cloud[id] = words
            }
        }
        return TimelineTranscriptContext(
            document: document, snapshot: read.snapshot, window: window, tracks: tracks,
            instances: read.instances, noWords: read.noWords, cloud: cloud, records: read.records,
            urls: read.urls, cacheDir: read.cacheDir, playhead: read.playhead,
            fill: TranscriptFill.fill(for: document))
    }

    /// This Mac's words for each media: a stored whole-file run, else one
    /// read by the fill as this call's want (TX-12).
    private func deviceWords(
        _ ids: [UInt32], language: Transcriber.Language, context: TimelineTranscriptContext,
        stop: AgentCallCancel?
    ) throws -> [UInt32: TimelineTranscript.MediaWords] {
        guard let cacheDir = context.cacheDir else {
            throw ToolError(message: "The project has no cache folder to keep the words in.")
        }
        var out: [UInt32: TimelineTranscript.MediaWords] = [:]
        var items: [TranscriptFill.Item] = []
        for id in ids {
            guard let record = context.records[id], let url = context.urls[id] else { continue }
            guard
                let item = TimelineTranscript.fillItem(
                    record, url: url, cacheDir: cacheDir, language: language)
            else {
                throw ToolError(message: "“\(record.name)” cannot be read.")
            }
            if let words = TimelineTranscript.deviceWords(item) {
                out[id] = words
            } else {
                items.append(item)
            }
        }
        guard !items.isEmpty else { return out }
        let fill = context.fill
        let owner = fill.newOwner()
        fill.want(owner: owner, items: items)
        stop?.onCancel { fill.release(owner: owner) }
        let outcomes = fill.wait(owner: owner)
        fill.release(owner: owner)
        if outcomes.values.contains(.cancelled) {
            throw ToolError(message: Transcriber.TranscribeError.cancelled.localizedDescription)
        }
        for item in items {
            if case .failed(let why)? = outcomes[item.media] { throw ToolError(message: why) }
            guard let words = TimelineTranscript.deviceWords(item) else {
                throw ToolError(
                    message: "What was heard in “\(item.name)” could not be read back from the "
                        + "project's cache.")
            }
            out[item.media] = words
        }
        return out
    }

    static func wordRow(_ word: TimelineTranscript.Word) -> [String: Any] {
        var row: [String: Any] = [
            "text": word.text, "start": word.start, "end": word.end, "clip": Int(word.clip),
            "track": Int(word.track), "media": Int(word.media), "engine": word.engine.rawValue,
            "filler": word.filler, "editable": word.editable,
            "id": [
                "nest_path": word.id.nestPath.map { Int($0) }, "media": Int(word.id.media),
                "source": word.id.source, "k": word.id.k,
            ] as [String: Any],
        ]
        if let speaker = word.speaker { row["speaker"] = speaker }
        if let why = word.why { row["why"] = why }
        return row
    }
}
