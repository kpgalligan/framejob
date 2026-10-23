import AppKit

/// The agent's filler tools: `detect_fillers`, the read half of Clip ▸ Remove
/// Filler Words… (road map "cut-by-transcript" CT-2, CT-3) and the agent's
/// path to the cut (spec §11 TR-4, TR-9), and `transcribe_for_fillers`, the
/// mirror of that sheet's Transcribe button (TR-10).
///
/// `detect_fillers` is an APP-STATE tool, not an op — it changes nothing and
/// registers no undo step, as `detect_silence` does
/// (`AgentServer+Silence.swift`, whose posture this follows). The words are
/// a Swift cache (`cache/transcripts/`), so an agent that could only call
/// `ripple_delete_ranges` would have nothing to cut by; this answers the
/// ranges and `ripple_delete_ranges` makes the one undo step.
///
/// It stays on the MAIN thread, out of `AgentServer.offMainTools`, for
/// `detect_silence`'s reason: reading a few cached transcripts and one pass
/// of arithmetic waits on nothing and has no completion to deliver. It never
/// makes a network call: only a cached AssemblyAI transcript that asked for
/// filler words is read (TR-7). `transcribe_for_fillers` is the other
/// posture: a paid upload, off main (`AgentServer.offMainTools`), always
/// withheld from the assistant (AI-7 as TR-10 amends it).
extension AgentServer {

    /// `detect_fillers` — the read half of Clip ▸ Remove Filler Words…, and
    /// the agent's path. Nothing is edited: feed `ranges` to
    /// `ripple_delete_ranges` to make the cut.
    func detectFillers(_ a: [String: Any]) throws -> String {
        let document = try target(a)
        let clips = try optionalClipsArg(a, "clips", document)
        let input = FillerDetector.read(from: document, clips: clips)
        let outcome = FillerDetector.detect(input)

        var result: [String: Any] = [
            "ok": true,
            "ranges": outcome.spans.map { [$0.start, $0.end] },
            "count": outcome.spans.count,
            "removes": outcome.removed,
            "scope": outcome.scope.rawValue,
            "clips": outcome.clips.map { Int($0) },
            "fillers": outcome.candidates.map { candidate -> [String: Any] in
                [
                    "clip": Int(candidate.clip), "words": candidate.words,
                    "range": [candidate.span.start, candidate.span.end],
                ]
            },
            "dropped": outcome.dropped.map { drop -> [String: Any] in
                ["clip": Int(drop.clip), "words": drop.words, "reason": Self.sentence(drop.reason)]
            },
            "needs_transcript": outcome.needsTranscript.map { Int($0) },
            "locked": outcome.locked.map { Int($0) },
        ]
        if clips != nil, !outcome.skipped.isEmpty {
            result["skipped"] = outcome.skipped.map { $0.description }
        }
        var notes: [String] = []
        if outcome.clips.isEmpty, outcome.needsTranscript.isEmpty, outcome.locked.isEmpty {
            notes.append("Nothing in scope plays speech from a media file, so nothing was read.")
        }
        if !outcome.needsTranscript.isEmpty {
            notes.append(
                "Media \(Self.fillerList(outcome.needsTranscript)) has no transcript made with "
                    + "filler words, so its fillers cannot be found: filler removal needs an "
                    + "AssemblyAI transcript (spec §11 TR-7). transcribe_for_fillers makes "
                    + "one for a media, keeping its earlier request (a paid upload).")
        }
        if !outcome.locked.isEmpty {
            notes.append(
                "Clip \(Self.fillerList(outcome.locked)) is on a locked track, which "
                    + "ripple_delete_ranges neither cuts nor moves, so its fillers were not read.")
        }
        if !notes.isEmpty { result["note"] = notes.joined(separator: " ") }
        result["project"] = summary(document)
        return try jsonResult(result)
    }

