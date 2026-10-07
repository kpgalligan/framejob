import AppKit

/// The inspector's shared vocabulary (spec §4.3): which tabs exist, the
/// disclosure section every pane is built from, the row and
/// control builders, and — the piece that carries the most rules —
/// `InspectorBinding`, which is the ONE place that knows how a pane reads a
/// property and how an edit made in a pane reaches the document.
///
/// Two rules live here and nowhere else, because getting either wrong is
/// invisible until a project is saved:
///
///  - **Reads are evaluated.** With the playhead inside an action, a field
///    must show the value the frame actually has, which is
///    `rc_project_clip_state` (§7.1), not the clip's base props.
///  - **Writes follow the read.** Inside an action, an edit sets THAT
///    action's end patch (`set_action_end`); outside one it merges into the
///    base props (`set_video` and friends) with every selected clip in a
///    single op, which is what §4.3 means by "edit their common properties
///    together".
///
/// Controls come from `OptionControls.swift` — they hold no value of their
/// own, so "model → inspector" is one walk calling `refresh()`
/// (`refreshOptionControls(in:)`). The one control added here is the slider:
/// the options bar never needed one, and forking the Rasterize-copied files
/// to add it would break the "keep them in sync" rule in app/CLAUDE.md.

// MARK: - Metrics

/// The inspector's fixed dimensions. Separate from `DS` because they describe
/// this panel's grid, not the app's chrome.
enum InspectorMetrics {
    static let labelWidth: CGFloat = 76
    static let rowSpacing: CGFloat = 7
    static let sectionSpacing: CGFloat = 2
    static let inset: CGFloat = 10
    /// 28, not 26: the header now carries a state summary beside the title,
    /// and the design sizes the row around it.
    static let headerHeight: CGFloat = 28
    static let fieldWidth: CGFloat = 58
    static let wideFieldWidth: CGFloat = 72
    static let popupWidth: CGFloat = 116
    /// The row-mark column in front of every row's label (spec §11 CI-7).
    static let markGutter: CGFloat = 14
}

// MARK: - Refreshing

/// Re-reads every descriptor-driven control under `view`. The controls store
/// no value (OptionControls.swift), so this single walk IS the model →
/// inspector direction; nothing else pushes values into a field.
func refreshOptionControls(in view: NSView) {
    for subview in view.subviews {
        if let control = subview as? any OptionControl { control.refresh() }
        refreshOptionControls(in: subview)
    }
}

// MARK: - Small labels

/// A row's leading label. A plain `NSTextField` so it participates in the
/// stack's baseline alignment, styled once here so no pane re-invents it.
final class InspectorRowLabel: NSTextField {
    init(_ text: String) {
        super.init(frame: .zero)
        stringValue = text
        isEditable = false
        isBordered = false
        isBezeled = false
        drawsBackground = false
        font = DS.sans(11)
        textColor = DS.textMuted
        lineBreakMode = .byTruncatingTail
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("InspectorRowLabel does not support NSCoder")
    }
}

/// The "the selected clips disagree about this value" marker. Shown beside a
/// field rather than blanking it: the field still edits (writing the value to
/// every clip), which is what §4.3's "edit their common properties together"
/// asks for.
final class InspectorMixedBadge: NSTextField, OptionControl {
    private let mixed: () -> Bool

    init(mixed: @escaping () -> Bool) {
        self.mixed = mixed
        super.init(frame: .zero)
        stringValue = "mixed"
        isEditable = false
        isBordered = false
        isBezeled = false
        drawsBackground = false
        font = DS.mono(9)
        textColor = DS.textFaint
        toolTip = "The selected clips have different values"
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("InspectorMixedBadge does not support NSCoder")
    }

    func refresh() {
        isHidden = !mixed()
    }
}

