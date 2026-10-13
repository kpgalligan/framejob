import AppKit

#if FRAMEJOB_DEV_TOOLS
/// `snapshot_ui`'s layout dump (road map 11's V2a): every view under a
/// captured root, pre-order, and the problems three rules find in them.
///
/// Pure over an `NSView` tree, so a probe can put a synthetic tree to it
/// (`tools/proof/v2_layout_probe.swift`). Main-thread only, as every AppKit
/// read is.
///
/// **The rules, each only for a view that is not hidden (itself or an
/// ancestor):**
/// - **ambiguous** — `hasAmbiguousLayout` (V1's L1/L2 measured it truthful
///   in an `-O` build);
/// - **outside_superview** — a view of non-zero area, not the root and not a
///   clip view's document, whose ALIGNMENT rect (`alignmentRect(forFrame:)`,
///   the rect Auto Layout pins) passes its superview's bounds by more than
///   `tolerance` on any side — so a label pinned flush, whose frame is its
///   alignment inset wider, is not one;
/// - **truncated** — a text field with text whose intrinsic width passes its
///   frame by more than `tolerance`, unless it wraps (V1's L4–L7; #70 is
///   the shape of it).
///
/// A problem on one of AppKit's private `_NS…` views goes to
/// `private_problems` and never to `problems` (V1's L3 found three such
/// views ambiguous inside the Text sub-tab's text view), so an empty
/// `problems` means the app's own views are clean.
///
/// **A secure field's text never leaves it**: its `text` and a truncation's
/// detail are `null` for any `NSSecureTextField` (Settings' key field), and a
/// field editor's (the text view that edits a field, a secure one included)
/// is `null` too; an ordinary text view's `text` is its string.
/// `tooltip` is the view's own `toolTip`, `null` when it has none and always
/// for a secure field — what a label cut short can still be read by
/// (`hevc_alpha_proof.py` E1 holds the export sheet's footnote to it).
///
/// **A view that draws several things in one view names them as parts**
/// (`UISnapshotParts`; the Assistant tab's transcript, whose entries are
/// ranges of one text view, spec §11 AI-17): one record each, class
/// `UISnapshotPart`, right after the view's own record and before its
/// subviews, parented to it. A part never produces a problem.
enum UISnapshotLayout {
    static let tolerance: CGFloat = 0.5

    /// `views`, `problems` and `private_problems` for the tree under `root`,
    /// with `skipping` and its subtree left out (the staged fill).
    static func report(root: NSView, skipping: NSView?) -> [String: Any] {
        var views: [[String: Any]] = []
        var problems: [[String: Any]] = []
        var privateProblems: [[String: Any]] = []

        func visit(_ view: NSView, parent: Int, depth: Int) {
            if let skipping, view === skipping { return }
            let index = views.count
            let frame = UISnapshot.rect(view, in: root)
            let hidden = view.isHiddenOrHasHiddenAncestor
            let ambiguous = view.hasAmbiguousLayout
            let intrinsic = view.intrinsicContentSize
            let identifier = view.accessibilityIdentifier()
            views.append([
                "i": index,
                "parent": parent,
                "depth": depth,
                "class": className(view),
                "id": identifier.isEmpty ? NSNull() : identifier as Any,
                "frame": frame,
                "hidden": hidden,
                "ambiguous": ambiguous,
                "intrinsic": [metric(intrinsic.width), metric(intrinsic.height)],
                "text": UISnapshot.orNull(text(of: view)),
                "tooltip": UISnapshot.orNull(tooltip(of: view)),
            ])
            if let named = view as? UISnapshotParts {
                for part in named.snapshotParts() {
                    views.append([
                        "i": views.count,
                        "parent": index,
                        "depth": depth + 1,
                        "class": "UISnapshotPart",
                        "id": part.id,
                        "frame": partRect(part.rect, of: view, in: root),
                        "hidden": hidden,
                        "ambiguous": false,
                        "intrinsic": [-1, -1],
                        "text": String(part.text.prefix(200)),
                    ])
                }
            }
            if !hidden {
                for (kind, detail) in findings(view, isRoot: parent < 0, ambiguous: ambiguous) {
                    var detail = detail
                    if kind == "outside_superview" { detail["superview"] = parent }
                    let problem: [String: Any] = [
                        "kind": kind, "view": index, "class": className(view), "frame": frame,
                        "detail": detail,
                    ]
                    if isPrivate(view) {
                        privateProblems.append(problem)
                    } else {
                        problems.append(problem)
                    }
                }
            }
            for sub in view.subviews {
                visit(sub, parent: index, depth: depth + 1)
            }
        }
        visit(root, parent: -1, depth: 0)
        return ["views": views, "problems": problems, "private_problems": privateProblems]
    }

