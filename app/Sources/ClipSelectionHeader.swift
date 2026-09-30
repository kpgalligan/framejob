import AppKit

// MARK: - Selection header

/// The 44 pt block above the sections: the kind chip, the clip's name, and one
/// mono line of the facts a machine produced — how long it is, and where those
/// pixels came from.
///
/// It is the third view of the one selection model, the other two being the
/// timeline bar's block and the canvas's handles, so the chip and the kind word
/// come from `ClipKindStyle` and agree with them by construction. Drawn rather
/// than composed from controls — with ONE exception since format version 3:
/// for a single clip the name line is an `InspectorNameField`, because this
/// header is where the clip's OWN name is set and the only place it is cleared
/// (the strip's inline editor drops an empty commit — `TimelineView+Rename.swift`
/// says why). A multi-selection keeps the drawn "N clips selected". A label is
/// a 6 pt dot at the line's right end, the strip's dot, so the two views agree.
/// The field binds by clip ID and reads fresh through it (`timingSection`'s rule).
final class ClipSelectionHeaderView: NSView, OptionControl {
    static let height: CGFloat = 44
    /// The name line: 16 pt at y 8 drawn, a 20 pt field at y 6 typed into —
    /// both centred on y 16 — with the meta line under it. An
    /// `InspectorNameField` pins its own height at `DS.controlHeight`, more
    /// than a 44 pt band with a meta line can give, so the field's is
    /// re-pinned (`installNameField`).
    private static let nameTop: CGFloat = 8
    private static let nameHeight: CGFloat = 16
    private static let fieldTop: CGFloat = 6
    private static let fieldHeight: CGFloat = 20
    private static let metaTop: CGFloat = 27
    private static let dotSize: CGFloat = 6
    private static let dotGap: CGFloat = 6

    private let binding: InspectorBinding
    private var nameField: InspectorNameField?
    /// The field's right edge, pulled in by the dot's room while a label is set.
    private var nameTrailing: NSLayoutConstraint?

    init(binding: InspectorBinding) {
        self.binding = binding
        super.init(frame: .zero)
        wantsLayer = true
        // Decided once: the pane, header included, is rebuilt whenever the
        // selected ids change (`structureSignature`).
        if binding.isSingle, let clip = binding.primary {
            installNameField(for: clip.id)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ClipSelectionHeaderView does not support NSCoder")
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.height)
    }

    /// Redraws only when what it SAYS changed. The panel refreshes on every
    /// playhead tick when the selected clip has actions
    /// (`EditorViewController+Inspector.swift`), and re-laying two truncating
    /// strings across a 44 pt band thirty times a second for a value that moves
    /// once per click is work for nothing. The field's own `refresh` is as
    /// cheap, and skips itself while it is typed into.
    func refresh() {
        nameField?.refresh()
        let label = self.label
        let trailing = -(InspectorMetrics.inset + (label == nil ? 0 : Self.dotSize + Self.dotGap))
        if let constraint = nameTrailing, constraint.constant != trailing {
            constraint.constant = trailing
        }
        let next = [name, meta, label ?? ""]
        guard next != lastDrawn else { return }
        lastDrawn = next
        needsDisplay = true
    }

    private var lastDrawn: [String] = []

    // MARK: The name field

