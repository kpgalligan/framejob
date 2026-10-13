import AppKit

/// The Color sub-tab's **Wheels** section (spec §11 GR-11, grading-2 G2-2):
/// Lift, Gamma and Gain across one row, each a disc for the colour push, a
/// master strip and a master field.
///
/// Every control writes only its own keys — a puck its wheel's `x, y`, a
/// strip or a field its wheel's `master` — through `binding.ops(video:)`, so a
/// write over several clips keeps each one's other values and lands on an
/// action's end when one is selected. A puck or strip drag is the live trio
/// (one undo step named after the wheel); a field, a double-click and Reset
/// commit once, and a strip's double-click off the knob first undoes its
/// first click's jump, so it too is one step (#272). The row never depends on
/// a value, so a live drag never rebuilds the pane (`structureSignature` is
/// unchanged), and it has one row mark and one mixed badge for the whole
/// `video.wheels` key (CI-7, CI-9).
extension VideoPane {
    // MARK: Wheels

    func wheelsSection() -> InspectorSection {
        let binding = self.binding
        func wheels() -> ColorWheels { binding.videoProps.wheels }
        func ops(_ patch: ColorWheelsPatch) -> [ReelOp] {
            binding.ops(video: VideoPatch(wheels: patch))
        }
        let view = ColorWheelsView(binding: binding, wheels: wheels, ops: ops)
        let row = inspectorRow(
            nil, [view], mixed: { binding.mixedVideo { $0.wheels } }, binding: binding,
            writes: ops(.neutral),
            default: .derived(binding, name: "Wheels", read: wheels) { ops(ColorWheelsView.whole($0)) })
        let gutter = row.gutter
        view.keyed = { [weak gutter] in gutter?.isKeyed == true }
        return InspectorSection(
            id: "video.wheels", title: "Wheels",
            summary: { wheels().isNeutral ? "neutral" : "adjusted" },
            reset: { binding.apply("Wheels", video: VideoPatch(wheels: .neutral)) },
            defaultExpanded: false,
            rows: [row])
    }
}

/// The Wheels row's three columns — Lift · Gamma · Gain — each a title, a
/// square-framed `ColorWheelControl`, a `WheelStripControl` and a master
/// field (2 decimals, no unit, −1…1). The disc is the column less 4 pt,
/// capped at 112 pt, so it is about 78 pt at the default pane and 70 at the
/// narrowest. Hugging 1: the row's stretchy element (`inspectorRow` gives it
/// no trailing spacer).
final class ColorWheelsView: NSView {
    static let gap: CGFloat = 4
    static let maxDisc: CGFloat = 112
    /// Whether the row is keyed; the controls ask it when they draw.
    var keyed: () -> Bool = { false }
    private(set) var discs: [ColorWheelControl] = []
    private(set) var strips: [WheelStripControl] = []
    /// `document.project` at each strip's press, while its gesture runs.
    private var stripStarts: [ColorWheelKind: ReelProject] = [:]
    /// `document.project` after each strip's release, and when, kept only
    /// when the gesture made a step (#272): the step a double-click's reset
    /// amends.
    private var stripSteps: [ColorWheelKind: (step: ReelProject, at: TimeInterval)] = [:]

    /// All nine of `wheels` as a patch: the row default's write.
    static func whole(_ wheels: ColorWheels) -> ColorWheelsPatch {
        func patch(_ wheel: ColorWheel) -> ColorWheelPatch {
            ColorWheelPatch(x: wheel.x, y: wheel.y, master: wheel.master)
        }
        return ColorWheelsPatch(
            lift: patch(wheels.lift), gamma: patch(wheels.gamma), gain: patch(wheels.gain))
    }

