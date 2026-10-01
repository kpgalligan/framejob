// tools/proof/speed_limits_probe.swift — the in-process instrument behind
// `speed_limits_probe.py` (issue batch B52b, #190 part 2: the ×1000 build).
// Compiled as `main.swift` over every other file in `app/Sources` on
// `speed_spike.py`'s `build_probe` line, with the app's `Fonts`, `Blank.mp4`
// and a `default.metallib` of `Compositor.metal` beside the binary, linked
// against HEAD's core or a mutant's.
//
//     speed_limits_probe ui     --media P
//     speed_limits_probe export --media P --clips R:S:k|v[,…] --file OUT --deadline SEC
//
// It CALLS the app's code — `ReelSpeed.limits`, `SpeedSheetController`'s
// statics, `VideoPane.silentAudioNote`, `ReelProject.applying`,
// `MediaImporter.waitForProbe`, `ReelExport.settings`, `Exporter` — and
// restates none of it. The timeline and the export follow
// `speed_spike/speed_probe.swift:75-190, 379-431`.
//
// One line `ANSWER {json}` on stdout and exit 0; a crash is the caller's.
import AVFoundation
import AppKit

var answer: [String: Any] = ["error": NSNull()]

func finish() -> Never {
    let data = (try? JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys]))
        ?? Data("{\"error\":\"the answer would not serialise\"}".utf8)
    print("ANSWER " + String(decoding: data, as: UTF8.self))
    fflush(stdout)
    exit(0)
}

