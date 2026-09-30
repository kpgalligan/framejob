import Foundation

// MARK: - AssemblyAIClient: one request, and the delegate under it

/// What a reply MEANS and who delivers it: `Reply`, the status classifier,
/// the two readers that cut a served body apart, the one-delete-then-throw
/// helper, the cancellable wait, the log line — and `SessionDelegate`, the
/// object `URLSession` calls back on its own one-wide queue.
///
/// It is beside `AssemblyAIClient.swift` rather than in it because that file
/// holds road map 6 §5c's five calls and §8's numbers and stood at 487 lines
/// with this in it, against the 400-line cap on a new file (app/CLAUDE.md,
/// road map 6 §5h). The split is the one the spec already made for
/// `AssemblyAITranscript.swift`, one seam further along: the wire VALUES
/// left first, then the wire MACHINERY, so what is left in the client file
/// is the five calls a reader came for.
///
/// `request` and `send` did NOT come here, and neither did
/// `withoutCredential(_:)`. Those three are the members that touch
/// `credential`, `delegate` and `session`, and `private` on a stored property
/// does not cross a file: moving them would have widened the credential to
/// pay a size toll, which is the wrong direction. `classify` below CALLS
/// `withoutCredential` and does not name the credential itself.
extension AssemblyAIClient {

    struct Reply {
        var data = Data()
        var response: HTTPURLResponse?
        var error: (any Error)?
    }

    /// The status a reply carries, as an error or nil. A redirect arrives
    /// as a 3xx because the delegate refused to follow it.
    func classify(_ reply: Reply) -> ClientError? {
        if let error = reply.error as? URLError {
            switch error.code {
            case .cancelled: return .cancelled
            case .timedOut: return .timedOut
            default: return .noNetwork
            }
        }
        if reply.error != nil { return .noNetwork }
        guard let response = reply.response else {
            return .malformed("the request answered nothing at all")
        }
        let code = response.statusCode
        switch code {
        case 200..<300: return nil
        case 300..<400: return .redirected(code)
        case 401, 403: return .keyRefused(code)
        case 402:
            return .account(
                withoutCredential(sentence(in: reply.data) ?? "AssemblyAI answered \(code)"))
        case 400..<500:
            return .request(
                withoutCredential(sentence(in: reply.data) ?? "AssemblyAI answered \(code)"))
        default: return .server(code)
        }
    }

    /// AssemblyAI's own `error` sentence out of a body, relayed verbatim —
    /// through `withoutCredential`, which is what makes "verbatim" a promise
    /// about the SERVER's text and not about this client's key.
    private func sentence(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let text = object["error"] as? String, !text.isEmpty
        else { return nil }
        return text
    }

    /// The served bytes of a top-level `words` ARRAY, or nil when the key is
    /// absent, does not begin `[`, or will not decode as words.
    func wordsBytes(in body: Data) -> Data? {
        guard let range = JSONValueRange.topLevel(key: "words", in: body) else { return nil }
        let bytes = body.subdata(in: range)
        guard bytes.first == UInt8(ascii: "[") else { return nil }
        guard (try? JSONDecoder().decode([TranscriptWord].self, from: bytes)) != nil else {
            return nil
        }
        return bytes
    }

    /// Whether `text` repeats this client's own credential — the question
    /// `withoutCredential` answers by changing the text, asked without it.
    func carriesCredential(_ text: String) -> Bool {
        withoutCredential(text) != text
    }

    /// The ONE gate for a transcript id this client puts in a path (`poll`,
    /// `delete`) or accepts from a submit reply or a recovery-list row: plain
    /// (`isPlainIdentifier`) AND not the credential. An id that repeats the
    /// key would put it in a request path and a log line, so it is never
    /// sent and never accepted (#187, R2·1).
    func isSendableIdentifier(_ id: String) -> Bool {
        Self.isPlainIdentifier(id) && !carriesCredential(id)
    }

    /// One `delete` before a throw, and the error to throw.
    func refusing(_ failure: ClientError, id: String) -> ClientError {
        delete(id: id)
        return failure
    }

