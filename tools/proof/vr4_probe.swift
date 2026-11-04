// Road map creator-jobs VR4a — word caption pages re-paged from their own words, presets by the
// short side (spec §11 VR-40, VR-41, VR-46), measured through the app's own sources with no app:
// R1 every re-paged page's lines within 0.86 of the new width, R6 the three VR-41 sites on a tall
// canvas and byte-identical to the old formula on a wide and a square one, and `overTwoLines`;
// R10 Make Vertical with a recognised track whose re-page throws `tooMany`.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own `main.swift`, with
// `FRAMEJOB_DEV_TOOLS`, against `libframejob_core.a`, through `swift_build.py`:
//
//   vr4_probe <work dir> main               -> {"rows": [{"id", "pass", "detail"}, ...]}
//   vr4_probe <work dir> pages <out.json>   -> R4's five styles' pages laid on 1920 × 1080
//   vr4_probe <work dir> measure <project> [names]  -> {"pages", "worst", "budget", "over"}
//
// `pages` writes, per style, the `add_text_clip` arguments (at, duration, text) and the batch's
// `set_video` patch that `CaptionPages.build` + `CaptionLayout.place` make, for `vr4_proof.py` to
// send as op tools. `measure` reads a `get_project` project and measures every word-styled page
// on a caption track exactly as `CaptionPages` does: each line alone, in the page's recognised
// style at the page's size, no box. Nothing here opens a window or reads a file but its input.
import AppKit

guard CommandLine.arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: vr4_probe <work dir> main|pages|measure …\n".utf8))
    exit(2)
}
let work = URL(fileURLWithPath: CommandLine.arguments[1])
let mode = CommandLine.arguments[2]
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

let second = ReelTime.perSecond
let fps = Fps.thirty

var rows: [[String: Any]] = []
func row(_ id: String, _ problems: [String], _ detail: String) {
    rows.append(["id": id, "pass": problems.isEmpty,
                 "detail": problems.isEmpty ? detail : problems.joined(separator: "; ")])
}

func write(_ object: Any) -> Never {
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        ?? Data("{}".utf8)
    FileHandle.standardOutput.write(data)
    exit(0)
}

// MARK: - The fixture's words

/// Fifty-odd words, 0.32 s apart and 0.28 s long, three sentences: wide enough that a 1920
/// page holds more of them than a 1080 one.
let sentence = "Frame Job measures every caption page against the width of the canvas it lands "
    + "on, so a vertical version keeps its words readable everywhere. Corrections typed by "
    + "hand stay exactly where they were, and nothing is regenerated from the transcript "
    + "afterwards. Each page stays inside its own clip, even after a split or a trim."
func fixtureWords(from: Ticks = 0) -> [CaptionCues.Word] {
    sentence.split(separator: " ").enumerated().map { index, token in
        let start = from + Ticks(index) * 192_000
        return CaptionCues.Word(text: String(token), start: start, end: start + 168_000,
                                speaker: nil)
    }
}
let wordsEnd = fixtureWords().last!.end + second

struct Config {
    let style: CaptionStyle
    let looks: CaptionLooks
}
let configs = [
    Config(style: .highlight, looks: CaptionLooks(fill: true)),
    Config(style: .pill, looks: CaptionLooks(slide: true)),
    Config(style: .karaoke, looks: .none),
    Config(style: .build, looks: .none),
    Config(style: .oneWord, looks: .none),
]

func newProject(_ width: Int, _ height: Int) -> ReelProject {
    guard let project = ReelProject.new(width: width, height: height, fps: fps) else {
        FileHandle.standardError.write(Data("no project\n".utf8))
        exit(3)
    }
    return project
}

func applied(_ project: ReelProject, _ ops: [ReelOp]) throws -> ReelProject {
    guard let next = try project.applying(ops).project else {
        throw ReelCoreError(message: "the ops did not apply")
    }
    return next
}

/// One style's pages built and placed on `project`'s canvas, on a new caption track.
func laid(_ config: Config, on project: ReelProject) throws -> CaptionLayout.Plan {
    let canvas = project.snapshot.canvas
    let cues = CaptionPages.build(
        from: fixtureWords(), span: 0 ..< wordsEnd, frame: canvas.fps.frameDuration,
        request: CaptionPages.Request(
            style: config.style, canvas: CGSize(width: canvas.width, height: canvas.height)),
        engine: .assemblyai)
    return try CaptionLayout.place(cues, in: project, style: config.style, looks: config.looks)
}

