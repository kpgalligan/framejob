// tools/proof/v2_layout_probe.swift — road map 11's V2a: `UISnapshotLayout`
// put to synthetic view trees, one per rule, each with its control.
//
// `v2_snapshot.py` copies it to `work/v2_snapshot/probe/main.swift` and
// compiles it LAST with every file in `app/Sources` but `main.swift`, over
// `harness/build.sh`'s swiftc line (`-D REELCUT_DEV_TOOLS`), so the rules
// measured are the ones the app ships. It prints exactly one stdout line,
// `ANSWER <json>`: `{"P1": {"ok": Bool, "detail": String}, … "P7": …}`.
//
// P1 an ambiguous view is one problem naming it, and the tree without it has
//    none (the road map's mutant, here rather than in the running app);
// P2 a pinned view and a hidden ambiguous view are not flagged;
// P3 an ambiguous `_NS…` view is in `private_problems` only;
// P4 a truncating label is flagged, a fitting and a wrapping label are not;
// P5 a view past its superview is flagged, a clip view's document and a
//    zero-area view are not;
// P6 `skipping` drops the view and its subtree;
// P7 the rule measures the ALIGNMENT rect (#140, #129): a label pinned flush
//    to its container, whose frame passes it by the label's alignment inset,
//    is not flagged, and a label whose alignment rect is 10 pt past its
//    container is flagged with exactly that overhang.
import AppKit

final class V2ProbeAmbiguous: NSView {}
final class V2ProbePinned: NSView {}
@objc(_NSV2ProbeView) final class V2ProbePrivate: NSView {}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

typealias Row = [String: Any]

func window(_ root: NSView) -> NSWindow {
    let w = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
        styleMask: [.titled], backing: .buffered, defer: false)
    w.contentView = root
    root.layoutSubtreeIfNeeded()
    return w
}

func container() -> NSView {
    NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
}

func problems(_ report: [String: Any], _ key: String = "problems") -> [Row] {
    report[key] as? [Row] ?? []
}

func index(of view: NSView, in report: [String: Any], root: NSView) -> Int? {
    // Pre-order, as the report walks.
    func walk(_ v: NSView, _ list: inout [NSView]) {
        list.append(v)
        for s in v.subviews { walk(s, &list) }
    }
    var list: [NSView] = []
    walk(root, &list)
    return list.firstIndex { $0 === view }
}

func summary(_ list: [Row]) -> String {
    list.map { "\($0["kind"] ?? "?"):\($0["class"] ?? "?")" }.joined(separator: ", ")
}

/// A view pinned leading, top and width in `root`: its height is ambiguous.
func addAmbiguous(_ view: NSView, to root: NSView) {
    view.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(view)
    NSLayoutConstraint.activate([
        view.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
        view.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
        view.widthAnchor.constraint(equalToConstant: 50),
    ])
}

var answer: [String: Any] = [:]

// P1
do {
    let root = container()
    let ambiguous = V2ProbeAmbiguous()
    addAmbiguous(ambiguous, to: root)
    let w = window(root)
    let with = UISnapshotLayout.report(root: root, skipping: nil)
    ambiguous.removeFromSuperview()
    root.layoutSubtreeIfNeeded()
    let without = UISnapshotLayout.report(root: root, skipping: nil)
    let list = problems(with)
    let ok = list.count == 1 && list[0]["kind"] as? String == "ambiguous"
        && list[0]["class"] as? String == "V2ProbeAmbiguous" && list[0]["view"] as? Int == 1
        && problems(without).isEmpty
    answer["P1"] = [
        "ok": ok,
        "detail": "with: [\(summary(list))]; without: [\(summary(problems(without)))]",
    ]
    _ = w
}

// P2
do {
    let root = container()
    let pinned = V2ProbePinned()
    pinned.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(pinned)
    NSLayoutConstraint.activate([
        pinned.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
        pinned.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
        pinned.widthAnchor.constraint(equalToConstant: 50),
        pinned.heightAnchor.constraint(equalToConstant: 20),
    ])
    let hidden = V2ProbeAmbiguous()
    addAmbiguous(hidden, to: root)
    hidden.isHidden = true
    let w = window(root)
    let report = UISnapshotLayout.report(root: root, skipping: nil)
    let hiddenAmbiguous = hidden.hasAmbiguousLayout
    let ok = problems(report).isEmpty && !pinned.hasAmbiguousLayout && hiddenAmbiguous
    answer["P2"] = [
        "ok": ok,
        "detail": "problems [\(summary(problems(report)))]; pinned ambiguous "
            + "\(pinned.hasAmbiguousLayout); hidden view ambiguous \(hiddenAmbiguous) (must be "
            + "true, or the row proves nothing)",
    ]
    _ = w
}

