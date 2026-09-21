import Foundation

/// AssemblyAI's REST API, as five synchronous methods — road map 6 §5c
/// whole. Foundation only: no AppKit, no document, nothing about a project,
/// so a probe drives it against the stand-in server over a socket and, for
/// the retry and backoff rules, against an injected `URLProtocol` with no
/// socket at all.
///
/// **R6-7: no `async`.** Each method builds a task and waits on a semaphore
/// the delegate signals — `Transcriber`'s `TaskSink` shape, and the delegate
/// queue is one of ours for its reason: the framework's default would make an
/// off-main tool's wait depend on somebody else's queue staying free.
///
/// **A redirect is never followed.** `willPerformHTTPRedirection` always
/// answers nil, so the 3xx is delivered as the task's own response and comes
/// back as `.redirected`. Following one would re-send the `authorization`
/// header to whatever host the `Location` named — the spike's Python client
/// needed a `NoRedirect` handler for exactly this.
///
/// **The credential is in one header and in no log line.** A log line carries
/// a method, a path and a status; the session is `.ephemeral` with its
/// cookie, cache and credential storage cleared, so the framework writes
/// nothing about a request to disk either.
final class AssemblyAIClient {

    /// The numbers road map 6 §8 says a person may want to change, in one
    /// value a probe can replace wholesale.
    struct Tuning: Equatable {
        /// Seconds between polls — AssemblyAI's own SDKs' default.
        var pollInterval: TimeInterval
        /// The poll ceiling never falls below this, however short the audio.
        var pollCeilingFloor: TimeInterval
        /// Audio seconds per second of ceiling: floor(147 ÷ 3) from C0's q8,
        /// which measured an hour completing in 24.4 s — three times the
        /// measured rate is the margin a queue can eat.
        var pollCeilingDivisor: Double
        /// One retry: a dropped socket's worth, and two uploads of a 100 MB
        /// file are the cost of a third.
        var uploadRetries: Int
        var retryBackoff: TimeInterval
        /// Consecutive 5xx or transport errors a poll loop tolerates.
        var pollFailuresTolerated: Int
        /// The janitor's budget per item; the slowest DELETE C0 timed was
        /// 1.70 s.
        var deleteTimeout: TimeInterval
        /// Every other request's ceiling.
        var requestTimeout: TimeInterval

        static let shipped = Tuning(
            pollInterval: 3, pollCeilingFloor: 300, pollCeilingDivisor: 49, uploadRetries: 1,
            retryBackoff: 1, pollFailuresTolerated: 3, deleteTimeout: 5, requestTimeout: 60)

        /// `max(300 s, audio seconds / 49)` — §8's row.
        func pollCeiling(audioSeconds: Double) -> TimeInterval {
            guard pollCeilingDivisor > 0 else { return pollCeilingFloor }
            return max(pollCeilingFloor, audioSeconds / pollCeilingDivisor)
        }
    }

    /// AssemblyAI's 10-hour ceiling per `audio_url`, in seconds — four
    /// minutes of processing at q8's rate, and 550 MB of FLAC.
    static let maxMediaSeconds = 36_000
    /// `keyterms_prompt`'s documented ceiling on Universal-3.5 Pro.
    static let maxKeyterms = 1000

    /// Why a call failed, in the order a person can act on them (§5c). The
    /// first six carry 5c's sentences; the last four are this client's own.
    enum ClientError: LocalizedError, Equatable {
        case noNetwork
        case keyRefused(Int)
        case account(String)
        case request(String)
        case server(Int)
        case transcript(String)
        case redirected(Int)
        case timedOut
        case cancelled
        case malformed(String)

        var errorDescription: String? {
            switch self {
            case .noNetwork:
                return "No network connection"
            case .keyRefused:
                return "AssemblyAI refused the API key — check it in Reelcut ▸ Settings"
            case .account(let sentence):
                return sentence
            case .request(let sentence):
                return sentence
            case .server(let code):
                return "AssemblyAI answered \(code)"
            case .transcript(let sentence):
                return sentence
            case .redirected(let code):
                return "AssemblyAI answered \(code) and asked to be redirected, which Reelcut "
                    + "does not follow: the API key would go to another host."
            case .timedOut:
                return "AssemblyAI did not finish the transcript in the time allowed."
            case .cancelled:
                return "The transcription was cancelled."
            case .malformed(let what):
                return "AssemblyAI's answer could not be read: \(what)"
            }
        }
    }