    /// `transcribe_for_fillers` — the Transcribe button of Clip ▸ Remove
    /// Filler Words…' rows (`FillerSheetController+Transcribe.swift`): one
    /// media re-transcribed with AssemblyAI, with its previous request plus
    /// filler words (`FillerTranscription`, TR-10). Only the media's
    /// transcript cache is written: no caption is placed, no undo step made.
    ///
    /// Refused in this order, every step above the network: the media id,
    /// a document with nowhere to keep the cache, a media no clip plays from
    /// its file, then the credential; a media that already has a filler
    /// transcript answers with no request, between the last two.
    func transcribeForFillers(_ a: [String: Any]) throws -> String {
        guard !Thread.isMainThread else {
            throw ToolError(
                message: "transcribe_for_fillers must run on the server thread — its name is "
                    + "missing from AgentServer.offMainTools.")
        }
        struct Context {
            let document: ProjectDocument
            let media: UInt32
            let cache: URL
            let jobs: [Transcriber.Job]
            let records: [UInt32: MediaSnapshot]
            let ready: Bool
            let frame: Ticks
            let canvas: CGSize
        }
        let context = try onMain { () -> Context in
            let document = try self.target(a)
            let media = try self.mediaArg(a, "media", document)
            guard let cache = document.cacheDirectory else {
                throw ToolError(
                    message: "This document has nowhere to keep its transcript cache, so it "
                        + "cannot be transcribed with AssemblyAI. Save it first.")
            }
            let snapshot = document.editedProject.snapshot
            let jobs = FillerTranscription.jobs(
                for: media.id, in: snapshot, urls: document.mediaURLs())
            guard let first = jobs.first else {
                throw ToolError(
                    message: "No clip in this timeline plays media \(media.id) from its file, so "
                        + "it cannot be transcribed.")
            }
            var records: [UInt32: MediaSnapshot] = [:]
            for entry in snapshot.media { records[entry.id] = entry }
            return Context(
                document: document, media: media.id, cache: cache, jobs: jobs, records: records,
                ready: Self.fillersReady(media, url: first.source, cache: cache),
                frame: max(snapshot.canvas.fps.frameDuration, 1),
                canvas: CGSize(width: snapshot.canvas.width, height: snapshot.canvas.height))
        }
        let options = FillerTranscription.options(
            for: MediaTranscript.readStamp(for: context.media, in: context.cache))

        var result: [String: Any]
        if context.ready {
            var report = CloudTranscriber.Report()
            report.cached = [context.media]
            result = Self.cloudFields(
                report, code: options.languageCode, endpoint: nil,
                notes: [
                    "Media \(context.media) already has a transcript made with filler words, so "
                        + "nothing was uploaded."
                ])
            result["ready"] = true
        } else {
            guard
                let credential = AssemblyAIConfiguration.credential(
                    store: AssemblyAIConfiguration.store())
            else {
                throw ToolError(
                    message: CloudTranscriber.AccessError.credentialRequired.localizedDescription)
            }
            let client: AssemblyAIClient
            do {
                client = AssemblyAIClient(
                    base: try AssemblyAIConfiguration.baseURL(), credential: credential)
            } catch {
                throw ToolError(message: error.localizedDescription)
            }
            let transcriber = CloudTranscriber(
                client: client, cacheDirectory: context.cache, media: context.records)
            do {
                _ = try transcriber.transcribe(
                    context.jobs, options: options, refresh: FillerTranscription.refresh,
                    frame: context.frame,
                    pages: CaptionPages.Request(style: .subtitles, canvas: context.canvas),
                    cancel: Transcriber.CancelToken())
            } catch {
                throw ToolError(message: Self.cloudFailure(error, report: transcriber.report))
            }
            result = Self.cloudFields(
                transcriber.report, code: options.languageCode, endpoint: client.base.host,
                notes: [])
        }
        return try onMain {
            if !context.ready {
                // Asked again: the run's answer is what the cache holds now.
                let media = context.document.editedProject.snapshot.media(context.media)
                result["ready"] = media.map {
                    Self.fillersReady($0, url: context.jobs[0].source, cache: context.cache)
                } ?? false
            }
            result["ok"] = true
            result["media"] = Int(context.media)
            result["project"] = self.summary(context.document)
            return try self.jsonResult(result)
        }
    }

    /// Whether the media now has a transcript `FillerDetector` reads.
    private static func fillersReady(_ media: MediaSnapshot, url: URL, cache: URL) -> Bool {
        FillerDetector.fillersFile(for: media, url: url, in: cache) != nil
    }

    /// A drop reason as the answer's sentence.
    private static func sentence(_ reason: FillerDetector.DropReason) -> String {
        switch reason {
        case .tooShort:
            return "too short to cut once its edges are on the 32 ms grid and the frame grid"
        case .overlapsWord(let clip, let text):
            return "it overlaps \"\(text)\" in clip \(clip)"
        case .nest(let clip):
            return "it crosses nest clip \(clip), which a cut must not split"
        case .transition:
            return "it crosses a transition"
        }
    }

    /// "3, 7, 9".
    private static func fillerList(_ ids: [UInt32]) -> String {
        ids.map { String($0) }.joined(separator: ", ")
    }
}
