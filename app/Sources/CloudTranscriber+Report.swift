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
            return warnings
        }
    }

}
