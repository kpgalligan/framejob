import AppKit

/// One slot of the scopes panel: a header with the picker at its left and
/// the faint "Rec. 709 · encoded" caption at its right, the picked scope's
/// body, and — for the waveform and the histogram — the two clipping
/// readouts. Its height is its kind's chrome plus `bodyHeight`, which the
/// panel's layout rule sets.
final class ScopeSlotView: NSView {
    static let inset: CGFloat = 12
    static let headerTop: CGFloat = 10
    static let gap: CGFloat = 8
    static let readoutHeight: CGFloat = 15
    static let readoutGap: CGFloat = 4
    static let bottomPad: CGFloat = 8
    /// The body's width inside the insets.
    static let bodyWidth = ScopesPanelView.width - 2 * inset
    static let caption = "Rec. 709 · encoded"

    /// Owner choice 4: Waveform 200, Parade 200, Vectorscope a 224 pt
    /// square, Histogram 140.
    static func preferredBodyHeight(for kind: ScopeKind) -> CGFloat {
        switch kind {
        case .waveform, .parade: return 200
        case .vectorscope: return bodyWidth
        case .histogram: return 140
        }
    }

    /// Whether `kind` shows the two clipping readouts under its body.
    static func hasReadouts(_ kind: ScopeKind) -> Bool {
        kind == .waveform || kind == .histogram
    }

    /// Everything in the slot but the body: the header, the gaps, the
    /// readouts when the kind has them, the bottom pad.
    static func chromeHeight(for kind: ScopeKind) -> CGFloat {
        let readouts = hasReadouts(kind) ? gap + 2 * readoutHeight + readoutGap : 0
        return headerTop + DS.controlHeight + gap + readouts + bottomPad
    }

    let name: String
    /// What the picker chose; setting it puts that kind's body in.
    var kind: ScopeKind = .waveform {
        didSet {
            guard kind != oldValue else { return }
            installBody()
        }
    }
    /// The body's height from the panel's rule; a vectorscope's square side
    /// is min(`bodyWidth`, it).
    var bodyHeight: CGFloat = 0 {
        didSet {
            guard bodyHeight != oldValue else { return }
            applyHeights()
        }
    }
    var onPick: ((ScopeKind) -> Void)?
    private(set) var body: NSView = WaveformTraceView()

    private lazy var picker = OptionPopupControl(
        width: 120, items: ScopeKind.allCases.map(\.title),
        read: { [weak self] in
            self.flatMap { ScopeKind.allCases.firstIndex(of: $0.kind) } ?? 0
        },
        write: { [weak self] index in self?.onPick?(ScopeKind.allCases[index]) },
        enabled: { true },
        // A pick redraws the picker through `kind`'s `installBody`.
        onEdit: {})
    private let captionLabel = NSTextField(labelWithString: ScopeSlotView.caption)
    private let highlights = NSTextField(labelWithString: WaveformTrace.noHighlights)
    private let shadows = NSTextField(labelWithString: WaveformTrace.noShadows)
    private var bodyConstraints: [NSLayoutConstraint] = []
    private var heightConstraint: NSLayoutConstraint?
    private var readoutTop: NSLayoutConstraint?

    init(name: String) {
        self.name = name
        super.init(frame: .zero)
        setAccessibilityIdentifier("scopes.\(name)")
        build()
        installBody()
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("ScopeSlotView does not support NSCoder")
    }

    /// `trace` drawn in the body (nil, or another kind's, is "no frame yet").
    func show(_ trace: ScopeTrace?) {
        var readouts: (String, String)?
        switch (trace, body) {
        case (.waveform(let t)?, let view as WaveformTraceView):
            view.trace = t
            readouts = (t.highlightsReadout, t.shadowsReadout)
        case (.parade(let t)?, let view as ParadeView):
            view.trace = t
        case (.vectorscope(let t)?, let view as VectorscopeView):
            view.trace = t
        case (.histogram(let t)?, let view as HistogramView):
            view.trace = t
            readouts = (t.highlightsReadout, t.shadowsReadout)
        default:
            clearBody()
        }
        highlights.stringValue = readouts?.0 ?? WaveformTrace.noHighlights
        shadows.stringValue = readouts?.1 ?? WaveformTrace.noShadows
    }

