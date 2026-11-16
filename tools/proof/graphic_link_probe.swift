// tools/proof/graphic_link_probe.swift — `graphic_link_probe.py`'s rows over
// the app's own `GraphicLink.swift`, `GraphicLinkDownload.swift` and
// `GraphicLinkController.swift` (spec §11 G-49), built with
// `FRAMEJOB_DEV_TOOLS` so the loopback switch exists.
//
//     graphic_link_probe <port> <the served package's file>
//
// Prints one JSON object, `{"rows": [{"id", "pass", "detail"}]}`. The U rows
// make no request; the F and K rows fetch from the driver's listener on
// `127.0.0.1:<port>`.

import Foundation

var rows: [[String: Any]] = []
func row(_ id: String, _ pass: Bool, _ detail: String) {
    rows.append(["id": id, "pass": pass, "detail": detail])
}

let arguments = CommandLine.arguments
guard arguments.count == 3, let port = Int(arguments[1]),
    let served = FileManager.default.contents(atPath: arguments[2])
else {
    FileHandle.standardError.write(Data("usage: graphic_link_probe <port> <file>\n".utf8))
    exit(2)
}
let base = "http://127.0.0.1:\(port)"
let strict = GraphicLink.Policy()
var loopback = GraphicLink.Policy()
loopback.loopbackHTTP = true

func encoded(_ src: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return src.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
}
func link(_ src: String) -> String { "framejob://graphic?src=" + encoded(src) }
func sentence(_ text: String, _ policy: GraphicLink.Policy = strict) -> String {
    switch GraphicLink.parse(text, scheme: "framejob", policy: policy) {
    case .success(let request): return "OK \(request.source.absoluteString)"
    case .failure(let refusal): return refusal.sentence
    }
}
/// Every case refused in a sentence holding its `want`; the detail lists what each answered.
func refusals(_ id: String, _ cases: [(String, String)], _ policy: GraphicLink.Policy = strict) {
    var fine = true
    var notes: [String] = []
    for (text, want) in cases {
        let got = sentence(text, policy)
        if got.hasPrefix("OK ") || !got.contains(want) { fine = false }
        notes.append("\(text.prefix(70)) → \(got)")
    }
    row(id, fine, notes.joined(separator: " | "))
}

// MARK: - U: the rules, no request

do {
    let good = GraphicLink.parse(
        "FrameJob://GRAPHIC?src=" + encoded("HTTPS://Example.com:8443/a/lower-third.fjgraphic"),
        scheme: "framejob", policy: strict)
    if case .success(let request) = good {
        row(
            "U1",
            request.source.absoluteString == "HTTPS://Example.com:8443/a/lower-third.fjgraphic"
                && request.host == "example.com" && request.fileName == "lower-third.fjgraphic",
            "source \(request.source.absoluteString) host \(request.host) file \(request.fileName)")
    } else {
        row("U1", false, sentence(link("https://example.com/a/lower-third.fjgraphic")))
    }
}
let fine = "https://example.com/x.fjgraphic"
refusals(
    "U2",
    [
        ("framejobs://graphic?src=" + encoded(fine), "it is not a framejob:// link"),
        ("https://graphic?src=" + encoded(fine), "it is not a framejob:// link"),
        ("not a url at all", "it is not a framejob:// link"),
        ("", "it is not a framejob:// link"),
    ])
do {
    let long = link(fine + "?" + String(repeating: "a", count: 2049))
    let atCap = "framejob://graphic?src="
        + encoded("https://example.com/" + String(repeating: "a", count: 1900) + ".fjgraphic")
    let got = sentence(long)
    row(
        "U2b",
        got == "the link is longer than 2,048 bytes" && atCap.utf8.count <= 2048
            && sentence(atCap).hasPrefix("OK "),
        "\(long.utf8.count) bytes → \(got); \(atCap.utf8.count) bytes → \(sentence(atCap).prefix(12))")
}
refusals(
    "U3",
    [
        ("framejob://project?src=" + encoded(fine), "does not know the action \"project\""),
        ("framejob://?src=" + encoded(fine), "does not know the action \"\""),
        ("framejob:graphic?src=" + encoded(fine), "does not know the action"),
    ])
