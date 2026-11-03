// Road map "creator-jobs" CJ6, spike CJ-S1 — the clip ceiling, rows (1), (2),
// (3) and (7).
//
// Built with every `app/Sources` file but `main.swift` (this file is the
// entry) through `tools/proof/swift_build.py` by `ceiling_spike.py`, against
// `core/target/release`'s library — the scratch build's raised cap when N is
// past 4,096. One project per run:
//
//   ceiling_spike <project.json> <out.json>
//
// (1) `split` with no clips at `mid` (⌊duration / 2⌋ to the whole second
//     plus 0.5 s, strictly inside one clip on every track), 20 times on one
//     base handle; every answer must be `.applied`.
// (2) `ReelProject.from(json:)` and then `.planJSON` on that fresh handle (its
//     memo empty), 5 times.
// (3) `recipeJSON(at:)` at 20 times from a fixed-seed generator.
// (7) a fresh `TimelineView` as a 1440 × 862 window's content, laid out,
//     `update`d, the zoom arm, laid out again and `cacheDisplay`ed; 20 samples
//     per arm. `fit`: `fit()`, and the zoom must equal `fitZoom` for the
//     clip view's width and differ from `defaultZoom`. `default`: no zoom
//     call, and the zoom must equal `defaultZoom`. A failed assertion scores
//     the arm failed (its reason in `failures`), never an exit.
//
// The answer: `{clips, duration, rows: {split_ms, open_plan_ms, recipe_ms,
// timeline_fit_ms, timeline_default_ms}}`, each `{median, samples, failures}`; the two
// timeline rows add `parts_median`, the median of each part of a sample (make, layout and
// update, zoom and layout, draw), for the record.
import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write(Data("usage: ceiling_spike <project.json> <out.json>\n".utf8))
    exit(2)
}

func ms(_ start: UInt64) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
}

func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

func median(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let mid = sorted.count / 2
    return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
}

func row(_ samples: [Double], _ failures: [String]) -> [String: Any] {
    ["median": median(samples) ?? NSNull(), "samples": samples, "failures": failures]
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
NSApp.appearance = NSAppearance(named: .aqua)

let text: String
do {
    text = try String(contentsOfFile: args[1], encoding: .utf8)
} catch {
    FileHandle.standardError.write(Data("cannot read \(args[1]): \(error)\n".utf8))
    exit(1)
}
let base: ReelProject
do {
    base = try ReelProject.from(json: text)
} catch {
    FileHandle.standardError.write(Data("the core refused the project: \(error)\n".utf8))
    exit(1)
}
let snapshot = base.snapshot
let duration = base.duration
let second = ReelTime.perSecond
let mid = (duration / 2) / second * second + second / 2
var rows: [String: Any] = [:]

// (1)
do {
    var samples: [Double] = []
    var failures: [String] = []
    for _ in 0..<20 {
        let start = now()
        let answer: ReelEdit
        do {
            answer = try base.applying(ReelOp.split(clips: nil, at: mid))
        } catch {
            failures.append("error: \(error)")
            continue
        }
        let took = ms(start)
        switch answer {
        case .applied: samples.append(took)
        case .identity: failures.append("identity at \(mid)")
        case .refused(let why): failures.append("refused: \(why.reason)")
        }
    }
    rows["split_ms"] = row(samples, failures)
}

// (2)
do {
    var samples: [Double] = []
    var failures: [String] = []
    for _ in 0..<5 {
        let start = now()
        do {
            let fresh = try ReelProject.from(json: text)
            let plan = fresh.planJSON
            let took = ms(start)
            if plan.count < 2 { failures.append("empty plan") } else { samples.append(took) }
        } catch {
            failures.append("error: \(error)")
        }
    }
    rows["open_plan_ms"] = row(samples, failures)
}

// (3)
do {
    var state: UInt64 = 0x5EED_C0FF_EE15_0001
    func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 11
    }
    var samples: [Double] = []
    var failures: [String] = []
    for _ in 0..<20 {
        let t = Ticks(next() % UInt64(max(duration, 1)))
        let start = now()
        let recipe = base.recipeJSON(at: t)
        let took = ms(start)
        if recipe == nil { failures.append("no recipe at \(t)") } else { samples.append(took) }
    }
    rows["recipe_ms"] = row(samples, failures)
}

// (7)
/// One sample, with its parts (ms) for the record: the window and view made,
/// the first layout and `update`, the zoom arm and second layout, the draw.
func timelineSample(fit: Bool) -> (Double?, String?, [Double]) {
    let start = now()
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1440, height: 862),
        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let view = TimelineView()
    window.contentView = view
    let made = ms(start)
    view.layoutSubtreeIfNeeded()
    view.update(snapshot: snapshot, selection: [], playhead: 0, inOutRange: nil,
                cacheDirectory: nil)
    let updated = ms(start)
    if fit { view.fit() }
    view.layoutSubtreeIfNeeded()
    let zoomed = ms(start)
    var failure: String?
    let width = view.content.enclosingScrollView?.contentView.bounds.width ?? 0
    if fit {
        let want = TimelineLayout.fitZoom(duration: snapshot.duration, width: width)
        if width <= 40 {
            failure = "the clip view is \(width) pt wide: fit() did nothing"
        } else if view.zoom != want {
            failure = "fit: zoom \(view.zoom), fitZoom \(want) at width \(width)"
        } else if view.zoom == TimelineLayout.defaultZoom {
            failure = "fit: zoom \(view.zoom) is the default zoom"
        }
    } else if view.zoom != TimelineLayout.defaultZoom {
        failure = "default: zoom \(view.zoom), want \(TimelineLayout.defaultZoom)"
    }
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        return (nil, "no bitmap for \(view.bounds)", [])
    }
    view.cacheDisplay(in: view.bounds, to: rep)
    let took = ms(start)
    window.contentView = nil
    window.close()
    let parts = [made, updated - made, zoomed - updated, took - zoomed]
    return failure == nil ? (took, nil, parts) : (nil, failure, parts)
}

for (key, fit) in [("timeline_fit_ms", true), ("timeline_default_ms", false)] {
    var samples: [Double] = []
    var failures: [String] = []
    var parts: [[Double]] = [[], [], [], []]
    for _ in 0..<20 {
        autoreleasepool {
            let (took, failure, part) = timelineSample(fit: fit)
            if let took { samples.append(took) }
            if let failure { failures.append(failure) }
            for (i, value) in part.enumerated() { parts[i].append(value) }
        }
    }
    var entry = row(samples, failures)
    entry["parts_median"] = ["make", "layout_update", "zoom_layout", "draw"].enumerated()
        .reduce(into: [String: Any]()) { $0[$1.element] = median(parts[$1.offset]) ?? NSNull() }
    rows[key] = entry
}

let answer: [String: Any] = [
    "clips": snapshot.clips.count, "tracks": snapshot.tracks.count, "duration": duration,
    "mid": mid, "rows": rows,
]
do {
    let data = try JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys])
    try data.write(to: URL(fileURLWithPath: args[2]))
} catch {
    FileHandle.standardError.write(Data("cannot write \(args[2]): \(error)\n".utf8))
    exit(1)
}
print("\(snapshot.clips.count) clips: rows written to \(args[2])")
