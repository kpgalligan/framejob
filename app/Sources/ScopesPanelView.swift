import AppKit

/// What `ScopesPanelView.layout(picks:paneHeight:)` answers: whether the
/// bottom slot shows, and one body height per shown slot, top first.
struct ScopeSlotLayout: Equatable {
    let showsBottom: Bool
    let bodyHeights: [CGFloat]
}

/// View ▸ Scopes' panel (spec §11 GR-5, GR-10): a fixed 248 pt column at the
/// pane's right edge, its full height, holding two stacked slots, each with a
/// picker. Off, it is zero wide and hidden and the canvas takes the pane. Its
/// contents are a 248 pt block pinned to its leading edge and clipped, so a
/// zero width never asks a constraint for a negative one. Shown, its window's
/// tap (`WaveformTaps`) is attached with the passes its visible slots show —
/// one pass per kind and zoom, so one scope in both slots costs one, and two
/// vectorscopes at different zooms two (spec §11 GR-31) — and hidden, or out
/// of its window, detached.
///
/// **The layout rule** (owner, 2026-10-10, GR-10 as amended in G2-1): when
/// the pane cannot hold both slots' bodies at their preferred heights, both
/// shrink by one factor to fit, the vectorscope square and centred; below
/// `twoSlotMinHeight` only the top slot shows. A layout pass that shows or
/// hides the bottom slot, and every pick and zoom, re-attach the tap with
/// the new passes and ask for a frame (`onNeedsFrame`), so no slot waits
/// empty.
///
/// **Nothing here persists** (GR-5, GR-10, GR-31): a new window starts with
/// the panel off, the picks at `openingPicks` and every zoom ×1; a pick or a
/// zoom lasts while the window is open (a zoom across a pick of another scope
/// and back, and across hide and show) and has no `UserDefaults` key and no
/// MCP tool (`render_frame {vectorscope_zoom}` is the capability).
final class ScopesPanelView: NSView {
    static let width: CGFloat = 248
    static let openingPicks: [ScopeKind] = [.waveform, .vectorscope]
    /// The pane height below which only the top slot shows.
    static let twoSlotMinHeight: CGFloat = 360

    /// The rule above, pure: both bodies at their preferred heights when the
    /// pane holds them, else both scaled by one factor to fit, each rounded
    /// down to a whole point; one slot below `twoSlotMinHeight`, its body
    /// min(preferred, room).
    static func layout(picks: [ScopeKind], paneHeight: CGFloat) -> ScopeSlotLayout {
        let showsBottom = picks.count > 1 && paneHeight >= twoSlotMinHeight
        let shown = Array(picks.prefix(showsBottom ? 2 : 1))
        let preferred = shown.map(ScopeSlotView.preferredBodyHeight)
        let chrome = shown.map(ScopeSlotView.chromeHeight).reduce(0, +)
        let room = max(0, paneHeight - chrome)
        let total = preferred.reduce(0, +)
        let factor = total > 0 ? min(1, room / total) : 0
        return ScopeSlotLayout(
            showsBottom: showsBottom,
            bodyHeights: preferred.map { ($0 * factor).rounded(.down) })
    }

    private let content = NSView()
    private let slots = [ScopeSlotView(name: "top"), ScopeSlotView(name: "bottom")]
    private(set) var picks: [ScopeKind] = ScopesPanelView.openingPicks
    /// Whether the last layout pass showed the bottom slot.
    private(set) var showsBottomSlot = false
    /// Asks for a frame to measure: the window composes its paused frame
    /// again (`EditorViewController.refreshSeeing`).
    var onNeedsFrame: (() -> Void)?
    /// Just under required: a pane narrower than the panel (never reached,
    /// the split keeps 380 pt) squeezes it rather than logging a conflict.
    private lazy var widthConstraint: NSLayoutConstraint = {
        let width = widthAnchor.constraint(equalToConstant: 0)
        width.priority = NSLayoutConstraint.Priority(999)
        return width
    }()
    /// The key the tap is attached under, while shown.
    private var key: Int?

    init() {
        super.init(frame: .zero)
        widthConstraint.isActive = true
        isHidden = true
        wantsLayer = true
        layer?.masksToBounds = true
        setAccessibilityIdentifier("scopes.panel")
        build()
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("ScopesPanelView does not support NSCoder")
    }

    var isShown: Bool { widthConstraint.constant > 0 }

    /// The kinds the visible slots show: the top pick, and the bottom's while
    /// its slot shows.
    var shownKinds: Set<ScopeKind> { Set(picks.prefix(showsBottomSlot ? 2 : 1)) }

    /// The passes the visible slots show: each one's kind and zoom.
    var shownPasses: Set<ScopePass> { Set(slots.prefix(showsBottomSlot ? 2 : 1).map(\.pass)) }

    /// The slot views, top first (for the instruments that read their
    /// bodies' rects).
    var slotViews: [ScopeSlotView] { slots }

