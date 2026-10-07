// Road map 8, W4b — the declarations `word_captions_sheet_probe.swift`'s rows
// share: the fixture, the sheet builder, the popup chooser, the byte readers
// and `MemoryDefaults`. A pure move out of the probe (W4b residue, road map 8
// §10.10), made so S8 and S9 could land under its 400-line cap;
// `word_captions_chrome.py` copies this file beside the probe's `main.swift`
// and passes both to `swiftc`. S8's four readers (`sansWords`, `commit`,
// `page`, `measured`) were written here beside the moved lines, which is what
// keeps the probe under its cap. Declarations only: `check`, `rows` and the
// argument guard stay in the probe, and `speech` is a global `let`, so it is
// initialised lazily — on first use, after the probe's guard has run.
//
// `MemoryDefaults` is `tools/proof/harness/main.swift`'s, the SAME text: every
// keyed call answered from memory, the argument domain empty, every domain
// write a trap (a crash, so a scored FAILURE) — the sheet reaches
// `string(forKey:)`, `set(_:forKey:)` and, on a keyed cloud start,
// `volatileDomain(forName: UserDefaults.argumentDomain)`.
import AppKit

let speech = CommandLine.arguments[2]
let vertical = CGSize(width: 1080, height: 1920)
let horizontal = CGSize(width: 1920, height: 1080)
let language = Transcriber.Language(
    identifier: "en-US", displayName: "English (United States)", installed: true)

/// What sits on the timeline beside the one media clip.
enum Extra { case none, emptyCaptions, textCaptions, mediaCaptions }

/// One audio media over the fixture, one clip on it, and `extra`.
func document(_ canvas: CGSize, _ extra: Extra = .none) -> ProjectDocument? {
    let document = ProjectDocument()
    guard let lane = document.project.snapshot.tracks.first?.id else { return nil }
    document.performGroupedEdit(
        "Setup",
        [
            .setCanvas(width: Int(canvas.width), height: Int(canvas.height)),
            .addMedia(
                descriptor: MediaDescriptor(
                    path: speech, kind: .audio, duration: 3_600_000, hasAudio: true)),
        ])
    guard let media = document.project.snapshot.media.first?.id else { return nil }
    document.performGroupedEdit("Clip", [.addClip(track: lane, media: media, at: 0)])
    guard extra != .none else { return document }
    let track = document.project.snapshot.nextId
    let count = document.project.snapshot.tracks.count
    var ops: [ReelOp] = [.addTrack(index: count, name: "Captions")]
    switch extra {
    case .textCaptions:
        ops.append(
            .addTextClip(
                track: track, at: 0, duration: 600_000, text: TextPatch(content: "Old words")))
    case .mediaCaptions: ops.append(.addClip(track: track, media: media, at: 0))
    case .none, .emptyCaptions: break
    }
    document.performGroupedEdit("Captions", ops)
    return document
}

/// The harness's `MemoryDefaults`, restated: the probe links no harness.
final class MemoryDefaults: UserDefaults {
    private var values: [String: Any] = [:]

    // Keyed reads, off `values`.
    override func object(forKey defaultName: String) -> Any? { values[defaultName] }
    override func string(forKey defaultName: String) -> String? { values[defaultName] as? String }
    override func array(forKey defaultName: String) -> [Any]? { values[defaultName] as? [Any] }
    override func dictionary(forKey defaultName: String) -> [String: Any]? {
        values[defaultName] as? [String: Any]
    }
    override func data(forKey defaultName: String) -> Data? { values[defaultName] as? Data }
    override func stringArray(forKey defaultName: String) -> [String]? {
        values[defaultName] as? [String]
    }
    override func url(forKey defaultName: String) -> URL? { values[defaultName] as? URL }
    override func integer(forKey defaultName: String) -> Int {
        (values[defaultName] as? NSNumber)?.intValue ?? 0
    }
    override func float(forKey defaultName: String) -> Float {
        (values[defaultName] as? NSNumber)?.floatValue ?? 0
    }
    override func double(forKey defaultName: String) -> Double {
        (values[defaultName] as? NSNumber)?.doubleValue ?? 0
    }
    override func bool(forKey defaultName: String) -> Bool {
        (values[defaultName] as? NSNumber)?.boolValue ?? false
    }

