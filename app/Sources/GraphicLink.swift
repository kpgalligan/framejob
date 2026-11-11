// app/Sources/GraphicLink.swift — the rules of a `framejob://graphic?src=…`
// link, pure (spec §11 G-49 (a), (b), (d)): what a link may say, what
// address Frame Job fetches from, and the name the fetched file is saved
// under. Foundation only; no request is made here.
//
// **Every part of a link is hostile input**: a web page wrote it. Each rule
// refuses in its own sentence, and a piece of the link quoted in a sentence
// is cut to 60 characters.
//
// **One host string.** `allows` tests `URL.host` of the very URL the request
// is sent to (percent-decoded), lowercased, and `displayHost` shows that
// same string: only letters, digits, hyphens and dots, two or more labels,
// none empty. So an address, a one-word name, a trailing dot and a
// percent-escaped suffix are all refused by the characters or the labels
// before the private suffixes are compared.

import Foundation

enum GraphicLink {
    /// What the app allows beyond the rules: nothing, outside a dev build.
    struct Policy {
        #if FRAMEJOB_DEV_TOOLS
        /// `-RCDevGraphicLinkLoopbackHTTP YES`: `http://127.0.0.1` passes (G-49 (l)).
        var loopbackHTTP = false
        #endif
    }

    /// A link that passed: where to fetch, the host to show, the file's name.
    struct Request {
        let source: URL
        let host: String
        let fileName: String
    }

    /// A rule's own sentence.
    struct Refusal: Error, Equatable {
        let sentence: String
    }

    static let action = "graphic"
    static let maxBytes = 2048
    static let fallbackFileName = "graphic.fjgraphic"
    static let privateSuffixes = [
        ".local", ".localhost", ".internal", ".home.arpa", ".lan", ".home",
    ]

    // MARK: - The link (G-49 (a))

    static func parse(_ text: String, scheme: String, policy: Policy) -> Result<Request, Refusal> {
        func refused(_ sentence: String) -> Result<Request, Refusal> {
            .failure(Refusal(sentence: sentence))
        }
        guard text.utf8.count <= maxBytes else {
            return refused("the link is longer than 2,048 bytes")
        }
        guard let link = URLComponents(string: text),
            link.scheme?.lowercased() == scheme.lowercased()
        else { return refused("it is not a \(scheme):// link") }
        let named = link.host ?? ""
        guard named.lowercased() == action else {
            return refused(
                "Frame Job does not know the action \"\(quoted(named))\"; the only one is "
                    + action)
        }
        guard link.user == nil, link.password == nil else {
            return refused("the link carries a user name or a password")
        }
        guard link.port == nil else { return refused("the link carries a port") }
        guard link.path.isEmpty || link.path == "/" else {
            return refused("the link carries a path")
        }
        guard link.fragment == nil else { return refused("the link carries a fragment") }
        let items = link.queryItems ?? []
        if let other = items.first(where: { $0.name != "src" }) {
            return refused("the link has a key other than src: \"\(quoted(other.name))\"")
        }
        guard let first = items.first, let src = first.value, !src.isEmpty else {
            return refused("the link names no src")
        }
        guard items.count == 1 else { return refused("the link names src more than once") }
        switch address(src, what: "src", policy: policy) {
        case .failure(let refusal):
            return .failure(refusal)
        case .success(let source):
            guard let host = displayHost(source) else {
                return refused(hostSentence("src", source.host ?? ""))
            }
            return .success(Request(source: source, host: host, fileName: fileName(for: source)))
        }
    }

    // MARK: - An address Frame Job fetches from (G-49 (b))

    /// `text` as a URL that `allows` passes, or the refusal. `what` is `src`.
    static func address(_ text: String, what: String, policy: Policy) -> Result<URL, Refusal> {
        guard text.utf8.count <= maxBytes else {
            return .failure(Refusal(sentence: "\(what) is longer than 2,048 bytes"))
        }
        let plain = text.unicodeScalars.allSatisfy { $0.value > 0x20 && $0.value < 0x7f }
        guard plain, !text.contains("\\"), let url = URL(string: text) else {
            return .failure(Refusal(sentence: "\(what) is not a URL in plain ASCII"))
        }
        if let refusal = allows(url, what: what, policy: policy) { return .failure(refusal) }
        return .success(url)
    }

    /// Nil when Frame Job may send a request to `url`; `what` is `src` or `the redirect`.
    static func allows(_ url: URL, what: String, policy: Policy) -> Refusal? {
        let scheme = url.scheme?.lowercased() ?? ""
        let host = (url.host ?? "").lowercased()
        guard url.user == nil, url.password == nil else {
            return Refusal(sentence: "\(what) must not carry a user name or a password")
        }
        #if FRAMEJOB_DEV_TOOLS
        if policy.loopbackHTTP, scheme == "http", host == "127.0.0.1" { return nil }
        #endif
        guard scheme == "https" else {
            return Refusal(sentence: "\(what) must be an https URL")
        }
        guard isPublicName(host) else { return Refusal(sentence: hostSentence(what, host)) }
        return nil
    }

    /// (b)'s host rule over a lowercased host.
    static func isPublicName(_ host: String) -> Bool {
        guard !host.isEmpty, host.utf8.count <= 253 else { return false }
        let allowed = host.unicodeScalars.allSatisfy {
            ($0.value >= 0x61 && $0.value <= 0x7a) || ($0.value >= 0x30 && $0.value <= 0x39)
                || $0 == "-" || $0 == "."
        }
        guard allowed else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty && $0.count <= 63 }),
            let last = labels.last
        else { return false }
        if last.allSatisfy(\.isNumber) || last.hasPrefix("0x") { return false }
        return !privateSuffixes.contains { host.hasSuffix($0) }
    }

    /// The host a request to `url` goes to, as shown: nil when it has none.
    static func displayHost(_ url: URL) -> String? {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        return host
    }

    private static func hostSentence(_ what: String, _ host: String) -> String {
        "\(what) names \"\(quoted(host))\", which is not a public host name; Frame Job fetches "
            + "only from a named host on the internet, never an address, a one-word name or a "
            + "private suffix"
    }

    // MARK: - The file's name (G-49 (d))

    /// `source`'s last path component when it is a plain `.fjgraphic` name, else the fallback.
    static func fileName(for source: URL) -> String {
        let name = source.lastPathComponent
        let plain = name.unicodeScalars.allSatisfy {
            ($0.value < 0x80 && CharacterSet.alphanumerics.contains($0))
                || $0 == " " || $0 == "." || $0 == "_" || $0 == "-"
        }
        guard plain, (1...100).contains(name.count), !name.hasPrefix("."),
            name.lowercased().hasSuffix(".fjgraphic")
        else { return fallbackFileName }
        return name
    }

    /// A piece of the link as a sentence shows it: at most 60 characters, no control ones.
    static func quoted(_ text: String) -> String {
        let clean = String(text.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7f })
        return clean.count > 60 ? String(clean.prefix(60)) + "…" : clean
    }

    /// `33554432` as `33,554,432`.
    static func grouped(_ value: Int64) -> String {
        var digits = String(abs(value))
        var out = ""
        while digits.count > 3 {
            out = "," + digits.suffix(3) + out
            digits = String(digits.dropLast(3))
        }
        return (value < 0 ? "-" : "") + digits + out
    }
}
