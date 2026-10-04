// Issue batch B80 — the opt-in ffmpeg conversion records its original (spec
// §11 #233) and copies a constant-rate VP9 stream, checked on the copy (#227):
// the probe behind `ffmpeg_rewrap_proof.py`'s rows F0, O1–O5, T1–T3, V1–V8.
// Issue batch B81 (spec §11 #227 as amended): V7's plan count, and rows V9
// (one re-encode per file), V10 (`discard(_:ifStill:)`), G1 (`onFrameGrid`),
// C1 (the ceilings) and P1 (no second attempt for a plan that copies no VP9);
// and M1 (spec §11 #234's risk): whether a tool's hop to the main thread is
// served while the conversion question is up.
//
// M1 is the one row that puts a window up: `FFmpegRewrap.consent(for:)`'s
// alert, twice, for about 2 s each, in this `.prohibited` process, which is
// never activated and takes no key window from anyone. Each showing is ended
// by `NSApp.abortModal()` from a `.common` timer, which answers the question
// "no"; nothing ticks its box, so `ask` remembers nothing. A showing that will
// not end is a scored FAILURE of M1 after 30 s, answered from a watchdog
// thread with every earlier row intact — never a hang.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `Reelcut`, against `libreelcut_core.a` —
// `tools/proof/harness/build.sh`'s swiftc line, `-D REELCUT_DEV_TOOLS` — by
// `ffmpeg_rewrap_proof.py`, on `agent_open_probe.swift`'s pattern: a
// `.prohibited` process, `AgentLane.prepareAtLaunch()`, every import made on a
// background thread while main spins its run loop.
//
//   ffmpeg_rewrap_probe <work-dir> <scratch-home> -RCFFmpegImport always \
//       -RCFFmpegPath <work-dir>/tools/ffmpeg
//
// The script launches it with `CFFIXED_USER_HOME=<scratch-home>`, so
// `AppSupport.directory` — and with it `Rewrapped/` — is inside the proof's
// work folder. F0 holds that before any import: when `Rewrapped/` resolves
// anywhere else the probe answers F0 failed and runs nothing. The two launch
// defaults are read from the argument domain; the probe writes no
// `UserDefaults`.
//
// `<work-dir>/tools/ffmpeg` is the script's wrapper: it appends its argv as a
// JSON line to `<work-dir>/ffmpeg.log` and obeys `<work-dir>/mode` (`pass`,
// `fail-copy`, `swap-copy`, `bad-encode`), which this probe writes before a
// row. A row's run count is the log's lines that hold `-i <its source>`,
// less the lines whose last argument is under `<work-dir>/t/` (the T rows'
// own runs). Its sibling `<work-dir>/tools/ffprobe`, which the product
// finds beside it, appends its argv to `<work-dir>/ffprobe.log`; a PLAN of a
// source is a line there that holds `-show_streams` and ends in its path.
//
// Prints exactly one stdout line:
//   ANSWER {"rows":[{"id","ok","detail"}],"measure":{…}}
import AVFoundation
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
let work = URL(fileURLWithPath: argv.count > 1 ? argv[1] : NSTemporaryDirectory())
let scratchHome = URL(fileURLWithPath: argv.count > 2 ? argv[2] : "/nonexistent-b80-home")
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

func canonical(_ path: String) -> String {
    URL(fileURLWithPath: path).resolvingSymlinksInPath().path
}

/// A value crossing from a background thread to main.
final class Pending<T> {
    private let lock = NSLock()
    private var stored: T?

    var value: T? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ result: T) {
        lock.lock()
        stored = result
        lock.unlock()
    }
}

/// `body` on a background thread while main spins; nil when it has not
/// returned within `seconds`.
func offMain<T>(_ seconds: Double = 300, _ body: @escaping () -> T) -> T? {
    let pending = Pending<T>()
    DispatchQueue.global().async { pending.set(body()) }
    let deadline = Date().addingTimeInterval(seconds)
    while pending.value == nil && Date() < deadline { spin(0.02) }
    return pending.value
}