    /// A finished transcript and the bytes of its `words` array exactly as
    /// served — never re-serialised, because a `0.98` does not survive that
    /// (`MediaTranscript`'s header argues it).
    struct Fetched {
        let response: TranscriptResponse
        let wordsJSON: Data
    }

    let base: URL
    let tuning: Tuning
    private let credential: String
    private let delegate: SessionDelegate
    private let session: URLSession

    /// `protocolClasses` is the probe's seam: an injected `URLProtocol` lets
    /// the retry, the backoff and the ceiling be measured with no socket.
    init(
        base: URL, credential: String, tuning: Tuning = .shipped,
        protocolClasses: [AnyClass]? = nil
    ) {
        self.base = base
        self.credential = credential
        self.tuning = tuning
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = tuning.requestTimeout
        if let protocolClasses = protocolClasses {
            configuration.protocolClasses = protocolClasses
        }
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "com.kgalligan.reelcut.assemblyai-delegate"
        self.delegate = SessionDelegate()
        self.session = URLSession(
            configuration: configuration, delegate: delegate, delegateQueue: queue)
    }

    deinit {
        session.finishTasksAndInvalidate()
    }

    // MARK: - The five calls

    /// `POST /v2/upload` — the body streams from the file and is never in
    /// memory. One retry on a transport error or a 5xx, none on a 4xx.
    func upload(
        file: URL, cancel: Transcriber.CancelToken? = nil,
        progress: ((Int64, Int64) -> Void)? = nil
    ) throws -> URL {
        var request = self.request("POST", path: "/v2/upload")
        request.setValue("application/octet-stream", forHTTPHeaderField: "content-type")
        var attempt = 0
        while true {
            if cancel?.isCancelled == true { throw ClientError.cancelled }
            let reply = send(request, file: file, cancel: cancel, progress: progress)
            if let failure = classify(reply) {
                guard failure.isRetriable, attempt < tuning.uploadRetries,
                    cancel?.isCancelled != true
                else { throw failure }
                attempt += 1
                note("retry \(attempt) of upload after \(failure.shortName)")
                sleep(tuning.retryBackoff, cancel: cancel)
                continue
            }
            guard
                let object = try? JSONSerialization.jsonObject(with: reply.data)
                    as? [String: Any], let text = object["upload_url"] as? String,
                let url = URL(string: text)
            else { throw ClientError.malformed("the upload answered no `upload_url`") }
            return url
        }
    }

    /// `POST /v2/transcript` — answers the transcript's id.
    func submit(_ request: TranscriptRequest) throws -> String {
        var post = self.request("POST", path: "/v2/transcript")
        post.setValue("application/json", forHTTPHeaderField: "content-type")
        post.httpBody = try JSONEncoder().encode(request)
        let reply = send(post)
        if let failure = classify(reply) { throw failure }
        guard
            let response = try? JSONDecoder().decode(TranscriptResponse.self, from: reply.data)
        else { throw ClientError.malformed("the submission answered no transcript") }
        return response.id
    }

    /// `GET /v2/transcript/{id}` every `pollInterval` until it is
    /// `completed`, it is `error`, the ceiling passes or the token is
    /// cancelled.
    ///
    /// **Every throwing exit deletes the transcript first** (R6-4): one
    /// `delete(id:)`, best effort, before the throw. A transcript AssemblyAI
    /// is still making, or has made and nobody read, is one it keeps
    /// indefinitely, and this is the one place that knows its id.
    ///
    /// **A `completed` body with no words array is `.malformed`, never an
    /// empty transcript.** `[]` is an array and means zero words, a real
    /// answer about audio nobody spoke in; an absent `words`, a `null` one
    /// and an object are bodies this client cannot read, and turning one into
    /// "nothing was said" would cache a broken response as a fact.
    func poll(
        id: String, audioSeconds: Double, cancel: Transcriber.CancelToken? = nil,
        waited: ((TimeInterval) -> Void)? = nil
    ) throws -> Fetched {
        let ceiling = tuning.pollCeiling(audioSeconds: audioSeconds)
        let started = Date()
        var failures = 0
        while true {
            if cancel?.isCancelled == true { throw refusing(.cancelled, id: id) }
            if Date().timeIntervalSince(started) > ceiling { throw refusing(.timedOut, id: id) }
            let reply = send(request("GET", path: "/v2/transcript/\(id)"), cancel: cancel)
            if let failure = classify(reply) {
                guard failure.isRetriable else { throw refusing(failure, id: id) }
                failures += 1
                note("poll \(id) failed (\(failure.shortName)), \(failures) in a row")
                if failures > tuning.pollFailuresTolerated { throw refusing(failure, id: id) }
            } else {
                failures = 0
                guard
                    let response = try? JSONDecoder().decode(
                        TranscriptResponse.self, from: reply.data)
                else { throw refusing(.malformed("the transcript did not decode"), id: id) }
                if response.status == "error" {
                    throw refusing(
                        .transcript(response.error ?? "AssemblyAI could not transcribe it"),
                        id: id)
                }
                if response.status == "completed" {
                    guard let words = wordsBytes(in: reply.data) else {
                        throw refusing(
                            .malformed("the transcript came back completed with no words array"),
                            id: id)
                    }
                    return Fetched(response: response, wordsJSON: words)
                }
            }
            waited?(Date().timeIntervalSince(started))
            sleep(tuning.pollInterval, cancel: cancel)
        }
    }