// MARK: - The measure (R1, and `measure`)

/// Every word-styled page on a caption track, each line measured alone as `CaptionPages`
/// measures it; a lone word carrying `width` is the pager's own wrap and is excepted.
func measure(_ snapshot: ProjectSnapshot, only names: Set<String>? = nil)
    -> (pages: Int, worst: Double, budget: Double, over: [String])
{
    let budget = CaptionPages.Rules.standard.widthBudget * Double(snapshot.canvas.width)
    var pages = 0
    var worst = 0.0
    var over: [String] = []
    for track in snapshot.tracks where CaptionLayout.isCaptionTrackName(track.name) {
        if let names, !names.contains(track.name) { continue }
        for clip in snapshot.clips(onTrack: track.id) {
            guard let text = clip.text, text.wordStyle != nil,
                let found = CaptionRelayout.recognise(text)
            else { continue }
            pages += 1
            let lone = text.tokenCount == 1 && text.width != nil
            for line in text.content.split(separator: "\n") {
                let width = Double(LayerRenderers.measuredSize(
                    for: found.style.textProps(content: String(line), size: text.size, width: nil)
                ).width)
                if !lone { worst = max(worst, width) }
                if width > budget, !lone {
                    over.append("clip \(clip.id) \"\(line)\" \(Int(width)) px")
                }
            }
        }
    }
    return (pages, worst, budget, over)
}

// MARK: - R1

func r1() {
    var problems: [String] = []
    var detail = ""
    do {
        var project = newProject(1920, 1080)
        for config in configs {
            project = try applied(project, laid(config, on: project).ops)
        }
        let wide = measure(project.snapshot)
        project = try applied(project, [.setCanvas(width: 1080, height: 1920, rescaleClips: false)])
        let planned = try CaptionRelayout.plan(project)
        if planned.outcome.relaid.count != configs.count {
            problems.append("relaid \(planned.outcome.relaid.count) of \(configs.count) tracks; "
                            + "kept \(planned.outcome.kept)")
        }
        project = try applied(project, planned.ops)
        let tall = measure(project.snapshot)
        if !tall.over.isEmpty {
            problems.append("over \(Int(tall.budget)) px: " + tall.over.prefix(4).joined(separator: ", "))
        }
        if tall.pages <= wide.pages {
            problems.append("\(tall.pages) pages at 1080 against \(wide.pages) at 1920")
        }
        detail = "\(wide.pages) pages at 1920 × 1080 (widest line \(Int(wide.worst)) px) re-paged "
            + "into \(tall.pages) at 1080 × 1920, the widest line \(Int(tall.worst)) px of "
            + "\(Int(tall.budget)); \(planned.outcome.relaid.count) tracks relaid"
    } catch {
        problems.append("threw: \(error.localizedDescription)")
    }
    row("R1", problems, detail)
}

// MARK: - R6

func size(_ w: Int, _ h: Int) -> CGSize { CGSize(width: w, height: h) }

/// The old formula, spelt out: size `(H × sizeFraction).rounded()`, x `xFraction × W`,
/// y `yFraction × H`.
func oldPatches(_ preset: TextPreset, _ w: Int, _ h: Int) -> (text: TextPatch, video: VideoPatch) {
    let height = Double(h)
    return (
        TextPatch(font: preset.font, size: (height * preset.sizeFraction).rounded(),
                  align: preset.align, valign: "middle", backdrop: .some(preset.backdrop)),
        VideoPatch(x: preset.xFraction * Double(w), y: preset.yFraction * height, opacity: 1)
    )
}

func json(_ op: ReelOp) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(op.json.utf8))) as? [String: Any] ?? [:]
}

func cuesOf(_ texts: [String]) -> [CaptionLayout.Cue] {
    texts.enumerated().map { index, text in
        CaptionLayout.Cue(start: Ticks(index) * 2 * second, end: Ticks(index) * 2 * second + second,
                          text: text, tag: "cue \(index + 1)")
    }
}