/// `serve`, from a background thread, as the MCP server thread calls it.
func call(_ tool: String, _ arguments: [String: Any]) -> String? {
    let body = json(arguments)
    return offMain { AgentLane.shared.serve(tool: tool, argumentsJSON: body) }
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

func brief(_ result: String?) -> String {
    guard let result = result else { return "no answer" }
    return (isError(result) ? "error: " : "ok: ") + String(text(result).prefix(120))
}

// MARK: - F0: the scratch home and the wrapper

let rewrapped = AppSupport.subdirectory("Rewrapped")
let homeRoot = canonical(scratchHome.path) + "/"
let insideHome = rewrapped.map { canonical($0.path).hasPrefix(homeRoot) } ?? false
let wrapper = work.appendingPathComponent("tools").appendingPathComponent("ffmpeg")
let located = FFmpegRewrap.tools()
let wrapped = located.map { canonical($0.ffmpeg.path) == canonical(wrapper.path) } ?? false
measure["rewrapped"] = rewrapped?.path ?? NSNull()
measure["ffmpeg"] = located?.ffmpeg.path ?? NSNull()
measure["ffprobe"] = located?.ffprobe.path ?? NSNull()
measure["policy"] = FFmpegRewrap.policy.rawValue
row("F0", insideHome && wrapped && FFmpegRewrap.policy == .always,
    "Rewrapped/ is \(rewrapped?.path ?? "nil"), inside the scratch home \(scratchHome.path): "
        + "\(insideHome); FFmpegRewrap.tools()?.ffmpeg is \(located?.ffmpeg.path ?? "nil"), the "
        + "wrapper: \(wrapped); ffprobe \(located?.ffprobe.path ?? "nil"); policy "
        + "\(FFmpegRewrap.policy.rawValue)")
let rewrappedFolder = rewrapped ?? URL(fileURLWithPath: "/nonexistent-b80-rewrapped")
guard insideHome, wrapped, FFmpegRewrap.policy == .always, let tools = located else { answer() }

// MARK: - What the rows read

func fixture(_ name: String) -> URL { work.appendingPathComponent(name) }

/// Whether `path` is a file directly inside the scratch home's `Rewrapped/`.
func inRewrapped(_ path: String) -> Bool {
    canonical((path as NSString).deletingLastPathComponent) == canonical(rewrappedFolder.path)
}

func listing() -> [String] {
    ((try? manager.contentsOfDirectory(atPath: rewrappedFolder.path)) ?? []).sorted()
}

/// `Rewrapped/`'s files made for `source`: the finished ones and the partials.
func files(for source: URL) -> (finished: [String], partial: [String]) {
    let stem = source.deletingPathExtension().lastPathComponent + "-"
    let own = listing().filter { $0.hasPrefix(stem) }
    return (own.filter { !$0.hasSuffix(".partial.mov") },
            own.filter { $0.hasSuffix(".partial.mov") })
}

func setMode(_ mode: String) {
    try? Data(mode.utf8).write(to: work.appendingPathComponent("mode"), options: .atomic)
}

/// Every run of a wrapper so far, as its argv.
func log(_ name: String = "ffmpeg.log") -> [[String]] {
    let data = (try? Data(contentsOf: work.appendingPathComponent(name))) ?? Data()
    return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap {
        (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String]
    }
}

/// How many times the product planned `source`: the ffprobe wrapper's lines
/// that hold `-show_streams` and end in its path.
func plans(of source: URL) -> Int {
    log("ffprobe.log").filter { line in
        line.contains("-show_streams")
            && line.last.map { canonical($0) == canonical(source.path) } == true
    }.count
}

/// The product's ffmpeg runs over `source`: the lines that hold `-i <source>`,
/// less the T rows' own (their last argument is under `<work>/t/`).
func runs(for source: URL) -> [[String]] {
    let scratch = canonical(work.appendingPathComponent("t").path) + "/"
    return log().filter { line in
        guard let last = line.last, !canonical(last).hasPrefix(scratch),
            let index = line.firstIndex(of: "-i"), index + 1 < line.count
        else { return false }
        return canonical(line[index + 1]) == canonical(source.path)
    }
}

func holds(_ line: [String], _ flag: String, _ value: String) -> Bool {
    line.indices.dropLast().contains { line[$0] == flag && line[$0 + 1] == value }
}

func runsLine(_ lines: [[String]]) -> String {
    let each = lines.map { line in
        (holds(line, "-c:v", "copy") ? "-c:v copy" : "an encoder") + " "
            + (holds(line, "-f", "mp4") ? "-f mp4" : holds(line, "-f", "mov") ? "-f mov" : "-f ?")
    }
    return "\(lines.count) -i run(s) [\(each.joined(separator: "; "))]"
}

/// The first track of `type`'s format, as its four characters.
func format(_ url: URL, _ type: AVMediaType) -> String? {
    let asset = AVURLAsset(url: url)
    guard let track = CompositionBuilder.firstTrack(of: asset, mediaType: type),
        let description = (track.formatDescriptions as! [CMFormatDescription]).first
    else { return nil }
    let code = CMFormatDescriptionGetMediaSubType(description)
    return String(decoding: [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }, as: UTF8.self)
}

/// The first audio stream's sample-entry tag as the FILE spells it — the
/// real ffprobe's `codec_tag_string`, `mp4a` for AAC. CoreMedia's media
/// subtype for the same track is `aac ` (`format(_:_:)`), so the row reads
/// the file and prints both.
func audioTag(_ url: URL) -> String? {
    let arguments = [
        "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=codec_tag_string",
        "-of", "csv=p=0", url.path,
    ]
    guard let result = try? FFmpegRewrap.run(tools.ffprobe, arguments, timeout: 20),
        result.status == 0
    else { return nil }
    let text = String(decoding: result.output, as: UTF8.self)
    return text.split(whereSeparator: \.isNewline).first.map {
        $0.trimmingCharacters(in: .whitespaces)
    }
}

/// The first video frame decoded to 32BGRA: its size, whether the buffer is
/// BGRA, and `DecoderSupport.decodesFirstFrame`'s own answer.
func firstFrame(_ url: URL) -> (width: Int, height: Int, bgra: Bool, decodes: Bool)? {
    DecoderSupport.enable()
    let asset = AVURLAsset(url: url)
    guard let track = CompositionBuilder.firstTrack(of: asset, mediaType: .video),
        let reader = try? AVAssetReader(asset: asset)
    else { return nil }
    let decodes = DecoderSupport.decodesFirstFrame(of: track, in: asset)
    let output = AVAssetReaderTrackOutput(
        track: track,
        outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    guard reader.canAdd(output) else { return nil }
    reader.add(output)
    defer { reader.cancelReading() }
    guard reader.startReading() else { return (0, 0, false, decodes) }
    while let sample = output.copyNextSampleBuffer() {
        guard let image = CMSampleBufferGetImageBuffer(sample) else { continue }
        return (CVPixelBufferGetWidth(image), CVPixelBufferGetHeight(image),
                CVPixelBufferGetPixelFormatType(image) == kCVPixelFormatType_32BGRA, decodes)
    }
    return (0, 0, false, decodes)
}

/// The count: frame k asked for at exactly k·D/N, both tolerances zero. A
/// RIGHT answer is one whose actual time compares equal to the request.
func exactFrames(_ file: URL, _ num: Int, _ den: Int, _ count: Int)
    -> (right: Int, distinct: Int) {
    DecoderSupport.enable()
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: file))
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    var right = 0
    var seen = Set<Double>()
    for k in 0..<count {
        let request = CMTime(value: CMTimeValue(k * den), timescale: CMTimeScale(num))
        var actual = CMTime.invalid
        guard (try? generator.copyCGImage(at: request, actualTime: &actual)) != nil,
            actual.isValid
        else { continue }
        if CMTimeCompare(actual, request) == 0 { right += 1 }
        seen.insert(actual.seconds)
    }
    return (right, seen.count)
}