// P3
do {
    let root = container()
    let privateView = V2ProbePrivate()
    addAmbiguous(privateView, to: root)
    let w = window(root)
    let report = UISnapshotLayout.report(root: root, skipping: nil)
    let hidden = problems(report, "private_problems")
    let ok = problems(report).isEmpty && hidden.count == 1
        && hidden[0]["class"] as? String == "_NSV2ProbeView"
        && UISnapshotLayout.isPrivate(privateView)
    answer["P3"] = [
        "ok": ok,
        "detail": "problems [\(summary(problems(report)))]; private_problems [\(summary(hidden))]",
    ]
    _ = w
}

// P4
do {
    let root = container()
    let long = "A label far too long to fit the hundred and twenty points it was given here"
    let truncating = NSTextField(labelWithString: long)
    truncating.frame = NSRect(x: 10, y: 10, width: 120, height: 20)
    let fitting = NSTextField(labelWithString: "Fits")
    fitting.frame = NSRect(x: 10, y: 40, width: 200, height: 20)
    let wrapping = NSTextField(wrappingLabelWithString: long)
    wrapping.preferredMaxLayoutWidth = 360
    wrapping.frame = NSRect(x: 10, y: 70, width: 120, height: 80)
    for field in [truncating, fitting, wrapping] { root.addSubview(field) }
    let w = window(root)
    let report = UISnapshotLayout.report(root: root, skipping: nil)
    let list = problems(report)
    let flagged = Set(list.compactMap { $0["view"] as? Int })
    let t = index(of: truncating, in: report, root: root) ?? -1
    let f = index(of: fitting, in: report, root: root) ?? -1
    let wr = index(of: wrapping, in: report, root: root) ?? -1
    let wrapIntrinsic = wrapping.intrinsicContentSize.width
    let ok = list.count == 1 && list[0]["kind"] as? String == "truncated" && flagged == [t]
        && !flagged.contains(f) && !flagged.contains(wr) && wrapIntrinsic > 120.5
    answer["P4"] = [
        "ok": ok,
        "detail": "problems [\(summary(list))] at \(flagged.sorted()); truncating #\(t) "
            + "intrinsic \(truncating.intrinsicContentSize.width), fitting #\(f), wrapping #\(wr) "
            + "intrinsic \(wrapIntrinsic) vs frame 120 (must exceed it, or the exemption is "
            + "untested)",
    ]
    _ = w
}

// P5
do {
    let root = container()
    let parent = NSView(frame: NSRect(x: 10, y: 10, width: 100, height: 100))
    let past = NSView(frame: NSRect(x: 80, y: 10, width: 40, height: 20))
    let zero = NSView(frame: NSRect(x: 150, y: 10, width: 0, height: 20))
    parent.addSubview(past)
    parent.addSubview(zero)
    root.addSubview(parent)
    let scroll = NSScrollView(frame: NSRect(x: 150, y: 10, width: 100, height: 100))
    let document = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 900))
    scroll.documentView = document
    root.addSubview(scroll)
    let w = window(root)
    let report = UISnapshotLayout.report(root: root, skipping: nil)
    let list = problems(report).filter { $0["kind"] as? String == "outside_superview" }
    let p = index(of: past, in: report, root: root) ?? -1
    let z = index(of: zero, in: report, root: root) ?? -1
    let d = index(of: document, in: report, root: root) ?? -1
    let flagged = Set(list.compactMap { $0["view"] as? Int })
    let detail = list.first?["detail"] as? [String: Any]
    let ok = flagged == [p] && (detail?["overhang"] as? [Double]) == [0, 0, 20, 0]
    answer["P5"] = [
        "ok": ok,
        "detail": "outside_superview at \(flagged.sorted()) (past #\(p), zero-area #\(z), clip "
            + "document #\(d)); overhang \(detail?["overhang"] ?? "none")",
    ]
    _ = w
}

