import AppKit

/// What the Transcript tab asks of the editor (spec §11 TX-22): whether the
/// transport plays, and a seek that leaves playback as it was; since TX3a
/// (TX-31, TX-32) the document's in/out range, read and set through
/// `set_range`'s door, the cut as one "Delete Words" step (true when it
/// applied), and a refusal's beep and sentence.
protocol TranscriptHost: AnyObject {
    var transcriptIsPlaying: Bool { get }
    func transcriptSeek(to time: Ticks)
    var transcriptRange: TranscriptCut.Range? { get }
    func transcriptSetRange(_ range: TranscriptCut.Range?)
    @discardableResult func transcriptDelete(_ range: TranscriptCut.Range) -> Bool
    func transcriptRefuse(_ sentence: String)
}

/// The inspector's fifth tab (road map "creator-jobs" TX2a, spec §11 TX-20):
/// the timeline's words in paragraphs (`TranscriptView`), under the tab's bar
/// (`TranscriptBar`, TX2b, spec §11 TX-24) — Words from, Language, the status
/// with Stop or Read, the same-speech notes and the clips with no words. The
/// bar is built once in `init` and is the pane's one `makeHeader()` instance,
/// so the controller pins it above the scroll view, as it does the Clip tab's
/// header, and it never scrolls with the text.
///
/// `AssistantPane`'s shape: the view is built ONCE in `init`, never in
/// `makeSections()`, and the pane is exactly the visible height (`== 0` at
/// priority 1 under the controller's `>=`), so the transcript scrolls in its
/// own `NSScrollView`. It reaches the editor only through `TranscriptHost`
/// (`inspector.parent`) and the static table below, after
/// `TimelineView+TrackMix`'s "static table keyed by the view", because
/// `InspectorViewController.swift` and `EditorViewController.swift` are
/// frozen. Whether it shows follows its superview, window and hidden state;
/// shown, its source loads and wants (TX-22), hidden it releases.
final class TranscriptPane: InspectorPaneView {
    let transcriptView = TranscriptView(frame: NSRect(x: 0, y: 0, width: 280, height: 400))
    private(set) var source: TranscriptTabSource!
    private(set) var bar: TranscriptBar!
    private let scroll = NSScrollView()
    private weak var lastProject: ReelProject?
    private var shownRebuilds = -1
    /// The range the selection last set (TX-31); nil after a clear or a cut.
    private var rangeSet: TranscriptCut.Range?

    /// The pane each inspector made, weak to weak.
    private static let table = NSMapTable<InspectorViewController, TranscriptPane>.weakToWeakObjects()

    static func pane(in inspector: InspectorViewController) -> TranscriptPane? {
        table.object(forKey: inspector)
    }

    override var tab: InspectorTab { .transcript }
    override var emptyMessage: String? { nil }
    override var structureSignature: String { "transcript" }

