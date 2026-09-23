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
