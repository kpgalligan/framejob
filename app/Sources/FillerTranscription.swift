import Foundation

/// Remove Filler Words' re-transcribe (road map "cut-by-transcript" CT-3, spec
/// §11 TR-2, TR-7, TR-10): the request, the jobs and the estimate one press
/// of the sheet's Transcribe button sends for one media, shared by the sheet
/// (`FillerSheetController+Transcribe.swift`) and its mirror,
/// `transcribe_for_fillers` (`AgentServer+Fillers.swift`), so the two cannot
/// send different requests or quote different prices.
///
/// It holds no document. The jobs come from a snapshot and its media URLs,
/// and the estimate from a cache directory, all passed by value — which is
/// what lets the tool read them in one main-thread hop and run off main.
///
/// **TR-10's request.** The media's PREVIOUS request is kept — the marker's
/// language, speaker labels and vocabulary — so the filler transcript is the
/// same transcript as before with the fillers in it; the shipped models,
/// `disfluencies: true` and `refresh: true` are added. With no marker it is
/// detection, no speakers and no vocabulary. `refresh` is what makes a media
/// whose caption transcript is current upload again: `CloudEstimate.fate`
/// and `CloudTranscriber.transcribe` both judge currency for `.captions`,
/// which ignores `disfluencies` (TR-2).
enum FillerTranscription {

    /// Always on: a media in the sheet's list has a transcript that serves
    /// captions or none, and either way it must be fetched again.
    static let refresh = true

    /// The marker's request with fillers asked for, or detection with none.
    static func options(for marker: TranscriptStamp?) -> TranscriptOptions {
        TranscriptOptions(
            speechModels: TranscriptOptions.shippedModels,
            languageCode: marker?.languageCode,
            speakerLabels: marker?.speakerLabels ?? false,
            keytermsPrompt: marker?.keytermsPrompt ?? [],
            disfluencies: true)
    }

    /// `Transcriber.jobs` over the snapshot's clips that play `media`; the
    /// clips it refuses (a reversed one, one whose audio is off, a missing
    /// file) are left out, as a caption run leaves them.
    static func jobs(
        for media: UInt32, in snapshot: ProjectSnapshot, urls: [UInt32: URL]
    ) -> [Transcriber.Job] {
        let clips = snapshot.clips.filter { clip in
            guard case .media(let id, _, _) = clip.source else { return false }
            return id == media
        }
        return Transcriber.jobs(for: clips, in: snapshot, urls: urls).jobs
    }

    /// What one press would upload and cost, by `CloudEstimate`'s own rules
    /// over the same request the run sends; nil when there is nothing to run.
    static func estimate(
        jobs: [Transcriber.Job], media: [UInt32: MediaSnapshot], cacheDirectory: URL
    ) -> CloudEstimate? {
        guard !jobs.isEmpty else { return nil }
        let facts = CloudEstimate.facts(jobs: jobs, media: media, cacheDirectory: cacheDirectory)
        return CloudEstimate(
            facts: facts, options: options(for: facts.first?.marker), refresh: refresh)
    }
}