/// An editable TIMECODE — the Clip tab's In and Out. `OptionFieldControl` is
/// a number with a unit and would spell 4.5 seconds "4.50 s"; a clip's edges
/// are read against the ruler, so they are spelled the way the ruler and the
/// toolbar spell them.
///
/// Parsing is the core's (`ReelTime.parse`), so `1:23`, `83.5` and `1:23:04`
/// mean here what they mean in the toolbar's field — and, exactly as there,
/// text it refuses beeps and the field snaps back rather than committing a
/// guess. A trim the CORE refuses beeps too, from `applyEdit`; nothing here
/// clamps a value into range on the user's behalf.
final class InspectorTimecodeField: NSTextField, OptionControl, NSTextFieldDelegate {
    private let read: () -> Ticks
    private let write: (Ticks) -> Void
    private let fps: () -> Fps
    private let frames: () -> Bool
    private let onEdit: () -> Void

    init(
        read: @escaping () -> Ticks, write: @escaping (Ticks) -> Void,
        fps: @escaping () -> Fps, frames: @escaping () -> Bool,
        onEdit: @escaping () -> Void
    ) {
        self.read = read
        self.write = write
        self.fps = fps
        self.frames = frames
        self.onEdit = onEdit
        super.init(frame: .zero)
        DSField.style(self, height: DS.controlHeight, radius: DS.controlRadius, font: DS.mono(11))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 104).isActive = true
        delegate = self
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("InspectorTimecodeField does not support NSCoder")
    }

    private var formatted: String {
        ReelTime.format(read(), fps: fps(), frames: frames())
    }

    func refresh() {
        // Skipped while the field is being typed into, or the value it is
        // about to commit would be overwritten by the one it replaces.
        guard currentEditor() == nil else { return }
        let value = formatted
        if stringValue != value { stringValue = value }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard stringValue != formatted else { return }
        guard let ticks = ReelTime.parse(stringValue, fps: fps()) else {
            NSSound.beep()
            // Set directly rather than through `refresh()`: the field editor
            // may still be attached here, and `refresh()` would defer to it.
            stringValue = formatted
            return
        }
        write(ReelTime.snapToFrame(ticks, fps: fps()))
        onEdit()
    }
}

/// A section's one-line note — "Editing action 2's end state" (§4.3). Hides
/// itself when the closure returns nil, so a section pays nothing for a note
/// it does not currently have.
final class InspectorNoteLabel: NSTextField, OptionControl {
    private let note: () -> String?

    init(note: @escaping () -> String?) {
        self.note = note
        super.init(frame: .zero)
        isEditable = false
        isBordered = false
        isBezeled = false
        drawsBackground = false
        font = DS.sans(11)
        textColor = DS.accent
        lineBreakMode = .byTruncatingTail
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("InspectorNoteLabel does not support NSCoder")
    }

    func refresh() {
        let text = note()
        stringValue = text ?? ""
        isHidden = text == nil
    }
}

// MARK: - Multi-line text

/// The Text tab's content editor: an `NSTextView` that commits on blur (and
/// on ⌘Return), because a text clip's content is typed, not dialled. The
/// `refresh()` is skipped while it holds first responder, or every keystroke
/// would be overwritten by the value it just wrote.
final class InspectorTextArea: NSView, OptionControl, NSTextViewDelegate {
    private let read: () -> String
    private let write: (String) -> Void
    private let enabled: () -> Bool
    private let onEdit: () -> Void
    private let textView = NSTextView()
    private let scroll = NSScrollView()