func fail(_ message: String) -> Never {
    answer["error"] = message
    finish()
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else { fail("usage: speed_limits_probe ui|export --key value …") }
let mode = arguments[1]
answer["mode"] = mode
var options: [String: String] = [:]
var index = 2
while index < arguments.count {
    let key = arguments[index]
    guard key.hasPrefix("--"), index + 1 < arguments.count else { fail("bad argument \(key)") }
    options[String(key.dropFirst(2))] = arguments[index + 1]
    index += 2
}

func string(_ name: String) -> String {
    guard let value = options[name] else { fail("--\(name) is required for \(mode)") }
    return value
}

NSApplication.shared.setActivationPolicy(.prohibited)

let perSecond = Double(ReelTime.perSecond)

func seconds(_ ticks: Ticks) -> Double { Double(ticks) / perSecond }

// MARK: - The timeline

/// One op through the app's own `applying`; any arm but `.applied` stops the
/// probe, except an identity the caller expected (`set_speed` at the rate
/// and pitch mode the clip already has).
func apply(_ project: ReelProject, _ op: ReelOp, identityOK: Bool = false) -> ReelProject {
    let edit: ReelEdit
    do {
        edit = try project.applying([op])
    } catch {
        fail("\(op.name) threw: \(error.localizedDescription)")
    }
    switch edit {
    case .applied(let next):
        return next
    case .identity:
        if identityOK { return project }
        fail("\(op.name) answered identity")
    case .refused(let refusal):
        fail("\(op.name) was refused: \(refusal.reason)")
    }
}

/// One `--clips` entry: the rate, the seconds to trim it to (0 = untrimmed)
/// and the pitch mode.
struct Entry {
    let rate: Double
    let trim: Double
    let keepPitch: Bool
}

func entries(_ text: String) -> [Entry] {
    text.split(separator: ",").map { part in
        let fields = part.split(separator: ":").map(String.init)
        guard fields.count == 3, let rate = Double(fields[0]), let trim = Double(fields[1]),
            fields[2] == "k" || fields[2] == "v"
        else { fail("bad --clips entry \(part)") }
        return Entry(rate: rate, trim: trim, keepPitch: fields[2] == "k")
    }
}

/// `set_canvas` to the media, `add_media`, then per entry `add_clip` at the
/// cursor, `set_speed(rate, keepPitch)`, and `trim_end` to start + S when
/// S > 0.
func buildTimeline(_ path: String, _ list: [Entry]) -> ReelProject {
    let descriptor: MediaDescriptor
    do {
        descriptor = try MediaImporter.waitForProbe(URL(fileURLWithPath: path))
    } catch {
        fail("the probe of \(path) failed: \(error.localizedDescription)")
    }
    var project = ProjectDocument().project
    if descriptor.hasVideo {
        project = apply(
            project,
            .setCanvas(width: descriptor.width, height: descriptor.height, fps: descriptor.fps))
    }
    let media = project.snapshot.nextId
    project = apply(project, .addMedia(descriptor: descriptor))
    guard let track = project.snapshot.tracks.first?.id else { fail("the project has no track") }
    var cursor: Ticks = 0
    for entry in list {
        let minted = project.snapshot.nextId
        project = apply(project, .addClip(track: track, media: media, at: cursor))
        guard let placed = project.snapshot.clip(minted) else {
            fail("add_clip minted no clip \(minted) at \(cursor)")
        }
        project = apply(
            project, .setSpeed(clip: minted, rate: entry.rate, keepPitch: entry.keepPitch),
            identityOK: placed.speed == entry.rate
                && placed.audioProps.keepPitch == entry.keepPitch)
        if entry.trim > 0, let clip = project.snapshot.clip(minted) {
            let end = clip.start + Ticks((entry.trim * perSecond).rounded())
            if end < clip.start + clip.duration {
                project = apply(project, .trimEnd(clip: minted, to: end))
            }
        }
        guard let clip = project.snapshot.clip(minted) else { fail("clip \(minted) is gone") }
        cursor = clip.start + clip.duration
    }
    answer["timeline"] = project.snapshot.clips.map { clip -> [String: Any] in
        ["id": Int(clip.id), "speed": clip.speed, "keep_pitch": clip.audioProps.keepPitch,
         "start_s": seconds(clip.start), "duration_s": seconds(clip.duration)]
    }
    return project
}

// MARK: - The UI's numbers

/// The limits, the Speed sheet's range and presets, and the Speed section's
/// note for one clip at each (rate, pitch mode) of U2.
func runUI() -> Never {
    let path = string("media")
    let limits = ReelSpeed.limits
    answer["limits"] = ["min": limits.min, "max": limits.max, "audio_max": limits.audioMax]
    answer["sheet_range"] = [
        SpeedSheetController.rateRange.lowerBound, SpeedSheetController.rateRange.upperBound,
    ]
    answer["sheet_presets"] = SpeedSheetController.presets
    var notes: [[String: Any]] = []
    for (rate, keep) in [(1.0, true), (12.0, true), (12.0, false), (12.5, true), (12.5, false)] {
        let project = buildTimeline(path, [Entry(rate: rate, trim: 0, keepPitch: keep)])
        let snapshot = project.snapshot
        let note = VideoPane.silentAudioNote(for: snapshot.clips, in: snapshot, limits: limits)
        notes.append([
            "rate": rate, "keep_pitch": keep, "note": note.map { $0 as Any } ?? NSNull(),
            "speed": snapshot.clips.first?.speed ?? 0,
        ])
    }
    answer["notes"] = notes
    answer.removeValue(forKey: "timeline")
    finish()
}

// MARK: - Export

/// One h264 export through `Exporter().export`, polled on the main run loop
/// in slices of at most 10 ms, under a deadline (`speed_probe.swift:379-431`).
func runExport() -> Never {
    let project = buildTimeline(string("media"), entries(string("clips")))
    let file = URL(fileURLWithPath: string("file"))
    guard let deadlineSeconds = Double(string("deadline")) else { fail("--deadline") }
    answer["file"] = file.path
    let settings: ExportSettings
    do {
        settings = try ReelExport.settings(project, preset: "h264")
    } catch {
        answer["outcome"] = "failure"
        fail("the core would not resolve h264: \(error.localizedDescription)")
    }
    try? FileManager.default.removeItem(at: file)
    var urls: [UInt32: URL] = [:]
    for media in project.snapshot.media { urls[media.id] = URL(fileURLWithPath: media.path) }

    let exporter = Exporter()
    var outcome: Result<URL, any Error>?
    let start = Date()
    exporter.export(
        project: project, urls: urls, settings: settings, to: file,
        progress: { _ in },
        completion: { result in outcome = result })
    let deadline = start.addingTimeInterval(deadlineSeconds)
    while outcome == nil, Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    answer["wall_s"] = Date().timeIntervalSince(start)
    switch outcome {
    case .success?:
        answer["outcome"] = "success"
    case .failure(let error)?:
        answer["outcome"] = "failure"
        answer["error"] = error.localizedDescription
    case nil:
        answer["outcome"] = "deadline"
    }
    finish()
}

switch mode {
case "ui":
    runUI()
case "export":
    runExport()
default:
    fail("unknown mode \(mode)")
}
