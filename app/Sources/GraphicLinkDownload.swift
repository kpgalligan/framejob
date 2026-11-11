// app/Sources/GraphicLinkDownload.swift — the one GET a `framejob://` link
// causes (spec §11 G-49 (d)): an ephemeral session of its own with no
// cookies, no cache and no credential storage; every redirect held to
// `GraphicLink.allows`, at most `maxRedirects`; only status 200; at most
// `maxBytes` as delivered, refused at the headers when the declared length
// is larger and cut off when the body passes it; `idleTimeout` with no byte
// and `totalTimeout` in all. The body streams to
// `<temporary directory>/FrameJobLink-<UUID>/<name>`. One answer only: a
// `multipart/x-mixed-replace` body is delivered as a response per part, and
// the second is refused, so a fetch makes one folder and counts one file.
//
// **The first refusal wins.** A rule that refuses records its sentence and
// cancels the task; the cancel's own error, and whatever the task still
// delivers, never replace it. On any refusal the folder is removed here; on
// success it is the caller's to remove (`Fetched.folder`).
//
// **No `async`** (spec §11 W-8): a delegate session on a serial queue, as
// `AssemblyAIClient`'s. No authentication delegate: with no credential
// storage a 401 arrives as a status, and server trust is the system's.
// State is touched on the delegate queue only; `completion` runs on main,
// once.

import Foundation

final class GraphicLinkDownload: NSObject, URLSessionDataDelegate {
    struct Limits {
        var maxBytes: Int64
        var idleTimeout: TimeInterval
        var totalTimeout: TimeInterval
        var maxRedirects: Int

        static let shipped = Limits(
            maxBytes: 32 * 1024 * 1024, idleTimeout: 30, totalTimeout: 120, maxRedirects: 5)
    }

    struct Fetched {
        let file: URL
        let folder: URL
        let firstHost: String
        let finalHost: String
        let bytes: Int64
    }

    private let request: GraphicLink.Request
    private let policy: GraphicLink.Policy
    private let limits: Limits
    private let queue = OperationQueue()
    private var session: URLSession?
    private var completion: ((Result<Fetched, GraphicLink.Refusal>) -> Void)?
    private var totalTimer: DispatchWorkItem?

    // Delegate queue only, until `completion` has run.
    private var refusal: GraphicLink.Refusal?
    private var redirects = 0
    /// A response was taken; another (a multipart body's next part) is refused.
    private var answered = false
    /// The temporary folder this fetch made, if it got that far; read after `completion`.
    private(set) var folder: URL?
    private var file: URL?
    private var handle: FileHandle?
    private var bytes: Int64 = 0
    private var finalHost: String?

    init(request: GraphicLink.Request, policy: GraphicLink.Policy, limits: Limits = .shipped) {
        self.request = request
        self.policy = policy
        self.limits = limits
        queue.maxConcurrentOperationCount = 1
        queue.name = "com.kgalligan.framejob.graphic-link"
        super.init()
    }

    /// Starts the fetch; `completion` runs on main, once. Main.
    func start(completion: @escaping (Result<Fetched, GraphicLink.Refusal>) -> Void) {
        self.completion = completion
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = limits.idleTimeout
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        self.session = session
        var get = URLRequest(url: request.source)
        get.httpMethod = "GET"
        get.setValue("*/*", forHTTPHeaderField: "Accept")
        let task = session.dataTask(with: get)
        let timer = DispatchWorkItem { [weak self, weak task] in
            guard let self, let task else { return }
            self.queue.addOperation {
                self.refuse("the download took longer than \(Self.seconds(self.limits.totalTimeout))",
                    cancelling: task)
            }
        }
        totalTimer = timer
        DispatchQueue.global().asyncAfter(deadline: .now() + limits.totalTimeout, execute: timer)
        task.resume()
    }

    private static func seconds(_ interval: TimeInterval) -> String {
        interval == interval.rounded() ? "\(Int(interval)) s" : "\(interval) s"
    }

    /// Records the first refusal and cancels. Delegate queue.
    private func refuse(_ sentence: String, cancelling task: URLSessionTask) {
        if refusal == nil { refusal = GraphicLink.Refusal(sentence: sentence) }
        task.cancel()
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        redirects += 1
        if redirects > limits.maxRedirects {
            refuse("the server redirected more than \(limits.maxRedirects) times", cancelling: task)
            completionHandler(nil)
            return
        }
        guard let url = newRequest.url else {
            refuse("the redirect is not a URL in plain ASCII", cancelling: task)
            completionHandler(nil)
            return
        }
        if let refused = GraphicLink.allows(url, what: "the redirect", policy: policy) {
            refuse(refused.sentence, cancelling: task)
            completionHandler(nil)
            return
        }
        completionHandler(newRequest)
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard refusal == nil else {
            completionHandler(.cancel)
            return
        }
        guard !answered else {
            refuse("the server answered more than once", cancelling: dataTask)
            completionHandler(.cancel)
            return
        }
        answered = true
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            refuse("the server answered \(status), not 200", cancelling: dataTask)
            completionHandler(.cancel)
            return
        }
        if response.expectedContentLength > limits.maxBytes {
            refuse(
                "the file is \(GraphicLink.grouped(response.expectedContentLength)) bytes; a "
                    + "graphic sent by link is at most \(GraphicLink.grouped(limits.maxBytes))",
                cancelling: dataTask)
            completionHandler(.cancel)
            return
        }
        finalHost = response.url.flatMap(GraphicLink.displayHost)
        do {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("FrameJobLink-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            self.folder = folder
            let file = folder.appendingPathComponent(request.fileName)
            guard FileManager.default.createFile(atPath: file.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            self.file = file
            handle = try FileHandle(forWritingTo: file)
        } catch {
            refuse(
                "the download could not be saved: \(error.localizedDescription)",
                cancelling: dataTask)
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard refusal == nil, let handle else { return }
        bytes += Int64(data.count)
        if bytes > limits.maxBytes {
            refuse(
                "the file is larger than \(GraphicLink.grouped(limits.maxBytes)) bytes",
                cancelling: dataTask)
            return
        }
        do {
            try handle.write(contentsOf: data)
        } catch {
            refuse(
                "the download could not be saved: \(error.localizedDescription)",
                cancelling: dataTask)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        totalTimer?.cancel()
        try? handle?.close()
        handle = nil
        if refusal == nil, let error {
            let code = (error as NSError).code
            refusal = GraphicLink.Refusal(
                sentence: (error as NSError).domain == NSURLErrorDomain
                    && code == NSURLErrorTimedOut
                    ? "the server sent nothing for \(Self.seconds(limits.idleTimeout))"
                    : "the connection failed: \(error.localizedDescription)")
        }
        let result: Result<Fetched, GraphicLink.Refusal>
        if let refusal {
            if let folder { try? FileManager.default.removeItem(at: folder) }
            result = .failure(refusal)
        } else if let file, let folder {
            result = .success(
                Fetched(
                    file: file, folder: folder, firstHost: request.host,
                    finalHost: finalHost ?? request.host, bytes: bytes))
        } else {
            result = .failure(GraphicLink.Refusal(
                    sentence: "the connection failed: the server answered nothing"))
        }
        session.finishTasksAndInvalidate()
        let completion = self.completion
        self.completion = nil
        DispatchQueue.main.async { completion?(result) }
    }
}