    init(
        read: @escaping () -> String, write: @escaping (String) -> Void,
        enabled: @escaping () -> Bool, onEdit: @escaping () -> Void
    ) {
        self.read = read
        self.write = write
        self.enabled = enabled
        self.onEdit = onEdit
        super.init(frame: .zero)
        wantsLayer = true
        setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        textView.isRichText = false
        textView.font = DS.sans(12)
        textView.textColor = DS.textStrong
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.delegate = self
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = DS.controlRadius
        scroll.layer?.borderWidth = 1
        scroll.layer?.borderColor = DS.border.cgColor
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 72),
        ])
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("InspectorTextArea does not support NSCoder")
    }

    func refresh() {
        let active = enabled()
        alphaValue = active ? 1 : 0.42
        textView.isEditable = active
        textView.isSelectable = active
        guard window?.firstResponder !== textView else { return }
        let value = read()
        if textView.string != value { textView.string = value }
    }

    private func commit() {
        let value = textView.string
        guard value != read() else { return }
        write(value)
        onEdit()
    }

    func textDidEndEditing(_ notification: Notification) {
        commit()
    }

    /// ⌘Return commits without leaving the field — the same bargain the
    /// canvas's inline text session makes (PreviewCanvasView).
    func textView(
        _ view: NSTextView, doCommandBy commandSelector: Selector
    ) -> Bool {
        guard commandSelector == #selector(NSResponder.insertNewline(_:)),
              NSApp.currentEvent?.modifierFlags.contains(.command) == true
        else { return false }
        commit()
        return true
    }
}

// MARK: - Binding

/// Reading and writing the selection's properties (spec §4.3). Created once
/// by `InspectorViewController` and handed to every pane; `invalidate()` at
/// the start of each refresh drops the evaluated-state cache so a moved
/// playhead is never read stale.
final class InspectorBinding {
    weak var inspector: InspectorViewController?

    /// Evaluated props per clip, filled lazily. Only a clip with a selected
    /// action (`.end`, `.start`) or with the playhead inside it (`.playhead`)
    /// ever reaches the FFI; everything else reads its base props straight
    /// off the snapshot, and `.defaults` reads neither.
    private struct Evaluated {
        var video: VideoProps?
        var audio: AudioProps?
        var text: TextProps?
        var graphic: [String: GraphicPropValue]?
    }
    private struct CacheKey: Hashable {
        let clip: UInt32
        let mode: ReadMode
    }
    private var cache: [CacheKey: Evaluated] = [:]

    /// WHEN a read is answered for (road map 9 §5): `.end` is the selected
    /// action's end state (spec §11 CI-2) and what every field shows;
    /// `.start` is the selected action's start, the keyed slider segment's
    /// far end; `.playhead` is the document's playhead whenever it is inside
    /// the clip, whatever is selected — the coral tick and the "now" tag;
    /// `.defaults` is what a row resets to (spec §11 CI-9): the four props
    /// readers answer `VideoProps.identity`, `AudioProps()`, `TextProps()`
    /// and `ShapeProps()`, with no FFI call and no cache entry.
    enum ReadMode: Hashable { case end, start, playhead, defaults }
    private(set) var mode: ReadMode = .end

    /// Runs `read` in `mode` and restores the mode it found.
    func at<T>(_ mode: ReadMode, _ read: () -> T) -> T {
        let saved = self.mode
        self.mode = mode
        defer { self.mode = saved }
        return read()
    }

    init(inspector: InspectorViewController) {
        self.inspector = inspector
    }

    // MARK: Model access

    var document: ProjectDocument? { inspector?.document }

    /// **The project the CLIP tab reads and writes** — the scoped one while a
    /// nest is open (road map 2's phase 9), so a selected clip inside a nest
    /// resolves, its evaluated state is asked of a project that has it, and
    /// the canvas the transform rows measure against is the nest's frozen
    /// size. At the top level it is `document.project` exactly as before.
    ///
    /// The Document and Media tabs deliberately do NOT read it: they are
    /// about the FILE, whatever container the timeline happens to be showing,
    /// so they take `documentProject` / `documentSnapshot` below. That split
    /// is the whole of the scope's footprint in the inspector.
    var project: ReelProject? { document?.editedProject }