    /// Shows or hides the panel for the document keyed `key`.
    func setShown(_ shown: Bool, key: Int) {
        widthConstraint.constant = shown ? Self.width : 0
        isHidden = !shown
        if shown {
            self.key = key
            attach()
        } else {
            WaveformTaps.shared.detach(key: key)
            self.key = nil
            show(nil)
        }
    }

    /// Slot `slot` (0 top, 1 bottom) shows `kind` from now on.
    func pick(_ kind: ScopeKind, slot: Int) {
        guard picks.indices.contains(slot) else { return }
        picks[slot] = kind
        slots[slot].kind = kind
        needsLayout = true
        guard key != nil else { return }
        attach()
        onNeedsFrame?()
    }

    /// Slot `slot`'s vectorscope zoom from now on (1, 2 or 4; anything else
    /// ignored). Its body is cleared until the next reading, as a pick's is.
    func zoom(_ zoom: Int, slot: Int) {
        guard slots.indices.contains(slot), VectorscopeTrace.zooms.contains(zoom),
            slots[slot].zoom != zoom
        else { return }
        slots[slot].zoom = zoom
        slots[slot].show(nil)
        guard key != nil else { return }
        attach()
        onNeedsFrame?()
    }

    /// The traces to draw, by pass; nil is "no frame yet" (the readouts say
    /// "—").
    func show(_ traces: [ScopePass: ScopeTrace]?) {
        for slot in slots {
            slot.show(traces?[slot.pass])
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let key else { return }
        if window == nil {
            WaveformTaps.shared.detach(key: key)
        } else {
            attach()
        }
    }

    override func layout() {
        let rule = Self.layout(picks: picks, paneHeight: bounds.height)
        slots[0].bodyHeight = rule.bodyHeights[0]
        if rule.showsBottom {
            slots[1].bodyHeight = rule.bodyHeights[1]
        }
        slots[1].isHidden = !rule.showsBottom
        super.layout()
        guard rule.showsBottom != showsBottomSlot else { return }
        showsBottomSlot = rule.showsBottom
        guard key != nil else { return }
        attach()
        onNeedsFrame?()
    }

    override func draw(_ dirtyRect: NSRect) {
        DS.chromeBackground.setFill()
        bounds.fill()
        DS.border.setFill()
        NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill()
    }

    private func attach() {
        guard let key else { return }
        WaveformTaps.shared.attach(key: key, passes: shownPasses) { [weak self] traces in
            self?.show(traces)
        }
    }

    private func build() {
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        for (index, slot) in slots.enumerated() {
            slot.kind = picks[index]
            slot.onPick = { [weak self] kind in self?.pick(kind, slot: index) }
            slot.onZoom = { [weak self] zoom in self?.zoom(zoom, slot: index) }
            slot.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(slot)
        }
        slots[1].isHidden = true
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.widthAnchor.constraint(equalToConstant: Self.width),
            slots[0].topAnchor.constraint(equalTo: content.topAnchor),
            slots[1].topAnchor.constraint(equalTo: slots[0].bottomAnchor),
        ])
        for slot in slots {
            NSLayoutConstraint.activate([
                slot.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                slot.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            ])
        }
    }
}

/// The "Ungraded" tag (spec §11 GR-4): top-left of the preview pane, inside
/// the canvas's 24 pt void, shown while View ▸ Show Ungraded is on. It takes
/// no clicks, so a gesture on the canvas beneath it is the canvas's.
final class UngradedTagView: NSTextField {
    init() {
        super.init(frame: .zero)
        stringValue = "Ungraded"
        isEditable = false
        isSelectable = false
        isBezeled = false
        isBordered = false
        drawsBackground = true
        backgroundColor = DS.chromeBackground
        textColor = DS.textMuted
        font = DS.mono(10)
        isHidden = true
        setAccessibilityIdentifier("preview.ungraded")
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("UngradedTagView does not support NSCoder")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The "Selection" tag (spec §11 GR-13): Show Selection's, beside
/// "Ungraded" in the preview's top-left void, shown only while the switch
/// is on. It takes no clicks.
final class SelectionTagView: NSTextField {
    init() {
        super.init(frame: .zero)
        stringValue = "Selection"
        isEditable = false
        isSelectable = false
        isBezeled = false
        isBordered = false
        drawsBackground = true
        backgroundColor = DS.chromeBackground
        textColor = DS.textMuted
        font = DS.mono(10)
        isHidden = true
        setAccessibilityIdentifier("preview.selection")
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("SelectionTagView does not support NSCoder")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The "SDR Version" tag (spec §11 HD-7, HD-14 (g)): Show SDR Version's,
/// third in the preview's top-left void, shown only while the switch is on —
/// in an SDR project too, where the picture does not change. It takes no
/// clicks.
final class SDRVersionTagView: NSTextField {
    init() {
        super.init(frame: .zero)
        stringValue = "SDR Version"
        isEditable = false
        isSelectable = false
        isBezeled = false
        isBordered = false
        drawsBackground = true
        backgroundColor = DS.chromeBackground
        textColor = DS.textMuted
        font = DS.mono(10)
        isHidden = true
        setAccessibilityIdentifier("preview.sdrVersion")
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("SDRVersionTagView does not support NSCoder")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