func sheet() -> TranscribeSheetController {
    let suite = "vr4-probe-\(getpid())"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return TranscribeSheetController(
        document: ProjectDocument(), store: MemoryStore(), defaults: defaults, environment: [:],
        languages: [Transcriber.Language(identifier: "en-US",
                                         displayName: "English (United States)")])
}

func r6() {
    var problems: [String] = []
    var notes: [String] = []
    let preset = CaptionLayout.captionPreset
    let shortCues = cuesOf(["A short caption", "Another one"])
    let controller = sheet()
    // The two canvases whose output must not change, byte for byte.
    for (w, h) in [(1920, 1080), (1080, 1080)] {
        for row in TextPreset.all {
            let new = row.patches(on: size(w, h))
            let old = oldPatches(row, w, h)
            if ReelOp.setText(clips: [1], patch: new.text).json
                != ReelOp.setText(clips: [1], patch: old.text).json
                || ReelOp.setVideo(clips: [1], patch: new.video).json
                != ReelOp.setVideo(clips: [1], patch: old.video).json
            {
                problems.append("\(w)×\(h) \(row.name): Text ▸ Presets differs from the old formula")
            }
        }
        do {
            let project = newProject(w, h)
            let plan = try CaptionLayout.place(shortCues, in: project)
            let snapshot = project.snapshot
            var old: [ReelOp] = [.addTrack(index: snapshot.tracks.count, name: "Captions")]
            let height = Double(h)
            var base = TextPatch(
                font: preset.font, size: (height * preset.sizeFraction).rounded(),
                align: preset.align, valign: "middle", backdrop: .some(preset.backdrop),
                width: .some(Double(w) * CaptionLayout.wrapFraction))
            for cue in shortCues {
                base.content = cue.text
                old.append(.addTextClip(track: snapshot.nextId, at: cue.start,
                                        duration: cue.end - cue.start, text: base))
            }
            let created = (json(plan.ops.last!)["clips"] as? [Int] ?? []).map { UInt32($0) }
            old.append(.setVideo(clips: created, patch: VideoPatch(
                x: preset.xFraction * Double(w), y: preset.yFraction * height, opacity: 1)))
            if plan.ops.map(\.json) != old.map(\.json) {
                problems.append("\(w)×\(h): place's Subtitles ops differ from the old formula")
            }
            if plan.overTwoLines != 0 {
                problems.append("\(w)×\(h): overTwoLines \(plan.overTwoLines), want 0")
            }
        } catch {
            problems.append("\(w)×\(h) place threw: \(error.localizedDescription)")
        }
        let cue = shortCues[0]
        let preview = controller.previewProps(for: cue, canvas: size(w, h))
        let oldPreview = TextProps(
            content: cue.text, font: preset.font,
            size: (Double(h) * preset.sizeFraction).rounded(), align: preset.align,
            valign: "middle", backdrop: preset.backdrop,
            width: Double(w) * CaptionLayout.wrapFraction)
        if preview != oldPreview {
            problems.append("\(w)×\(h): the sheet's Subtitles preview differs from the old formula")
        }
    }
    // The tall canvas: VR-41's size, wrap and y at each site.
    let tall = size(1080, 1920)
    let caption = preset.patches(on: tall)
    let presetText = json(ReelOp.setText(clips: [1], patch: caption.text))["patch"] as? [String: Any]
    let presetVideo = json(ReelOp.setVideo(clips: [1], patch: caption.video))["patch"] as? [String: Any]
    let presetSize = presetText?["size"] as? Double
    let presetY = presetVideo?["y"] as? Double
    if presetSize != 38 || presetY != 480 {
        problems.append("Text ▸ Presets Caption on 1080 × 1920: size \(presetSize ?? -1), y "
                        + "\(presetY ?? -1); want 38, 480")
    }
    notes.append("Presets Caption size \(presetSize ?? -1) y \(presetY ?? -1)")
    do {
        let project = newProject(1080, 1920)
        let plan = try CaptionLayout.place(shortCues, in: project)
        let first = plan.ops.first { $0.name == "add_text_clip" }.map(json)
        let text = first?["text"] as? [String: Any]
        let y = (json(plan.ops.last!)["patch"] as? [String: Any])?["y"] as? Double
        let got = (text?["size"] as? Double, text?["width"] as? Double, y)
        if got.0 != 38 || got.1 != 864 || got.2 != 480 {
            problems.append("place on 1080 × 1920: size \(got.0 ?? -1), wrap \(got.1 ?? -1), y "
                            + "\(got.2 ?? -1); want 38, 864, 480")
        }
        notes.append("place size \(got.0 ?? -1) wrap \(got.1 ?? -1) y \(got.2 ?? -1)")
    } catch {
        problems.append("place on 1080 × 1920 threw: \(error.localizedDescription)")
    }
    let tallPreview = controller.previewProps(for: shortCues[0], canvas: tall)
    if tallPreview.size != 38 || tallPreview.width != 864 {
        problems.append("the sheet's preview on 1080 × 1920: size \(tallPreview.size), wrap "
                        + "\(tallPreview.width ?? -1); want 38, 864")
    }
    notes.append("preview size \(tallPreview.size) wrap \(tallPreview.width ?? -1)")
    // overTwoLines: a long cue wraps past two lines at 864 px; a short one does not; on the
    // wide canvas nothing is counted.
    let long = "This caption is long enough that at the tall canvas's wrap width it runs on "
        + "for three lines or more, which the plan counts and the report says"
    do {
        let tallPlan = try CaptionLayout.place(cuesOf([long, "Short"]), in: newProject(1080, 1920))
        let widePlan = try CaptionLayout.place(cuesOf([long, "Short"]), in: newProject(1920, 1080))
        let words = try CaptionLayout.place(
            CaptionPages.build(from: fixtureWords(), span: 0 ..< wordsEnd,
                               frame: fps.frameDuration,
                               request: CaptionPages.Request(style: .highlight, canvas: tall),
                               engine: .apple),
            in: newProject(1080, 1920), style: .highlight)
        if tallPlan.overTwoLines != 1 || !tallPlan.report.contains(
            "1 caption wraps to more than two lines on this canvas.")
        {
            problems.append("overTwoLines on 1080 × 1920 \(tallPlan.overTwoLines), report "
                            + "\(tallPlan.report.debugDescription); want 1 and its sentence")
        }
        if widePlan.overTwoLines != 0 || words.overTwoLines != 0 {
            problems.append("overTwoLines \(widePlan.overTwoLines) on 1920 × 1080 and "
                            + "\(words.overTwoLines) for a word style; want 0, 0")
        }
        notes.append("overTwoLines tall \(tallPlan.overTwoLines) wide \(widePlan.overTwoLines)")
    } catch {
        problems.append("overTwoLines threw: \(error.localizedDescription)")
    }
    row("R6", problems, "byte-identical on 1920 × 1080 and 1080 × 1080; "
        + notes.joined(separator: "; "))
}