    init(
        binding: InspectorBinding, wheels: @escaping () -> ColorWheels,
        ops: @escaping (ColorWheelsPatch) -> [ReelOp]
    ) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        var previous: NSView?
        for kind in ColorWheelKind.allCases {
            let column = makeColumn(kind, binding: binding, wheels: wheels, ops: ops)
            addSubview(column)
            NSLayoutConstraint.activate([
                column.topAnchor.constraint(equalTo: topAnchor),
                column.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            if let previous {
                column.leadingAnchor.constraint(equalTo: previous.trailingAnchor, constant: Self.gap)
                    .isActive = true
                column.widthAnchor.constraint(equalTo: previous.widthAnchor).isActive = true
            } else {
                column.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
            }
            previous = column
        }
        previous?.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ColorWheelsView does not support NSCoder")
    }

    private func makeColumn(
        _ kind: ColorWheelKind, binding: InspectorBinding,
        wheels: @escaping () -> ColorWheels, ops: @escaping (ColorWheelsPatch) -> [ReelOp]
    ) -> NSView {
        func wheel() -> ColorWheel { kind.wheel(wheels()) }
        func push() -> (x: Double, y: Double) { (wheel().x, wheel().y) }
        func master() -> Double { wheel().master }
        let name = kind.title
        let title = InspectorRowLabel(name)
        title.alignment = .center
        // A label hugs at 250, above the stack's pull, and would hold the
        // column to its own width; the column is the row's to size.
        title.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let disc = ColorWheelControl(
            read: push,
            write: { [weak binding] x, y in
                // A puck sends its wheel's push alone, never the master.
                let moved = ColorWheelPatch(x: x, y: y)
                binding?.liveUpdate(ops(kind.patch(moved)))
            },
            begin: { [weak binding] in binding?.liveBegin() },
            end: { [weak binding] in binding?.liveEnd(name) },
            reset: { [weak binding] in
                binding?.apply(name, ops(kind.patch(ColorWheelPatch(x: 0, y: 0))))
            },
            enabled: { true },
            start: { [weak binding] in
                guard let binding, let x = binding.startValue({ push().x }),
                      let y = binding.startValue({ push().y })
                else { return nil }
                return (x, y)
            },
            now: { [weak binding] in
                guard let binding, let x = binding.nowValue({ push().x }),
                      let y = binding.nowValue({ push().y })
                else { return nil }
                return (x, y)
            })
        let strip = WheelStripControl(
            read: master,
            write: { [weak binding] value in
                binding?.liveUpdate(ops(kind.patch(ColorWheelPatch(master: value))))
            },
            begin: { [weak self, weak binding] in self?.stripBegan(kind, binding: binding) },
            end: { [weak self, weak binding] in
                self?.stripEnded(kind, name: name, binding: binding)
            },
            reset: { [weak self, weak binding] in
                self?.stripReset(
                    kind, name: name, binding: binding,
                    ops: ops(kind.patch(ColorWheelPatch(master: 0))))
            },
            enabled: { true },
            start: { [weak binding] in binding?.startValue(master) },
            now: { [weak binding] in binding?.nowValue(master) })
        let field = OptionFieldControl(
            width: InspectorMetrics.fieldWidth, unit: "", decimals: 2, min: -1, max: 1,
            read: master,
            write: { [weak binding] value in
                binding?.apply(name, ops(kind.patch(ColorWheelPatch(master: value))))
            },
            enabled: { true },
            onEdit: { [weak binding] in binding?.edited() })
        disc.keyed = { [weak self] in self?.keyed() ?? false }
        strip.keyed = { [weak self] in self?.keyed() ?? false }
        discs.append(disc)
        strips.append(strip)

        let column = NSView()
        column.translatesAutoresizingMaskIntoConstraints = false
        for view in [title, disc, strip, field] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            column.addSubview(view)
        }
        // The disc is the column less 4 pt, square, never past `maxDisc`; the
        // fill is a lower priority than the cap so a wide pane stops at 112.
        let fill = disc.widthAnchor.constraint(equalTo: column.widthAnchor, constant: -Self.gap)
        fill.priority = NSLayoutConstraint.Priority(750)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: column.topAnchor),
            title.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            title.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            disc.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            disc.centerXAnchor.constraint(equalTo: column.centerXAnchor),
            disc.heightAnchor.constraint(equalTo: disc.widthAnchor),
            disc.widthAnchor.constraint(lessThanOrEqualToConstant: Self.maxDisc),
            disc.widthAnchor.constraint(lessThanOrEqualTo: column.widthAnchor),
            fill,
            strip.topAnchor.constraint(equalTo: disc.bottomAnchor, constant: 6),
            strip.leadingAnchor.constraint(equalTo: disc.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: disc.trailingAnchor),
            strip.heightAnchor.constraint(equalToConstant: 13),
            field.topAnchor.constraint(equalTo: strip.bottomAnchor, constant: 4),
            field.centerXAnchor.constraint(equalTo: column.centerXAnchor),
            field.bottomAnchor.constraint(equalTo: column.bottomAnchor),
        ])
        return column
    }

    // MARK: The strip's double-click (#272)

    /// A strip's press: the handle it starts from, then the live trio.
    private func stripBegan(_ kind: ColorWheelKind, binding: InspectorBinding?) {
        stripStarts[kind] = binding?.document?.project
        stripSteps[kind] = nil
        binding?.liveBegin()
    }

    /// A strip's release: the live trio's end, then the handle it left,
    /// kept only when the gesture registered a step (the handle moved).
    private func stripEnded(_ kind: ColorWheelKind, name: String, binding: InspectorBinding?) {
        binding?.liveEnd(name)
        if let after = binding?.document?.project, after !== stripStarts[kind] {
            stripSteps[kind] = (after, ProcessInfo.processInfo.systemUptime)
        }
        stripStarts[kind] = nil
    }

    /// A strip's double-click: the reset amends the step its first click
    /// left when that release is within the double-click interval — so an
    /// earlier gesture's step is never reused — and is its own step
    /// otherwise.
    private func stripReset(
        _ kind: ColorWheelKind, name: String, binding: InspectorBinding?, ops: [ReelOp]
    ) {
        let last = stripSteps.removeValue(forKey: kind)
        if let last,
            ProcessInfo.processInfo.systemUptime - last.at <= NSEvent.doubleClickInterval
        {
            binding?.amend(name, ops, step: last.step)
        } else {
            binding?.apply(name, ops)
        }
    }
}
