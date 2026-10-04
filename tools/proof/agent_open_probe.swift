// Issue batch B79 — an agent's `open_project` reads off the main thread (spec
// §11 #231): the probe behind `agent_open_proof.py`'s rows A0–A7. Issue batch
// B81 — one document per path while a person's open is in flight (spec §11
// #234): rows A8–A14.
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
// between two ticks. A tick is main running: a read on main gives none. It
// also notes the milliseconds from the call's start to its first and last
// partial tick, so a call's seconds divide into before, during and after
// the copy's write (#235).
//
// A8–A14 race a person's open against an agent's call. Nothing there sleeps
// for a guessed time: `ProbeDocumentController`'s two `makeDocument`
// overrides HOLD a finished read, off main, until the other side has got as
// far as the row needs (`Race`), each hold bounded at 120 s, and an expired
// hold fails its row by name. The overrides also note `Thread.isMainThread`
// as each person's read is entered, and A8, A10 and A11 — File ▸ Open's own
// action, the direct call and reopen — print the count and fail when a
// person's read was entered on the main thread, or none was entered.
//
// Prints exactly one stdout line:
//   ANSWER {"rows":[{"id","ok","detail"}],"measure":{…}}
import AppKit

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

/// What rows A8–A14 share with the controller's overrides: how long a
/// finished read is held, and what each side did. Any thread; one lock.
final class Race {
    /// When a person's read (one not inside `withoutAsking`) is let go.
    enum Mode {
        /// Once `opens(of:)` has answered above 0 to someone — the agent's
        /// step saw the open in flight — or the row's agent call answered.
        case seen
        /// Once the row's agent call has answered.
        case answered
    }

    static let holdBound: TimeInterval = 120

    private let lock = NSLock()
    private var mode: Mode?
    private var holdsAgent = false
    private var agentCall: Pending?
    private var panel: URL?
    private var askedAbove = false
    private var personCalled = false
    private var personEntered = 0
    private var personOnMain = 0
    private var agentEntered = 0
    private var agentMade: [NSDocument] = []
    private var entered: [String: Int] = [:]
    private var errors = 0
    private var late: [String] = []
    private var ended: (document: NSDocument?, wasOpen: Bool, error: (any Error)?)?

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    /// A row begins: `person` is how its person's read is held (nil: not at
    /// all), `holdsAgent` whether the agent's read waits for the person-style
    /// open to have been called, `panel` what the Open panel answers.
    func begin(person: Mode?, holdsAgent agent: Bool = false, panel url: URL? = nil) {
        locked {
            (mode, holdsAgent, agentCall, panel) = (person, agent, nil, url)
            (askedAbove, personCalled, personEntered, agentEntered) = (false, false, 0, 0)
            personOnMain = 0
            (agentMade, entered, errors, late, ended) = ([], [:], 0, [], nil)
        }
    }

    /// No hold from here on; the counts stay readable.
    func end() { locked { (mode, holdsAgent) = (nil, false) } }

    func agent(_ call: Pending) { locked { agentCall = call } }
    func noteAsk() { locked { askedAbove = true } }
    func notePersonCalled() { locked { personCalled = true } }
    func noteOpen(_ url: URL) { locked { entered[canonical(url.path), default: 0] += 1 } }
    func noteError() { locked { errors += 1 } }
    func noteEnd(_ document: NSDocument?, _ wasOpen: Bool, _ error: (any Error)?) {
        locked { ended = (document, wasOpen, error) }
    }
    /// A read entered `makeDocument`; `onMain` is that thread's own
    /// `Thread.isMainThread`, kept for a person's read.
    func noteEntered(agent: Bool, onMain: Bool) {
        locked {
            if agent { agentEntered += 1 } else { personEntered += 1 }
            if !agent && onMain { personOnMain += 1 }
        }
    }
    func noteMade(_ document: NSDocument, agent: Bool) {
        locked { if agent { agentMade.append(document) } }
    }

    var panelURL: URL? { locked { panel } }
    var personMakes: Int { locked { personEntered } }
    var personMakesOnMain: Int { locked { personOnMain } }
    var agentMakes: Int { locked { agentEntered } }
    var agentDocuments: [NSDocument] { locked { agentMade } }
    var presented: Int { locked { errors } }
    var expired: [String] { locked { late } }
    var completion: (document: NSDocument?, wasOpen: Bool, error: (any Error)?)? {
        locked { ended }
    }
    func opens(_ url: URL) -> Int { locked { entered[canonical(url.path)] ?? 0 } }

    private func released(agent: Bool) -> Bool {
        locked {
            if agent { return !holdsAgent || personCalled }
            guard let mode else { return true }
            let answered = agentCall?.value != nil
            return mode == .seen ? askedAbove || answered : answered
        }
    }

