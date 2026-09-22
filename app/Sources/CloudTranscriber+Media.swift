import Foundation

/// The two halves of a cloud run that are about ONE media file: the janitor,
/// which is the run's first act, and the round trip, which is everything
/// between "this media is not cached" and "its words are on disk".
///
/// They are here rather than in `CloudTranscriber.swift` because that file
/// holds the run's SHAPE — the janitor, the grouping, the classification, the
/// per-job derivation and the two closing throws — and a reader following
/// that shape does not need the header's twelve fields or the order of the
/// five calls in front of them. Both files are under the 400-line cap a new
/// file has (app/CLAUDE.md, road map 6 §5h).
extension CloudTranscriber {

    /// Why one media could not be sent, in a sentence with no prefix on it.
    ///
    /// `Transcriber.TranscribeError.failed` would wrap this in "The
    /// transcription failed: ", which is true of the run and not of the
    /// media, and the refusal has to name the FILE and the limit — road map
    /// 6 §5g puts the ten-hour refusal above the network for exactly that
    /// reason: it is knowable before a byte is extracted, let alone sent.
    enum MediaError: LocalizedError, Equatable {
        case tooLong(String)

        var errorDescription: String? {
            switch self {
            case .tooLong(let name):
                return "“\(name)” is longer than AssemblyAI's 10-hour limit for one file."
            }
        }
    }

    // MARK: - The janitor

    /// R6-4's first act: every cached transcript whose remote copy this app
    /// has not managed to delete gets its DELETE retried, best effort, on
    /// `deleteTimeout` each.
    ///
    /// A success rewrites that one flag and nothing else —
    /// `MediaTranscript.File`'s header is mutated and written back through
    /// the same door, so the served `words` bytes are spliced through
    /// untouched and the file is never re-serialised. A failure is REPORTED
    /// rather than swallowed, because R6-11 makes it mean something: the run
    /// will not fetch that media at all, since this file is the one record of
    /// the id still owed a delete.
    ///
    /// A repeat DELETE of an already-deleted transcript answers 200 (C0's
    /// q6), so a retry can never make things worse.
    ///
    /// **A Stop is heard BETWEEN items.** `cancel` is optional and defaulted
    /// so `retryDeletes()` still means what it always did, but a run that has
    /// one hands its token over: each DELETE has only `deleteTimeout` of its
    /// own, and a cache owing three of them against a server that answers
    /// nothing made a person wait out fifteen seconds of a Stop they had
    /// already pressed (the reader review, §10.13 R1·2). What is left
    /// unvisited is in NEITHER list — nothing was attempted for it — which is
    /// safe because the one caller throws `cancelled` on the next line.
    func retryDeletes(cancel: Transcriber.CancelToken? = nil) -> (
        deleted: [UInt32], failed: [UInt32]
    ) {
        guard let client else { return ([], []) }
        var deleted: [UInt32] = []
        var failed: [UInt32] = []
        for row in MediaTranscript.undeleted(in: cacheDirectory) {
            if cancel?.isCancelled == true { break }
            switch client.delete(id: row.transcriptID) {
            case .failed:
                failed.append(row.media)
                continue
            // An id no request could be made from is in NEITHER list: saying
            // `deleted` would report a delete nothing sent and would write
            // `remote_deleted: true` over the one record that something is
            // owed, and saying `failed` would HOLD the media for ever over a
            // string (the reader review's fix pass, §10.13).
            case .notSent:
                continue
            case .deleted:
                break
            }
            if var file = MediaTranscript.read(for: row.media, in: cacheDirectory) {
                file.header.remoteDeleted = true
                MediaTranscript.write(file, for: row.media, in: cacheDirectory)
            }
            deleted.append(row.media)
        }
        return (deleted, failed)
    }

    // MARK: - One media's round trip