func countLine(_ counted: (right: Int, distinct: Int), _ num: Int, _ den: Int) -> String {
    "the count at \(num)/\(den): \(counted.right)/30 right, \(counted.distinct)/30 distinct"
}

/// One import through the product's blocking face, off the main thread.
func importing(_ source: URL) -> (descriptor: MediaDescriptor?, error: String?) {
    let outcome = offMain { Result { try MediaImporter.probeBlocking(url: source) } }
    switch outcome {
    case .success(let descriptor)?: return (descriptor, nil)
    case .failure(let error)?: return (nil, error.localizedDescription)
    case nil: return (nil, "no answer in 300 s")
    }
}

func hasOriginal(_ descriptor: MediaDescriptor?, _ source: URL) -> Bool {
    descriptor?.original.map { canonical($0.path) == canonical(source.path) } ?? false
}

/// A one-media project of `descriptor`, with `path` and `bookmark` swapped in.
func project(_ descriptor: MediaDescriptor, path: String, bookmark: String?) -> ReelProject? {
    var d = descriptor
    d.path = path
    d.bookmark = bookmark
    guard let base = ReelProject.new(width: 640, height: 360, fps: .thirty) else { return nil }
    return (try? base.applying(.addMedia(descriptor: d))).project
}

// MARK: - O1–O3: the conversion's original (#233)

setMode("pass")
let v0 = fixture("v0.mkv")
let converted = importing(v0)
do {
    let d = converted.descriptor
    var resolved: String?
    if let bookmark = d?.original?.bookmark, let data = Data(base64Encoded: bookmark) {
        var stale = false
        resolved = (try? URL(
            resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil,
            bookmarkDataIsStale: &stale))?.path
    }
    row("O1", d.map { inRewrapped($0.path) && manager.fileExists(atPath: $0.path) } ?? false
        && hasOriginal(d, v0) && resolved.map(canonical) == canonical(v0.path),
        "probeBlocking(v0.mkv): path \(d?.path ?? "nil") (\(converted.error ?? "no error")); "
            + "original.path \(d?.original?.path ?? "nil"); its bookmark resolves to "
            + "\(resolved ?? "nil")")
}