// P6
do {
    let root = container()
    let kept = NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
    let dropped = NSView(frame: NSRect(x: 60, y: 0, width: 50, height: 50))
    let child = V2ProbeAmbiguous()
    addAmbiguous(child, to: dropped)
    root.addSubview(kept)
    root.addSubview(dropped)
    let w = window(root)
    let all = UISnapshotLayout.report(root: root, skipping: nil)
    let skipped = UISnapshotLayout.report(root: root, skipping: dropped)
    let allViews = (all["views"] as? [Row])?.count ?? -1
    let skippedViews = (skipped["views"] as? [Row])?.count ?? -1
    let classes = (skipped["views"] as? [Row] ?? []).compactMap { $0["class"] as? String }
    let ok = allViews == 4 && skippedViews == 2 && !classes.contains("V2ProbeAmbiguous")
        && problems(all).count == 1 && problems(skipped).isEmpty
    answer["P6"] = [
        "ok": ok,
        "detail": "views \(allViews) → \(skippedViews) with skipping; problems "
            + "\(problems(all).count) → \(problems(skipped).count)",
    ]
    _ = w
}

// P7
do {
    let root = container()
    let flushBox = NSView(frame: NSRect(x: 10, y: 150, width: 200, height: 100))
    let controlBox = NSView(frame: NSRect(x: 10, y: 10, width: 200, height: 100))
    root.addSubview(flushBox)
    root.addSubview(controlBox)
    let flush = NSTextField(labelWithString: "Flush to its container")
    flush.translatesAutoresizingMaskIntoConstraints = false
    flushBox.addSubview(flush)
    let control = NSTextField(labelWithString: "Control")
    control.translatesAutoresizingMaskIntoConstraints = false
    controlBox.addSubview(control)
    NSLayoutConstraint.activate([
        flush.leadingAnchor.constraint(equalTo: flushBox.leadingAnchor),
        flush.trailingAnchor.constraint(equalTo: flushBox.trailingAnchor),
        flush.topAnchor.constraint(equalTo: flushBox.topAnchor),
        control.trailingAnchor.constraint(equalTo: controlBox.trailingAnchor, constant: 10),
        control.topAnchor.constraint(equalTo: controlBox.topAnchor),
    ])
    let w = window(root)
    let report = UISnapshotLayout.report(root: root, skipping: nil)
    let list = problems(report)
    let f = index(of: flush, in: report, root: root) ?? -1
    let c = index(of: control, in: report, root: root) ?? -1
    let onFlush = list.filter { $0["view"] as? Int == f }
    let onControl = list.filter {
        $0["view"] as? Int == c && $0["kind"] as? String == "outside_superview"
    }
    let overhang = (onControl.first?["detail"] as? [String: Any])?["overhang"] as? [Double]
    let inset = flush.alignmentRectInsets
    let frame = flush.frame
    let bounds = flushBox.bounds
    let passes = frame.minX < bounds.minX - 0.5 || frame.maxX > bounds.maxX + 0.5
        || frame.minY < bounds.minY - 0.5 || frame.maxY > bounds.maxY + 0.5
    let ambiguous = flush.hasAmbiguousLayout || control.hasAmbiguousLayout
    let ok = inset.left > 0.5 && passes && onFlush.isEmpty && onControl.count == 1
        && overhang == [0, 0, 10, 0] && !ambiguous
    answer["P7"] = [
        "ok": ok,
        "detail": "flush label #\(f): alignment insets [\(inset.left), \(inset.top), "
            + "\(inset.right), \(inset.bottom)] (left must exceed 0.5, or the row proves "
            + "nothing), frame \(frame) vs its container \(bounds): passes it \(passes), "
            + "problems [\(summary(onFlush))]; control label #\(c): outside_superview "
            + "\(onControl.count), overhang \(overhang.map { "\($0)" } ?? "none") (want "
            + "[0, 0, 10, 0]); ambiguous \(ambiguous)",
    ]
    _ = w
}

let data = (try? JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys])) ?? Data()
print("ANSWER " + String(decoding: data, as: UTF8.self))