refusals(
    "U3b",
    [
        ("framejob://graphic:81?src=" + encoded(fine), "the link carries a port"),
        ("framejob://u@graphic?src=" + encoded(fine), "the link carries a user name or a password"),
        ("framejob://u:p@graphic?src=" + encoded(fine), "the link carries a user name or a password"),
        ("framejob://graphic?src=" + encoded(fine) + "#f", "the link carries a fragment"),
        ("framejob://graphic/x?src=" + encoded(fine), "the link carries a path"),
    ])
row(
    "U3c", sentence("framejob://graphic/?src=" + encoded(fine)).hasPrefix("OK "),
    sentence("framejob://graphic/?src=" + encoded(fine)))
refusals(
    "U4",
    [
        ("framejob://graphic", "the link names no src"),
        ("framejob://graphic?src=", "the link names no src"),
        ("framejob://graphic?src=" + encoded(fine) + "&src=" + encoded(fine),
            "the link names src more than once"),
        ("framejob://graphic?src=" + encoded(fine) + "&next=1",
            "the link has a key other than src: \"next\""),
        ("framejob://graphic?to=1&src=" + encoded(fine), "the link has a key other than src: \"to\""),
    ])
refusals(
    "U5",
    [
        (link("http://example.com/x.fjgraphic"), "src must be an https URL"),
        (link("file:///etc/passwd"), "src must be an https URL"),
        (link("ftp://example.com/x.fjgraphic"), "src must be an https URL"),
        (link("framejob://graphic?src=x"), "src must be an https URL"),
        (link("data:text/plain,hello"), "src must be an https URL"),
        (link("example.com/x.fjgraphic"), "src must be an https URL"),
        (link("https://exämple.com/x.fjgraphic"), "src is not a URL in plain ASCII"),
        (link("https://example.com/a b"), "src is not a URL in plain ASCII"),
        (link("https://example.com\\@evil.example/x"), "src is not a URL in plain ASCII"),
    ])
refusals(
    "U6",
    [
        (link("https://user@example.com/x.fjgraphic"), "src must not carry a user name or a password"),
        (link("https://user:pass@example.com/x.fjgraphic"),
            "src must not carry a user name or a password"),
    ])
do {
    let hosts = [
        "127.0.0.1", "10.0.0.1", "192.168.1.1", "2130706433", "0x7f.0.0.1", "0x7f000001",
        "[::1]", "[fe80::1]", "localhost", "router", "printer.local", "a.internal", "nas.lan",
        "box.home", "x.home.arpa", "a.localhost",
        // The six a trailing dot or a percent escape would have let through.
        "localhost.", "printer.local.", "a.internal.", "127.0.0.1.", "ex%61mple.%6cocal",
        "example.com%2e",
        // An empty label inside (a trailing one already reads as a numeric last label).
        "example..com",
    ]
    refusals("U7", hosts.map { (link("https://\($0)/x.fjgraphic"), "which is not a public host name") })
    var redirectsFine = true
    var notes: [String] = []
    for host in hosts {
        guard let url = URL(string: "https://\(host)/x.fjgraphic") else {
            notes.append("\(host): no URL")
            continue
        }
        let got = GraphicLink.allows(url, what: "the redirect", policy: loopback)?.sentence
        if got?.hasPrefix("the redirect names") != true { redirectsFine = false }
        notes.append("\(host): \(got ?? "ALLOWED")")
    }
    row("U7b", redirectsFine, notes.joined(separator: " | "))
    let passes = ["example.com", "xn--exmple-cua.com", "a-b.c0.example.co.uk"].map {
        ($0, sentence(link("https://\($0)/x.fjgraphic")))
    }
    let shown: String
    if case .success(let request) = GraphicLink.parse(
        link("https://XN--Exmple-CUA.com/x.fjgraphic"), scheme: "framejob", policy: strict)
    {
        shown = request.host
    } else {
        shown = "refused"
    }
    row(
        "U7c", passes.allSatisfy { $0.1.hasPrefix("OK ") } && shown == "xn--exmple-cua.com",
        passes.map { "\($0.0) → \($0.1.prefix(30))" }.joined(separator: " | ") + " | shown \(shown)")
}
do {
    let cases: [(String, String)] = [
        ("https://example.com/a/lower-third.fjgraphic", "lower-third.fjgraphic"),
        ("https://example.com/My%20Title_2.FJGRAPHIC", "My Title_2.FJGRAPHIC"),
        ("https://example.com/a/..%2Fx.fjgraphic", "graphic.fjgraphic"),
        ("https://example.com/" + String(repeating: "a", count: 92) + ".fjgraphic",
            "graphic.fjgraphic"),
        ("https://example.com/a%3Ab.fjgraphic", "graphic.fjgraphic"),
        ("https://example.com/.fjgraphic", "graphic.fjgraphic"),
        ("https://example.com/lower-third", "graphic.fjgraphic"),
        ("https://example.com/", "graphic.fjgraphic"),
    ]
    var good = true
    var notes: [String] = []
    for (src, want) in cases {
        let got = URL(string: src).map(GraphicLink.fileName(for:)) ?? "no URL"
        if got != want { good = false }
        notes.append("\(src.suffix(30)) → \(got)")
    }
    row("U8", good, notes.joined(separator: " | "))
}
do {
    let local = link("http://127.0.0.1:9/x.fjgraphic")
    let off = sentence(local)
    let on = sentence(local, loopback)
    let others = [
        "http://localhost:9/x.fjgraphic", "http://127.0.0.2:9/x.fjgraphic",
        "http://example.com/x.fjgraphic", "https://127.0.0.1:9/x.fjgraphic",
    ].map { sentence(link($0), loopback) }
    row(
        "U9",
        off == "src must be an https URL" && on.hasPrefix("OK ")
            && others.allSatisfy { !$0.hasPrefix("OK ") },
        "strict: \(off) | switch: \(on) | \(others.joined(separator: " | "))")
}