    /// The single-clip name line, typed into. It shows what the strip shows
    /// (`name(of:)` — own name or fallback), so what you read is what you
    /// edit, and commits the clip's OWN name: the trimmed text, or `null` for
    /// an emptied field, which is how a name goes back to the fallback.
    /// Emptying a field that already showed the fallback has nothing to
    /// clear: no op is sent (the core's refusal would only beep). Either way
    /// the field re-reads the model as the commit ends — `InspectorNameField`
    /// sets itself directly there, because its `refresh` is skipped while
    /// the field editor is attached, which it still is at that point.
    private func installNameField(for id: UInt32) {
        let binding = self.binding
        /// Read fresh through the captured id, never captured itself: a
        /// rename REPLACES the clip snapshot, and the header is refreshed.
        func clip() -> ClipSnapshot? { binding.snapshot.clip(id) }
        let field = InspectorNameField(
            read: { clip().map { binding.snapshot.name(of: $0) } ?? "" },
            write: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty, clip()?.name == nil { return }
                let patch = ClipPatch(name: .some(trimmed.isEmpty ? nil : trimmed))
                binding.apply("Rename Clip", [.setClip(clips: [id], patch: patch)])
            },
            enabled: { clip() != nil },
            onEdit: { binding.edited() })
        field.font = DS.sans(12, weight: .semibold)
        field.toolTip = "The clip's own name — empty it to go back to what the clip shows"
        // The field pins its own `DS.controlHeight` height; the one
        // constraint is re-pinned rather than fought with a second.
        for constraint in field.constraints
        where constraint.firstItem === field && constraint.firstAttribute == .height {
            constraint.constant = Self.fieldHeight
        }
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)
        let trailing = field.trailingAnchor.constraint(
            equalTo: trailingAnchor, constant: -InspectorMetrics.inset)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.nameLeft),
            field.topAnchor.constraint(equalTo: topAnchor, constant: Self.fieldTop),
            trailing,
        ])
        nameTrailing = trailing
        nameField = field
    }

    // MARK: What it says

    /// The chip's ink: the kind's tint, or the neutral one when the selection
    /// holds more than one kind and no single tint would be true.
    private var chipColor: NSColor {
        let clips = binding.clips
        guard let first = clips.first else { return DS.borderStrong }
        let tint = ClipKindStyle.tint(for: first, in: binding.snapshot)
        let mixed = clips.dropFirst().contains {
            ClipKindStyle.tint(for: $0, in: binding.snapshot) != tint
        }
        return mixed ? DS.borderStrong : tint
    }

    private var name: String {
        let clips = binding.clips
        guard let first = clips.first else { return "No selection" }
        guard clips.count == 1 else { return "\(clips.count) clips selected" }
        return binding.snapshot.name(of: first)
    }

    /// The label the selection agrees on — nil when the clips disagree or
    /// none has one, so the dot never claims a colour for a clip that has
    /// another. An unknown name draws in the neutral ink, as on the strip.
    private var label: String? {
        let clips = binding.clips
        guard let first = clips.first?.label, !first.isEmpty,
              clips.allSatisfy({ $0.label?.lowercased() == first.lowercased() })
        else { return nil }
        return first
    }

    /// The meta line: the kind word, the duration in the DOCUMENT's timecode
    /// (never the source's), and the source's own facts where there are any.
    private var meta: String {
        let clips = binding.clips
        let canvas = binding.canvas
        guard let first = clips.first else { return "" }
        guard clips.count == 1 else {
            let total = clips.reduce(Ticks(0)) { $0 + $1.duration }
            return ReelTime.format(total, fps: canvas.fps, frames: canvas.timecodeFrames)
                + " total"
        }
        var parts = [ClipKindStyle.name(for: first, in: binding.snapshot)]
        parts.append(
            ReelTime.format(first.duration, fps: canvas.fps, frames: canvas.timecodeFrames))
        if let size = binding.snapshot.sourceSize(of: first), size.width > 0, size.height > 0 {
            parts.append("\(Int(size.width))×\(Int(size.height))")
        }
        // The source's own rate, not the canvas's: it is the one fact here
        // that says whether this clip is being conformed.
        if let media = binding.snapshot.media(for: first), media.hasVideo, media.fps.double > 0 {
            parts.append("\(media.fps.displayName) fps")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Drawing

    /// Where the name line starts: after the chip and its gap.
    private static var nameLeft: CGFloat { InspectorMetrics.inset + 8 + 8 }

    override func draw(_ dirtyRect: NSRect) {
        DS.border.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()

        let chip = NSRect(x: InspectorMetrics.inset, y: bounds.midY - 13, width: 8, height: 26)
        chipColor.setFill()
        chip.fill()

        let left = Self.nameLeft
        var nameRight = bounds.width - InspectorMetrics.inset
        if let label = label {
            // At the line's right end, centred on it, like the strip's.
            let dot = NSRect(
                x: nameRight - Self.dotSize,
                y: Self.nameTop + Self.nameHeight / 2 - Self.dotSize / 2,
                width: Self.dotSize, height: Self.dotSize)
            ClipLabel.color(named: label).setFill()
            NSBezierPath(ovalIn: dot).fill()
            nameRight = dot.minX - Self.dotGap
        }
        // The field paints its own line when there is one.
        if nameField == nil {
            let line = NSRect(
                x: left, y: Self.nameTop, width: max(nameRight - left, 10),
                height: Self.nameHeight)
            draw(name, in: line, font: DS.sans(12, weight: .semibold), color: DS.textStrong)
        }
        let width = max(bounds.width - left - InspectorMetrics.inset, 10)
        draw(meta, in: NSRect(x: left, y: Self.metaTop, width: width, height: 13),
             font: DS.mono(10), color: DS.textFaint)
    }

    /// One truncating line. `TimelineDraw.label` clips instead, which is right
    /// on a clip bar (the bar's edge says where it stopped) and wrong here,
    /// where a cut-off file name has nothing to say it was cut off.
    private func draw(_ text: String, in rect: NSRect, font: NSFont, color: NSColor) {
        guard !text.isEmpty, rect.width > 8 else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        text.draw(
            in: rect,
            withAttributes: [
                .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
            ])
    }
}