    override init(inspector: InspectorViewController) {
        super.init(inspector: inspector)
        source = TranscriptTabSource(document: inspector.document) { [weak self] in
            self?.sourceChanged()
        }
        bar = TranscriptBar(source: source)
        Self.table.setObject(self, forKey: inspector)

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        transcriptView.autoresizingMask = [.width]
        scroll.documentView = transcriptView
        addSubview(scroll)
        let collapse = heightAnchor.constraint(equalToConstant: 0)
        collapse.priority = NSLayoutConstraint.Priority(1)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            collapse,
        ])
        transcriptView.onActivate = { [weak self] index in self?.seek(token: index) }
        transcriptView.onParagraph = { [weak self] index in self?.seek(paragraph: index) }
        transcriptView.onSelect = { [weak self] selection in self?.selectionChanged(selection) }
        transcriptView.onDelete = { [weak self] in self?.deleteWords() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TranscriptPane does not support NSCoder")
    }

    private var host: TranscriptHost? { inspector?.parent as? TranscriptHost }

    /// The bar, the same instance every build, pinned above the scroll view.
    override func makeHeader() -> (any OptionControl)? { bar }

    // MARK: - Shown or not

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        shownChanged()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        shownChanged()
    }

    override func viewDidHide() {
        super.viewDidHide()
        shownChanged()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        shownChanged()
    }

    /// Whether the tab is on screen in its window.
    var isShown: Bool { window != nil && superview != nil && !isHiddenOrHasHiddenAncestor }

    private func shownChanged() {
        let shown = isShown
        if shown { lastProject = inspector?.document?.editedProject }
        source.setShown(shown)
    }

    // MARK: - The inspector's calls

    /// A new edited project: the source rebuilds, unless a live gesture
    /// runs (then once after it).
    override func refresh() {
        super.refresh()
        guard isShown, let document = inspector?.document else { return }
        let project = document.editedProject
        guard project !== lastProject || source.isDirty else { return }
        if !document.isLiveEditing { lastProject = project }
        source.update()
    }

    /// The playhead moved: the highlight follows it, kept in sight while
    /// playing (TX-22). Nothing while the tab is not shown.
    func playheadMoved() {
        guard isShown, let document = inspector?.document else { return }
        transcriptView.setHighlight(
            source.model.highlight(at: document.playhead),
            follow: host?.transcriptIsPlaying ?? false)
    }

    /// A click on a clip while the tab shows (TX-20): its first word — for a
    /// nest clip, the first word inside it — scrolled to the top, no seek.
    func reveal(_ clips: [ClipSnapshot]) {
        guard let clip = clips.first else { return }
        guard
            let index = source.model.tokens.firstIndex(where: {
                $0.word.clip == clip.id || $0.word.id.nestPath.first == clip.id
            })
        else { return }
        transcriptView.scrollToToken(index)
    }

    // MARK: - The source's changes

    private func sourceChanged() {
        bar.refresh()
        guard source.rebuilds != shownRebuilds, let document = inspector?.document else { return }
        shownRebuilds = source.rebuilds
        let canvas = document.editedProject.snapshot.canvas
        transcriptView.show(source.model, fps: canvas.fps, timecodeFrames: canvas.timecodeFrames)
        transcriptView.setHighlight(source.model.highlight(at: document.playhead), follow: false)
        // The selection was re-mapped by identity: while the document's range
        // is still the one it set, the range follows it (TX-31).
        if rangeSet != nil, host?.transcriptRange == rangeSet {
            selectionChanged(transcriptView.selection)
        }
    }

    // MARK: - Selecting and deleting words (TX-31, TX-32)

    /// The plan of `selection` against the edited container.
    private func plan(_ selection: ClosedRange<Int>) -> TranscriptCut.Plan? {
        guard let document = inspector?.document else { return nil }
        let container = document.editedProject.snapshot
        return TranscriptCut.plan(
            selection, table: source.cutTable(), container: container,
            total: ShotSplit.clipCount(document.project.snapshot), fps: container.canvas.fps)
    }

    /// A person's selection: widened, adopted, and its snapped cut made the
    /// in/out range. A cleared selection clears the range only while it is
    /// still the one the selection set.
    func selectionChanged(_ selection: ClosedRange<Int>?) {
        guard let host else { return }
        guard let selection, let plan = plan(selection) else {
            if rangeSet != nil, host.transcriptRange == rangeSet { host.transcriptSetRange(nil) }
            rangeSet = nil
            return
        }
        transcriptView.adopt(plan.selection)
        let range = plan.range.end > plan.range.start ? plan.range : nil
        host.transcriptSetRange(range)
        rangeSet = range
    }

    /// ⌫, ⌦, Edit ▸ Delete or Edit ▸ Ripple Delete with words selected:
    /// planned again, refused in TX-32's order, else one "Delete Words".
    func deleteWords() {
        guard let host, let selection = transcriptView.selection, let plan = plan(selection) else {
            NSSound.beep()
            return
        }
        transcriptView.adopt(plan.selection)
        if let refusal = plan.refusal {
            host.transcriptRefuse(refusal.sentence)
            return
        }
        guard plan.range.end > plan.range.start else {
            NSSound.beep()
            return
        }
        // Cleared first, so the rebuild the cut causes does not re-plan.
        let held = rangeSet
        rangeSet = nil
        if !host.transcriptDelete(plan.range) { rangeSet = held }
    }

    // MARK: - Seeking

    private func seek(token index: Int) {
        guard source.model.tokens.indices.contains(index) else { return }
        host?.transcriptSeek(to: source.model.tokens[index].word.start)
    }

    private func seek(paragraph index: Int) {
        guard source.model.paragraphs.indices.contains(index) else { return }
        host?.transcriptSeek(to: source.model.paragraphs[index].start)
    }
}
