import AppKit

/// The Transcript tab's view (road map "creator-jobs" TX2a, spec §11 TX-21,
/// TX-22; TX-S2's candidate (b)): a custom `NSView` laid out by TextKit 2 —
/// an `NSTextLayoutManager` over an `NSTextContentStorage`, with viewport
/// layout, so only the fragments in sight are laid out and drawn.
///
/// **Not an `NSText`** (TX-21): `handleEditorKey` gives up on an `NSText`
/// first responder, and `SpaceKey.route` hands Space to the transport for any
/// first responder that is neither editable text nor a button. So Space, J,
/// K, L, I, O and M reach the editor exactly as from the timeline; the view
/// keeps only the keys `+Keys` names.
///
/// The text is one string: each paragraph's timecode on a line of its own,
/// then its words joined by spaces. `tokenStarts` and `tokenLengths` map a
/// token to its UTF-16 range, `timecodeRanges` a paragraph's timecode. The
/// highlight and the selection are drawn behind the text (`+Highlight`); the
/// geometry and the hit-tests are `+Layout`'s.
final class TranscriptView: NSView, NSTextViewportLayoutControllerDelegate {
    /// A token clicked or arrowed to.
    var onActivate: ((Int) -> Void)?
    /// A paragraph's timecode clicked.
    var onParagraph: ((Int) -> Void)?
    /// The clock the 3 s follow pause reads (TX-22). Internal: a probe sets it.
    var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

    var highlight: Int? { highlighted }
    private(set) var selection: ClosedRange<Int>?
    private(set) var lastPersonScroll: TimeInterval?
    /// Where a ⇧-extension started.
    var selectionAnchor: Int?

    static let inset = NSSize(width: InspectorMetrics.inset, height: 8)
    static let followPause: TimeInterval = 3

    let contentStorage = NSTextContentStorage()
    let layoutManager = NSTextLayoutManager()
    private let container = NSTextContainer(size: .zero)
    /// The fragments the last viewport layout produced, top to bottom.
    var fragments: [NSTextLayoutFragment] = []