    /// `DELETE /v2/transcript/{id}` on `deleteTimeout`. Best effort by
    /// design: a failed delete is RECORDED in the cache file and retried by
    /// the next run's janitor, and a repeat answers 200 (q6), so a retry
    /// cannot make things worse.
    @discardableResult
    func delete(id: String) -> Bool {
        var request = self.request("DELETE", path: "/v2/transcript/\(id)")
        request.timeoutInterval = tuning.deleteTimeout
        return classify(send(request)) == nil
    }

    // MARK: - One request

    /// `request` and `send` stay in this file and not in `+Session.swift`
    /// because they are the two members that touch `credential`, `delegate`
    /// and `session`, which are `private` — and `private` on a stored
    /// property does not cross a file. Keeping them here is what lets the
    /// credential stay private rather than being widened for a size toll.
    func request(_ method: String, path: String, query: String? = nil) -> URLRequest {
        var components = URLComponents(
            url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.query = query
        var request = URLRequest(url: components?.url ?? base.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue(credential, forHTTPHeaderField: "authorization")
        request.timeoutInterval = tuning.requestTimeout
        return request
    }

    /// Builds the task, hands the delegate its sink, waits. The wait has no
    /// deadline of its own: `timeoutIntervalForRequest` is the bound, and a
    /// second one here would leave a task running with nobody to read it.
    func send(
        _ request: URLRequest, file: URL? = nil, cancel: Transcriber.CancelToken? = nil,
        progress: ((Int64, Int64) -> Void)? = nil
    ) -> Reply {
        let task =
            file.map { session.uploadTask(with: request, fromFile: $0) }
            ?? session.dataTask(with: request)
        let sink = delegate.open(task.taskIdentifier, progress: progress)
        cancel?.attach(task)
        task.resume()
        sink.done.wait()
        cancel?.release()
        let reply = delegate.close(task.taskIdentifier)
        note("\(request.httpMethod ?? "?") \(request.url?.path ?? "?") → "
            + "\(reply.response?.statusCode.description ?? reply.error.map { _ in "error" } ?? "?")")
        return reply
    }

    /// `GET /v2/transcript?limit=1` — the cheapest authenticated call, for
    /// the Settings window's Verify button.
    func verify() -> Result<Void, ClientError> {
        let reply = send(request("GET", path: "/v2/transcript", query: "limit=1"))
        if let failure = classify(reply) { return .failure(failure) }
        return .success(())
    }
}

extension AssemblyAIClient.ClientError {
    /// Whether one more attempt could answer differently: a server fault, a
    /// dropped connection or a timeout. Never a refused key or request, an
    /// account problem or a cancel — those answer the same way for ever and
    /// a retry after one costs a second upload for nothing.
    var isRetriable: Bool {
        switch self {
        case .noNetwork, .server, .timedOut: return true
        default: return false
        }
    }

    /// The case's name for a log line, with no sentence in it: a relayed
    /// sentence may quote a URL.
    var shortName: String {
        switch self {
        case .noNetwork: return "noNetwork"
        case .keyRefused(let code): return "keyRefused(\(code))"
        case .account: return "account"
        case .request: return "request"
        case .server(let code): return "server(\(code))"
        case .transcript: return "transcript"
        case .redirected(let code): return "redirected(\(code))"
        case .timedOut: return "timedOut"
        case .cancelled: return "cancelled"
        case .malformed: return "malformed"
        }
    }
}
