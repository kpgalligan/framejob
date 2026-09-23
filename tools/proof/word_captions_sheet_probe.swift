// Road map 8, W4b — the Generate Captions sheet's Style row, read
// structurally (`word_captions_chrome.py` builds and runs it).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `Reelcut`, against `libreelcut_core.a` —
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
    s.vocabularyField.stringValue = "Reelcut"
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

let out: [String: Any] = ["ok": true, "registered": registered, "rows": rows]
let data = (try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])) ?? Data()
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
exit(0)
