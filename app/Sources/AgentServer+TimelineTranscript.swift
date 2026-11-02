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
        var order: [(media: UInt32, first: Ticks, underPlayhead: Bool)] = []
        for instance in context.instances {
            let start = instance.segment.start
            let end = start + instance.segment.duration
            if let window, !(start < window.to && end > window.from) { continue }
            let under = start <= context.playhead && context.playhead < end
            if let at = order.firstIndex(where: { $0.media == instance.job.media }) {
                order[at].first = min(order[at].first, start)
                order[at].underPlayhead = order[at].underPlayhead || under
            } else {
                order.append((instance.job.media, start, under))
            }
        }
        order.sort { ($0.underPlayhead ? 0 : 1, $0.first, $0.media) < ($1.underPlayhead ? 0 : 1, $1.first, $1.media) }
        let needed = order.map(\.media)

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
        let urls = document.mediaURLs()
        var scoped: [UInt32: ReelProject] = [:]
        guard let plan = edited.plan ?? Self.noPlan else {
            throw ToolError(message: "The timeline's composition plan could not be read.")
        }
        let read = TimelineTranscript.read(
            plan: plan, snapshot: snapshot, urls: urls,
            maps: { clip, nestPath in
                guard !nestPath.isEmpty else { return edited.sourceMap(clip) }
                guard let nest = snapshot.nests.first(where: { $0.clips.contains { $0.id == clip } })
                else { return nil }
                if scoped[nest.id] == nil { scoped[nest.id] = document.project.scoped(nest.id) }
                return scoped[nest.id]?.sourceMap(clip)
            })
        let cacheDir = document.cacheDirectory
        var cloud: [UInt32: TimelineTranscript.MediaWords] = [:]
        var records: [UInt32: MediaSnapshot] = [:]
        for instance in read.instances {
            let id = instance.job.media
            guard records[id] == nil, let record = snapshot.media(id) else { continue }
            records[id] = record
            guard let cacheDir,
                let cached = TranscriptReader.cached(for: record, url: instance.job.source, in: cacheDir)
            else { continue }
            cloud[id] = TimelineTranscript.MediaWords(
                media: id, engine: .assemblyai, language: cached.file.header.languageCode,
                fillersReported: cached.fillersReported,
                words: TimelineTranscript.sourceWords(cloud: cached.file))
        }
        return TimelineTranscriptContext(
            document: document, snapshot: snapshot, window: window, tracks: tracks,
            instances: read.instances, noWords: read.noWords, cloud: cloud, records: records,
            urls: urls, cacheDir: cacheDir, playhead: document.playhead,
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
                let stamp = DeviceTranscriptCache.currentStamp(
                    record, url: url, language: language.identifier)
            else {
                throw ToolError(message: "“\(record.name)” cannot be read.")
            }
            let item = TranscriptFill.Item(
                media: id, url: url, name: record.name, duration: record.duration, stamp: stamp,
                cacheDir: cacheDir, language: language, record: record)
            if let heard = DeviceTranscriptCache.lookup(
                item.job, media: id, stamp: stamp, in: cacheDir)
            {
                out[id] = Self.deviceMediaWords(id, heard, language)
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
            guard
                let heard = DeviceTranscriptCache.lookup(
                    item.job, media: item.media, stamp: item.stamp, in: cacheDir)
            else {
                throw ToolError(
                    message: "What was heard in “\(item.name)” could not be read back from the "
                        + "project's cache.")
            }
            out[item.media] = Self.deviceMediaWords(item.media, heard, language)
        }
        return out
    }

    /// A plan with nothing in it, for a container the core gave none.
    private static let noPlan = ReelJSON.decode(CompositionPlan.self, from: "{}")

    private static func deviceMediaWords(
        _ id: UInt32, _ heard: DeviceTranscriptCache.Heard, _ language: Transcriber.Language
    ) -> TimelineTranscript.MediaWords {
        TimelineTranscript.MediaWords(
            media: id, engine: .apple, language: language.identifier, fillersReported: false,
            words: TimelineTranscript.sourceWords(device: heard))
    }

    private static func wordRow(_ word: TimelineTranscript.Word) -> [String: Any] {
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
