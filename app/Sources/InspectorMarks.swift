import AppKit

/// The row marks of the Clip inspector (road map 9 §5, spec §11 CI-7): what
/// the SELECTED action does to one row, in a 14 pt gutter before its label.
///
/// A row's mark is derived from two lists of `"group.key"` paths: the keys
/// its control WRITES — taken from the row's own `ops(read())` at build time,
/// so a write that lands on the action's end patch and one that lands on the
/// base props name the same key — and the keys it only FOLLOWS (Gain follows
/// Volume). Both empty is `.none`, action or no action: a row that says
/// nothing about what it writes (a readout, a Document-tab row) is never
/// marked ⊘ by omission.
enum RowMark: Equatable {
    /// Nothing to say — the gutter stays blank.
    case none
    /// ◆ — the row writes a key the selected action's end patch holds.
    case keyed
    /// ◆ and "at end" — the same, for a discrete control, which switches at
    /// the action's end rather than ramping.
    case keyedAtEnd
    /// ◇ — ANOTHER action keys it; the number is that action's time-order
    /// number (`ActionBands.ordered`).
    case other(Int)
    /// ○ — the row follows a keyed value without writing it.
    case follows
    /// ⊘ — the row writes the clip whatever is selected (CI-3, motion, a
    /// list's length): the selected action cannot animate it.
    case notAnimatable
}

/// A section's marks, folded from its gutters: how many KEYS its rows write
/// that the selected action holds (CI-6's count, so a section's `◆N` agrees
/// with its sub-tab's), whether any row is ◇, and whether every row that
/// writes is ⊘.
struct SectionMarks: Equatable {
    var keyed: Int
    var other: Bool
    var allNotAnimatable: Bool

    static let empty = SectionMarks(keyed: 0, other: false, allNotAnimatable: false)
}

/// The 14 pt column in front of every `inspectorRow`, blank at `.none`. It is
/// the row's FIRST subview, so `refreshOptionControls(in:)` refreshes it
/// before the row's controls — which is what lets its `refresh()` set the
/// label's ink and the controls' keyed border with nothing after it undoing
/// them (`OptionFieldControl.refresh()` never touches its layer).
final class InspectorMarkGutter: NSView, OptionControl {
    let writes: [String]
    let follows: [String]
    private(set) var mark: RowMark = .none
    private weak var binding: InspectorBinding?
    private let animates: Bool
    private let discrete: Bool
    private weak var label: InspectorRowLabel?
    private let controls: [NSView]