// MARK: - F: the fetch

func spin(_ seconds: TimeInterval, until done: () -> Bool) {
    let deadline = Date().addingTimeInterval(seconds)
    while !done(), Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

struct Got {
    var fetched: GraphicLinkDownload.Fetched?
    var sentence: String?
    var folder: URL?
    var seconds: TimeInterval = 0
    var leftBehind: Bool { folder.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }
    var said: String { sentence ?? (fetched.map { "FETCHED \($0.bytes) bytes" } ?? "NO ANSWER") }
}
var leftovers: [String] = []

func fetch(_ path: String, _ limits: GraphicLinkDownload.Limits, id: String) -> Got {
    var got = Got()
    switch GraphicLink.address(base + path, what: "src", policy: loopback) {
    case .failure(let refusal):
        got.sentence = "NOT SENT: " + refusal.sentence
        return got
    case .success(let source):
        let request = GraphicLink.Request(
            source: source, host: GraphicLink.displayHost(source) ?? "",
            fileName: GraphicLink.fileName(for: source))
        let download = GraphicLinkDownload(request: request, policy: loopback, limits: limits)
        var done = false
        let started = Date()
        download.start { result in
            switch result {
            case .success(let fetched): got.fetched = fetched
            case .failure(let refusal): got.sentence = refusal.sentence
            }
            done = true
        }
        spin(limits.totalTimeout + 15) { done }
        got.seconds = Date().timeIntervalSince(started)
        got.folder = done ? download.folder : nil
        if got.sentence != nil, got.leftBehind { leftovers.append(id) }
        return got
    }
}
let roomy = GraphicLinkDownload.Limits(
    maxBytes: 1_048_576, idleTimeout: 5, totalTimeout: 10, maxRedirects: 5)

do {
    let got = fetch("/pkg/late.fjgraphic", roomy, id: "F1")
    let file = got.fetched?.file
    let bytes = file.flatMap { FileManager.default.contents(atPath: $0.path) }
    let temp = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path
    let inTemp = got.fetched.map {
        $0.folder.resolvingSymlinksInPath().path.hasPrefix(temp + "/FrameJobLink-")
            && $0.file.deletingLastPathComponent().path == $0.folder.path
    }
    row(
        "F1",
        bytes == served && got.fetched?.bytes == Int64(served.count) && inTemp == true
            && file?.lastPathComponent == "late.fjgraphic" && got.fetched?.firstHost == "127.0.0.1"
            && got.fetched?.finalHost == "127.0.0.1",
        "\(got.said); file \(file?.path ?? "none"); equal \(bytes == served); under temp "
            + "\(inTemp ?? false)")
    if let folder = got.fetched?.folder { try? FileManager.default.removeItem(at: folder) }
}
do {
    let a = fetch("/status/404", roomy, id: "F2")
    let b = fetch("/status/500", roomy, id: "F2")
    row(
        "F2",
        a.sentence == "the server answered 404, not 200"
            && b.sentence == "the server answered 500, not 200",
        "\(a.said) | \(b.said)")
}
do {
    let targets: [(String, String)] = [
        ("http://example.invalid/x", "the redirect must be an https URL"),
        ("https://127.0.0.1:1/x", "the redirect names \"127.0.0.1\", which is not a public host"),
        ("https://u:p@example.invalid/x", "the redirect must not carry a user name or a password"),
        ("http://localhost:\(port)/never/f3", "the redirect must be an https URL"),
    ]
    var good = true
    var notes: [String] = []
    for (target, want) in targets {
        let got = fetch("/redirect?to=" + encoded(target), roomy, id: "F3")
        if got.sentence?.hasPrefix(want) != true { good = false }
        notes.append("\(target) → \(got.said)")
    }
    row("F3", good, notes.joined(separator: " | "))
    // URLSession refuses a redirect to `file:` itself, before the delegate is asked.
    let file = fetch("/redirect?to=" + encoded("file:///etc/hosts"), roomy, id: "F3f")
    row(
        "F3f",
        file.fetched == nil
            && (file.sentence?.hasPrefix("the connection failed: ") == true
                || file.sentence == "the redirect must be an https URL"),
        file.said)
}
do {
    let six = fetch("/chain/6", roomy, id: "F4")
    let five = fetch("/chain/5", roomy, id: "F4")
    row(
        "F4",
        six.sentence == "the server redirected more than 5 times"
            && five.fetched?.bytes == Int64(served.count),
        "six: \(six.said) | five: \(five.said)")
    if let folder = five.fetched?.folder { try? FileManager.default.removeItem(at: folder) }
}
do {
    let got = fetch("/declared/1048577", roomy, id: "F5")
    let atCap = fetch("/declared/1048576", roomy, id: "F5")
    row(
        "F5",
        got.sentence == "the file is 1,048,577 bytes; a graphic sent by link is at most 1,048,576"
            && got.folder == nil && atCap.fetched?.bytes == 1_048_576,
        "\(got.said); folder made \(got.folder != nil) | at the cap: \(atCap.said)")
    if let folder = atCap.fetched?.folder { try? FileManager.default.removeItem(at: folder) }
}
do {
    var limits = roomy
    limits.totalTimeout = 4
    let got = fetch("/endless", limits, id: "F6")
    row(
        "F6", got.sentence == "the file is larger than 1,048,576 bytes" && got.folder != nil,
        "\(got.said) after \(String(format: "%.1f", got.seconds)) s; folder made \(got.folder != nil)")
}
do {
    var limits = roomy
    limits.idleTimeout = 1
    limits.totalTimeout = 6
    let got = fetch("/stall", limits, id: "F7")
    row(
        "F7", got.sentence == "the server sent nothing for 1 s" && got.seconds < 5,
        "\(got.said) after \(String(format: "%.1f", got.seconds)) s")
}
do {
    var limits = roomy
    limits.idleTimeout = 1
    limits.totalTimeout = 2
    let got = fetch("/drip", limits, id: "F8")
    row(
        "F8", got.sentence == "the download took longer than 2 s" && got.seconds < 5,
        "\(got.said) after \(String(format: "%.1f", got.seconds)) s")
}

/// The `FrameJobLink-*` folders in the temporary directory now.
func linkFolders() -> Set<String> {
    let temp = FileManager.default.temporaryDirectory
    let names = (try? FileManager.default.contentsOfDirectory(atPath: temp.path)) ?? []
    return Set(names.filter { $0.hasPrefix("FrameJobLink-") })
}
do {
    // A multipart/x-mixed-replace body is a response per part: the second is refused, and
    // the one folder the first made is removed.
    let before = linkFolders()
    let got = fetch("/multipart/40", roomy, id: "F9")
    let made = linkFolders().subtracting(before)
    row(
        "F9",
        got.sentence == "the server answered more than once" && made.isEmpty,
        "\(got.said) after \(String(format: "%.1f", got.seconds)) s; FrameJobLink-* folders "
            + "this fetch left: \(made.count)")
    for name in made {
        try? FileManager.default.removeItem(
            at: FileManager.default.temporaryDirectory.appendingPathComponent(name))
    }
}

// MARK: - K: one at a time, and the folder

do {
    var handed: [(folder: URL, held: Bool, origin: String)] = []
    var unreadable = false
    let controller = GraphicLinkController(
        scheme: "framejob", policy: loopback, limits: roomy,
        handOff: { fetched, origin, afterRead in
            let bytes = FileManager.default.contents(atPath: fetched.file.path)
            handed.append((fetched.folder, bytes == served, origin))
            afterRead(unreadable ? "x.fjgraphic cannot be imported: a stand-in refusal" : nil)
        })
    var outcomes: [Int: GraphicLinkController.Outcome] = [:]
    func open(_ index: Int, _ path: String) {
        controller.receive(link(base + path)) { outcomes[index] = $0 }
    }
    func words(_ index: Int) -> String {
        switch outcomes[index] {
        case .sheet(let first, let final, let bytes, let gone):
            return "sheet \(first)→\(final) \(bytes) bytes, temp removed \(gone)"
        case .refused(let host, let sentence, _): return "refused(\(host ?? "-")): \(sentence)"
        case .unreadable(let host, let message, let gone):
            return "unreadable(\(host)): \(message), temp removed \(gone)"
        case nil: return "NO ANSWER"
        }
    }
    open(1, "/slow/1500/late.fjgraphic")
    open(2, "/pkg/late.fjgraphic")
    let secondAtOnce = words(2)
    spin(12) { outcomes[1] != nil }
    open(3, "/pkg/late.fjgraphic")
    spin(12) { outcomes[3] != nil }
    var sheets = 0
    for index in [1, 3] { if case .sheet = outcomes[index] { sheets += 1 } }
    row(
        "K1",
        secondAtOnce == "refused(-): Frame Job is already fetching a graphic from 127.0.0.1"
            && sheets == 2 && handed.count == 2,
        "second, at once: \(secondAtOnce) | first: \(words(1)) | third: \(words(3)); handed "
            + "\(handed.count)")
    let gone = handed.allSatisfy { !FileManager.default.fileExists(atPath: $0.folder.path) }
    var reported = true
    for index in [1, 3] {
        if case .sheet(_, _, _, true) = outcomes[index] { continue }
        reported = false
    }
    unreadable = true
    open(4, "/pkg/late.fjgraphic")
    spin(12) { outcomes[4] != nil }
    var refusedGone = false
    if case .unreadable("127.0.0.1", "x.fjgraphic cannot be imported: a stand-in refusal", true) =
        outcomes[4]
    {
        refusedGone = handed.last.map { !FileManager.default.fileExists(atPath: $0.folder.path) }
            ?? false
    }
    row(
        "K2",
        handed.count == 3 && handed.allSatisfy(\.held) && gone && reported && refusedGone
            && handed.allSatisfy { $0.origin == "From: 127.0.0.1" },
        "handed \(handed.count), each holding the served bytes \(handed.allSatisfy(\.held)); "
            + "folders gone after the read \(gone), reported \(reported); a refused read: "
            + "\(words(4)), folder gone \(refusedGone); origin \(handed.first?.origin ?? "none")")
    row(
        "K3", leftovers.isEmpty,
        leftovers.isEmpty
            ? "no refused fetch of F2–F8 left its folder"
            : "left behind by: \(leftovers.joined(separator: ", "))")
    row(
        "K4",
        GraphicLinkController.origin(first: "a.example.com", final: "cdn.example.net")
            == "From: cdn.example.net (the link named a.example.com)",
        GraphicLinkController.origin(first: "a.example.com", final: "cdn.example.net"))
}

let data = try JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