do {
    let v0a = fixture("v0a.mkv")
    let package = work.appendingPathComponent("o2.reelcut").path
    let made = call("new_project", ["path": package])
    let imported = call("import_media", ["project": package, "path": v0a.path])
    let read = call("get_project", ["project": package])
    let closed = call("close_project", ["project": package, "discard": true])
    let answered = body(imported)["original"] as? String
    let media = ((body(read)["project"] as? [String: Any])?["media"] as? [[String: Any]])?.first
    let stored = (media?["original"] as? [String: Any])?["path"] as? String
    row("O2", !isError(made) && !isError(imported) && !isError(closed)
        && answered.map(canonical) == canonical(v0a.path)
        && stored.map(canonical) == canonical(v0a.path),
        "new_project \(brief(made).prefix(40)); import_media {v0a.mkv} "
            + "\(brief(imported).prefix(60)) answers original \(answered ?? "absent"); get_project's media has original.path "
            + "\(stored ?? "absent"); close_project \(brief(closed).prefix(40))")
}

do {
    let added = converted.descriptor.flatMap { d in
        (try? ReelProject.new(width: 640, height: 360, fps: .thirty)?
            .applying(.addMedia(descriptor: d)))?.project
    }
    let media = added?.snapshot.media.first
    let tip = media.map { MediaRowView.toolTip(for: $0) } ?? ""
    let line = tip.split(separator: "\n").first.map(String.init) ?? ""
    let wanted = "\(v0.path) — copied into Reelcut's Rewrapped folder."
    let reveal = media.flatMap { revealURL(for: $0) }?.path
    row("O3", media?.name == "v0.mkv" && line == wanted
        && reveal.map(canonical) == canonical(v0.path),
        "add_media of O1's descriptor: MediaSnapshot.name \(media?.name ?? "nil"); the tooltip's "
            + "first line “\(line)”; revealURL \(reveal ?? "nil")")
}

// MARK: - T1–T3: the command's own output, no check between

try? manager.createDirectory(
    at: work.appendingPathComponent("t"), withIntermediateDirectories: true)

func commandRow(_ id: String, _ name: String, _ num: Int, _ den: Int) {
    let source = fixture(name)
    let plan = FFmpegRewrap.plan(for: source, with: tools)
    let output = work.appendingPathComponent("t").appendingPathComponent(
        source.deletingPathExtension().lastPathComponent + ".mov")
    var status: Int32?
    if let plan {
        let arguments = FFmpegRewrap.arguments(for: plan, with: tools, writing: output)
        status = offMain {
            (try? FFmpegRewrap.run(tools.ffmpeg, arguments, timeout: 120))?.status
        } ?? nil
    }
    let rate = plan?.videoRate
    let counted = manager.fileExists(atPath: output.path)
        ? exactFrames(output, num, den, 30) : (right: 0, distinct: 0)
    measure[id] = ["right": counted.right, "distinct": counted.distinct]
    row(id, plan?.copiesVP9 == true && rate == FFmpegRewrap.FrameRate(num: num, den: den)
        && status == 0 && counted.right == 30 && counted.distinct == 30,
        "\(name): plan copiesVP9 \(plan.map { String($0.copiesVP9) } ?? "no plan"), rate "
            + "\(rate.map { "\($0.num)/\($0.den)" } ?? "nil"); the command exits "
            + "\(status.map { String($0) } ?? "nothing"); \(countLine(counted, num, den))")
}

commandRow("T1", "v0.mkv", 30, 1)
commandRow("T2", "vn.mkv", 30000, 1001)
commandRow("T3", "v2.mkv", 30, 1)

// MARK: - V1–V8: the product's files (#227)

/// A VP9 copy the product kept: `vp09` with an `mp4a` sound entry, a first
/// frame that decodes to a 128×72 BGRA buffer, one copy run, every frame
/// exact.
func copiedRow(
    _ id: String, _ source: URL, _ imported: (descriptor: MediaDescriptor?, error: String?),
    _ num: Int, _ den: Int, wholeFrame: Bool
) {
    let file = imported.descriptor.map { URL(fileURLWithPath: $0.path) }
    let video = file.flatMap { format($0, .video) }
    let audio = file.flatMap { format($0, .audio) }
    let tag = file.flatMap(audioTag)
    let frame = file.flatMap(firstFrame)
    let ran = runs(for: source)
    let counted = file.map { exactFrames($0, num, den, 30) } ?? (right: 0, distinct: 0)
    measure[id] = ["right": counted.right, "distinct": counted.distinct]
    let frameOK = !wholeFrame || (tag == "mp4a" && frame.map {
        $0.width == 128 && $0.height == 72 && $0.bgra && $0.decodes
    } ?? false)
    row(id, video == "vp09" && frameOK && ran.count == 1
        && (ran.first.map { holds($0, "-c:v", "copy") && holds($0, "-f", "mp4") } ?? false)
        && counted.right == 30 && counted.distinct == 30,
        "\(source.lastPathComponent): \(file?.lastPathComponent ?? "no file") "
            + "(\(imported.error ?? "no error")); video \(video ?? "nil"), audio entry "
            + "\(tag ?? "nil") (CoreMedia subtype “\(audio ?? "nil")”); "
            + "first frame \(frame.map { "\($0.width)×\($0.height) BGRA \($0.bgra)" } ?? "nil"), "
            + "decodesFirstFrame \(frame.map { String($0.decodes) } ?? "nil"); \(runsLine(ran)); "
            + countLine(counted, num, den))
}

