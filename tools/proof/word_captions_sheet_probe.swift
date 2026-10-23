// Road map 8, W4b — the Generate Captions sheet's Style row, read
// structurally (`word_captions_chrome.py` builds and runs it).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `FrameJob`, against `libframejob_core.a` —
// `tools/proof/harness/build.sh`'s swiftc line — so every row drives the
// app's own `TranscribeSheetController`. A sheet cannot be put up
// offscreen, so what is measured is the view tree the card builds and what
// its controls add up to; the harness photographs the same card as a
// window's content. Every sheet's defaults are a `MemoryDefaults`, so no
// suite plist is ever written (road map 8 §10.10 says why not a named suite).
// The fixture, the builders and `MemoryDefaults` are
// `word_captions_sheet_support.swift`'s, compiled beside this file.
//
//   word_captions_sheet_probe <app_fonts_dir> <speech.aiff>
//
// One JSON object out: `rows` (name, ok, detail).
import AppKit
import CoreText

_ = NSApplication.shared
var rows: [[String: Any]] = []
func check(_ name: String, _ ok: Bool, _ detail: String) {
    rows.append(["name": name, "ok": ok, "detail": String(detail.prefix(1500))])
}
guard CommandLine.arguments.count >= 3 else {
    print(#"{"ok":false,"error":"usage: word_captions_sheet_probe <fonts> <speech.aiff>"}"#)
    exit(1)
}
var registered = 0
let fonts = URL(fileURLWithPath: CommandLine.arguments[1])
for name in ((try? FileManager.default.contentsOfDirectory(atPath: fonts.path)) ?? []).sorted()
where name.hasSuffix(".ttf") || name.hasSuffix(".otf") {
    if CTFontManagerRegisterFontsForURL(
        fonts.appendingPathComponent(name) as CFURL, .process, nil)
    {
        registered += 1
    }
}

// MARK: - S1 the popup's rows

if let doc = document(vertical) {
    let s = sheet(doc)
    let rowsSeen = s.stylePopup.itemArray.map { $0.representedObject as? String ?? "<nil>" }
    let titles = s.stylePopup.itemArray.map(\.title)
    check("S1 the Style popup lists the six styles in CaptionStyle.allCases order and opens on "
          + "Subtitles with empty defaults",
          rowsSeen == CaptionStyle.allCases.map(\.rawValue)
            && titles == CaptionStyle.allCases.map(\.displayName) && s.style == .subtitles,
          "rows \(rowsSeen), titles \(titles), opens on \(s.style.rawValue)")
} else {
    check("S1 the document builds", false, "")
}

// MARK: - S2 the preview

if let doc = document(vertical), let wide = document(horizontal) {
    let s = sheet(doc)
    var previews: [String: Data] = [:]
    for style in CaptionStyle.allCases {
        choose(style, on: s)
        previews[style.rawValue] = png(s.previewView.image)
    }
    let distinct = Set(previews.values).count
    check("S2 six previews on 1080×1920 are six distinct PNG byte strings",
          previews.count == 6 && distinct == 6,
          "\(previews.mapValues(\.count)) — \(distinct) distinct")
    let w = sheet(wide)
    choose(.highlight, on: w)
    let wideHighlight = png(w.previewView.image)
    check("S2 Highlight's preview differs between 1080×1920 and 1920×1080",
          wideHighlight != nil && wideHighlight != previews["highlight"],
          "\(wideHighlight?.count ?? 0) vs \(previews["highlight"]?.count ?? 0) bytes")
    let frame = max(doc.project.snapshot.canvas.fps.frameDuration, 1)
    let tall = CaptionPages.samplePage(
        TranscribeSheetController.fixedSampleWords,
        request: CaptionPages.Request(style: .highlight, canvas: vertical), frame: frame)
    let flat = CaptionPages.samplePage(
        TranscribeSheetController.fixedSampleWords,
        request: CaptionPages.Request(style: .highlight, canvas: horizontal), frame: frame)
    // §5h's measured note: at 1080 wide the WIDTH closes Highlight's sample
    // at four tokens; the balance step (§5c) then moves the fourth across
    // ("…HOW | IT LOOKS"), so the real first page holds three.
    let budget = CaptionPages.Rules.standard.widthBudget * Double(vertical.width)
    func width(_ text: String) -> Double {
        Double(LayerRenderers.measuredSize(
            for: CaptionStyle.highlight.textProps(
                content: text, size: CaptionStyle.highlight.size(for: vertical), width: nil)
        ).width)
    }
    let four = width("This is how it")
    let five = width(TranscribeSheetController.sampleText)
    check("S2 the sample page on 1080×1920 Highlight: the width closes at 4 tokens (§5h) and the "
          + "balance step leaves 3; on 1920×1080 all 5",
          four <= budget && five > budget && tall?.words?.count == 3 && flat?.words?.count == 5,
          "4 tokens \(Int(four)) px, 5 tokens \(Int(five)) px against \(Int(budget)); "
            + "\"\(tall?.text ?? "-")\" / \"\(flat?.text ?? "-")\"")
    choose(.karaoke, on: s)
    let karaoke = CaptionPages.samplePage(
        TranscribeSheetController.fixedSampleWords, request: s.pagesRequest, frame: frame
    ).map { s.previewProps(for: $0, canvas: vertical) }
    var (karaokeOK, karaokeDetail) = (false, "no page")
    if let p = karaoke {
        let upper = TextProps(
            content: p.content, font: p.font, size: p.size, color: p.color, align: p.align,
            valign: p.valign, lineSpacing: p.lineSpacing, tracking: p.tracking,
            outline: p.outline, backdrop: p.backdrop, width: p.width, animation: p.animation,
            textCase: .upper, words: p.words, wordStyle: p.wordStyle)
        let reveal = RecipeReveal(word: 2, wordPop: 1)
        let asWritten = bytes(LayerRenderers.textBitmap(p, reveal: reveal))
        let capitals = bytes(LayerRenderers.textBitmap(upper, reveal: reveal))
        karaokeOK = p.textCase == .asWritten && asWritten != nil && capitals != nil
            && asWritten != capitals
        karaokeDetail = "\"\(p.content)\" case \(p.textCase.rawValue); bitmaps differ "
            + "\(asWritten != capitals)"
    }
    check("S2 Karaoke previews as written (its textBitmap differs from the same props in "
          + "capitals)", karaokeOK, karaokeDetail)
    choose(.highlight, on: s)
    let highlightCase = CaptionPages.samplePage(
        TranscribeSheetController.fixedSampleWords, request: s.pagesRequest, frame: frame
    ).map { s.previewProps(for: $0, canvas: vertical).textCase }
    check("S2 Highlight's preview props are upper case", highlightCase == .upper,
          "\(highlightCase?.rawValue ?? "nil")")
} else {
    check("S2 the documents build", false, "")
}

// MARK: - S3 the Replace checkbox

let noTrack = replaceState(.none, .highlight)
check("S3 no caption track: Replace is disabled and off",
      noTrack.map { !$0.enabled && !$0.on && $0.label == "<hidden>" } ?? false, describe(noTrack))
let emptyTrack = replaceState(.emptyCaptions, .highlight)
check("S3 an empty \"Captions\" track: Replace is disabled",
      emptyTrack.map { !$0.enabled && !$0.on } ?? false, describe(emptyTrack))
let textTrack = replaceState(.textCaptions, .highlight)
check("S3 a \"Captions\" track with a text clip over the job: enabled, and the label names it "
      + "with its count",
      textTrack.map { $0.enabled && $0.on && $0.label == "Replaces “Captions” (1 caption)." }
        ?? false, describe(textTrack))
let subtitles = replaceState(.textCaptions, .subtitles)
check("S3 the same track with Subtitles: disabled",
      subtitles.map { !$0.enabled && !$0.on } ?? false, describe(subtitles))
let mediaTrack = replaceState(.mediaCaptions, .highlight)
check("S3 a \"Captions\" track holding a media clip: disabled",
      mediaTrack.map { !$0.enabled && !$0.on } ?? false, describe(mediaTrack))

// MARK: - S4 the remembered style

let suite = freshDefaults()
if let doc = document(vertical) {
    let first = sheet(doc, defaults: suite)
    choose(.pill, on: first)
    let written = suite.string(forKey: CaptionStyle.defaultsKey)
    let second = sheet(doc, defaults: suite)
    suite.set("bold", forKey: CaptionStyle.defaultsKey)
    let third = sheet(doc, defaults: suite)
    check("S4 choosing Pill writes \"pill\" to the defaults; a second sheet over them opens on "
          + "Pill; \"bold\" opens on Subtitles",
          written == "pill" && second.style == .pill && third.style == .subtitles,
          "wrote \(written ?? "nil"), reopened on \(second.style.rawValue), "
            + "\"bold\" on \(third.style.rawValue)")
} else {
    check("S4 the document builds", false, "")
}

// MARK: - S5 the commit

if let doc = document(vertical, .textCaptions) {
    let s = sheet(doc)
    let host = NSViewController()
    host.view = NSView()
    let animator = StillAnimator()
    host.present(s, animator: animator)
    let before = doc.editedProject.snapshot
    let old = before.tracks.first { $0.name == "Captions" }?.id
    choose(.pill, on: s)
    s.replaceCheckbox.state = .on
    s.controlChanged(nil)
    let job = s.jobs(in: s.scope).first
    let request = s.pagesRequest
    let cues = job.map {
        CaptionPages.cues(
            from: TranscribeSheetController.fixedSampleWords, span: $0.span,
            frame: max(before.canvas.fps.frameDuration, 1), request: request, engine: .apple,
            clip: $0.clip)
    } ?? []
    s.finish(.success(Transcriber.Outcome(cues: cues, problems: [], clips: job.map { [$0.clip] } ?? [])))
    let after = doc.editedProject.snapshot
    let captionTracks = after.tracks.filter {
        $0.name.range(of: #"^Captions( \d+)?$"#, options: .regularExpression) != nil
    }
    let placed = after.clips.filter { clip in captionTracks.contains { $0.id == clip.track } }
    let styled = !placed.isEmpty && placed.allSatisfy {
        $0.text?.font == "Montserrat-ExtraBold" && $0.text?.textCase == .upper
            && $0.text?.wordStyle?.activePill != nil
    }
    let canUndo = doc.undoManager?.canUndo ?? false
    doc.undoManager?.undo()
    let restored = doc.editedProject.snapshot
    let back = old.map { id in restored.tracks.contains { $0.id == id } } ?? false
        && restored.clips.filter { $0.track == old }.count == 1
    check("S5 Pill with Replace commits one caption track of Montserrat-ExtraBold, upper, "
          + "active_pill pages, the old track gone; one undo restores it",
          request == CaptionPages.Request(style: .pill, canvas: vertical)
            && captionTracks.count == 1 && styled && old != nil
            && !captionTracks.contains { $0.id == old } && canUndo && back,
          "\(cues.count) cues, tracks \(captionTracks.map(\.name)), \(placed.count) clips, "
            + "styled \(styled), old \(old.map(String.init) ?? "nil"), undo \(canUndo), back \(back)")
} else {
    check("S5 the document builds", false, "")
}

// MARK: - S6 the preview's words

let fixedWords = TranscribeSheetController.fixedSampleWords
if let bare = previewSheet(nil), let clip = bare.jobs(in: bare.scope).first?.clip {
    let bareWords = bare.sampleWords()
    let barePreview = png(bare.preview())
    check("S6 no transcript file: the fixed sample, and the miss is cached",
          bareWords == fixedWords && bare.sampleWordsCache[clip] != nil,
          "\(bareWords.map(\.text)), cached \(bare.sampleWordsCache[clip] != nil)")
    let spoken = transcriptFile([("Welcome", 100, 500), ("back", 600, 900), ("everyone", 1000, 1600)])
    if let file = spoken, let s = previewSheet(file), let job = s.jobs(in: s.scope).first {
        let words = s.sampleWords()
        let preview = png(s.preview())
        check("S6 a transcript written before the sheet: its words, and a different preview",
              words == MediaTranscript.words(for: job, in: file) && !words.isEmpty
                && preview != nil && preview != barePreview,
              "\(words.map(\.text)); preview differs \(preview != barePreview)")
    } else {
        check("S6 a transcript written before the sheet: its words, and a different preview",
              false, "the file or the sheet did not build")
    }
    let elsewhere = transcriptFile([("Later", 100_000, 100_400)])
    if let file = elsewhere, let s = previewSheet(file), let job = s.jobs(in: s.scope).first {
        let words = s.sampleWords()
        let preview = png(s.preview())
        check("S6 a transcript with no words in the clip: the fixed sample, and the no-file "
              + "preview byte for byte",
              MediaTranscript.words(for: job, in: file).isEmpty && words == fixedWords
                && preview != nil && preview == barePreview,
              "\(words.map(\.text)); equal \(preview == barePreview)")
    } else {
        check("S6 a transcript with no words in the clip: the fixed sample, and the no-file "
              + "preview byte for byte", false, "the file or the sheet did not build")
    }
    // Cut by transcript CT-1 (spec §11 TR-1, TR-8): a transcript holding
    // fillers previews what the same words make without them.
    let disfluent = transcriptFile([
        ("Welcome", 100, 500), ("um,", 520, 580), ("back", 600, 900), ("Uh", 920, 980),
        ("everyone", 1000, 1600),
    ])
    let fluent = transcriptFile([("Welcome", 100, 500), ("back", 600, 900), ("everyone", 1000, 1600)])
    if let withFillers = disfluent, let without = fluent, let a = previewSheet(withFillers),
        let b = previewSheet(without), let job = a.jobs(in: a.scope).first
    {
        let wordsA = a.sampleWords()
        let wordsB = b.sampleWords()
        let previewA = png(a.preview())
        let previewB = png(b.preview())
        check("S6 a transcript holding fillers: the same sampleWords() and the same preview, byte "
              + "for byte, as the same transcript without them",
              MediaTranscript.words(for: job, in: withFillers).count == 5 && wordsA == wordsB
                && !wordsA.isEmpty && previewA != nil && previewA == previewB,
              "\(wordsA.map(\.text)) vs \(wordsB.map(\.text)); equal \(previewA == previewB)")
    } else {
        check("S6 a transcript holding fillers: the same sampleWords() and the same preview, byte "
              + "for byte, as the same transcript without them", false,
              "the files or the sheets did not build")
    }
} else {
    check("S6 the document builds", false, "")
}

// MARK: - S7 a disabled checkbox replaces nothing

if let doc = document(vertical, .textCaptions), let bare = document(vertical) {
    let s = sheet(doc)
    choose(.highlight, on: s)
    s.replaceCheckbox.state = .on
    s.controlChanged(nil)
    let live = s.replaceExisting
    choose(.subtitles, on: s)
    let afterSubtitles = s.replaceExisting
    s.replaceCheckbox.state = .on
    let forcedOn = s.replaceExisting
    let n = sheet(bare)
    choose(.highlight, on: n)
    n.replaceCheckbox.state = .on
    let noTrack = n.replaceExisting
    check("S7 replaceExisting is false whenever the checkbox is disabled, whatever its state",
          live && !afterSubtitles && !forcedOn && !noTrack,
          "live \(live), after Subtitles \(afterSubtitles), forced on while disabled "
            + "\(forcedOn), no track \(noTrack)")
} else {
    check("S7 the documents build", false, "")
}

// MARK: - S8 a shrunk page is one page: measured, previewed, committed

let highlight = CaptionStyle.highlight
let base = highlight.size(for: vertical)
let budget = CaptionPages.Rules.standard.widthBudget * Double(vertical.width)
let ladder = ["Extraordinary", "Characteristic", "Straightforward", "Responsibilities",
              "Characteristically", "Uncharacteristically", "Incomprehensibilities",
              "Counterrevolutionaries"]
if let doc = document(vertical), let wrapDoc = document(vertical),
    let subDoc = document(vertical)
{
    let s = sheet(doc)
    choose(.highlight, on: s)
    let tried = ladder.map { ($0, page($0, s)) }
    if let (word, found) = tried.first(where: { $0.1?.size != nil && $0.1?.width == nil }),
        let cue = found, let size = cue.size
    {
        let measuredProps = highlight.textProps(content: cue.text, size: size, width: nil)
        let preview = s.previewProps(for: cue, canvas: vertical)
        let committed = commit(cue, doc, .highlight)
        let drawn = committed.flatMap {
            LayerRenderers.textBitmap($0, reveal: RecipeReveal(word: 1, wordPop: 1))?.width
        }
        let atBase = measured(highlight.textProps(content: cue.text, size: base, width: nil))
        let width = committed.map(measured) ?? .infinity
        let yesterday = committed.map { c in measured(TextProps(
            content: c.content, font: c.font, size: c.size, color: c.color, align: c.align,
            valign: c.valign, outline: OutlineProps(width: 0.08 * base, color: [0, 0, 0, 1]),
            width: c.width, textCase: c.textCase, wordStyle: c.wordStyle)) }
        check("S8 a shrunk page: the committed props are the measured props and the preview's, "
              + "its outline em × its own size, and it measures and draws inside the budget",
              preview == measuredProps && committed.map(sansWords) == measuredProps
                && committed?.words.count == 1 && committed?.outline?.width == 0.08 * size
                && width <= budget && atBase > budget && (drawn ?? .max) <= Int(budget),
              "\"\(word)\" at \(size) (base \(base)): committed \(Int(width)) px, at base "
                + "\(Int(atBase)) px, bitmap \(String(describing: drawn)) px, budget "
                + "\(Int(budget)); outline \(String(describing: committed?.outline?.width)); "
                + "preview equal \(preview == measuredProps); yesterday's commit "
                + "\(yesterday.map { Int($0) } ?? -1) px")
    } else {
        check("S8 a shrunk page: no candidate shrank without wrapping", false,
              tried.map { "\($0.0): \(String(describing: ($0.1?.size, $0.1?.width)))" }
                .joined(separator: "; "))
    }
    let w = sheet(wrapDoc)
    choose(.highlight, on: w)
    let cue = page("Donaudampfschifffahrtsgesellschaftskap", w)
    let wrapped = cue.map {
        highlight.textProps(content: $0.text, size: $0.size ?? -1, width: $0.width)
    }
    let wrapPreview = cue.map { w.previewProps(for: $0, canvas: vertical) }
    let wrapCommitted = cue.flatMap { commit($0, wrapDoc, .highlight) }
    check("S8 a wrapped page at the floor: committed, previewed and measured alike, at the "
          + "budget's width, its outline em × the floor size",
          cue?.size == 0.8 * base && cue?.width == budget && wrapped != nil
            && wrapPreview == wrapped && wrapCommitted.map(sansWords) == wrapped
            && wrapCommitted?.width == budget
            && wrapCommitted?.outline?.width == 0.08 * (cue?.size ?? -1),
          "size \(String(describing: cue?.size)) of \(base), width "
            + "\(String(describing: cue?.width)) of \(budget); committed width "
            + "\(String(describing: wrapCommitted?.width)), outline "
            + "\(String(describing: wrapCommitted?.outline?.width)); preview equal "
            + "\(wrapPreview == wrapped)")
    let t = sheet(subDoc)
    choose(.subtitles, on: t)
    let line = CaptionCues.build(
        from: TranscribeSheetController.fixedSampleWords,
        frame: max(t.snapshot.canvas.fps.frameDuration, 1), clip: t.jobs(in: t.scope).first?.clip
    ).first
    let subPreview = line.map { t.previewProps(for: $0, canvas: vertical) }
    let subCommitted = line.flatMap { commit($0, subDoc, .subtitles) }
    check("S8 Subtitles: the preview's props are the committed props, whole",
          subPreview != nil && subPreview == subCommitted,
          "preview \(String(describing: subPreview))\ncommitted \(String(describing: subCommitted))")
} else {
    check("S8 the documents build", false, "")
}

// MARK: - S9 the preview is redrawn on a key change only

// `preview()` mints a NEW `NSImage` every call, so identity is the draw count.
if let doc = document(vertical) {
    let s = sheet(doc)
    choose(.highlight, on: s)
    let job = s.jobs(in: s.scope).first
    let first = s.previewView.image
    for _ in 0 ..< 5 { s.refresh() }
    s.vocabularyField.stringValue = "Frame Job"
    s.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    let kept = first != nil && s.previewView.image === first
    choose(.pill, on: s)
    let pill = s.previewView.image
    choose(.highlight, on: s)
    let again = s.previewView.image
    let key = TranscribeSheetController.PreviewKey(
        style: .highlight, clip: job?.clip, canvas: vertical)
    check("S9 the preview is drawn 0 times across five refreshes and a Vocabulary keystroke, "
          + "and again on each style change",
          kept && pill != nil && pill !== first && again != nil && again !== first
            && again !== pill && job != nil && s.previewKey == key,
          "kept \(kept), Pill new \(pill !== first), Highlight again new \(again !== pill), "
            + "key \(String(describing: s.previewKey))")
} else {
    check("S9 the document builds", false, "")
}

// MARK: - S10 the three look boxes (issue batch B86 phase 2, spec §11 W-15)

// The table and the lists are WRITTEN here, not derived: the app derives them.
let liveTable: [Look: Set<CaptionStyle>] = [
    .slide: [.pill],
    .fill: [.highlight, .karaoke, .build],
    .dim: [.highlight, .pill, .karaoke, .build, .oneWord],
]
let styleLists: [Look: String] = [
    .slide: "pill",
    .fill: "highlight, karaoke or build",
    .dim: "highlight, pill, karaoke, build or one_word",
]
let lookTitles = ["Slide the pill", "Fill words as spoken", "Dim in pauses"]
if let doc = document(vertical) {
    let s = sheet(doc)
    let titles = Look.allCases.map { s.checkbox(for: $0).title }
    let ids = Look.allCases.map { s.checkbox(for: $0).accessibilityIdentifier() }
    let allOff = Look.allCases.allSatisfy { s.checkbox(for: $0).state == .off } && s.looks == .none
    var wrong: [String] = []
    for style in CaptionStyle.allCases {
        choose(style, on: s)
        for look in Look.allCases
        where s.checkbox(for: look).isEnabled != (liveTable[look]?.contains(style) ?? false) {
            wrong.append("\(look.rawValue) on \(style.rawValue): \(s.checkbox(for: look).isEnabled)")
        }
    }
    let lists = Look.allCases.map(\.styleList)
    check("S10 the three boxes carry the three titles in order, all off over empty defaults; "
          + "each is enabled exactly on its table's styles; each styleList is its literal",
          titles == lookTitles && allOff && wrong.isEmpty
            && ids == ["captions.look.slide", "captions.look.fill", "captions.look.dim"]
            && lists == Look.allCases.map { styleLists[$0] ?? "?" },
          "titles \(titles), ids \(ids), all off \(allOff), wrong \(wrong), lists \(lists)")
} else {
    check("S10 the document builds", false, "")
}

// MARK: - S11 the looks row laid out, S12 the note

let noteLiteral = "On-device words rarely carry a pause; this shows mostly with AssemblyAI."
if let doc = document(vertical) {
    var problems: [String] = []
    var noteWrong: [String] = []
    var heights: [String: CGFloat] = [:]
    var early: [String] = []
    var earlyReadings: [String] = []
    for (engine, s) in [("apple", sheet(doc)), ("assemblyai", cloudSheet(doc))] {
        // Before `host(_:)` and before any layout pass: the sheet is only built.
        let before = noteBeforeLayout(s)
        early += before.problems.map { "\(engine): \($0)" }
        earlyReadings.append("\(engine): \(before.reading)")
        let window = host(s)
        for style in CaptionStyle.allCases {
            choose(style, on: s)
            relayout(s, in: window)
            problems += looksLayoutProblems(s).map { "\(engine) \(style.rawValue): \($0)" }
            let visible = !s.dimNoteLabel.isHidden
            if visible != (engine == "apple" && style != .subtitles) {
                noteWrong.append("\(engine) \(style.rawValue): visible \(visible)")
            }
            heights["\(engine) \(style.rawValue)"] = s.view.fittingSize.height
        }
        if s.dimNoteLabel.stringValue != noteLiteral
            || s.dimNoteLabel.accessibilityIdentifier() != "captions.look.dimnote"
        {
            noteWrong.append("\(engine): \"\(s.dimNoteLabel.stringValue)\"")
        }
    }
    let shown = heights["apple highlight"] ?? -1
    let hidden = heights["apple subtitles"] ?? -1
    check("S11 laid out in a window, 6 styles × 2 engines: each box at least its intrinsic "
          + "width and inside the 258 pt column; a visible note at most 258 pt wide and at "
          + "least its fitting height",
          problems.isEmpty && shown > 0 && hidden > 0,
          "problems \(problems.prefix(6)); RECORDED, not scored — the card's fitting height on "
            + "this Mac: \(shown) pt with the note (Highlight) and \(hidden) pt without "
            + "(Subtitles), a difference of \(shown - hidden) pt")
    check("S11 before any layout, on a sheet just built (each engine): the note's intrinsic "
          + "size is above 0 and at most 258 pt wide and at least its cell's height at 258 pt, "
          + "which is taller than one line",
          early.isEmpty, "problems \(early); \(earlyReadings.joined(separator: "; "))")
    check("S12 the note is visible exactly when the engine is On this Mac and the style is a "
          + "word style, and it is the owner's sentence", noteWrong.isEmpty,
          "wrong \(noteWrong)")
} else {
    check("S11 the document builds", false, "")
    check("S11 before any layout: the document builds", false, "")
    check("S12 the document builds", false, "")
}

// MARK: - S13 the remembered boxes, S14 a greyed box keeps its tick

if let doc = document(vertical) {
    let memory = freshDefaults()
    let first = sheet(doc, defaults: memory)
    let untouched = lookKeys.allSatisfy { memory.object(forKey: $0.1) == nil }
    choose(.pill, on: first)
    tick(.slide, on: first)
    tick(.dim, on: first)
    choose(.karaoke, on: first)
    tick(.fill, on: first)
    let wrote = lookKeys.map { memory.object(forKey: $0.1) as? Bool }
    let second = sheet(doc, defaults: memory)
    let reopened = Look.allCases.map { second.checkbox(for: $0).state == .on }
    let older = freshDefaults()
    older.set("pill", forKey: "FrameJobCaptionStyle")
    let third = sheet(doc, defaults: older)
    let thirdOff = Look.allCases.allSatisfy { third.checkbox(for: $0).state == .off }
    check("S13 ticking each box where it is live writes true under its key; a second sheet over "
          + "those defaults opens ticked; defaults holding only the style pill open on Pill "
          + "with all three off",
          untouched && wrote == [true, true, true] && reopened == [true, true, true]
            && third.style == .pill && thirdOff && third.looks == .none,
          "untouched before a click \(untouched), wrote \(wrote), reopened \(reopened), older "
            + "opens on \(third.style.rawValue) with all off \(thirdOff)")

    let kept = freshDefaults()
    let s = sheet(doc, defaults: kept)
    choose(.pill, on: s)
    tick(.slide, on: s)
    let onPill = s.looks.slide
    choose(.karaoke, on: s)
    let box = s.slideCheckbox
    let greyed = !box.isEnabled && box.state == .on
    let counted = s.looks.slide
    let stillHeld = kept.bool(forKey: "FrameJobCaptionSlide")
    choose(.pill, on: s)
    let back = box.isEnabled && box.state == .on && s.looks.slide
    check("S14 Slide ticked on Pill, then Karaoke: the box is disabled and still ticked, "
          + "looks.slide is false and the defaults still hold true; back on Pill it is on",
          onPill && greyed && !counted && stillHeld && back,
          "on Pill \(onPill); on Karaoke greyed-and-ticked \(greyed), counted \(counted), "
            + "defaults \(stillHeld); back on Pill \(back)")
} else {
    check("S13 the document builds", false, "")
    check("S14 the document builds", false, "")
}

// MARK: - S15 what a commit writes, whole

let wordStyles = CaptionStyle.allCases.filter(\.isWordStyle)
var bare: [String] = []
var unmeasured: [String] = []
for style in wordStyles {
    let pages = commitLooks(style, nil) ?? []
    if pages.isEmpty || !pages.allSatisfy({ $0.wordStyle == style.wordStyle }) {
        bare.append("\(style.rawValue): \(pages.count) pages, \(String(describing: pages.first?.wordStyle))")
    }
    if !measuresAlike(pages, style) { unmeasured.append(style.rawValue) }
}
check("S15 (i) each of the five word styles with no box ticked commits the unedited preset's "
      + "word_style, whole", wordStyles.count == 5 && bare.isEmpty, "wrong \(bare)")
var pairs = 0
for style in wordStyles {
    var wrong: [String] = []
    let live = Look.allCases.filter { liveTable[$0]?.contains(style) ?? false }
    for look in live {
        pairs += 1
        let pages = commitLooks(style, look) ?? []
        let want = rebuilt(style, look)
        if pages.isEmpty || want == nil || !pages.allSatisfy({ $0.wordStyle == want }) {
            wrong.append("\(look.rawValue): \(pages.count) pages, committed "
                + "\(String(describing: pages.first?.wordStyle)), wanted \(String(describing: want))")
        }
        if !measuresAlike(pages, style) { unmeasured.append("\(style.rawValue)+\(look.rawValue)") }
    }
    check("S15 (ii) \(style.rawValue): each live look, ticked alone, commits the preset rebuilt "
          + "in the probe with only that look's field changed (\(live.map(\.rawValue)))",
          !live.isEmpty && wrong.isEmpty, "wrong \(wrong)")
}
var unequal: [String] = []
for style in CaptionStyle.allCases {
    if style.wordStyle(.none) != style.wordStyle { unequal.append("\(style.rawValue) .none") }
    for look in Look.allCases where !(liveTable[look]?.contains(style) ?? false) {
        var alone = CaptionLooks.none
        alone[look] = true
        if style.wordStyle(alone) != style.wordStyle {
            unequal.append("\(style.rawValue) \(look.rawValue)")
        }
    }
}
check("S15 (iii) for all six styles wordStyle(.none) == wordStyle, and a look that is not "
      + "live, alone, leaves wordStyle(_:) equal to wordStyle", unequal.isEmpty,
      "unequal \(unequal)")
check("S15 (iv) in each of the 14 commits every committed page measures what its looks-free "
      + "page measures", pairs == 9 && unmeasured.isEmpty,
      "\(5 + pairs) commits, differing \(unmeasured)")

// MARK: - S16 the preview's two frames

if let doc = document(vertical) {
    let k = sheet(doc)
    choose(.karaoke, on: k)
    let plain = png(k.previewView.image)
    tick(.fill, on: k)
    let filled = png(k.previewView.image)
    let beforeDim = k.previewView.image
    tick(.dim, on: k)
    let dimDrewNothing = beforeDim != nil && k.previewView.image === beforeDim
    let p = sheet(doc)
    choose(.pill, on: p)
    let settled = png(p.previewView.image)
    tick(.slide, on: p)
    let slid = png(p.previewView.image)
    // The second frame is mid-slide, not at rest: the sheet's own props drawn
    // at the preview's glide differ from the same props with none.
    let frame = max(doc.project.snapshot.canvas.fps.frameDuration, 1)
    let props = CaptionPages.samplePage(
        TranscribeSheetController.fixedSampleWords, request: p.pagesRequest, frame: frame
    ).map { p.previewProps(for: $0, canvas: vertical) }
    let midway = props.flatMap {
        bytes(LayerRenderers.textBitmap($0, reveal: RecipeReveal(word: 2, wordPop: 1, wordGlide: 0.2)))
    }
    let atRest = props.flatMap {
        bytes(LayerRenderers.textBitmap($0, reveal: RecipeReveal(word: 2, wordPop: 1)))
    }
    let all = CaptionLooks(slide: true, fill: true, dim: true)
    let one = TranscribeSheetController.previewReveals(tokens: 1, looks: all)
    let three = TranscribeSheetController.previewReveals(tokens: 3, looks: all)
    let none = TranscribeSheetController.previewReveals(tokens: 3, looks: .none)
    let revealsOK =
        one == [RecipeReveal(word: 1, wordPop: 1, wordFill: 0.5),
                RecipeReveal(word: 1, wordPop: 1, wordFill: 0.5)]
        && three == [RecipeReveal(word: 1, wordPop: 1, wordFill: 0.5),
                     RecipeReveal(word: 2, wordPop: 1, wordGlide: 0.2, wordFill: 0.5)]
        && none == [RecipeReveal(word: 1, wordPop: 1), RecipeReveal(word: 2, wordPop: 1)]
    check("S16 Karaoke's preview with Fill differs from without, Pill's with Slide differs from "
          + "without and its second frame is mid-slide; ticking Dim draws nothing; "
          + "previewReveals answers the literal values for 1 and 3 tokens",
          plain != nil && filled != nil && plain != filled && dimDrewNothing
            && settled != nil && slid != nil && settled != slid
            && midway != nil && atRest != nil && midway != atRest
            && (props?.tokenCount ?? 0) >= 2 && revealsOK,
          "Karaoke differs \(plain != filled), Dim kept the image \(dimDrewNothing), Pill "
            + "differs \(settled != slid), mid-slide differs from rest \(midway != atRest) on "
            + "\(props?.tokenCount ?? 0) tokens, reveals \(revealsOK): \(three)")
} else {
    check("S16 the document builds", false, "")
}

let out: [String: Any] = ["ok": true, "registered": registered, "rows": rows]
let data = (try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])) ?? Data()
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
exit(0)