// MARK: - R10

/// A recognised track that `relay` keeps for `tooMany`: the project filled to `RC_MAX_CLIPS`
/// with one-frame clips on another track, so the narrower canvas's extra pages do not fit.
func r10() {
    var problems: [String] = []
    var detail = ""
    do {
        var project = newProject(1920, 1080)
        let config = configs[0]
        project = try applied(project, laid(config, on: project).ops)
        let captionTrack = project.snapshot.tracks.last!.id
        let pages = project.snapshot.clips(onTrack: captionTrack).map(\.id)
        // The filler is one-frame SOUND clips of a descriptor-only media: a clip with a picture
        // would be classed and tried once per clip by Make Vertical's step (3) on a 4096-clip
        // handle, which is minutes, while the ceiling counts every clip alike.
        let fillerTrack = project.snapshot.nextId
        project = try applied(project, [
            .addTrack(index: 0, name: "Filler"),
            .addMedia(descriptor: MediaDescriptor(
                path: "/vr4-probe/tone.wav", kind: .audio, duration: fps.frameDuration,
                hasVideo: false, hasAudio: true)),
        ])
        let tone = project.snapshot.media.last!.id
        project = try applied(project, [.addClip(track: fillerTrack, media: tone, at: 0)])
        // The filler clip copied by JSON to fill the project to the ceiling.
        var object = try JSONSerialization.jsonObject(with: Data(project.json.utf8))
            as! [String: Any]
        var clips = object["clips"] as! [[String: Any]]
        let filler = clips.first { ($0["track"] as? Int) == Int(fillerTrack) }!
        var next = object["next_id"] as! Int
        let room = Int(RC_MAX_CLIPS) - clips.count
        for index in 1 ... room {
            var copy = filler
            copy["id"] = next
            copy["start"] = Int(fps.frameDuration) * (index + 1)
            next += 1
            clips.append(copy)
        }
        object["clips"] = clips
        object["next_id"] = next
        let text = String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
        project = try ReelProject.from(json: text)
        let total = project.snapshot.clips.count
        let settings = VerticalSettings(shape: .tall, follow: .center, zoom: 1, whereEmpty: .fit)
        let began = Date()
        let answer = try VerticalVersion.plan(project, settings: settings, subjects: [:],
                                              missing: [])
        let took = Date().timeIntervalSince(began)
        guard case .plan(let plan) = answer else {
            problems.append("Make Vertical refused: \(answer)")
            row("R10", problems, "")
            return
        }
        let kept = plan.captions?.kept.first { $0.track == captionTrack }
        if kept == nil || !(kept!.reason.contains("is more than this project has room for")) {
            problems.append("the caption track's kept entry \(String(describing: kept)); "
                            + "captions \(String(describing: plan.captions))")
        }
        let keeps = Set(plan.ops.compactMap { op -> UInt32? in
            let args = json(op)
            guard op.name == "reframe_clip", args["follow"] as? String == "keep" else { return nil }
            return (args["clip"] as? Int).map { UInt32($0) }
        })
        let entries = Dictionary(uniqueKeysWithValues: plan.entries.map { ($0.clip, $0) })
        let unframed = pages.filter { !keeps.contains($0) }
        let unentered = pages.filter { entries[$0]?.treatment != .kept }
        if !unframed.isEmpty || !unentered.isEmpty {
            problems.append("pages with no reframe_clip keep \(unframed), with no kept entry "
                            + "\(unentered)")
        }
        guard case .applied = try project.applying(plan.ops) else {
            problems.append("the plan's ops did not apply")
            row("R10", problems, detail)
            return
        }
        detail = "\(total) clips (the ceiling \(RC_MAX_CLIPS)); the caption track kept: "
            + "\(kept?.reason ?? "-"); its \(pages.count) pages each reframed by keep with a kept "
            + "entry; planned in \(String(format: "%.1f", took)) s and applied"
    } catch {
        problems.append("threw: \(error.localizedDescription)")
    }
    row("R10", problems, detail)
}