    /// A `completed` body must name the id that was polled, or it is
    /// `.malformed` (#71).
    ///
    /// `fetch` stores `response.id` in the cache file and later deletes it,
    /// so a body served under another id — `../upload`, or a plain id that
    /// is somebody else's — would be cached and promised a retry that can
    /// never be sent, or would move the DELETE to a transcript this run
    /// never made. Refusing here keeps the id `fetch` stores and deletes the
    /// submitted one, and `refusing` deletes the POLLED id, which is plain.
    func requireEchoedID(_ response: TranscriptResponse, polled id: String) throws {
        guard response.id != id else { return }
        throw refusing(
            .malformed(
                "the transcript came back completed under an id other than the one polled"),
            id: id)
    }

    /// Waits in slices of at most a tenth of a second, reading the token
    /// between them, so a cancel during a three-second gap is acted on in a
    /// tenth rather than at the next poll.
    func sleep(_ seconds: TimeInterval, cancel: Transcriber.CancelToken?) {
        var left = seconds
        while left > 0 {
            if cancel?.isCancelled == true { return }
            let slice = min(0.1, left)
            Thread.sleep(forTimeInterval: slice)
            left -= slice
        }
    }

    /// A method, a path and a status. Never a header and never a body:
    /// `authorization` is in one, a signed URL may be in the other. Named
    /// `note` rather than `log` because Darwin's `log(_:)` is a global
    /// function on `Double` and an unqualified `log("…")` resolves to it.
    ///
    /// Written straight to fd 1 through `FileHandle.standardOutput`, never
    /// `print` (#116): `print` is block-buffered (4096 B) under a file
    /// redirect, so an instance log held only the lines before the last full
    /// block. The throwing `write(contentsOf:)` because the legacy
    /// `write(_:)` raises an Objective-C exception on a bad descriptor.
    func note(_ line: String) {
        try? FileHandle.standardOutput.write(contentsOf: Data("AssemblyAI: \(line)\n".utf8))
    }

    // MARK: - The delegate

    /// One object for the whole session, holding a sink per task under a
    /// lock: the delegate queue is not the calling thread and a method here
    /// can arrive while another task is being opened.
    final class SessionDelegate: NSObject, URLSessionDataDelegate {
        final class Sink {
            let done = DispatchSemaphore(value: 0)
            var reply = Reply()
            var progress: ((Int64, Int64) -> Void)?
            var signalled = false
        }

        private let lock = NSLock()
        private var sinks: [Int: Sink] = [:]

        func open(_ identifier: Int, progress: ((Int64, Int64) -> Void)?) -> Sink {
            let sink = Sink()
            sink.progress = progress
            lock.lock()
            sinks[identifier] = sink
            lock.unlock()
            return sink
        }

        func close(_ identifier: Int) -> Reply {
            lock.lock()
            let sink = sinks.removeValue(forKey: identifier)
            lock.unlock()
            return sink?.reply ?? Reply()
        }

        private func sink(_ identifier: Int) -> Sink? {
            lock.lock()
            defer { lock.unlock() }
            return sinks[identifier]
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data)
        {
            guard let sink = sink(dataTask.taskIdentifier) else { return }
            lock.lock()
            sink.reply.data.append(data)
            lock.unlock()
        }

        func urlSession(
            _ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?
        ) {
            guard let sink = sink(task.taskIdentifier) else { return }
            lock.lock()
            sink.reply.response = task.response as? HTTPURLResponse
            sink.reply.error = error
            let already = sink.signalled
            sink.signalled = true
            lock.unlock()
            if !already { sink.done.signal() }
        }

        func urlSession(
            _ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
            totalBytesSent: Int64, totalBytesExpectedToSend: Int64
        ) {
            sink(task.taskIdentifier)?.progress?(totalBytesSent, totalBytesExpectedToSend)
        }

        /// Never followed. Answering nil delivers the 3xx as the task's own
        /// response, which `classify` turns into `.redirected`: the
        /// `authorization` header goes to no host but its own.
        func urlSession(
            _ session: URLSession, task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }
}
