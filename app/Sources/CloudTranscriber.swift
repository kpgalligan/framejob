import Foundation

/// The cloud engine's seam: `TranscriptionEngine`, the two spellings a
/// caption run can be asked for, and `CloudTranscriber`, which takes exactly
/// what `Transcriber` takes and answers exactly what `Transcriber` answers.
///
/// **Why a seam and not a body yet.** Road map 6 §5h says the seams are
/// written FIRST, in the tree, before the lanes that fill them start, so
/// every later file compiles against one shape rather than against a shape
/// that moves under it (R2's lesson). This file is that shape: road map 6's
/// c1-parts pipeline lands the declaration and `run`; c1-run lands
/// `transcribe`'s body — the janitor, the grouping, the extract, the upload,
/// the submit, the poll, the fetch, the cache write and the remote delete of
/// §5a. Until then `transcribe` throws a sentence saying so, and NOTHING in
/// the app constructs a `CloudTranscriber` at all: the sheet, the menu and
/// the `transcribe` tool still reach only `Transcriber`, so the placeholder
/// is unreachable rather than merely unused.
///
/// **`run` is not a placeholder.** It is the final code — the serial queue,
/// the synchronous body on it, the completion posted to main — because it is
/// `Transcriber.run`'s twin line for line and a body arriving later changes
/// nothing about it. R6-7: no `async` here or below it.
enum TranscriptionEngine: String, CaseIterable {
    /// On-device `SFSpeechRecognizer` — `Transcriber`, the default.
    case apple
    /// AssemblyAI over the network — `CloudTranscriber`.
    case assemblyai

    /// What the sheet remembers between opens (road map 6 §5a). An agent call
    /// never reads it: R6-2 says the cloud engine is asked for every time.
    static let defaultsKey = "ReelcutCaptionEngine"

    /// The popup's words. "On this Mac" rather than "Apple" because what the
    /// person is choosing is where their audio goes, not whose recogniser it
    /// is.
    var displayName: String {
        switch self {
        case .apple: return "On this Mac"
        case .assemblyai: return "AssemblyAI"
        }
    }
}

/// AssemblyAI as a second engine behind the one command (R6-1). Same jobs,
/// same cancel token, same frame, same `Outcome`, so
/// `TranscribeSheetController.finish` and the tool's placement code cannot
/// tell which engine ran.
final class CloudTranscriber {

    /// The serial queue the whole run happens on — `Transcriber.work`'s
    /// twin, and one of the queue seams app/CLAUDE.md lists. A run is
    /// network-bound minutes of somebody else's compute and must never be on
    /// main.
    private let work = DispatchQueue(label: "com.kgalligan.reelcut.cloud-transcribe")

    let client: AssemblyAIClient
    /// Where `cache/transcripts/` lives for this run — the document's cache
    /// directory, passed by value so the run holds no document.
    let cacheDirectory: URL
    /// The media records the jobs point at, by id, for the stamp.
    let media: [UInt32: MediaSnapshot]

    init(client: AssemblyAIClient, cacheDirectory: URL, media: [UInt32: MediaSnapshot]) {
        self.client = client
        self.cacheDirectory = cacheDirectory
        self.media = media
    }

    /// Transcribes every job and answers on the MAIN thread —
    /// `Transcriber.run`'s seam, so a sheet and a semaphore-waiting tool can
    /// both stay synchronous. `progress` is NOT hopped: it fires on the run's
    /// own queue and its caller bounces it.
    func run(
        jobs: [Transcriber.Job], options: TranscriptOptions, refresh: Bool, frame: Ticks,
        cancel: Transcriber.CancelToken, progress: ((Double, String) -> Void)? = nil,
        completion: @escaping (Result<Transcriber.Outcome, any Error>) -> Void
    ) {
        work.async { [weak self] in
            guard let self = self else { return }
            let outcome = Result {
                try self.transcribe(
                    jobs, options: options, refresh: refresh, frame: frame, cancel: cancel,
                    progress: progress)
            }
            DispatchQueue.main.async { completion(outcome) }
        }
    }

    /// The synchronous body, road map 6 §5a. Call it off the main thread.
    ///
    /// Not built yet, and it says so rather than answering an empty outcome:
    /// an engine that silently placed no captions would be indistinguishable
    /// from a recording with no speech in it, which is the failure shape road
    /// map 4's reader review named. Nothing constructs this class, so the
    /// sentence is unreachable today and is what a wrong wiring would print.
    func transcribe(
        _ jobs: [Transcriber.Job], options: TranscriptOptions, refresh: Bool, frame: Ticks,
        cancel: Transcriber.CancelToken, progress: ((Double, String) -> Void)? = nil
    ) throws -> Transcriber.Outcome {
        throw Transcriber.TranscribeError.failed("the AssemblyAI engine is not built yet")
    }
}