    /// The DOCUMENT, unscoped: what the Document tab's canvas rows, its
    /// marker list and its export-capability probe read, and what the Media
    /// tab asks "is this file used anywhere" of. `remove_media` and
    /// `set_canvas` are document-level ops (`ReelOp.isDocumentLevel`), so a
    /// pane that wrote them off a scoped snapshot would be answering about
    /// one project and editing another.
    var documentProject: ReelProject? { document?.project }
    var documentSnapshot: ProjectSnapshot { documentProject?.snapshot ?? .empty }
    var documentCanvas: CanvasSnapshot { documentSnapshot.canvas }
    var snapshot: ProjectSnapshot { project?.snapshot ?? .empty }
    var canvas: CanvasSnapshot { snapshot.canvas }
    var playhead: Ticks { document?.playhead ?? 0 }
    var clips: [ClipSnapshot] { inspector?.selectedClips ?? [] }
    var ids: [UInt32] { clips.map { $0.id } }
    var primary: ClipSnapshot? { clips.first }
    var isEmpty: Bool { clips.isEmpty }
    var isSingle: Bool { clips.count == 1 }

    /// The selected clips each property group actually applies to. A mixed
    /// selection is normal — a video clip and a text clip picked together —
    /// and sending `set_text` to the video one would be an error at the FFI,
    /// so every read, mixed test and op below works from these lists rather
    /// than from the raw selection.
    var videoClips: [ClipSnapshot] { clips.filter { InspectorTab.hasPixels($0, in: snapshot) } }
    var audioClips: [ClipSnapshot] { clips.filter { InspectorTab.hasAudio($0, in: snapshot) } }
    var textClips: [ClipSnapshot] {
        clips.filter { clip in
            if case .text = clip.source { return true }
            return false
        }
    }
    var shapeClips: [ClipSnapshot] {
        clips.filter { clip in
            if case .shape = clip.source { return true }
            return false
        }
    }

    func invalidate() {
        cache.removeAll(keepingCapacity: true)
    }

    // MARK: Actions

    /// The SELECTED action when it is `clip`'s (spec §11 CI-2). The playhead
    /// is not consulted: the editing target is the selection, so a field
    /// neither moves with the playhead nor writes to a span it happens to sit
    /// in.
    func action(_ clip: ClipSnapshot) -> ActionSnapshot? {
        guard let id = document?.selectedAction else { return nil }
        return clip.actions.first { $0.id == id }
    }

    /// The document's selected action, when it is on the single selected clip.
    var selectedAction: ActionSnapshot? { document?.selectedActionSnapshot }

    /// The lane's and the Clip chip's intent; nil leaves the mode.
    func selectAction(_ id: UInt32?) { inspector?.onSelectAction?(id) }

    // MARK: Evaluated reads

    private func evaluated(_ clip: ClipSnapshot) -> Evaluated {
        let key = CacheKey(clip: clip.id, mode: mode)
        if let cached = cache[key] { return cached }
        var state = Evaluated()
        // At the END tick: the core has merged every action ending there and
        // none starting there has progressed, so this is the end state.
        let time: Ticks?
        switch mode {
        case .end: time = action(clip).map { clip.start + $0.endTime }
        case .start: time = action(clip).map { clip.start + $0.start }
        case .playhead: time = clip.start <= playhead && playhead < clip.end ? playhead : nil
        case .defaults: time = nil
        }
        if let time, let raw = project?.clipState(clip.id, at: time) {
            state.video = InspectorBinding.decode(VideoProps.self, raw["video"])
            state.audio = InspectorBinding.decode(AudioProps.self, raw["audio"])
            state.text = InspectorBinding.decode(TextProps.self, raw["text"])
            state.graphic = InspectorBinding.decode(GraphicSnapshot.self, raw["graphic"])?.props
        }
        cache[key] = state
        return state
    }

    /// One property group of `rc_project_clip_state`'s untyped reply, decoded
    /// through the same lenient path as the project itself.
    static func decode<T: Decodable>(_ type: T.Type, _ value: Any?) -> T? {
        guard let object = value, JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return ReelJSON.decode(type, from: text)
    }