/// A source whose copy was not kept: it imports with its original as H.264
/// after two runs, the second a re-encode into a QuickTime file, and leaves
/// exactly one file and no partial.
///
/// `onePlan` (B81) also holds exactly one plan of it in `ffprobe.log`: the
/// second attempt takes the first's.
func fallbackRow(_ id: String, _ name: String, mode: String, onePlan: Bool = false) {
    let source = fixture(name)
    setMode(mode)
    let imported = importing(source)
    setMode("pass")
    let file = imported.descriptor.map { URL(fileURLWithPath: $0.path) }
    let video = file.flatMap { format($0, .video) }
    let ran = runs(for: source)
    let made = files(for: source)
    let planned = plans(of: source)
    let firstCopies = ran.first.map { holds($0, "-c:v", "copy") } ?? false
    let secondEncodes = ran.count == 2 && holds(ran[1], "-f", "mov")
        && !holds(ran[1], "-c:v", "copy")
    row(id, hasOriginal(imported.descriptor, source) && video == "avc1" && firstCopies
        && secondEncodes && made.finished.count == 1 && made.partial.isEmpty
        && (!onePlan || planned == 1),
        "\(name) (mode \(mode)): imports \(file?.lastPathComponent ?? "nothing") "
            + "(\(imported.error ?? "no error")), original "
            + "\(imported.descriptor?.original?.path ?? "nil"); video \(video ?? "nil"); "
            + "\(runsLine(ran)); \(made.finished.count) file(s) and \(made.partial.count) "
            + "partial(s) for it in Rewrapped/"
            + (onePlan ? "; \(planned) plan(s) of it in ffprobe.log (exactly 1 wanted)" : ""))
}

copiedRow("V1", v0, converted, 30, 1, wholeFrame: true)

// MARK: - O5, O4: the re-copy on open (after V1, which reads O1's file)

func recopyRow(_ id: String, discarding: Bool) {
    guard let d = converted.descriptor else {
        row(id, false, "not run: O1 answered no descriptor")
        return
    }
    let digest = URL(fileURLWithPath: d.path)
    if discarding { FFmpegRewrap.discard(digest) }
    let onDisk = manager.fileExists(atPath: digest.path)
    let missingPath = "/nonexistent-b80/" + digest.lastPathComponent
    guard let missing = project(d, path: missingPath, bookmark: nil) else {
        row(id, false, "not run: the project could not be made")
        return
    }
    let (linesBefore, filesBefore) = (log().count, listing())
    let repaired = offMain(120) {
        ProjectDocument.recopyingMissingCopies(missing, watch: nil)
    }
    let (linesAfter, filesAfter) = (log().count, listing())
    let media = repaired?.snapshot.media.first
    let kept = media?.original.map { canonical($0.path) == canonical(v0.path) } ?? false
    let facts = "conversion on disk before \(onDisk); media path \(media?.path ?? "nil"), "
        + "original \(media?.original?.path ?? "nil"); ffmpeg.log \(linesBefore) → "
        + "\(linesAfter) lines; Rewrapped/ \(filesBefore.count) → \(filesAfter.count) files"
    if discarding {
        row(id, !onDisk && repaired.map { $0.json == missing.json } == true
            && linesAfter == linesBefore && filesAfter == filesBefore,
            "the conversion discarded: the same JSON "
                + "\(repaired.map { String($0.json == missing.json) } ?? "no answer"); " + facts)
    } else {
        row(id, onDisk && media.map { canonical($0.path) == canonical(digest.path) } == true
            && kept && linesAfter == linesBefore,
            "the conversion still on disk: the media's path is the digest file "
                + "\(media.map { String(canonical($0.path) == canonical(digest.path)) } ?? "nil"); "
                + facts)
    }
}

recopyRow("O5", discarding: false)
recopyRow("O4", discarding: true)

let v2 = fixture("v2.mkv")
copiedRow("V2", v2, importing(v2), 30, 1, wholeFrame: true)

do {
    let p1 = fixture("p1.ivf")
    let imported = importing(p1)
    let file = imported.descriptor.map { URL(fileURLWithPath: $0.path) }
    let video = file.flatMap { format($0, .video) }
    let ran = runs(for: p1)
    row("V3", imported.descriptor != nil && video == "avc1" && ran.count == 1
        && !(ran.first.map { holds($0, "-c:v", "copy") } ?? true),
        "p1.ivf: imports \(file?.lastPathComponent ?? "nothing") "
            + "(\(imported.error ?? "no error")); video \(video ?? "nil"); \(runsLine(ran))")
}

