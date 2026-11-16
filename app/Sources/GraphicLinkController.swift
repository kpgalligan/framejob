// app/Sources/GraphicLinkController.swift — what happens to one
// `framejob://` link (spec §11 G-49): parsed, refused or fetched, one fetch
// at a time, then handed on. Foundation only, and every value it works with
// is an initialiser parameter, so `tools/proof/graphic_link_probe.py` builds
// it with `GraphicLink.swift` and `GraphicLinkDownload.swift` alone; the
// app's own values, the Apple Event handler and the alert are
// `GraphicLinkController+App.swift`'s.
//
// **Every caller of `receive` passes who is told**: the handler passes the
// alert, the dev tool `open_link` its own reader, so no outcome can reach
// another call's reader.
//
// **The temporary folder is removed straight after the hand-off's read**:
// G-47's reader holds every byte in memory. Main only.

import Foundation

final class GraphicLinkController: NSObject {
    enum Outcome {
        /// The package was read and the Import Graphic sheet asked for.
        case sheet(firstHost: String, finalHost: String, bytes: Int64, tempRemoved: Bool)
        /// A rule of G-49 refused: its sentence, and the host once the fetch had begun.
        case refused(host: String?, sentence: String, tempRemoved: Bool)
        /// The fetched file is not a package G-47 takes: the reader's own words.
        case unreadable(host: String, message: String, tempRemoved: Bool)
    }
    typealias Report = (Outcome) -> Void
    /// Hands a fetched file on with its host line; calls back once the file has been read,
    /// with the reader's refusal in its own words, or nil.
    typealias HandOff = (GraphicLinkDownload.Fetched, String, @escaping (String?) -> Void) -> Void

    private let scheme: String
    private let policy: GraphicLink.Policy
    private let limits: GraphicLinkDownload.Limits
    private let handOff: HandOff
    /// The fetch in flight and the host it was asked of (G-49 (e)).
    private var fetching: (host: String, download: GraphicLinkDownload)?

    init(
        scheme: String, policy: GraphicLink.Policy, limits: GraphicLinkDownload.Limits,
        handOff: @escaping HandOff
    ) {
        self.scheme = scheme
        self.policy = policy
        self.limits = limits
        self.handOff = handOff
        super.init()
    }

    // MARK: - The link

    /// One link: refused, or fetched and handed on. `report` is told once. Main.
    func receive(_ text: String, report: @escaping Report) {
        let request: GraphicLink.Request
        switch GraphicLink.parse(text, scheme: scheme, policy: policy) {
        case .failure(let refusal):
            report(.refused(host: nil, sentence: refusal.sentence, tempRemoved: true))
            return
        case .success(let parsed):
            request = parsed
        }
        if let fetching {
            report(
                .refused(
                    host: nil,
                    sentence: "Frame Job is already fetching a graphic from \(fetching.host)",
                    tempRemoved: true))
            return
        }
        let download = GraphicLinkDownload(request: request, policy: policy, limits: limits)
        fetching = (request.host, download)
        download.start { [self] result in
            fetching = nil
            switch result {
            case .failure(let refusal):
                report(
                    .refused(
                        host: request.host, sentence: refusal.sentence,
                        tempRemoved: Self.isGone(download.folder)))
            case .success(let fetched):
                let origin = Self.origin(first: fetched.firstHost, final: fetched.finalHost)
                handOff(fetched, origin) { message in
                    try? FileManager.default.removeItem(at: fetched.folder)
                    let gone = Self.isGone(fetched.folder)
                    if let message {
                        report(
                            .unreadable(
                                host: fetched.finalHost, message: message, tempRemoved: gone))
                    } else {
                        report(
                            .sheet(
                                firstHost: fetched.firstHost, finalHost: fetched.finalHost,
                                bytes: fetched.bytes, tempRemoved: gone))
                    }
                }
            }
        }
    }

    private static func isGone(_ folder: URL?) -> Bool {
        guard let folder else { return true }
        return !FileManager.default.fileExists(atPath: folder.path)
    }

    /// The sheet's host line (G-49 (g)).
    static func origin(first: String, final: String) -> String {
        first == final ? "From: \(final)" : "From: \(final) (the link named \(first))"
    }
}