    func video(_ clip: ClipSnapshot) -> VideoProps {
        mode == .defaults ? .identity : evaluated(clip).video ?? clip.videoProps
    }
    func audio(_ clip: ClipSnapshot) -> AudioProps {
        mode == .defaults ? AudioProps() : evaluated(clip).audio ?? clip.audioProps
    }
    func text(_ clip: ClipSnapshot) -> TextProps {
        mode == .defaults ? TextProps() : evaluated(clip).text ?? clip.text ?? TextProps()
    }
    /// A graphic clip's props, evaluated (spec §11 G-34 (h), (l)); `.defaults`
    /// answers none, so every row reads its schema default.
    func graphicProps(_ clip: ClipSnapshot) -> [String: GraphicPropValue] {
        mode == .defaults ? [:] : evaluated(clip).graphic ?? clip.graphic?.props ?? [:]
    }
    /// Shapes are not animatable (§5.4's patch covers video, audio and text),
    /// so this is always the base description.
    func shape(_ clip: ClipSnapshot) -> ShapeProps {
        mode == .defaults ? ShapeProps() : clip.shape ?? ShapeProps()
    }

    /// The list a WRITE of a list-valued video key must be built from — and
    /// the length `structural` below must measure a new one against.
    ///
    /// `video(_:)` answers what the playhead SHOWS, which is what every `read:`
    /// closure in the inspector wants and what every row displays. It is the
    /// wrong list to build an EDIT out of. Inside an action a write lands on
    /// the action's END patch, and `actions.rs`'s `merge` replaces an array
    /// whole rather than entry by entry, so an array built from the
    /// interpolated values pins every entry the user did not touch at whatever
    /// it happened to read at the playhead: with a base of
    /// `[blur 0.2, sepia 0.3]` and an end of `[blur 1.0, sepia 0.3]`, dialling
    /// the sepia at the midpoint re-sends the blur at 0.6 and its ramp is
    /// silently flattened.
    ///
    /// So a write reads the list it is about to REPLACE — the action's own end
    /// `filters` or `obscure` when the end patch carries one, and the clip's
    /// base list when it does not. The same answer is what a new length has to
    /// be compared against, for the same reason read the other way: that array
    /// is the one an end patch must match to interpolate at all, and comparing
    /// against the base alone made the section rewrite the clip's base stack
    /// whenever an earlier action had already changed the count.
    ///
    /// Note what this is NOT: it is not the list at the action's START, which
    /// is the truly exact answer and needs a second `clip_state` call at a
    /// time nothing else in the inspector asks about. The pair above agrees
    /// with it in every case the inspector can produce, because the section
    /// can only ever write the length it can see.
    func editedList<T>(
        _ clip: ClipSnapshot, action end: (VideoPatch) -> [T]?, base: (VideoProps) -> [T]
    ) -> [T] {
        if let inside = action(clip), let list = inside.end.video.flatMap(end) { return list }
        return base(clip.videoProps)
    }

    /// The same list for the selection: the FIRST video clip's, which is the
    /// clip every row in a section already reads.
    func editedList<T>(action end: (VideoPatch) -> [T]?, base: (VideoProps) -> [T]) -> [T] {
        guard let clip = videoClips.first else { return [] }
        return editedList(clip, action: end, base: base)
    }

    /// The values the fields show: the FIRST applicable clip's, evaluated.
    var videoProps: VideoProps { videoClips.first.map { video($0) } ?? .identity }
    var audioProps: AudioProps { audioClips.first.map { audio($0) } ?? AudioProps() }
    var textProps: TextProps { textClips.first.map { text($0) } ?? TextProps() }
    var shapeProps: ShapeProps { shapeClips.first.map { shape($0) } ?? ShapeProps() }

    // MARK: Mixed tests