    /// `NSStringFromClass`, with a Swift module prefix (`Frame Job.`) stripped.
    static func className(_ view: NSView) -> String {
        let name = NSStringFromClass(type(of: view))
        guard !name.hasPrefix("_Tt"), let dot = name.lastIndex(of: ".") else { return name }
        return String(name[name.index(after: dot)...])
    }

    /// One of AppKit's private views, by the `_NS` class-name prefix.
    static func isPrivate(_ view: NSView) -> Bool {
        NSStringFromClass(type(of: view)).hasPrefix("_NS")
    }

    // MARK: - The rules

    private static func findings(
        _ view: NSView, isRoot: Bool, ambiguous: Bool
    ) -> [(String, [String: Any])] {
        var found: [(String, [String: Any])] = []
        if ambiguous {
            found.append(("ambiguous", [:]))
        }
        if !isRoot, let overhang = overhang(view) {
            found.append(("outside_superview", ["overhang": overhang]))
        }
        if let truncation = truncation(view) {
            found.append(("truncated", truncation))
        }
        return found
    }

    /// `[left, top, right, bottom]` in points the view's alignment rect
    /// passes the superview's bounds by, or nil when it is within them (or
    /// exempt). The zero-area exemption reads the frame.
    private static func overhang(_ view: NSView) -> [Double]? {
        guard let superview = view.superview, !(superview is NSClipView) else { return nil }
        guard view.frame.width * view.frame.height > 0 else { return nil }
        let frame = view.alignmentRect(forFrame: view.frame)
        let bounds = superview.bounds
        let left = bounds.minX - frame.minX
        let right = frame.maxX - bounds.maxX
        let above = superview.isFlipped ? bounds.minY - frame.minY : frame.maxY - bounds.maxY
        let below = superview.isFlipped ? frame.maxY - bounds.maxY : bounds.minY - frame.minY
        let sides = [left, above, right, below]
        guard sides.contains(where: { $0 > tolerance }) else { return nil }
        return sides.map { UISnapshot.round2(max(0, $0)) }
    }

    private static func truncation(_ view: NSView) -> [String: Any]? {
        guard let field = view as? NSTextField, !field.stringValue.isEmpty,
            field.frame.width > 0
        else { return nil }
        let intrinsic = field.intrinsicContentSize.width
        guard intrinsic != NSView.noIntrinsicMetric, intrinsic > field.frame.width + tolerance
        else { return nil }
        let wraps = field.cell?.wraps == true && !field.usesSingleLineMode
        guard !wraps else { return nil }
        return [
            "text": UISnapshot.orNull(text(of: field)),
            "intrinsic_width": UISnapshot.round2(intrinsic),
            "frame_width": UISnapshot.round2(field.frame.width),
            "visible": !field.visibleRect.isEmpty,
        ]
    }

    // MARK: - Values

    private static func metric(_ value: CGFloat) -> Double {
        value == NSView.noIntrinsicMetric ? -1 : UISnapshot.round2(value)
    }

    /// A part's rect, in `view`'s own coordinates, as `UISnapshot.rect`'s
    /// [x, top, w, h] in `root`'s.
    private static func partRect(_ rect: NSRect, of view: NSView, in root: NSView) -> [Double] {
        let r = view.convert(rect, to: root)
        let top = root.isFlipped ? r.minY : root.bounds.height - r.maxY
        return [r.minX, top, r.width, r.height].map { UISnapshot.round2($0) }
    }

    /// A label's, a button's or a text view's text, first 200 characters;
    /// never a secure field's, and never a field editor's.
    private static func text(of view: NSView) -> String? {
        if view is NSSecureTextField { return nil }
        if let field = view as? NSTextField { return String(field.stringValue.prefix(200)) }
        if let button = view as? NSButton { return String(button.title.prefix(200)) }
        if let textView = view as? NSTextView, !textView.isFieldEditor {
            return String(textView.string.prefix(200))
        }
        return nil
    }

    /// A view's tooltip, first 200 characters; never a secure field's.
    private static func tooltip(of view: NSView) -> String? {
        if view is NSSecureTextField { return nil }
        return view.toolTip.map { String($0.prefix(200)) }
    }
}

/// A view that names what it draws, for the layout dump, in place of
/// subviews it does not have.
protocol UISnapshotParts: AnyObject {
    func snapshotParts() -> [UISnapshotPart]
}

/// One named part: its identifier, its text, and its rect in the naming
/// view's own coordinates.
struct UISnapshotPart: Equatable {
    let id: String
    let text: String
    let rect: NSRect
}
#endif