    private func clearBody() {
        (body as? WaveformTraceView)?.trace = nil
        (body as? ParadeView)?.trace = nil
        (body as? VectorscopeView)?.trace = nil
        (body as? HistogramView)?.trace = nil
    }

    private func build() {
        captionLabel.font = DS.mono(9)
        captionLabel.textColor = DS.textFaint
        captionLabel.alignment = .right
        // 12 + 120 + 2 + the caption's 102 + 12 fill the 248 pt slot; should
        // the caption ever be wider, it, not the picker, gives way.
        captionLabel.setContentCompressionResistancePriority(
            NSLayoutConstraint.Priority(740), for: .horizontal)
        captionLabel.setAccessibilityIdentifier("scopes.\(name).caption")
        for readout in [highlights, shadows] {
            readout.font = DS.mono(11)
            readout.textColor = DS.textMuted
        }
        highlights.setAccessibilityIdentifier("scopes.\(name).highlights")
        shadows.setAccessibilityIdentifier("scopes.\(name).shadows")
        for view in [picker, captionLabel, highlights, shadows] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let inset = Self.inset
        let height = heightAnchor.constraint(equalToConstant: 0)
        let top = highlights.topAnchor.constraint(equalTo: topAnchor)
        heightConstraint = height
        readoutTop = top
        NSLayoutConstraint.activate([
            height, top,
            picker.topAnchor.constraint(equalTo: topAnchor, constant: Self.headerTop),
            picker.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            captionLabel.centerYAnchor.constraint(equalTo: picker.centerYAnchor),
            captionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            captionLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: picker.trailingAnchor, constant: 2),
            highlights.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            highlights.heightAnchor.constraint(equalToConstant: Self.readoutHeight),
            shadows.topAnchor.constraint(
                equalTo: highlights.bottomAnchor, constant: Self.readoutGap),
            shadows.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            shadows.heightAnchor.constraint(equalToConstant: Self.readoutHeight),
        ])
    }

    /// The picked kind's body in place of the last one, empty until a trace.
    private func installBody() {
        NSLayoutConstraint.deactivate(bodyConstraints)
        body.removeFromSuperview()
        switch kind {
        case .waveform: body = WaveformTraceView()
        case .parade: body = ParadeView()
        case .vectorscope: body = VectorscopeView()
        case .histogram: body = HistogramView()
        }
        body.setAccessibilityIdentifier("scopes.\(name).trace")
        body.translatesAutoresizingMaskIntoConstraints = false
        addSubview(body)
        let top = Self.headerTop + DS.controlHeight + Self.gap
        if kind == .vectorscope {
            bodyConstraints = [
                body.topAnchor.constraint(equalTo: topAnchor, constant: top),
                body.centerXAnchor.constraint(equalTo: centerXAnchor),
                body.widthAnchor.constraint(equalToConstant: 0),
                body.heightAnchor.constraint(equalToConstant: 0),
            ]
        } else {
            bodyConstraints = [
                body.topAnchor.constraint(equalTo: topAnchor, constant: top),
                body.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.inset),
                body.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.inset),
                body.heightAnchor.constraint(equalToConstant: 0),
            ]
        }
        NSLayoutConstraint.activate(bodyConstraints)
        highlights.isHidden = !Self.hasReadouts(kind)
        shadows.isHidden = !Self.hasReadouts(kind)
        show(nil)
        picker.refresh()
        applyHeights()
    }

    /// The slot's, the body's and the readouts' heights for `bodyHeight`.
    private func applyHeights() {
        let side = kind == .vectorscope ? min(Self.bodyWidth, bodyHeight) : bodyHeight
        for constraint in bodyConstraints where constraint.firstAttribute == .height
            || constraint.firstAttribute == .width
        {
            constraint.constant = side
        }
        heightConstraint?.constant = Self.chromeHeight(for: kind) + bodyHeight
        readoutTop?.constant =
            Self.headerTop + DS.controlHeight + Self.gap + bodyHeight + Self.gap
    }
}

#if FRAMEJOB_DEV_TOOLS
extension ScopeSlotView: UISnapshotParts {
    /// The picker draws its item itself, so the layout dump names it:
    /// `scopes.<top|bottom>.picker`, its text the pick's title.
    func snapshotParts() -> [UISnapshotPart] {
        [UISnapshotPart(id: "scopes.\(name).picker", text: kind.title, rect: picker.frame)]
    }
}
#endif