    /// Whether a list of clips disagrees about one value.
    func mixed<T: Equatable>(_ clips: [ClipSnapshot], _ read: (ClipSnapshot) -> T) -> Bool {
        guard let first = clips.first.map(read) else { return false }
        return clips.dropFirst().contains { read($0) != first }
    }

    /// Whether the whole selection disagrees — for clip-level values (speed).
    func mixed<T: Equatable>(_ read: (ClipSnapshot) -> T) -> Bool {
        mixed(clips, read)
    }

    func mixedVideo<T: Equatable>(_ read: @escaping (VideoProps) -> T) -> Bool {
        mixed(videoClips) { read(video($0)) }
    }

    func mixedAudio<T: Equatable>(_ read: @escaping (AudioProps) -> T) -> Bool {
        mixed(audioClips) { read(audio($0)) }
    }

    func mixedText<T: Equatable>(_ read: @escaping (TextProps) -> T) -> Bool {
        mixed(textClips) { read(text($0)) }
    }

    func mixedShape<T: Equatable>(_ read: @escaping (ShapeProps) -> T) -> Bool {
        mixed(shapeClips) { read(shape($0)) }
    }
}

// MARK: - Pane

/// What the inspector hosts in its scroll view. A pane is rebuilt only when
/// the SHAPE of the model changes (`structureSignature`) and refreshed on
/// every other document change — rebuilding on each edit would tear down the
/// control under the user's cursor.
protocol InspectorPane: NSView {
    var tab: InspectorTab { get }
    var structureSignature: String { get }
    func rebuild()
    func refresh()
    var pinnedBlock: NSView? { get }
}

/// The base every pane subclasses: a vertical stack of `InspectorSection`s
/// plus the empty-state label. Subclasses override `makeSections()` and, when
/// their row set depends on the model (the actions table, the media list, the
/// markers list), `structureSignature`.
class InspectorPaneView: NSView, InspectorPane {
    let binding: InspectorBinding
    weak var inspector: InspectorViewController?
    private let stack = NSStackView()
    private(set) var sections: [InspectorSection] = []
    /// The current build's header, when the pane makes one.
    private var headerControl: (any OptionControl)?
    /// The header, hosted ABOVE the scroll view by the controller.
    var pinnedBlock: NSView? { headerControl }
    /// The previous build's views, held one generation past their removal —
    /// see the pitfall in `rebuild()`.
    private var retired: [NSView] = []

    init(inspector: InspectorViewController) {
        self.inspector = inspector
        self.binding = inspector.binding
        super.init(frame: .zero)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = InspectorMetrics.sectionSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        // The pane is a scroll-view document view: the clip view fixes its
        // width, and nothing fixes its height — so the content has to. The
        // bottom pin is a `<=` at full strength plus an `==` at low priority,
        // which resolves to "as tall as the sections, but never shorter than
        // the visible area" once `InspectorViewController` adds its own
        // minimum (a pane that stopped at its content would leave the Media
        // tab's Finder-drop target the size of its rows).
        //
        // That `==` sits ONE BELOW `.defaultLow`, and the one is load-bearing.
        // An `InspectorSection` sets no hugging priority, so it keeps the
        // default 250 — and at 250 the pin TIED with it: the solver could pay
        // the same price to satisfy "the stack reaches the bottom" by giving
        // the pane its content's height (right) or by STRETCHING one section
        // past its rows (wrong), and nothing in the constraint set chose. It
        // picked per PROCESS, so a render was reproducible within a run and
        // bistable across runs — `phase3_chrome.py` scored 29, 30, 31 or 33
        // out of 33 on identical input, and the offscreen harness wrote two
        // distinct PNGs for one package (measured: 9 renders one way, 3 the
        // other, in twelve). At 249 the stretch is strictly the dearer answer,
        // so the sections stay at their intrinsic heights and the pane's
        // bottom moves instead — which is what the paragraph above always
        // meant. Do not "tidy" it back to `.defaultLow`.
        let hug = stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        hug.priority = NSLayoutConstraint.Priority(rawValue: 249)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            hug,
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("InspectorPaneView does not support NSCoder")
    }