    private(set) var model = TranscriptTokens.empty
    private(set) var tokenStarts: [Int] = []
    private(set) var tokenLengths: [Int] = []
    private(set) var timecodeRanges: [NSRange] = []
    /// Each contiguous run of words that cannot be cut, with its reason.
    private(set) var dimRuns: [(range: NSRange, why: String)] = []
    var highlighted: Int?
    /// The timecode style the last `show` used, for a restyle.
    private var shownStyle: (fps: Fps, frames: Bool)?
    private var observed: [NSObjectProtocol] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        container.widthTracksTextView = false
        container.lineFragmentPadding = 0
        layoutManager.textContainer = container
        contentStorage.addTextLayoutManager(layoutManager)
        layoutManager.textViewportLayoutController.delegate = self
        setAccessibilityIdentifier("transcript.view")
        setAccessibilityRole(.textArea)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TranscriptView does not support NSCoder")
    }

    deinit {
        for token in observed { NotificationCenter.default.removeObserver(token) }
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    // MARK: - The text

    /// Lays `tokens` out, keeping the top visible token's identity at its
    /// offset from the visible top, else the nearest later start.
    func show(_ tokens: TranscriptTokens, fps: Fps, timecodeFrames: Bool) {
        let anchor = topVisibleToken().map { index -> (TimelineTranscript.Identity, Ticks, CGFloat) in
            let token = model.tokens[index]
            let y = (rects(forToken: index).first?.minY ?? visibleRect.minY) - visibleRect.minY
            return (token.word.id, token.word.start, y)
        }
        let selected = selection.map { (model.tokens[$0.lowerBound].word.id, model.tokens[$0.upperBound].word.id) }
        let lit = highlighted.map { model.tokens[$0].word.id }
        let anchored = selectionAnchor.flatMap { model.tokens.indices.contains($0) ? model.tokens[$0].word.id : nil }
        model = tokens
        shownStyle = (fps, timecodeFrames)
        contentStorage.textStorage?.setAttributedString(text(fps: fps, frames: timecodeFrames))
        highlighted = lit.flatMap { model.index(of: $0) }
        selection = selected.flatMap { pair in
            guard let low = model.index(of: pair.0), let high = model.index(of: pair.1), low <= high
            else { return nil }
            return low...high
        }
        // The ⇧-extension's anchor follows its word, else the selection's
        // start: an old index can lie past a shrunk text.
        selectionAnchor = selection.map { range in
            anchored.flatMap { model.index(of: $0) }.flatMap { range.contains($0) ? $0 : nil } ?? range.lowerBound
        }
        fitContainer()
        layoutViewport()
        if let (id, start, offset) = anchor,
            let index = model.index(of: id) ?? model.firstIndex(atOrAfter: start),
            let rect = rects(forToken: index).first
        {
            scroll(to: rect.minY - offset)
        }
        needsDisplay = true
    }

    /// The whole transcript as one attributed string, recording each token's
    /// and each timecode's UTF-16 range as it goes. Built as one string and
    /// then styled by ranges: an attributed string per word cost a third of
    /// a rebuild (TX-S2).
    private func text(fps: Fps, frames: Bool) -> NSAttributedString {
        let plain = NSMutableString()
        var starts: [Int] = []
        var lengths: [Int] = []
        var timecodes: [NSRange] = []
        var faint: [NSRange] = []
        var struck: [NSRange] = []
        var dim: [(range: NSRange, why: String)] = []
        starts.reserveCapacity(model.tokens.count)
        lengths.reserveCapacity(model.tokens.count)
        func extend(_ ranges: inout [NSRange], _ range: NSRange) {
            if let last = ranges.last, NSMaxRange(last) >= range.location - 1 {
                ranges[ranges.count - 1] = NSUnionRange(last, range)
            } else {
                ranges.append(range)
            }
        }
        for paragraph in model.paragraphs {
            let stamp = ReelTime.format(paragraph.start, fps: fps, frames: frames)
            timecodes.append(NSRange(location: plain.length, length: (stamp as NSString).length))
            plain.append(stamp)
            plain.append("\n")
            for index in paragraph.firstToken..<paragraph.endToken {
                let token = model.tokens[index]
                if index > paragraph.firstToken { plain.append(" ") }
                if token.collapsedBefore > 0 {
                    extend(&faint, NSRange(location: plain.length, length: 2))
                    plain.append("⋯ ")
                }
                let range = NSRange(location: plain.length, length: (token.word.text as NSString).length)
                plain.append(token.word.text)
                starts.append(range.location)
                lengths.append(range.length)
                if token.struck {
                    extend(&struck, range)
                } else if !token.word.editable {
                    extend(&faint, range)
                }
                if !token.word.editable, let why = token.word.why {
                    if let last = dim.last, last.why == why, index > paragraph.firstToken,
                        !model.tokens[index - 1].word.editable
                    {
                        dim[dim.count - 1].range = NSUnionRange(last.range, range)
                    } else {
                        dim.append((range, why))
                    }
                }
            }
            plain.append("\n")
        }
        let out = NSMutableAttributedString(string: plain as String, attributes: wordAttributes)
        let faintColor = resolved(DS.textFaint)
        for range in faint { out.addAttribute(.foregroundColor, value: faintColor, range: range) }
        for range in struck {
            out.addAttributes(
                [.foregroundColor: faintColor, .strikethroughStyle: NSUnderlineStyle.single.rawValue],
                range: range)
        }
        let timecode = timecodeAttributes
        for range in timecodes {
            out.setAttributes(timecode, range: NSRange(location: range.location, length: range.length + 1))
        }
        tokenStarts = starts
        tokenLengths = lengths
        timecodeRanges = timecodes
        dimRuns = dim
        return out
    }

    /// A system colour as concrete sRGB in the view's appearance: TextKit 2
    /// draws a dynamic colour (`labelColor`) into a `CGContext` as nothing
    /// (measured, TX-S2), so the text is styled with resolved colours and
    /// restyled when the appearance changes.
    func resolved(_ color: NSColor) -> NSColor {
        var out = color
        effectiveAppearance.performAsCurrentDrawingAppearance {
            out = color.usingColorSpace(.sRGB) ?? color
        }
        return out
    }

    var wordAttributes: [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        style.paragraphSpacing = 12
        return [.font: DS.sans(13), .foregroundColor: resolved(DS.textStrong), .paragraphStyle: style]
    }

    var timecodeAttributes: [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 2
        return [.font: DS.mono(10), .foregroundColor: resolved(DS.textMuted), .paragraphStyle: style]
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        guard let style = shownStyle else { return }
        show(model, fps: style.fps, timecodeFrames: style.frames)
    }

    // MARK: - Viewport layout

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged {
            fitContainer()
            layoutViewport()
        }
    }

    /// The width of the clip view it sits in, always: an autoresizing width
    /// adds the clip view's growth to whatever width it was made with.
    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        matchSuperviewWidth()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        matchSuperviewWidth()
    }

    private func matchSuperviewWidth() {
        guard let width = superview?.bounds.width, width > 0, frame.width != width else { return }
        setFrameSize(NSSize(width: width, height: frame.height))
    }

    private func fitContainer() {
        let width = max(bounds.width - 2 * Self.inset.width, 40)
        if container.size.width != width { container.size = CGSize(width: width, height: 0) }
    }

    override func layout() {
        super.layout()
        layoutViewport()
    }

    /// Lays out the fragments in sight; `didLayout` sizes the view.
    func layoutViewport() {
        layoutManager.textViewportLayoutController.layoutViewport()
    }

    func viewportBounds(for controller: NSTextViewportLayoutController) -> CGRect {
        var shown = visibleRect
        if shown.isEmpty { shown = NSRect(x: 0, y: 0, width: bounds.width, height: 800) }
        let overscan = shown.height / 2
        return shown.insetBy(dx: 0, dy: -overscan)
            .offsetBy(dx: -Self.inset.width, dy: -Self.inset.height)
    }

    func textViewportLayoutControllerWillLayout(_ controller: NSTextViewportLayoutController) {
        fragments = []
    }

    func textViewportLayoutController(
        _ controller: NSTextViewportLayoutController,
        configureRenderingSurfaceFor textLayoutFragment: NSTextLayoutFragment
    ) {
        fragments.append(textLayoutFragment)
    }

    func textViewportLayoutControllerDidLayout(_ controller: NSTextViewportLayoutController) {
        let used = layoutManager.usageBoundsForTextContainer.height
        let height = ceil(max(used + 2 * Self.inset.height, enclosingScrollView?.contentSize.height ?? 0))
        if abs(frame.height - height) > 0.5 { super.setFrameSize(NSSize(width: frame.width, height: height)) }
        refreshToolTips()
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        drawMarks(in: dirtyRect)
        // Walked from the fragment at the dirty top rather than read from
        // `fragments`: a layout elsewhere (a far highlight's rects) can move
        // the fragments in sight after the viewport's last pass.
        let top = CGPoint(x: 0, y: max(dirtyRect.minY - Self.inset.height, 0))
        guard let start = layoutManager.textLayoutFragment(for: top)?.rangeInElement.location
            ?? fragments.first?.rangeInElement.location
        else { return }
        layoutManager.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) {
            fragment in
            let frame = fragment.layoutFragmentFrame.offsetBy(
                dx: Self.inset.width, dy: Self.inset.height)
            guard frame.minY <= dirtyRect.maxY else { return false }
            if frame.intersects(dirtyRect) { fragment.draw(at: frame.origin, in: context) }
            return true
        }
    }

    // MARK: - Scrolling

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for token in observed { NotificationCenter.default.removeObserver(token) }
        observed = []
        guard let scroll = enclosingScrollView else { return }
        let center = NotificationCenter.default
        for name in [NSScrollView.willStartLiveScrollNotification, NSScrollView.didLiveScrollNotification] {
            observed.append(
                center.addObserver(forName: name, object: scroll, queue: .main) { [weak self] _ in
                    self?.personScrolled()
                })
        }
        scroll.contentView.postsBoundsChangedNotifications = true
        observed.append(
            center.addObserver(
                forName: NSView.boundsDidChangeNotification, object: scroll.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.layoutViewport()
            })
    }

    /// A person's own scroll: the follow pauses for `followPause` seconds.
    func personScrolled() {
        lastPersonScroll = now()
    }

    /// Scrolls the enclosing clip view so `y` is the visible top, clamped.
    func scroll(to y: CGFloat) {
        guard let scroll = enclosingScrollView else { return }
        let clip = scroll.contentView
        let bottom = max(0, frame.height - clip.bounds.height)
        clip.scroll(to: NSPoint(x: 0, y: min(max(0, y), bottom)))
        scroll.reflectScrolledClipView(clip)
        layoutViewport()
    }

    func setSelection(_ range: ClosedRange<Int>?) {
        let old = selection
        selection = range
        invalidate(old)
        invalidate(range)
    }
}