    // Keyed writes, into `values`; a nil removes.
    override func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
    override func set(_ value: Int, forKey defaultName: String) { values[defaultName] = value }
    override func set(_ value: Float, forKey defaultName: String) { values[defaultName] = value }
    override func set(_ value: Double, forKey defaultName: String) { values[defaultName] = value }
    override func set(_ value: Bool, forKey defaultName: String) { values[defaultName] = value }
    override func set(_ url: URL?, forKey defaultName: String) { values[defaultName] = url }
    override func removeObject(forKey defaultName: String) { values[defaultName] = nil }

    // Domain reads. The volatile domains are EMPTY: an in-memory argument
    // domain holds no `-RCAssemblyAIEndpoint`, which is what the sheet's keyed
    // cloud start reads through `AssemblyAIConfiguration`.
    override func dictionaryRepresentation() -> [String: Any] { values }
    override func volatileDomain(forName domainName: String) -> [String: Any] { [:] }
    override func objectIsForced(forKey key: String) -> Bool { false }
    override func objectIsForced(forKey key: String, inDomain domain: String) -> Bool { false }

    // Everything else would reach the real defaults domain: a trap, which is
    // a crash and so a scored FAILURE, never a silent write to disk.
    override func register(defaults registrationDictionary: [String: Any]) { trap() }
    override func addSuite(named suiteName: String) { trap() }
    override func removeSuite(named suiteName: String) { trap() }
    override func persistentDomain(forName domainName: String) -> [String: Any]? { trap() }
    override func setPersistentDomain(_ domain: [String: Any], forName domainName: String) {
        trap()
    }
    override func removePersistentDomain(forName domainName: String) { trap() }
    override func setVolatileDomain(_ domain: [String: Any], forName domainName: String) {
        trap()
    }
    override func removeVolatileDomain(forName domainName: String) { trap() }
    override func synchronize() -> Bool { trap() }
    private func trap(_ function: String = #function) -> Never {
        fatalError("MemoryDefaults: \(function) would reach the real defaults domain")
    }
}
func freshDefaults() -> UserDefaults { MemoryDefaults() }
/// `finish` ends a clean run in `dismiss(self)`, which raises for a controller
/// nobody presented; S5's host presents the sheet with an animator that does
/// nothing, so there is something to dismiss.
final class StillAnimator: NSObject, NSViewControllerPresentationAnimator {
    func animatePresentation(of viewController: NSViewController, from: NSViewController) {}
    func animateDismissal(of viewController: NSViewController, from: NSViewController) {}
}
func sheet(_ document: ProjectDocument, defaults: UserDefaults = freshDefaults())
    -> TranscribeSheetController
{
    let sheet = TranscribeSheetController(
        document: document, store: MemoryStore(), defaults: defaults, environment: [:],
        languages: [language])
    _ = sheet.view
    return sheet
}
/// The popup chosen the way AppKit chooses it: the row, then its action.
func choose(_ style: CaptionStyle, on sheet: TranscribeSheetController) {
    if let index = sheet.stylePopup.itemArray.firstIndex(where: {
        $0.representedObject as? String == style.rawValue
    }) {
        sheet.stylePopup.selectItem(at: index)
    }
    sheet.perform(#selector(TranscribeSheetController.styleChanged(_:)), with: nil)
}
func png(_ image: NSImage?) -> Data? {
    guard let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
}
func bytes(_ context: CGContext?) -> Data? {
    guard let context, let data = context.data else { return nil }
    var out = Data(bytes: data, count: context.bytesPerRow * context.height)
    out.append(contentsOf: Array("\(context.width)x\(context.height)".utf8))
    return out
}

// MARK: - S3's reader

func replaceState(_ extra: Extra, _ style: CaptionStyle) -> (enabled: Bool, on: Bool, label: String)? {
    guard let doc = document(vertical, extra) else { return nil }
    let s = sheet(doc)
    choose(style, on: s)
    s.replaceCheckbox.state = .on
    s.controlChanged(nil)
    return (s.replaceCheckbox.isEnabled, s.replaceCheckbox.state == .on,
            s.replaceLabel.isHidden ? "<hidden>" : s.replaceLabel.stringValue)
}
func describe(_ state: (enabled: Bool, on: Bool, label: String)?) -> String {
    state.map { "enabled \($0.enabled), on \($0.on), label \($0.label)" } ?? "no document"
}

// MARK: - S6's transcript and sheet

func transcriptFile(_ words: [(String, Int, Int)]) -> MediaTranscript.File? {
    let json = "[" + words.map {
        "{\"text\":\"\($0.0)\",\"start\":\($0.1),\"end\":\($0.2),\"confidence\":0.9,\"speaker\":null}"
    }.joined(separator: ",") + "]"
    let header = MediaTranscript.Header(
        provider: MediaTranscript.provider, transcriptID: "t_sheet",
        requested: TranscriptOptions(
            speechModels: TranscriptOptions.shippedModels, languageCode: nil,
            speakerLabels: false, keytermsPrompt: []),
        speechModelUsed: "universal-3-5-pro", languageCode: "en_us", languageConfidence: nil,
        audioDuration: 6, extractedSeconds: 6, uploadedFormat: "flac", audioTrackStartMs: 0,
        fetchedAt: "2026-09-23T00:00:00Z", remoteDeleted: true)
    return try? MediaTranscript.File(header: header, wordsJSON: Data(json.utf8))
}
/// A fresh sheet over a fresh document, with `file` written into the
/// document's cache BEFORE the sheet is built; Highlight chosen.
func previewSheet(_ file: MediaTranscript.File?) -> TranscribeSheetController? {
    guard let doc = document(vertical) else { return nil }
    if let file, let cache = doc.cacheDirectory, let media = doc.project.snapshot.media.first {
        _ = MediaTranscript.write(file, for: media.id, in: cache)
    }
    let s = sheet(doc)
    choose(.highlight, on: s)
    return s
}

// MARK: - S8's readers

/// `p` with no `words` — the one field the pager's props leave empty.
func sansWords(_ p: TextProps) -> TextProps {
    TextProps(
        content: p.content, font: p.font, size: p.size, color: p.color, align: p.align,
        valign: p.valign, lineSpacing: p.lineSpacing, tracking: p.tracking, outline: p.outline,
        backdrop: p.backdrop, width: p.width, animation: p.animation, textCase: p.textCase,
        words: [], wordStyle: p.wordStyle)
}
/// `cue` committed through `place` onto `doc`: the one new text clip's `text`.
func commit(_ cue: CaptionLayout.Cue, _ doc: ProjectDocument, _ style: CaptionStyle) -> TextProps? {
    let before = Set(doc.project.snapshot.clips.map(\.id))
    guard let plan = try? CaptionLayout.place([cue], in: doc.project, style: style) else {
        return nil
    }
    doc.performGroupedEdit("S8", plan.ops)
    let made = doc.project.snapshot.clips.filter { !before.contains($0.id) && $0.text != nil }
    return made.count == 1 ? made[0].text : nil
}
/// One word paged as Highlight on 1080×1920 over the sheet's first job.
func page(_ word: String, _ s: TranscribeSheetController) -> CaptionLayout.Cue? {
    CaptionPages.cues(
        from: [CaptionCues.Word(text: word, start: 0, end: 108_000)], span: 0 ..< 1_200_000,
        frame: max(s.snapshot.canvas.fps.frameDuration, 1),
        request: CaptionPages.Request(style: .highlight, canvas: vertical), engine: .apple,
        clip: s.jobs(in: s.scope).first?.clip
    ).first
}
/// A page's measured width, the pager's own measurement.
func measured(_ p: TextProps) -> Double { Double(LayerRenderers.measuredSize(for: p).width) }

// MARK: - S10–S16's helpers (issue batch B86 phase 2, spec §11 W-15)

typealias Look = CaptionLooks.Look
/// The three remembered keys, as LITERALS: the probe's own spelling of them.
let lookKeys: [(Look, String)] = [
    (.slide, "ReelcutCaptionSlide"), (.fill, "ReelcutCaptionFill"), (.dim, "ReelcutCaptionDim"),
]
/// A box clicked the way AppKit clicks it: its state, then its action with
/// the box as the sender.
func tick(_ look: Look, on sheet: TranscribeSheetController, _ on: Bool = true) {
    let box = sheet.checkbox(for: look)
    box.state = on ? .on : .off
    sheet.perform(#selector(TranscribeSheetController.lookChanged(_:)), with: box)
}
/// A sheet over defaults that remember AssemblyAI: the cloud state.
func cloudSheet(_ document: ProjectDocument) -> TranscribeSheetController {
    let defaults = freshDefaults()
    defaults.set("assemblyai", forKey: "ReelcutCaptionEngine")
    return sheet(document, defaults: defaults)
}
/// The style's preset REBUILT here, field by field, with only `look`'s field
/// changed — the oracle S15 holds `CaptionStyle.wordStyle(_:)` and the commit
/// to. It reads the no-argument `wordStyle`, which phase 2 does not edit.
func rebuilt(_ style: CaptionStyle, _ look: Look) -> WordStyle? {
    guard let p = style.wordStyle else { return nil }
    let pill = p.activePill.map {
        ActivePill(
            color: $0.color, padding: $0.padding, radius: $0.radius,
            glide: look == .slide ? true : $0.glide)
    }
    return WordStyle(
        mode: p.mode, activeColor: p.activeColor, activeScale: p.activeScale, activePill: pill,
        spokenColor: p.spokenColor, upcomingColor: p.upcomingColor,
        activeFill: look == .fill ? true : p.activeFill,
        pauseDim: look == .dim ? 0.5 : p.pauseDim)
}
var keptAlive: [AnyObject] = []
/// S15's commit, S5's method: a fresh document and sheet, `style` chosen,
/// `look` ticked (or none), the fixed sample paged and handed to
/// `finish(.success(…))`. Answers every placed clip's `text`.
func commitLooks(_ style: CaptionStyle, _ look: Look?) -> [TextProps]? {
    guard let doc = document(vertical) else { return nil }
    let s = sheet(doc)
    let host = NSViewController()
    host.view = NSView()
    let animator = StillAnimator()
    keptAlive.append(contentsOf: [host, animator])
    host.present(s, animator: animator)
    choose(style, on: s)
    if let look { tick(look, on: s) }
    guard let job = s.jobs(in: s.scope).first else { return nil }
    let before = doc.editedProject.snapshot
    let cues = CaptionPages.cues(
        from: TranscribeSheetController.fixedSampleWords, span: job.span,
        frame: max(before.canvas.fps.frameDuration, 1), request: s.pagesRequest, engine: .apple,
        clip: job.clip)
    s.finish(.success(Transcriber.Outcome(cues: cues, problems: [], clips: [job.clip])))
    let old = Set(before.clips.map(\.id))
    return doc.editedProject.snapshot.clips.filter { !old.contains($0.id) }.compactMap(\.text)
}
/// Whether every committed page measures what its looks-free page measures.
func measuresAlike(_ pages: [TextProps], _ style: CaptionStyle) -> Bool {
    pages.allSatisfy {
        LayerRenderers.measuredSize(for: $0)
            == LayerRenderers.measuredSize(
                for: style.textProps(content: $0.content, size: $0.size, width: $0.width))
    }
}
/// S11's reading BEFORE any layout, on a sheet just built and not yet hosted:
/// what the note's `preferredMaxLayoutWidth` is for. A wrapping label with
/// none answers its ONE-LINE size until a layout pass has handed it a width,
/// (335.5 × 15.0 pt, where the line gives 257.5 × 30.0; 2026-10-06); the hosted rows
/// cannot see it, since by then the 258 pt column has bounded the label. So:
/// the note's `intrinsicContentSize` is above 0 and at most 258 pt wide, and
/// at least as tall as its cell needs at 258 pt — which must itself be taller
/// than the cell on one line (the control: the sentence does wrap there).
func noteBeforeLayout(_ s: TranscribeSheetController) -> (problems: [String], reading: String) {
    let note = s.dimNoteLabel
    let size = note.intrinsicContentSize
    func cellHeight(_ width: CGFloat) -> CGFloat {
        note.cell?.cellSize(
            forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)
        ).height ?? .infinity
    }
    let wrapped = cellHeight(258)
    let oneLine = cellHeight(100_000)
    var problems: [String] = []
    if !(wrapped > oneLine + 0.5) {
        problems.append("CONTROL: the note's cell is \(wrapped) tall at 258 and \(oneLine) on one line")
    }
    if !(size.width > 0 && size.width <= 258.5) {
        problems.append("the note's intrinsic width before layout is \(size.width)")
    }
    if !(size.height + 0.5 >= wrapped) {
        problems.append("the note's intrinsic height before layout is \(size.height), needs \(wrapped)")
    }
    return (
        problems,
        "intrinsic \(size.width) × \(size.height); its cell at 258 pt is \(wrapped) tall, on one "
            + "line \(oneLine)"
    )
}
/// The card as the harness hosts it: a window's content, at its fitting size.
func host(_ s: TranscribeSheetController) -> NSWindow {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 420, height: 400), styleMask: [.titled],
        backing: .buffered, defer: true)
    window.isReleasedWhenClosed = false
    window.contentViewController = s
    keptAlive.append(window)
    relayout(s, in: window)
    return window
}
func relayout(_ s: TranscribeSheetController, in window: NSWindow) {
    s.view.layoutSubtreeIfNeeded()
    window.setContentSize(s.view.fittingSize)
    s.view.layoutSubtreeIfNeeded()
}
/// A view's ALIGNMENT rect in `root`'s coordinates — what Auto Layout places
/// and what `snapshot_ui`'s layout rules measure (#140): a label's frame is a
/// few points wider than it (measured here: 261.5 pt of frame for 258).
func aligned(_ view: NSView, in root: NSView) -> CGRect {
    let rect = view.alignmentRect(forFrame: view.frame)
    return view.superview.map { $0.convert(rect, to: root) } ?? rect
}
/// S11's reading of the laid-out looks row, in alignment rects: every box at
/// least its intrinsic width and inside the 258 pt controls column (the
/// preview's own rect), and a VISIBLE note at most 258 pt wide and at least
/// as tall as its text needs at its frame's width. Empty when all of it holds.
func looksLayoutProblems(_ s: TranscribeSheetController) -> [String] {
    let column = aligned(s.previewView, in: s.view)
    var problems: [String] = []
    for look in Look.allCases {
        let box = s.checkbox(for: look)
        let frame = aligned(box, in: s.view)
        let need = box.intrinsicContentSize.width
        if frame.width + 0.5 < need {
            problems.append("\(look.rawValue) is \(frame.width) wide, needs \(need)")
        }
        if frame.minX < column.minX - 0.5 || frame.maxX > column.maxX + 0.5 {
            problems.append(
                "\(look.rawValue) \(frame.minX)…\(frame.maxX) leaves the column "
                    + "\(column.minX)…\(column.maxX)")
        }
    }
    let note = s.dimNoteLabel
    guard !note.isHidden else { return problems }
    let frame = note.frame
    let need = note.cell?.cellSize(
        forBounds: NSRect(x: 0, y: 0, width: frame.width, height: .greatestFiniteMagnitude)
    ).height ?? .infinity
    let width = aligned(note, in: s.view).width
    if width > 258.5 { problems.append("the note's alignment rect is \(width) wide") }
    if frame.height + 0.5 < need {
        problems.append("the note is \(frame.height) tall, needs \(need) at \(frame.width)")
    }
    return problems
}