    /// Holds a finished read until the other side has got far enough. Never
    /// on main, where a hold could not end; bounded, and an expiry is named.
    func hold(agent: Bool) {
        guard !Thread.isMainThread else { return }
        let deadline = Date().addingTimeInterval(Self.holdBound)
        while !released(agent: agent) {
            if Date() >= deadline {
                locked {
                    late.append("\(agent ? "the agent's" : "the person's") read was held "
                        + "\(Int(Self.holdBound)) s and let go unreleased")
                }
                return
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }
}

func canonical(_ path: String) -> String {
    URL(fileURLWithPath: path).resolvingSymlinksInPath().path
}

let race = Race()

/// A probe outside the bundle has no Info.plist, so the shared controller
/// can name neither a file's type nor the document class
/// (`recording_probe.py`'s precedent): the FIRST controller instantiated
/// becomes `.shared`. It is the app's own `ProjectDocumentController` (spec
/// §11 #234) with the seams rows A8–A14 need: what was asked and entered is
/// noted in `race`, a read is held after it is made, the Open panel answers
/// the row's URL with no panel, and a presented error is counted, not shown.
final class ProbeDocumentController: ProjectDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }

    override func typeForContents(of url: URL) throws -> String {
        url.pathExtension.lowercased() == ProjectDocument.projectFileExtension
            ? ProjectDocument.projectTypeIdentifier : "public.movie"
    }

    override func documentClass(forType typeName: String) -> AnyClass? { ProjectDocument.self }

    override func opens(of url: URL) -> Int {
        let count = super.opens(of: url)
        if count > 0 { race.noteAsk() }
        return count
    }

    override func openDocument(
        withContentsOf url: URL, display displayDocument: Bool,
        completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void
    ) {
        race.noteOpen(url)
        super.openDocument(withContentsOf: url, display: displayDocument) {
            document, wasOpen, error in
            race.noteEnd(document, wasOpen, error)
            completionHandler(document, wasOpen, error)
        }
    }

    override func beginOpenPanel(completionHandler: @escaping ([URL]?) -> Void) {
        let urls = race.panelURL.map { [$0] }
        DispatchQueue.main.async { completionHandler(urls) }
    }

    override func presentError(_ error: any Error) -> Bool {
        race.noteError()
        return false
    }

    override func makeDocument(withContentsOf url: URL, ofType typeName: String) throws
        -> NSDocument {
        let agent = MediaImporter.isWithoutAsking
        race.noteEntered(agent: agent, onMain: Thread.isMainThread)
        let document = try super.makeDocument(withContentsOf: url, ofType: typeName)
        race.noteMade(document, agent: agent)
        race.hold(agent: agent)
        return document
    }

    override func makeDocument(
        for urlOrNil: URL?, withContentsOf contentsURL: URL, ofType typeName: String
    ) throws -> NSDocument {
        let agent = MediaImporter.isWithoutAsking
        race.noteEntered(agent: agent, onMain: Thread.isMainThread)
        let document = try super.makeDocument(
            for: urlOrNil, withContentsOf: contentsURL, ofType: typeName)
        race.noteMade(document, agent: agent)
        race.hold(agent: agent)
        return document
    }
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
    /// Milliseconds from `begin` to the first and the last tick that saw the
    /// partial; nil when none did.
    var firstPartialMs: Int?
    var lastPartialMs: Int?
    private var last: CFAbsoluteTime?
    private var began = CFAbsoluteTimeGetCurrent()