fallbackRow("V4", "v0b.mkv", mode: "fail-copy")
fallbackRow("V5", "v0c.mkv", mode: "swap-copy")

let vn = fixture("vn.mkv")
copiedRow("V6", vn, importing(vn), 30000, 1001, wholeFrame: false)

fallbackRow("V7", "vj.mkv", mode: "pass", onePlan: true)
fallbackRow("V8", "vg.mkv", mode: "pass")

// MARK: - V9: one re-encode per file (#227 as amended by B81)

do {
    let source = fixture("vj2.mkv")
    // Two imports of one failing VP9 file, started together.
    let first = Pending<Result<MediaDescriptor, any Error>>()
    let second = Pending<Result<MediaDescriptor, any Error>>()
    for pending in [first, second] {
        Thread.detachNewThread {
            pending.set(Result { try MediaImporter.probeBlocking(url: source) })
        }
    }
    let deadline = Date().addingTimeInterval(300)
    while (first.value == nil || second.value == nil) && Date() < deadline { spin(0.02) }
    let both = [first.value, second.value].map { $0.flatMap { try? $0.get() } }
    let paths = both.compactMap { $0?.path }
    let videos = paths.map { format(URL(fileURLWithPath: $0), .video) ?? "nil" }
    let ran = runs(for: source)
    let copies = ran.filter { holds($0, "-c:v", "copy") }.count
    let encodes = ran.count - copies
    let made = files(for: source)
    let imports = paths.count == 2 && Set(paths).count == 1 && videos == ["avc1", "avc1"]
        && encodes == 1 && copies <= 2 && made.finished.count == 1 && made.partial.isEmpty

    // THEN the second attempt, called directly: the kept re-encode is
    // answered, not discarded and made again.
    let digest = paths.first.map { URL(fileURLWithPath: $0) }
    let numberBefore = digest.flatMap { FFmpegRewrap.fileNumber(of: $0) }
    let linesBefore = log().count
    let again: Result<URL?, any Error>? = offMain {
        var planned: FFmpegRewrap.Plan?
        return Result {
            try FFmpegRewrap.assist(source, mayAsk: false, planned: &planned, reencodingVP9: true)
        }
    }
    let answered = again.flatMap { try? $0.get() }
    let numberAfter = digest.flatMap { FFmpegRewrap.fileNumber(of: $0) }
    let linesAfter = log().count
    let kept = digest != nil && answered.map { canonical($0.path) } == digest.map {
        canonical($0.path)
    } && linesAfter == linesBefore && numberBefore != nil && numberAfter == numberBefore
    row("V9", imports && kept,
        "two probeBlocking(vj2.mkv) started together: import "
            + "\(paths.map { ($0 as NSString).lastPathComponent }) as \(videos); "
            + "\(encodes) encoder run(s) and \(copies) copy run(s); \(made.finished.count) "
            + "file(s) and \(made.partial.count) partial(s) for it in Rewrapped/. Then "
            + "assist(…, reencodingVP9: true) called directly: answers "
            + "\(answered?.lastPathComponent ?? "nil"); ffmpeg.log \(linesBefore) → "
            + "\(linesAfter) lines; the file's number "
            + "\(numberBefore.map { String($0) } ?? "nil") → "
            + "\(numberAfter.map { String($0) } ?? "nil")")
}

// MARK: - V10: discard(_:ifStill:)

do {
    let folder = rewrappedFolder
    let replaced = folder.appendingPathComponent("b81-v10-replaced.mov")
    let numbered = folder.appendingPathComponent("b81-v10-numbered.mov")
    let spare = folder.appendingPathComponent("b81-v10-unnumbered.mov")
    for url in [replaced, numbered, spare] { try? Data("first".utf8).write(to: url) }
    // A file that replaced the one numbered: removed, and written again.
    let old = FFmpegRewrap.fileNumber(of: replaced)
    try? manager.removeItem(at: replaced)
    try? Data("second".utf8).write(to: replaced)
    let new = FFmpegRewrap.fileNumber(of: replaced)
    FFmpegRewrap.discard(replaced, ifStill: old)
    let left = manager.fileExists(atPath: replaced.path)
    // The one numbered.
    let own = FFmpegRewrap.fileNumber(of: numbered)
    FFmpegRewrap.discard(numbered, ifStill: own)
    let removed = !manager.fileExists(atPath: numbered.path)
    // No number at all.
    FFmpegRewrap.discard(spare, ifStill: nil)
    let spared = manager.fileExists(atPath: spare.path)
    for url in [replaced, numbered, spare] { try? manager.removeItem(at: url) }
    row("V10", old != nil && new != nil && old != new && left && own != nil && removed && spared,
        "discard(_:ifStill:) in Rewrapped/: a file that replaced the one numbered (number "
            + "\(old.map { String($0) } ?? "nil") → \(new.map { String($0) } ?? "nil")) is "
            + "left \(left); the one numbered is removed \(removed); a nil number leaves the "
            + "file \(spared)")
}