    init(
        binding: InspectorBinding?, writes: [ReelOp], follows: [ReelOp],
        label: InspectorRowLabel?, controls: [NSView], discrete: Bool
    ) {
        self.writes = InspectorBinding.paths(of: writes)
        self.follows = InspectorBinding.paths(of: follows)
        self.binding = binding
        self.animates = InspectorBinding.animates(writes)
        self.discrete = discrete
        self.label = label
        self.controls = controls
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: InspectorMetrics.markGutter).isActive = true
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("InspectorMarkGutter does not support NSCoder")
    }

    override var isFlipped: Bool { true }

    /// The keys this row writes that the selected action holds — what a
    /// section's `◆N` is the union of.
    func keyedWrites() -> Set<String> {
        guard let binding else { return [] }
        return binding.keyedPaths().intersection(writes)
    }

    func refresh() {
        let next = binding?.mark(
            writes: writes, follows: follows, animates: animates, discrete: discrete) ?? .none
        if next != mark {
            mark = next
            needsDisplay = true
        }
        let keyed = mark == .keyed || mark == .keyedAtEnd
        let ink = keyed ? DS.textStrong : mark == .notAnimatable ? DS.textFaint : DS.textMuted
        if let label, label.textColor != ink { label.textColor = ink }
        if case .other(let number) = mark {
            toolTip = "Changed by action \(number)"
        } else {
            toolTip = nil
        }
        for control in controls where control is OptionFieldControl
            || control is OptionPopupControl
        {
            if keyed { control.wantsLayer = true }
            guard let layer = control.layer else { continue }
            layer.borderWidth = keyed ? 1 : 0
            if keyed {
                effectiveAppearance.performAsCurrentDrawingAppearance {
                    layer.borderColor = DS.action.cgColor
                }
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let glyph: String
        let ink: NSColor
        switch mark {
        case .none: return
        case .keyed, .keyedAtEnd: (glyph, ink) = ("◆", DS.action)
        case .follows: (glyph, ink) = ("○", DS.action)
        case .other: (glyph, ink) = ("◇", DS.textFaint)
        case .notAnimatable: (glyph, ink) = ("⊘", DS.textFaint)
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: DS.mono(10), .foregroundColor: ink]
        let size = glyph.size(withAttributes: attributes)
        glyph.draw(
            at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
            withAttributes: attributes)
    }
}

/// A short mono tag after a row's controls — "at end" in the action ink, or
/// the coral "now …" of a field-only row. Hidden while `text` answers nil.
final class InspectorRowTag: NSTextField, OptionControl {
    private let text: () -> String?

    init(text: @escaping () -> String?, color: NSColor) {
        self.text = text
        super.init(frame: .zero)
        isEditable = false
        isBordered = false
        isBezeled = false
        drawsBackground = false
        font = DS.mono(10)
        textColor = color
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("InspectorRowTag does not support NSCoder")
    }

    func refresh() {
        let next = text()
        if stringValue != (next ?? "") { stringValue = next ?? "" }
        isHidden = next == nil
    }
}

// MARK: - The mark queries

extension InspectorBinding {
    /// The `"group.key"` paths a list of ops writes: `set_video`, `set_audio`
    /// and `set_text` by their patch's keys, `set_action_end` by each group
    /// of its patch; every other op (a trim, a speed, a reverse) writes none.
    static func paths(of ops: [ReelOp]) -> [String] {
        let groups = ["set_video": "video", "set_audio": "audio", "set_text": "text"]
        var found = Set<String>()
        for op in ops {
            guard let patch = op.args["patch"] as? [String: Any] else { continue }
            if let group = groups[op.name] {
                found.formUnion(patch.keys.map { group + "." + $0 })
            } else if op.name == "set_action_end" {
                found.formUnion(paths(inPatch: patch))
            }
        }
        return found.sorted()
    }

    /// An end patch's paths, spelled as `paths(of:)` spells them.
    private static func paths(inPatch patch: [String: Any]) -> [String] {
        patch.flatMap { group, value in
            ((value as? [String: Any])?.keys).map { $0.map { group + "." + $0 } } ?? []
        }
    }

    /// Whether any of the ops reaches an action's end patch.
    static func animates(_ ops: [ReelOp]) -> Bool {
        ops.contains { $0.name == "set_action_end" }
    }

    /// The selected action's end patch, as paths.
    func keyedPaths() -> Set<String> {
        guard let action = selectedAction else { return [] }
        return Set(Self.paths(inPatch: action.end.dictionary))
    }

    /// The time-order numbers of the single selected clip's OTHER actions
    /// whose end patch holds any of `paths`. One clip only: an action's
    /// number is its clip's, and two clips' numbers would say nothing.
    func otherActions(keying paths: [String]) -> [Int] {
        guard isSingle, let clip = primary, !paths.isEmpty else { return [] }
        let wanted = Set(paths)
        let selected = selectedAction?.id
        return ActionBands.ordered(clip).enumerated().compactMap { index, action in
            guard action.id != selected,
                  !wanted.isDisjoint(with: Self.paths(inPatch: action.end.dictionary))
            else { return nil }
            return index + 1
        }
    }

    /// Spec §11 CI-7's rule, in its order.
    func mark(writes: [String], follows: [String], animates: Bool, discrete: Bool) -> RowMark {
        if writes.isEmpty && follows.isEmpty { return .none }
        if selectedAction != nil {
            if !writes.isEmpty && !animates { return .notAnimatable }
            let keyed = keyedPaths()
            if !keyed.isDisjoint(with: writes) { return discrete ? .keyedAtEnd : .keyed }
            if !keyed.isDisjoint(with: follows) { return .follows }
        }
        if let number = otherActions(keying: writes + follows).first { return .other(number) }
        return .none
    }

    /// The value `read` answers at the PLAYHEAD, when the playhead is inside
    /// the first selected clip; nil otherwise.
    func nowValue(_ read: () -> Double) -> Double? {
        guard let clip = primary, clip.start <= playhead, playhead < clip.end else { return nil }
        return at(.playhead, read)
    }

    /// The value `read` answers at the selected action's START; nil with no
    /// action selected.
    func startValue(_ read: () -> Double) -> Double? {
        guard selectedAction != nil else { return nil }
        return at(.start, read)
    }
}