    func begin(onFirstPartial hook: (() -> Void)? = nil) {
        (ticks, partial, live, longestGap, last) = (0, 0, 0, 0, nil)
        (firstPartialMs, lastPartialMs, began) = (nil, nil, CFAbsoluteTimeGetCurrent())
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
            let ms = Int(((now - began) * 1000).rounded())
            if firstPartialMs == nil { firstPartialMs = ms }
            lastPartialMs = ms
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
    let seconds = (Date().timeIntervalSince(started) * 1000).rounded() / 1000
    facts["seconds"] = seconds
    // Where the call's seconds went (#235): before the copy's partial was
    // first seen, while it was being written, and after it was last seen.
    if let first = ticker.firstPartialMs, let last = ticker.lastPartialMs {
        facts["before_partial_s"] = Double(first) / 1000
        facts["partial_s"] = Double(last - first) / 1000
        facts["after_partial_s"] = ((seconds - Double(last) / 1000) * 1000).rounded() / 1000
    } else {
        facts["before_partial_s"] = NSNull()
        facts["partial_s"] = NSNull()
        facts["after_partial_s"] = NSNull()
    }
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
    func seconds(_ name: String) -> String {
        (facts[name] as? Double).map { String(format: "%.3f", $0) } ?? "no"
    }
    return "\(facts["seconds"] ?? "?") s (\(seconds("before_partial_s")) s before the "
        + ".partial.mov was first seen, \(seconds("partial_s")) s while it was written, "
        + "\(seconds("after_partial_s")) s after it was last seen); "
        + "\(facts["ticks"] ?? "?") main ticks, "
        + "\(facts["partial_ticks"] ?? "?") saw the .partial.mov, \(facts["live_ticks"] ?? "?") "
        + "saw a progress controller, longest gap \(facts["longest_gap_ms"] ?? "?") ms"
}

func count(_ key: String, _ name: String) -> Int {
    (measure[key] as? [String: Any])?[name] as? Int ?? 0
}

/// The fewest partial ticks A2 and A5 want. A count, not a timing: main ran
/// while the copy was written. How many ticks a copy lasts is the disk's
/// (#235: a re-copy's partial ticks went as low as 13 on a busy host).
let partialFloor = 3

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
    row("A2", count("a1", "partial_ticks") >= partialFloor,
        "\(count("a1", "partial_ticks")) main ticks saw the .partial.mov during the call "
            + "(at least \(partialFloor) wanted: a count; the copy's seconds are the disk's)")
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
    row("A5", count("a4", "partial_ticks") >= partialFloor,
        "\(count("a4", "partial_ticks")) main ticks saw the .partial.mov during the call "
            + "(at least \(partialFloor) wanted: a count; the copy's seconds are the disk's)")
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

// MARK: - A8–A14: one document per path while an open is in flight (#234)

let packageURL = URL(fileURLWithPath: package)
let controller = NSDocumentController.shared
let refusal = "is being opened in a window"

/// Spins main until `done` or `seconds` have passed; whether it was done.
func settle(_ seconds: Double, _ done: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while !done() && Date() < deadline { spin(0.02) }
    return done()
}

/// The call Welcome's Recent row and `FileDropView`'s drops make.
func personOpen(_ url: URL) {
    controller.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    race.notePersonCalled()
}

/// What a race row prints about where it ended: the documents at the
/// package's path, whether the one there is the person's open's own, the
/// errors and the holds.
func ending() -> (line: String, one: Bool, clean: Bool) {
    let landed = settle(10) { race.completion != nil }
    let holders = documents(at: package)
    let done = race.completion
    let same = holders.count == 1 && holders.first === done?.document
    let error = done?.error.map { $0.localizedDescription } ?? "nil"
    let late = race.expired
    return ("\(holders.count) open documents at the package's path, the person's open's own "
        + "\(same) (its completion called \(landed), error \(error)); "
        + "\(race.presented) errors presented; "
        + (late.isEmpty ? "no hold expired" : "EXPIRED: " + late.joined(separator: "; ")),
        same && landed && done?.error == nil,
        race.presented == 0 && late.isEmpty)
}

/// Where the row's person's reads were entered: the line, and whether at
/// least one was entered and none on the main thread.
func personThread() -> (line: String, offMain: Bool) {
    let (made, onMain) = (race.personMakes, race.personMakesOnMain)
    return ("the person's read entered makeDocument \(made) time(s), \(onMain) of them on the "
        + "main thread (at least 1, and 0 on main, wanted)", made >= 1 && onMain == 0)
}

/// Whether a document the agent's read made is among the open documents.
func agentDocumentOpen() -> Bool {
    race.agentDocuments.contains { made in controller.documents.contains { $0 === made } }
}

// A8, A9: File ▸ Open's own action, then the agent's call mid-read.
do {
    closeAll()
    race.begin(person: .seen, panel: packageURL)
    controller.openDocument(nil)
    let entered = settle(10) { race.opens(packageURL) >= 1 }
    let call = serve("open_project", ["path": package])
    race.agent(call)
    let result = wait(call, 150)
    let end = ending()
    let thread = personThread()
    row("A8", entered && !isError(result) && body(result)["already_open"] as? Bool == true
        && end.one && end.clean && race.opens(packageURL) == 1 && thread.offMain,
        "openDocument(nil) with the panel answering a4.reelcut: the open's override entered "
            + "\(race.opens(packageURL)) time(s); open_project mid-read: already_open "
            + "\(alreadyOpen(result)) (\(brief(result).prefix(60))); " + end.line
            + "; " + thread.line)
    row("A9", race.agentMakes == 0,
        "\(race.agentMakes) reads by the agent during A8 (\(race.personMakes) by the person)")
    race.end()
}

// A10: the agent's read first, held; the person-style open mid-read.
do {
    closeAll()
    race.begin(person: .seen, holdsAgent: true)
    let call = serve("open_project", ["path": package])
    race.agent(call)
    let entered = settle(60) { race.agentMakes >= 1 }
    personOpen(packageURL)
    let result = wait(call, 150)
    let end = ending()
    let leaked = agentDocumentOpen()
    let thread = personThread()
    row("A10", entered && !isError(result) && body(result)["already_open"] as? Bool == true
        && end.one && end.clean && race.agentMakes == 1 && !leaked && thread.offMain,
        "open_project first, its read held; openDocument(withContentsOf:display:) mid-read: "
            + "already_open \(alreadyOpen(result)) (\(brief(result).prefix(60))); "
            + "\(race.agentMakes) read(s) by the agent, its document among the open ones "
            + "\(leaked); " + end.line + "; " + thread.line)
    race.end()
}

// A11: A8 by reopenDocument(for:withContentsOf:display:).
do {
    closeAll()
    race.begin(person: .seen)
    controller.reopenDocument(for: packageURL, withContentsOf: packageURL, display: true) {
        document, wasOpen, error in
        race.noteEnd(document, wasOpen, error)
    }
    let call = serve("open_project", ["path": package])
    race.agent(call)
    let result = wait(call, 150)
    let end = ending()
    let thread = personThread()
    row("A11", !isError(result) && body(result)["already_open"] as? Bool == true
        && end.one && end.clean && race.personMakes == 1 && race.agentMakes == 0
        && thread.offMain,
        "reopenDocument(for:withContentsOf:display:), then open_project mid-read: already_open "
            + "\(alreadyOpen(result)) (\(brief(result).prefix(60))); \(race.personMakes) "
            + "read(s) by the person, \(race.agentMakes) by the agent; " + end.line
            + "; " + thread.line)
    race.end()
}

// A12: the wait's bound at step A.
AgentServer.personOpenWait = 1
do {
    closeAll()
    race.begin(person: .answered)
    personOpen(packageURL)
    let started = Date()
    let call = serve("open_project", ["path": package])
    race.agent(call)
    let result = wait(call, 150)
    let seconds = Date().timeIntervalSince(started)
    let end = ending()
    row("A12", isError(result) && text(result).contains(refusal) && seconds >= 1
        && race.agentMakes == 0 && end.one && end.clean,
        "personOpenWait 1 s; the person's open held until the call answers; open_project: "
            + "\(brief(result).prefix(120)) after \(String(format: "%.3f", seconds)) s (no "
            + "sooner than 1 wanted); \(race.agentMakes) read(s) by the agent; then " + end.line)
    race.end()
}

// A13: the wait's bound at step C.
do {
    closeAll()
    race.begin(person: .answered, holdsAgent: true)
    let call = serve("open_project", ["path": package])
    race.agent(call)
    let entered = settle(60) { race.agentMakes >= 1 }
    let started = Date()
    personOpen(packageURL)
    let result = wait(call, 150)
    let seconds = Date().timeIntervalSince(started)
    let end = ending()
    let leaked = agentDocumentOpen()
    row("A13", entered && isError(result) && text(result).contains(refusal) && seconds >= 1
        && race.agentMakes == 1 && !leaked && end.one && end.clean,
        "personOpenWait 1 s; open_project first, its read held; the person-style open "
            + "mid-read, held until the call answers; open_project: "
            + "\(brief(result).prefix(120)) \(String(format: "%.3f", seconds)) s after the "
            + "person's open was called (no sooner than 1 wanted); \(race.agentMakes) read(s) "
            + "by the agent, its document among the open ones \(leaked); then " + end.line)
    race.end()
}
AgentServer.personOpenWait = 30

// A14: new_project onto a path a person's open is reading.
do {
    closeAll()
    let file = packageURL.appendingPathComponent("project.json")
    let before = try? Data(contentsOf: file)
    race.begin(person: .answered)
    personOpen(packageURL)
    let call = serve("new_project", ["path": package])
    race.agent(call)
    let result = wait(call, 150)
    let end = ending()
    let after = try? Data(contentsOf: file)
    let open = AgentServer.shared.openProjects().count
    row("A14", isError(result) && text(result).contains(refusal)
        && text(result).contains("new_project did not write there")
        && before != nil && before == after && end.one && end.clean && open == 1,
        "the person-style open, held until the call answers; new_project {path: a4.reelcut}: "
            + "\(brief(result).prefix(160)); project.json's bytes unchanged "
            + "\(before != nil && before == after) (\(before?.count ?? -1) → "
            + "\(after?.count ?? -1)); then " + end.line + "; \(open) open project(s) in all")
    race.end()
}

closeAll()
answer()
