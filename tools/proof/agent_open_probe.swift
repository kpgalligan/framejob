// Issue batch B79 — an agent's `open_project` reads off the main thread (spec
// §11 #231): the probe behind `agent_open_proof.py`'s rows A0–A7.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `Reelcut`, against `libreelcut_core.a` —
// `tools/proof/harness/build.sh`'s swiftc line, `-D REELCUT_DEV_TOOLS` — by
// `agent_open_proof.py`, on `assistant_lane_probe.swift`'s pattern: a
// `.prohibited` process, `AgentLane.prepareAtLaunch()`, and every call made
// through `AgentLane.shared.serve` from a background thread while main spins
// its run loop, as the MCP server thread calls it.
//
//   agent_open_probe <work-dir> <big.webm> <scratch-home>
//
// The script launches it with `CFFIXED_USER_HOME=<scratch-home>`, so
// `AppSupport.directory` — and with it `Rewrapped/` — is inside the proof's
// work folder. A0 holds that before any call: when `Rewrapped/` resolves
// anywhere else the probe answers A0 failed and runs nothing.
//
// A 10 ms timer on the main run loop (`.common`) counts, during each call:
// its ticks, the ticks that saw a `.partial.mov` in `Rewrapped/`, the ticks
// with `RewrapProgressWindowController.live` non-empty, and the longest gap
// between two ticks. A tick is main running: a read on main gives none.
//
// Prints exactly one stdout line:
//   ANSWER {"rows":[{"id","ok","detail"}],"measure":{…}}
import AppKit

/// A probe outside the bundle has no Info.plist, so the shared controller
/// can name neither a file's type nor the document class
/// (`recording_probe.py`'s precedent): the FIRST controller instantiated
/// becomes `.shared`.
final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }

    override func typeForContents(of url: URL) throws -> String {
        url.pathExtension.lowercased() == ProjectDocument.projectFileExtension
            ? ProjectDocument.projectTypeIdentifier : "public.movie"
    }

    override func documentClass(forType typeName: String) -> AnyClass? { ProjectDocument.self }
}
_ = ProbeDocumentController()

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let delegate = AppDelegate()
delegate.applicationWillFinishLaunching(
    Notification(name: NSApplication.willFinishLaunchingNotification, object: app))

let argv = CommandLine.arguments
let work = argv.count > 1 ? argv[1] : NSTemporaryDirectory()
let fixture = URL(fileURLWithPath: argv.count > 2 ? argv[2] : "")
let scratchHome = URL(fileURLWithPath: argv.count > 3 ? argv[3] : "/nonexistent-b79-home")
let manager = FileManager.default

AgentLane.prepareAtLaunch()

var rows: [[String: Any]] = []
var measure: [String: Any] = [:]

func row(_ id: String, _ ok: Bool, _ detail: String) {
    rows.append(["id": id, "ok": ok, "detail": String(detail.prefix(1500))])
}

func answer() -> Never {
    let body: [String: Any] = ["rows": rows, "measure": measure]
    let data = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]))
        ?? Data("{}".utf8)
    print("ANSWER " + (String(data: data, encoding: .utf8) ?? "{}"))
    fflush(stdout)
    exit(0)
}

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
}

func json(_ object: [String: Any]) -> String {
    String(data: (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8),
           encoding: .utf8) ?? "{}"
}

/// A result crossing from the lane's thread to main.
final class Pending {
    private let lock = NSLock()
    private var stored: String?

    var value: String? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ result: String) {
        lock.lock()
        stored = result
        lock.unlock()
    }
}

/// `serve`, from a background thread, as the MCP server thread calls it.
func serve(_ tool: String, _ arguments: [String: Any]) -> Pending {
    let pending = Pending()
    let body = json(arguments)
    DispatchQueue.global().async {
        pending.set(AgentLane.shared.serve(tool: tool, argumentsJSON: body))
    }
    return pending
}

func wait(_ pending: Pending, _ seconds: Double) -> String? {
    let deadline = Date().addingTimeInterval(seconds)
    while pending.value == nil && Date() < deadline { spin(0.02) }
    return pending.value
}

func parsed(_ result: String?) -> [String: Any] {
    guard let result = result else { return [:] }
    return (try? JSONSerialization.jsonObject(with: Data(result.utf8))) as? [String: Any] ?? [:]
}

func isError(_ result: String?) -> Bool {
    guard result != nil else { return true }
    return parsed(result)["isError"] as? Bool == true
}

func text(_ result: String?) -> String {
    ((parsed(result)["content"] as? [[String: Any]]) ?? []).compactMap { $0["text"] as? String }
        .joined(separator: " ")
}

/// The tool's own JSON answer, out of its text block.
func body(_ result: String?) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(text(result).utf8))) as? [String: Any] ?? [:]
}

/// The answer's `already_open`, as the detail prints it.
func alreadyOpen(_ result: String?) -> String {
    (body(result)["already_open"] as? Bool).map { String($0) } ?? "absent"
}