// MARK: - G1: onFrameGrid

do {
    let thirty = FFmpegRewrap.FrameRate(num: 30, den: 1)
    // A 3-frame grid at 30 fps in 1/90000 s: 3000 units a frame.
    let grid = FFmpegRewrap.onFrameGrid(times: [0, 3000, 6000], timescale: 90000, rate: thirty)
    // The largest multiple of the step that is not above Int64.max.
    let top = (Int64.max / 3000) * 3000
    let one = FFmpegRewrap.onFrameGrid(times: [top], timescale: 90000, rate: thirty)
    // A second packet there: its expected time is past Int64.max.
    let two = FFmpegRewrap.onFrameGrid(times: [top, top], timescale: 90000, rate: thirty)
    let off = FFmpegRewrap.onFrameGrid(times: [0, 3000, 6001], timescale: 90000, rate: thirty)
    row("G1", grid && one && !two && !off,
        "onFrameGrid at 30/1 in 1/90000 s: [0, 3000, 6000] \(grid) (true wanted); one packet "
            + "at \(top), the largest multiple of 3000 not above Int64.max, \(one) (true); two "
            + "packets from there, the second's expected time past Int64.max, \(two) (false); "
            + "[0, 3000, 6001] \(off) (false)")
}

// MARK: - C1: the ceilings

do {
    let ceiling = AgentServer.probeCeiling
    let assist = FFmpegRewrap.longestAssist
    let conversion = FFmpegRewrap.longestConversion
    measure["C1"] = ["probe_ceiling": ceiling, "longest_assist": assist,
                     "longest_conversion": conversion]
    row("C1", ceiling == 29330 && assist == 2 * conversion + 440,
        "AgentServer.probeCeiling \(Int(ceiling)) s (29330 wanted); FFmpegRewrap.longestAssist "
            + "\(Int(assist)) s, 2 × longestConversion (\(Int(conversion)) s) + 440 = "
            + "\(Int(2 * conversion + 440)) s")
}

// MARK: - P1: no second attempt for a plan that copies no VP9

do {
    let source = fixture("p1b.ivf")
    setMode("bad-encode")
    let imported = importing(source)
    setMode("pass")
    // The source's own refusal: what AVFoundation's probe of it throws.
    let wanted: String? = offMain { () -> String? in
        do {
            _ = try MediaImporter.waitForProbe(source)
            return nil
        } catch {
            return error.localizedDescription
        }
    } ?? nil
    let ran = runs(for: source)
    let made = files(for: source)
    let planned = plans(of: source)
    row("P1", imported.descriptor == nil && wanted != nil && imported.error == wanted
        && planned == 1 && ran.count == 1 && made.finished.isEmpty && made.partial.isEmpty,
        "p1b.ivf (mode bad-encode): imports "
            + "\(imported.descriptor.map { ($0.path as NSString).lastPathComponent } ?? "nothing") "
            + "(\(imported.error ?? "no error"); the source's own refusal is "
            + "“\(wanted ?? "none: it probes")”); "
            + "\(planned) plan(s) of it in ffprobe.log (exactly 1 wanted); \(runsLine(ran)); "
            + "\(made.finished.count) file(s) and \(made.partial.count) partial(s) for it in "
            + "Rewrapped/")
}

// MARK: - M1: a tool's main hop while the conversion question is up (#234)

/// Times, each noted once, from any thread.
final class Marks {
    private let lock = NSLock()
    private var times: [String: Double] = [:]

    func mark(_ name: String) {
        lock.lock()
        if times[name] == nil { times[name] = ProcessInfo.processInfo.systemUptime }
        lock.unlock()
    }

    subscript(_ name: String) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        return times[name]
    }

    /// Seconds from `up` (the question on screen) to `name`.
    func since(_ name: String) -> Double? {
        guard let up = self["up"], let at = self[name] else { return nil }
        return at - up
    }
}

/// One showing of the conversion question. `consent(for:)` is called on a
/// background thread (`askedOnMain` false: how `MediaImporter.probe`'s import
/// queue and a read on AppKit's read queue reach it, by the source) or on main
/// itself. A `.common` timer, which the modal loop serves, sees the question
/// up (`NSApp.modalWindow`), starts a thread that makes a tool's hop to main
/// (`AgentServer.onMain`, which is `AgentLane.onMainWhenIdle`'s
/// `DispatchQueue.main.sync`), and 2 s later ends the modal.
struct Showing {
    let marks = Marks()
    let answered = Pending<Bool>()
    /// Whether the question was still up when the hop's body ran.
    let servedInModal = Pending<Bool>()