    /// A pane reads top-down and now runs to twenty sections, so its
    /// coordinates should read top-down too: (0, 0) is the selection header,
    /// and `scroll(to: .zero)` is the top of the list.
    ///
    /// **Pitfall:** an unflipped document view is bottom-origin, and a scroll
    /// view shows the bottom of one that is taller than its clip view. What
    /// keeps this panel off that path is a single constraint —
    /// `InspectorViewController.showPane` pins the pane's `topAnchor` to the
    /// clip view's — and a redesign that ever drops or reshapes that pin would
    /// open the Clip tab below the header and the whole Transform group, with
    /// nothing on screen to say anything was above. Flipped, the pin is a
    /// layout detail rather than the only thing standing between the user and
    /// an upside-down panel. Auto Layout itself is unaffected (measured: the
    /// same document height and the same at-rest visible rows either way).
    override var isFlipped: Bool { true }

    // MARK: Subclass hooks

    var tab: InspectorTab { .clip }

    /// The sections, in order. Called on every rebuild.
    func makeSections() -> [InspectorSection] { [] }

    /// A view ABOVE the sections, rebuilt with them and refreshed with them —
    /// the Clip tab's selection header. It is an `OptionControl` for the one
    /// reason every other control here is: `refresh()` is how the model
    /// reaches it, and nothing pushes values into a view in this panel.
    func makeHeader() -> (any OptionControl)? { nil }

    /// What the pane says when it has nothing to show; nil means "never
    /// empty" (Media and Document).
    var emptyMessage: String? { "Select a clip to edit its properties." }

    /// The model facts that change the pane's LAYOUT rather than its values.
    /// The default covers the selection and the action under the playhead;
    /// panes with tables extend it.
    var structureSignature: String {
        let clips = binding.clips.map { clip -> String in
            let action = binding.action(clip).map { String($0.id) } ?? "-"
            return "\(clip.id):\(clip.source.kindName):\(action)"
        }
        return clips.joined(separator: ",")
    }

    // MARK: Building

    func rebuild() {
        sections = []
        headerControl = nil
        // **Pitfall:** a rebuild often runs INSIDE a control's own event
        // handler — a button's `action()` applies the edit, the document
        // posts, and the pane rebuilds before that handler returns. Keeping
        // one generation of removed views alive means the control that
        // started it all is still there when its method returns.
        // `removeFromSuperview` also un-arranges it; `removeArrangedSubview`
        // alone would leave the view drawn on top of the new ones.
        retired = stack.arrangedSubviews
        for view in retired { view.removeFromSuperview() }
        if binding.isEmpty, let message = emptyMessage {
            let placeholder = InspectorPaneView.emptyRow(message)
            stack.addArrangedSubview(placeholder)
            placeholder.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            return
        }
        // Pinned above the scroll view, and only with something selected: with
        // nothing selected the empty row above has already said so, and a
        // header reading "No selection" beside it would say it twice.
        headerControl = makeHeader()
        for section in makeSections() {
            sections.append(section)
            stack.addArrangedSubview(section)
            section.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    /// The centred "nothing selected" line, built fresh each time so its
    /// constraints go away with the build that made it.
    private static func emptyRow(_ message: String) -> NSView {
        let box = NSView()
        let label = InspectorRowLabel(message)
        label.alignment = .center
        label.textColor = DS.textFaint
        label.lineBreakMode = .byWordWrapping
        label.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: box.topAnchor, constant: 28),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -28),
            label.leadingAnchor.constraint(
                equalTo: box.leadingAnchor, constant: InspectorMetrics.inset),
            label.trailingAnchor.constraint(
                equalTo: box.trailingAnchor, constant: -InspectorMetrics.inset),
        ])
        return box
    }

    func refresh() {
        headerControl?.refresh()
        for section in sections { section.refresh() }
    }
}