func brief(_ result: String?) -> String {
    guard let result = result else { return "no answer" }
    return (isError(result) ? "error: " : "ok: ") + String(text(result).prefix(200))
}

func canonical(_ path: String) -> String {
    URL(fileURLWithPath: path).resolvingSymlinksInPath().path
}

// MARK: - A0: the scratch home

let rewrapped = AppSupport.subdirectory("Rewrapped")
let fixtureBytes =
    ((try? manager.attributesOfItem(atPath: fixture.path))?[.size] as? NSNumber)?.intValue ?? 0
let homeRoot = canonical(scratchHome.path) + "/"
let insideHome = rewrapped.map { canonical($0.path).hasPrefix(homeRoot) } ?? false
measure["rewrapped"] = rewrapped?.path ?? NSNull()
measure["fixture_bytes"] = fixtureBytes
row("A0", insideHome && fixtureBytes > 0,
    "Rewrapped/ is \(rewrapped?.path ?? "nil"), inside the scratch home \(scratchHome.path): "
        + "\(insideHome); the fixture \(fixture.lastPathComponent) is \(fixtureBytes) bytes")
let rewrappedFolder = rewrapped ?? URL(fileURLWithPath: "/nonexistent-b79-rewrapped")
if !insideHome || fixtureBytes <= 0 { answer() }

/// Whether `path` is a file directly inside the scratch home's `Rewrapped/`.
func inRewrapped(_ path: String) -> Bool {
    canonical((path as NSString).deletingLastPathComponent) == canonical(rewrappedFolder.path)
}

func sawPartial() -> Bool {
    ((try? manager.contentsOfDirectory(atPath: rewrappedFolder.path)) ?? [])
        .contains { $0.hasSuffix(".partial.mov") }
}

// MARK: - The main-thread ticker

/// What main saw during one call. Main only.
final class Ticker {
    var active = false
    var ticks = 0
    var partial = 0
    var live = 0
    var longestGap = 0.0
    var onFirstPartial: (() -> Void)?
    private var last: CFAbsoluteTime?

    func begin(onFirstPartial hook: (() -> Void)? = nil) {
        (ticks, partial, live, longestGap, last) = (0, 0, 0, 0, nil)
        onFirstPartial = hook
        active = true
    }

    func tick() {
        guard active else { return }
        let now = CFAbsoluteTimeGetCurrent()
        if let last { longestGap = max(longestGap, now - last) }
        last = now
        ticks += 1
        if sawPartial() {
            partial += 1
            if partial == 1 { onFirstPartial?() }
        }
        if !RewrapProgressWindowController.live.isEmpty { live += 1 }
    }

    var facts: [String: Any] {
        ["ticks": ticks, "partial_ticks": partial, "live_ticks": live,
         "longest_gap_ms": Int((longestGap * 1000).rounded())]
    }
}

let ticker = Ticker()
let timer = Timer(timeInterval: 0.01, repeats: true) { _ in ticker.tick() }
RunLoop.main.add(timer, forMode: .common)

/// One `open_project` call, with what main saw while it ran.
func openProject(
    _ path: String, _ key: String, onFirstPartial hook: (() -> Void)? = nil
) -> String? {
    ticker.begin(onFirstPartial: hook)
    let started = Date()
    let result = wait(serve("open_project", ["path": path]), 600)
    ticker.active = false
    var facts = ticker.facts
    facts["seconds"] = (Date().timeIntervalSince(started) * 1000).rounded() / 1000
    measure[key] = facts
    return result
}

func documents(at path: String) -> [ProjectDocument] {
    AgentServer.shared.openProjects().filter {
        AgentServer.path(of: $0).map(canonical) == canonical(path)
    }
}

func closeAll() {
    for document in AgentServer.shared.openProjects() { document.close() }
    spin(0.2)
}

/// The first media of the one document at `path`: its path and original.
func firstMedia(at path: String) -> (path: String, original: String?)? {
    guard let media = documents(at: path).first?.project.snapshot.media.first else { return nil }
    return (media.path, media.original?.path)
}

func ticksLine(_ key: String) -> String {
    let facts = measure[key] as? [String: Any] ?? [:]
    return "\(facts["seconds"] ?? "?") s; \(facts["ticks"] ?? "?") main ticks, "
        + "\(facts["partial_ticks"] ?? "?") saw the .partial.mov, \(facts["live_ticks"] ?? "?") "
        + "saw a progress controller, longest gap \(facts["longest_gap_ms"] ?? "?") ms"
}

func count(_ key: String, _ name: String) -> Int {
    (measure[key] as? [String: Any])?[name] as? Int ?? 0
}

// MARK: - A1–A3: open_project of the WebM

