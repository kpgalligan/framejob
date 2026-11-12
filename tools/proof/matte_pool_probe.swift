// Built by tools/proof/matte_pool_probe.py as `main.swift` over every other
// file in `app/Sources` (`swift_build.py`). See that script's header.
//
// Issue batch B90 phase 3 (#253, spec §11 MT-9): the matte pool's schedule
// and its frame window, asked of the app's own `MattePlan` and `MattePool`;
// and (#597, spec §11 PR-19) its coverages' depth.
// No app, no metallib, no shader: a plan is arithmetic, and a pool needs only
// a device to make its targets. Every judgement is the script's; this file
// only answers what each call returned.
//
// argv[1] is the answer (JSON): `{"plans": [{"tag", "groups", "cuts",
// "steps": [{"group", "resolve", "release"}], "composites_live",
// "coverages"}], "pool": {…}}` — `pool` holds `error` when there is no
// Metal device.
import Foundation
import Metal

let outURL = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "")
var answer: [String: Any] = [:]

func finish() {
    let data = (try? JSONSerialization.data(
        withJSONObject: answer, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
    try? data.write(to: outURL)
}

// P1: plans.
let cases: [(String, [Int], [[Int]])] = [
    ("ten", Array(0..<10), (0..<10).map { [$0] }),
    ("shared", [0, 1], [[0, 1]]),
    ("separate", [0, 1], [[0], [1]]),
    ("unlisted", [0], [[7]]),
]
answer["plans"] = cases.map { tag, groups, cuts -> [String: Any] in
    let plan = MattePlan(groups: groups, cuts: cuts)
    return [
        "tag": tag, "groups": groups, "cuts": cuts,
        "steps": plan.steps.map {
            ["group": $0.group, "resolve": $0.resolve, "release": $0.release] as [String: Any]
        },
        "composites_live": plan.compositesLive, "coverages": plan.coverages,
    ]
}

func held(_ pool: MattePool) -> [Int] {
    [pool.held.composites, pool.held.coverages]
}

guard let device = MTLCreateSystemDefaultDevice() else {
    answer["pool"] = ["error": "no Metal device"]
    finish()
    exit(0)
}
var pool: [String: Any] = ["device": device.name]

// P2a: a composite given back is the next one taken; two takes without a
// give are two targets.
do {
    let subject = MattePool(device: device)
    subject.beginFrame(width: 64, height: 64, deep: false)
    let first = subject.takeComposite()
    if let first { subject.giveComposite(first) }
    let second = subject.takeComposite()
    let third = subject.takeComposite()
    pool["take_give_take_same"] = first != nil && first === second
    pool["two_takes_distinct"] = second != nil && third != nil && second !== third
    subject.endFrame()
}

// P2b: frame 1 holds three composites and coverages 0–1; then frames that
// use nothing.
do {
    let subject = MattePool(device: device)
    var after: [String: [Int]] = [:]
    for frame in 1...31 {
        subject.beginFrame(width: 64, height: 64, deep: false)
        if frame == 1 {
            _ = subject.takeComposite()
            _ = subject.takeComposite()
            _ = subject.takeComposite()
            _ = subject.coverage(0)
            _ = subject.coverage(1)
        }
        subject.endFrame()
        if [1, 29, 30, 31].contains(frame) { after[String(frame)] = held(subject) }
    }
    pool["window_from_1"] = after
}

// P2c: a fresh pool used (1, 1) at frame 20 alone.
do {
    let subject = MattePool(device: device)
    var after: [String: [Int]] = [:]
    for frame in 1...50 {
        subject.beginFrame(width: 64, height: 64, deep: false)
        if frame == 20 {
            _ = subject.takeComposite()
            _ = subject.coverage(0)
        }
        subject.endFrame()
        if [19, 20, 49, 50].contains(frame) { after[String(frame)] = held(subject) }
    }
    pool["window_from_20"] = after
}

// P3: a new size empties the pool and makes targets of that size.
do {
    let subject = MattePool(device: device)
    subject.beginFrame(width: 64, height: 64, deep: false)
    let old = subject.takeComposite()
    _ = subject.coverage(0)
    subject.endFrame()
    let before = held(subject)
    subject.beginFrame(width: 32, height: 16, deep: false)
    let emptied = held(subject)
    let composite = subject.takeComposite()
    let coverage = subject.coverage(0)
    subject.endFrame()
    pool["resize"] = [
        "before": before, "after_begin": emptied,
        "old_size": [old?.width ?? 0, old?.height ?? 0],
        "composite_size": [composite?.width ?? 0, composite?.height ?? 0],
        "coverage_size": [coverage?.width ?? 0, coverage?.height ?? 0],
        "composite_is_new": composite != nil && composite !== old,
    ] as [String: Any]
}

// P4 (spec §11 PR-19): a depth change empties the coverages, never the
// composites, and the coverage after it is of the new depth's format; the
// same depth again keeps it. And one 3840×2160 coverage's allocated bytes at
// each depth, as the device reports them.
do {
    let subject = MattePool(device: device)
    subject.beginFrame(width: 64, height: 64, deep: false)
    let composite = subject.takeComposite()
    let shallow = subject.coverage(0)
    subject.endFrame()
    subject.beginFrame(width: 64, height: 64, deep: true)
    let emptied = held(subject)
    let kept = subject.takeComposite()
    let deep = subject.coverage(0)
    subject.endFrame()
    subject.beginFrame(width: 64, height: 64, deep: true)
    let again = subject.coverage(0)
    subject.endFrame()
    subject.beginFrame(width: 64, height: 64, deep: false)
    let back = subject.coverage(0)
    subject.endFrame()
    var bytes: [String: Int] = [:]
    for (name, isDeep) in [("shallow", false), ("deep", true)] {
        let uhd = MattePool(device: device)
        uhd.beginFrame(width: 3840, height: 2160, deep: isDeep)
        bytes[name] = uhd.coverage(0)?.allocatedSize ?? 0
        uhd.endFrame()
    }
    pool["depth"] = [
        "shallow_format": shallow?.pixelFormat.rawValue ?? 0,
        "after_deep_begin": emptied,
        "composite_kept": composite != nil && kept === composite,
        "deep_format": deep?.pixelFormat.rawValue ?? 0,
        "deep_is_new": deep != nil && deep !== shallow,
        "deep_again_same": again != nil && again === deep,
        "back_format": back?.pixelFormat.rawValue ?? 0,
        "back_is_new": back != nil && back !== deep,
        "r8": MTLPixelFormat.r8Unorm.rawValue, "r16": MTLPixelFormat.r16Unorm.rawValue,
        "uhd_bytes": bytes,
    ] as [String: Any]
}

answer["pool"] = pool
finish()