// MARK: - Modes

switch mode {
case "main":
    r1()
    r6()
    r10()
    write(["rows": rows])
case "pages":
    var out: [[String: Any]] = []
    do {
        let project = newProject(1920, 1080)
        for config in configs {
            let plan = try laid(config, on: project)
            var clips: [[String: Any]] = []
            var video: Any = [:]
            for op in plan.ops {
                let args = json(op)
                switch op.name {
                case "add_text_clip":
                    clips.append(["at": args["at"] ?? 0, "duration": args["duration"] ?? 0,
                                  "text": args["text"] ?? [:]])
                case "set_video": video = args["patch"] ?? [:]
                default: break
                }
            }
            out.append(["style": config.style.rawValue, "looks": config.looks.names,
                        "font": config.style.font, "clips": clips, "video": video])
        }
    } catch {
        FileHandle.standardError.write(Data("pages threw: \(error)\n".utf8))
        exit(4)
    }
    let data = try! JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
    try! data.write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
    write(["styles": out.count])
case "measure":
    let data = try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
    let project = try! ReelProject.from(json: String(data: data, encoding: .utf8)!)
    let names = CommandLine.arguments.count > 4
        ? Set(CommandLine.arguments[4].split(separator: ",").map(String.init)) : nil
    let got = measure(project.snapshot, only: names)
    write(["pages": got.pages, "worst": got.worst, "budget": got.budget, "over": got.over])
default:
    FileHandle.standardError.write(Data("unknown mode \(mode)\n".utf8))
    exit(2)
}