let opened = openProject(fixture.path, "a1")
let firstCopy = firstMedia(at: fixture.path)
do {
    let answered = body(opened)
    let mediaCount = documents(at: fixture.path).first?.project.snapshot.media.count ?? 0
    let onDisk = firstCopy.map { manager.fileExists(atPath: $0.path) } ?? false
    row("A1", !isError(opened) && answered["project"] != nil && answered["already_open"] == nil
        && mediaCount == 1 && (firstCopy.map { inRewrapped($0.path) } ?? false) && onDisk,
        "open_project {\(fixture.lastPathComponent)}: \(brief(opened).prefix(80)); "
            + "already_open \(alreadyOpen(opened)); media \(mediaCount), "
            + "path \(firstCopy?.path ?? "nil") on disk \(onDisk); \(ticksLine("a1"))")
    row("A2", count("a1", "partial_ticks") >= 10,
        "\(count("a1", "partial_ticks")) main ticks saw the .partial.mov during the call "
            + "(at least 10 wanted)")
    row("A3", count("a1", "live_ticks") == 0 && count("a1", "ticks") > 0,
        "\(count("a1", "live_ticks")) of \(count("a1", "ticks")) main ticks saw a progress "
            + "controller in RewrapProgressWindowController.live")
}

// MARK: - A4–A6: the re-copy on open

let package = (work as NSString).appendingPathComponent("a4.reelcut")
try? manager.removeItem(atPath: package)

/// Removes the copy at `path` when it is a file directly in the scratch
/// home's `Rewrapped/`; whether it did.
func removeCopy(_ path: String?) -> Bool {
    guard let path, inRewrapped(path), manager.fileExists(atPath: path) else { return false }
    return (try? manager.removeItem(atPath: path)) != nil
}

/// `project.json`'s first media pointed at a path that is not there, with no
/// bookmark (`container_import_proof.py` M9's method).
func breakFirstMedia(_ package: String) -> Bool {
    let url = URL(fileURLWithPath: package).appendingPathComponent("project.json")
    guard let data = try? Data(contentsOf: url),
        var project = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
        var media = project["media"] as? [[String: Any]], !media.isEmpty,
        let path = media[0]["path"] as? String
    else { return false }
    media[0]["path"] = "/nonexistent-b79/" + (path as NSString).lastPathComponent
    media[0]["bookmark"] = NSNull()
    project["media"] = media
    guard let out = try? JSONSerialization.data(withJSONObject: project) else { return false }
    return (try? out.write(to: url, options: .atomic)) != nil
}

do {
    let saved = wait(serve("save_project", ["project": fixture.path, "path": package]), 180)
    let closed = wait(serve("close_project", ["project": package, "discard": true]), 60)
    let broken = breakFirstMedia(package)
    let removed = removeCopy(firstCopy?.path)
    let set = !isError(saved) && !isError(closed) && broken && removed
    let reopened = set ? openProject(package, "a4") : nil
    let media = firstMedia(at: package)
    let onDisk = media.map { manager.fileExists(atPath: $0.path) } ?? false
    let original = media?.original.map(canonical)
    row("A4", set && !isError(reopened) && body(reopened)["project"] != nil
        && (media.map { inRewrapped($0.path) } ?? false) && onDisk
        && original == canonical(fixture.path),
        "saved \(brief(saved).prefix(60)); closed \(brief(closed).prefix(60)); project.json "
            + "rewritten \(broken); copy removed \(removed); open_project {a4.reelcut}: "
            + "\(brief(reopened).prefix(80)); path \(media?.path ?? "nil") on disk \(onDisk), "
            + "original \(media?.original ?? "nil"); \(ticksLine("a4"))")
    row("A5", count("a4", "partial_ticks") >= 10,
        "\(count("a4", "partial_ticks")) main ticks saw the .partial.mov during the call "
            + "(at least 10 wanted)")
    row("A6", set && count("a4", "live_ticks") == 0 && count("a4", "ticks") > 0,
        "\(count("a4", "live_ticks")) of \(count("a4", "ticks")) main ticks saw a progress "
            + "controller in RewrapProgressWindowController.live")
}

// MARK: - A7: a document that came to hold the path during the read

do {
    let recopied = firstMedia(at: package)?.path
    let closed = wait(serve("close_project", ["project": package, "discard": true]), 60)
    let removed = removeCopy(recopied)
    var stubbed = false
    let raced = openProject(package, "a7") {
        // Main, on the first tick that sees the copy being written.
        let stub = ProjectDocument()
        stub.fileURL = URL(fileURLWithPath: package)
        NSDocumentController.shared.addDocument(stub)
        stubbed = true
    }
    let holders = documents(at: package).count
    row("A7", !isError(closed) && removed && stubbed && !isError(raced)
        && body(raced)["already_open"] as? Bool == true && holders == 1,
        "closed \(brief(closed).prefix(60)); copy removed \(removed); a stub document added "
            + "mid-read \(stubbed); open_project {a4.reelcut}: already_open "
            + "\(alreadyOpen(raced)) (\(brief(raced).prefix(60))); "
            + "\(holders) open documents at the package's path; \(ticksLine("a7"))")
}

closeAll()
answer()