    /// Whether everything the showing started has ended.
    var ended: Bool { answered.value != nil && marks["returned"] != nil }

    var line: String {
        func s(_ value: Double?) -> String { value.map { String(format: "%.3f s", $0) } ?? "never" }
        let order: String
        if let served = marks.since("served"), let aborted = marks.since("aborted") {
            order = served < aborted ? "BEFORE the abort" : "AFTER the abort"
        } else {
            order = "order unknown"
        }
        return "the question up; the hop called \(s(marks.since("called"))) later, its body "
            + "run at \(s(marks.since("served"))) with the question "
            + "\(servedInModal.value.map { $0 ? "still up" : "gone" } ?? "unknown") and returned "
            + "at \(s(marks.since("returned"))); NSApp.abortModal() at "
            + "\(s(marks.since("aborted"))) — the hop was served \(order); consent answered "
            + "\(answered.value.map { String($0) } ?? "nothing")"
    }

    var measure: [String: Any] {
        var out: [String: Any] = [:]
        for name in ["called", "served", "returned", "aborted"] {
            out[name] = marks.since(name).map { ($0 * 1000).rounded() / 1000 } ?? NSNull()
        }
        return out
    }
}

func showing(_ plan: FFmpegRewrap.Plan, askedOnMain: Bool) -> Showing {
    let shown = Showing()
    let marks = shown.marks
    let timer = Timer(timeInterval: 0.02, repeats: true) { _ in
        guard NSApp.modalWindow != nil else { return }
        if marks["up"] == nil {
            marks.mark("up")
            Thread.detachNewThread {
                marks.mark("called")
                AgentServer.shared.onMain {
                    marks.mark("served")
                    shown.servedInModal.set(NSApp.modalWindow != nil)
                }
                marks.mark("returned")
            }
        }
        if let up = marks["up"], ProcessInfo.processInfo.systemUptime - up >= 2 {
            marks.mark("aborted")
            NSApp.abortModal()
        }
    }
    RunLoop.main.add(timer, forMode: .common)
    defer { timer.invalidate() }
    if askedOnMain {
        shown.answered.set(FFmpegRewrap.consent(for: plan))
    } else {
        Thread.detachNewThread { shown.answered.set(FFmpegRewrap.consent(for: plan)) }
    }
    let deadline = Date().addingTimeInterval(20)
    while !shown.ended && Date() < deadline { spin(0.02) }
    return shown
}

do {
    // The hop with no question up: the control for "served".
    let plain = Marks()
    plain.mark("up")
    _ = offMain(20) { () -> Bool in
        AgentServer.shared.onMain { plain.mark("served") }
        return true
    }
    let control = plain.since("served")

    // A showing that will not end must not take the other rows with it: main
    // is then inside the modal loop, so the answer is given from here.
    let finished = Pending<Bool>()
    DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
        guard finished.value == nil else { return }
        row("M1", false, "a showing of the conversion question did not end within 30 s of the "
            + "row's start (NSApp.abortModal() from a .common timer did not end it, or the "
            + "question never came up)")
        answer()
    }
    if let plan = FFmpegRewrap.plan(for: v0, with: tools) {
        let off = showing(plan, askedOnMain: false)
        let on = off.ended ? showing(plan, askedOnMain: true) : Showing()
        finished.set(true)
        measure["M1"] = ["control": control.map { ($0 * 1000).rounded() / 1000 } ?? NSNull(),
                         "asked_off_main": off.measure, "asked_on_main": on.measure]
        func servedAfter(_ shown: Showing) -> Bool? {
            guard let served = shown.marks.since("served"),
                let aborted = shown.marks.since("aborted")
            else { return nil }
            return served >= aborted
        }
        row("M1", control.map { $0 < 1 } == true && off.ended && on.ended
            && off.answered.value == false && on.answered.value == false
            && servedAfter(off) == true && off.servedInModal.value == false
            && servedAfter(on) == false && on.servedInModal.value == true,
            "AgentServer.onMain {} from a background thread with no question up is served in "
                + "\(control.map { String(format: "%.3f s", $0) } ?? "never"). "
                + "consent(for: v0.mkv's plan) called OFF main (as the import queue calls "
                + "it): \(off.line). Called ON main: \(on.line). Wanted: off main the hop is "
                + "served only AFTER the abort, the question gone; on main BEFORE it, the "
                + "question still up; both answered false")
    } else {
        finished.set(true)
        row("M1", false, "not run: FFmpegRewrap.plan(for: v0.mkv) answered nil")
    }
}

for document in AgentServer.shared.openProjects() { document.close() }
spin(0.2)
answer()