    /// Extract, upload, submit, poll, write, delete — §5a step 3 in that
    /// order, and the order is the whole of this method's argument.
    ///
    /// **The ten-hour refusal is first**, off the media's own `duration`,
    /// before a single frame is extracted: an hour of FLAC is about 55 MB and
    /// ten hours is 550, and finding out after sending them that AssemblyAI
    /// will not take the file is the most expensive possible way to learn it.
    ///
    /// **The temporary audio is removed in a `defer`**, which covers every
    /// exit this method has — the throw from `upload`, the throw from
    /// `submit`, the poll that timed out, the cancel — because an extract is
    /// an input to one upload and a run that failed must leave nothing in
    /// `NSTemporaryDirectory()` behind it. `cloud_captions_probe.py`'s row T
    /// globs for `reelcut-upload-*` during and after a failed run rather than
    /// taking this comment's word for it.
    ///
    /// **The cache file is written BEFORE its marker, and the marker only
    /// when the file LANDED.** Either order can be interrupted; this one
    /// fails safe. A file with no marker is re-fetched next run (`isCurrent`
    /// needs both); a marker with no file would certify a transcript that is
    /// not there, and a marker over an OLDER file — which is what discarding
    /// `write`'s answer produced — certifies one that is there and is not the
    /// one that was asked for (the reader review, §10.13 R1·3).
    ///
    /// **The DELETE is last and its answer is recorded**, not assumed
    /// (R6-4). `poll` already deletes on every throwing exit of its own, so
    /// the only transcript this method can leave behind is one it fetched
    /// successfully and then failed to delete — which is what the janitor
    /// above is for, and what `remote_deleted: false` in the file means.
    func fetch(
        media: MediaSnapshot, url: URL, stamp: TranscriptStamp, options: TranscriptOptions,
        cancel: Transcriber.CancelToken,
        progress: @escaping (CloudProgress.Phase, Double, String) -> Void
    ) throws -> (file: MediaTranscript.File, uploaded: Report.Uploaded) {
        guard let client else { throw AccessError.credentialRequired }
        let name = media.name
        let seconds = ReelTime.seconds(media.duration)
        guard seconds <= Double(AssemblyAIClient.maxMediaSeconds) else {
            throw MediaError.tooLong(name)
        }

        // 16 kHz mono is what `Transcriber+Extract.swift` writes, so the
        // frames a whole track will produce are its seconds times the rate —
        // the denominator the extract's progress is measured against.
        let expected = max(1, seconds * 16000)
        progress(.extracting, 0, CloudProgress.detail(.extracting, file: name))
        let upload = try Transcriber.extractUpload(
            url: url, name: name, cancel: cancel,
            progress: { frames in
                progress(
                    .extracting, Double(frames) / expected,
                    CloudProgress.detail(.extracting, file: name))
            })
        defer { try? FileManager.default.removeItem(at: upload.url) }

        let bytes = Int64(
            (try? FileManager.default.attributesOfItem(atPath: upload.url.path))?[.size]
                .flatMap { ($0 as? NSNumber)?.int64Value } ?? 0)
        progress(.uploading, 0, CloudProgress.detail(.uploading, file: name, sent: 0, total: bytes))
        let audioURL = try client.upload(
            file: upload.url, cancel: cancel,
            progress: { sent, total in
                let whole = total > 0 ? total : bytes
                progress(
                    .uploading, whole > 0 ? Double(sent) / Double(whole) : 0,
                    CloudProgress.detail(.uploading, file: name, sent: sent, total: whole))
            })

        let id = try client.submit(TranscriptRequest(audioURL: audioURL, options: options))
        progress(.waiting, 0, CloudProgress.detail(.waiting, file: name, waited: 0))
        let fetched = try client.poll(
            id: id, audioSeconds: upload.seconds, cancel: cancel,
            waited: { waited in
                progress(
                    .waiting, CloudProgress.waiting(waited: waited, audioSeconds: upload.seconds),
                    CloudProgress.detail(.waiting, file: name, waited: waited))
            })

        progress(.saving, 0, CloudProgress.detail(.saving, file: name))
        let header = MediaTranscript.Header(
            provider: MediaTranscript.provider, transcriptID: fetched.response.id,
            requested: options, speechModelUsed: fetched.response.speechModelUsed,
            languageCode: fetched.response.languageCode,
            languageConfidence: fetched.response.languageConfidence,
            audioDuration: fetched.response.audioDuration ?? Int(upload.seconds.rounded(.up)),
            extractedSeconds: upload.seconds, uploadedFormat: upload.format.rawValue,
            // ALWAYS 0 — C0's q4 measured that an extract keeps a late audio
            // track's head, so a word's millisecond in the extract is its
            // millisecond in the media (`MediaTranscript.Header`'s own doc).
            audioTrackStartMs: 0, fetchedAt: Self.timestamp(), remoteDeleted: false)
        var file = try MediaTranscript.File(header: header, wordsJSON: fetched.wordsJSON)
        // ONLY when the file really landed. `write` answers `false` for every
        // way it can fail, and discarding that answer stamped the marker over
        // a cache file that still held an EARLIER request's words: `isCurrent`
        // then read the new marker and the old file and served the stale
        // transcript for ever, for a request it was never made from (the
        // reader review, §10.13 R1·3). The comment above says the marker
        // comes second so it fails safe; this is what makes that true.
        let transcriptWritten = MediaTranscript.write(file, for: media.id, in: cacheDirectory)
        if transcriptWritten {
            MediaTranscript.writeStamp(stamp, for: media.id, in: cacheDirectory)
        }

        let deleted = client.delete(id: fetched.response.id) == .deleted
        if deleted {
            file.header.remoteDeleted = true
            MediaTranscript.write(file, for: media.id, in: cacheDirectory)
        }
        return (
            file,
            Report.Uploaded(
                media: media.id, speechModelUsed: fetched.response.speechModelUsed,
                languageCode: fetched.response.languageCode,
                languageConfidence: fetched.response.languageConfidence,
                audioSeconds: header.audioDuration, format: upload.format,
                transcriptWritten: transcriptWritten,
                remoteDeleted: deleted)
        )
    }

    /// `fetched_at`, ISO-8601 in UTC — the one spelling of a time in the
    /// cache file, and a fixed one: a local-time stamp would make two
    /// machines' files differ over nothing.
    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date())
    }
}
