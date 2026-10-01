import Foundation

/// The cloud run result and its shared cleanup wording.
extension CloudTranscriber {

    /// Everything a caller may want to SAY about a run that the `Outcome`
    /// has no room for — which media were uploaded and what AssemblyAI said
    /// about each, which were served from the cache, and what the janitor
    /// managed.
    ///
    /// It is beside the outcome rather than inside it because `Outcome` is
    /// the shape BOTH engines answer and the on-device one has nothing to
    /// put in any of these fields. The tool reads it for its result keys and
    /// c1-chrome's report card reads it for its lines.
    struct Report: Equatable {

        /// One media this run sent to AssemblyAI, and what came back.
        struct Uploaded: Equatable {
            let media: UInt32
            /// R6-8: which model actually ran, so a fallback is reported.
            let speechModelUsed: String?
            let languageCode: String?
            /// Set when the language was DETECTED, not when it was named.
            let languageConfidence: Double?
            /// Seconds as AssemblyAI reported them — what was billed.
            let audioSeconds: Int
            let format: Transcriber.UploadFormat
            /// Whether this fetched transcript's initial JSON write landed.
            let transcriptWritten: Bool
            /// Whether the marker landed. Always false when
            /// `transcriptWritten` is: the marker only follows its file.
            let stampWritten: Bool
            /// Whether the remote transcript is confirmed gone (R6-4).
            let remoteDeleted: Bool
        }

        var uploaded: [Uploaded] = []
        /// Media served from `cache/transcripts/` with no request at all.
        var cached: [UInt32] = []
        /// Media whose earlier transcript the janitor deleted this run.
        var janitorDeleted: [UInt32] = []
        /// Media whose earlier transcript the janitor could NOT delete.
        var janitorFailed: [UInt32] = []
        /// Pending remote deletes retained because a keyless run sent no requests.
        var janitorDeferred: [UInt32] = []
        /// R6-11: in `janitorFailed` AND this run would otherwise have
        /// fetched them. A held media is in neither `uploaded` nor `cached`
        /// and its clips are reported as problems: its cache file is the one
        /// record of an id we still have to delete, and a fetch would
        /// overwrite it.
        var held: [UInt32] = []
        /// Media whose transcript was refused after AssemblyAI made it and
        /// whose DELETE answered `failed`. No file holds its id, so it is
        /// owed with no retry (R6-20).
        var refusedUndeleted: [UInt32] = []

        /// What was billed: every uploaded media's `audioSeconds`, the one
        /// reducer `AgentServer`'s bill sentence and its `audio_seconds` key
        /// both read.
        ///
        /// SATURATING, because every term is the SERVER's own
        /// `audio_duration` and `+` traps: two media answered
        /// `9223372036854775807` killed the whole app after both had been
        /// uploaded and billed (the reader review, §10.13 R1·1). Each term is
        /// floored at 0 first, so the sum only grows and an overflow can only
        /// be upward: `Int.max` is sticky, and a later negative term cannot
        /// pull a saturated total back down (#187, item 4).
        var billedSeconds: Int {
            uploaded.reduce(0) { sum, row in
                let (total, overflowed) = sum.addingReportingOverflow(max(0, row.audioSeconds))
                return overflowed ? Int.max : total
            }
        }

        /// One sentence per uploaded media whose marker did not land, in
        /// `uploaded` order (#187, item 2).
        ///
        /// It states only what `fetch` knows and promises nothing about the
        /// next run: on a `refresh` run over a current cache an older file
        /// and marker equal to this stamp survive the failed write and are
        /// served next time — the rule `AgentServer.billed`'s doc records
        /// (issue #29).
        func cacheWarnings(name: (UInt32) -> String) -> [String] {
            uploaded.filter { !$0.stampWritten }.map {
                "The transcript of \(name($0.media)) could not be kept in the project for reuse."
            }
        }

        /// Cleanup still owed, in stable per-media order. An ID can be
        /// retried only when its transcript JSON was saved in the project.
        func deletionWarnings(name: (UInt32) -> String) -> [String] {
            var seen: Set<UInt32> = []
            var warnings: [String] = []
            func append(_ id: UInt32, written: Bool) {
                guard seen.insert(id).inserted else { return }
                let target = name(id)
                var warning: String
                if written {
                    warning = "AssemblyAI has not confirmed deleting the transcript of \(target); "
                        + "it will be retried at the next run with an API key."
                } else {
                    warning = "AssemblyAI has not confirmed deleting the transcript of \(target). "
                        + "Its transcript could not be saved in the project, so Reelcut cannot "
                        + "retry deleting it automatically. Delete it in your AssemblyAI dashboard."
                }
                if held.contains(id) { warning += " It was not uploaded again in this run." }
                warnings.append(warning)
            }
            for id in janitorFailed { append(id, written: true) }
            for id in janitorDeferred where seen.insert(id).inserted {
                warnings.append(
                    "AssemblyAI has not confirmed deleting the transcript of \(name(id)); "
                        + "cleanup was deferred because no API key is set. Its deletion ID is "
                        + "retained in the project; a later run with a key for the originating "
                        + "account and region will retry deletion only if that ID is safe to send.")
            }
            for row in uploaded where !row.remoteDeleted {
                append(row.media, written: row.transcriptWritten)
            }
            for id in refusedUndeleted { append(id, written: false) }
            return warnings
        }
    }

}
