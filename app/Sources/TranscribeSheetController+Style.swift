import AppKit

// MARK: - Sheet: the Style row

/// The caption STYLE on the Generate Captions card — road map 8 §5e, W4b:
/// the Style popup, the preview under the looks row
/// (`TranscribeSheetController+Looks.swift`), and the "Replace existing
/// captions" checkbox with the list of what it will replace.
///
/// **The sheet commits what `transcribe {style, replace, slide, fill, dim}`
/// commits.** `style`, `replaceExisting`, `pagesRequest` and `looks` are the
/// four things `begin`, `beginCloud` and `finish` read, and they are computed
/// off the controls: the style off the popup's ITEM (app/CLAUDE.md's popup
/// rule), Replace only while the checkbox is live — which is the tool's two
/// rules read across (`AgentServer+Captions.swift`): a word style, and at
/// least one track `CaptionLayout.replaceableTracks` names — and each look
/// only while its box is enabled and on (spec §11 W-15).
///
/// **The preview is the renderer's own picture.** A sample page — the first
/// page `CaptionPages` makes of the scope's first clip's cached transcript,
/// else of `sampleText` — is laid out exactly as `place` would write it and
/// drawn by `LayerRenderers.textBitmap`, the routine the compositor uploads;
/// nothing is hand-drawn here but the plate and the scaling. A word style
/// shows two frames, the first and then the second word active — with a
/// ticked fill half done in both and a ticked pill half-way through its slide
/// in the second (`previewReveals`); the dim is not previewed. It is
/// redrawn only when its `PreviewKey` — the style, the first job's clip, the
/// canvas and the previewed looks — changes, so a keystroke in Vocabulary or
/// a click on Dim draws nothing.
///
/// **The style is remembered** under `CaptionStyle.defaultsKey`, read when
/// the popup is built and written when it changes, and never by the tool
/// (R6-2 read across). It is a display choice: not part of any transcript's
/// cache marker (R6-15), so a cached transcript stays a hit whatever is picked.
extension TranscribeSheetController {

    /// What the preview was last drawn for; `refreshStyleRow` redraws on a change only.
    /// `looks` are the PREVIEWED ones: `dim` is always false there.
    struct PreviewKey: Equatable {
        let style: CaptionStyle
        let clip: UInt32?
        let canvas: CGSize
        var looks = CaptionLooks.none
    }

    /// How far through its fill the preview draws the active word.
    static let previewFill = 0.5
    /// The slide's progress in the preview: `easeOut(0.2)` is 0.488, the pill
    /// drawn half-way between the first word and the second.
    static let previewGlide = 0.2

    /// The preview's size in points: column 1 of the grid, 420 − 44 − 106 − 12.
    static let previewSize = CGSize(width: 258, height: 80)

    /// Sentence case: each style's own `textCase` uppercases it through
    /// `laidContent` (`WordProps.swift`), so Subtitles and Karaoke preview as
    /// written and the other four in capitals — as `transcribe` commits them.
    static let sampleText = "This is how it looks"

    /// The chosen style, read off the item; anything unreadable is Subtitles.
    var style: CaptionStyle {
        guard let raw = stylePopup.selectedItem?.representedObject as? String else {
            return .subtitles
        }
        return CaptionStyle(rawValue: raw) ?? .subtitles
    }

    /// Replace only while the checkbox is live: a disabled box replaces
    /// nothing, whatever state it was left in.
    var replaceExisting: Bool {
        replaceCheckbox.isEnabled && replaceCheckbox.state == .on
    }

    /// What each job's words are paged for: the style, on this canvas.
    var pagesRequest: CaptionPages.Request {
        CaptionPages.Request(
            style: style,
            canvas: CGSize(width: snapshot.canvas.width, height: snapshot.canvas.height))
    }

    // MARK: - The three rows

    /// Grid row 7: Subtitles, then the five word styles, in
    /// `CaptionStyle.allCases` order, opening on the remembered one.
    func makeStyleRow() -> [NSView] {
        stylePopup.removeAllItems()
        stylePopup.menu?.autoenablesItems = false
        for style in CaptionStyle.allCases {
            let item = NSMenuItem(title: style.displayName, action: nil, keyEquivalent: "")
            item.representedObject = style.rawValue
            stylePopup.menu?.addItem(item)
        }
        let remembered = defaults.string(forKey: CaptionStyle.defaultsKey)
        let wanted = CaptionStyle.allCases.first { $0.rawValue == remembered } ?? .subtitles
        if let index = stylePopup.itemArray.firstIndex(where: {
            $0.representedObject as? String == wanted.rawValue
        }) {
            stylePopup.selectItem(at: index)
        }
        stylePopup.font = DS.sans(13)
        stylePopup.target = self
        stylePopup.action = #selector(styleChanged(_:))
        stylePopup.widthAnchor.constraint(equalToConstant: 200).isActive = true
        return [fieldLabel("Style:"), stylePopup]
    }

    /// Grid row 9: the preview, the full width of the controls column.
    func makePreviewRow() -> [NSView] {
        previewView.imageScaling = .scaleNone
        previewView.imageFrameStyle = .none
        previewView.widthAnchor.constraint(equalToConstant: Self.previewSize.width)
            .isActive = true
        previewView.heightAnchor.constraint(equalToConstant: Self.previewSize.height)
            .isActive = true
        return [fieldLabel(""), previewView]
    }

    /// Grid row 10: the checkbox, and under it the tracks it will replace.
    func makeReplaceRow() -> [NSView] {
        replaceCheckbox.font = DS.sans(12)
        replaceCheckbox.target = self
        replaceCheckbox.action = #selector(controlChanged(_:))
        replaceLabel.font = DS.sans(11)
        replaceLabel.textColor = DS.textMuted
        replaceLabel.isEditable = false
        replaceLabel.preferredMaxLayoutWidth = Self.previewSize.width
        let stack = NSStackView(views: [replaceCheckbox, replaceLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        return [fieldLabel("Replace:"), stack]
    }

    /// The Style popup: remember the choice, and recompute.
    @objc func styleChanged(_ sender: Any?) {
        defaults.set(style.rawValue, forKey: CaptionStyle.defaultsKey)
        refresh()
    }

    /// The four rows' state, recomputed — `refresh()` calls it on the way
    /// out, whichever engine it dispatched to. The looks row first: the
    /// preview's key reads `looks`, which reads each box's `isEnabled`.
    func refreshStyleRow() {
        refreshLooksRow()
        let jobs = jobs(in: scope)
        let replaceable = CaptionLayout.replaceableTracks(in: snapshot, jobs: jobs)
        let live = style.isWordStyle && !replaceable.isEmpty
        replaceCheckbox.isEnabled = live
        if !live { replaceCheckbox.state = .off }
        replaceLabel.isHidden = !live
        replaceLabel.stringValue = live ? replaceText(replaceable) : ""
        var previewed = looks
        previewed.dim = false
        let key = PreviewKey(
            style: style, clip: jobs.first?.clip,
            canvas: CGSize(width: snapshot.canvas.width, height: snapshot.canvas.height),
            looks: previewed)
        if key != previewKey {
            previewKey = key
            previewView.image = preview()
        }
    }

    /// "Replaces “Captions” (12 captions), “Captions 2” (3 captions)." — the
    /// tracks by name, in stack order, each with its clip count.
    private func replaceText(_ tracks: [UInt32]) -> String {
        let named = tracks.map { id -> String in
            let name = snapshot.tracks.first { $0.id == id }?.name ?? "track \(id)"
            let count = snapshot.clips.filter { $0.track == id }.count
            return "“\(name)” (\(count) caption\(count == 1 ? "" : "s"))"
        }
        return "Replaces " + named.joined(separator: ", ") + "."
    }

    // MARK: - The preview

    /// `sampleText`'s five tokens, one every 0.3 s from 0, each 0.18 s long.
    static var fixedSampleWords: [CaptionCues.Word] {
        sampleText.split(separator: " ").enumerated().map { index, token in
            let start = Ticks(index) * 180_000
            return CaptionCues.Word(text: String(token), start: start, end: start + 108_000)
        }
    }

    /// The words the preview pages: the first job's own words, up to twelve,
    /// when a cached transcript already has them, else `fixedSampleWords`.
    /// The ANSWER is cached per clip, a miss included — `refresh` runs per
    /// keystroke, and `MediaTranscript.read` is a disk read hit or miss.
    func sampleWords() -> [CaptionCues.Word] {
        guard let job = jobs(in: scope).first else { return Self.fixedSampleWords }
        if let cached = sampleWordsCache[job.clip] { return cached }
        var words: [CaptionCues.Word] = []
        if let directory = document?.cacheDirectory,
            let file = MediaTranscript.read(for: job.media, in: directory)
        {
            words = Array(MediaTranscript.words(for: job, in: file).prefix(12))
        }
        let answer = words.isEmpty ? Self.fixedSampleWords : words
        sampleWordsCache[job.clip] = answer
        return answer
    }

    /// The page's text props as `CaptionLayout.place` writes them: a word
    /// style's are `CaptionStyle.textProps` at the page's own size and width —
    /// the one construction the pager measured and `pagePatch` commits, with
    /// the sheet's `looks` as `place` is handed them — and Subtitles' are the
    /// Caption preset with its wrap box, mirrored.
    func previewProps(for cue: CaptionLayout.Cue, canvas: CGSize) -> TextProps {
        guard style.isWordStyle else {
            let preset = CaptionLayout.captionPreset
            return TextProps(
                content: cue.text, font: preset.font,
                size: (Double(canvas.height) * preset.sizeFraction).rounded(),
                align: preset.align, valign: "middle", backdrop: preset.backdrop,
                width: Double(canvas.width) * CaptionLayout.wrapFraction)
        }
        return style.textProps(
            content: cue.text, size: cue.size ?? style.size(for: canvas), width: cue.width,
            looks: looks)
    }

    /// A word style's two preview frames: the first word active, then the
    /// second (the first again on a one-word page), each with the fill at
    /// `previewFill` when Fill is on, and the second with the pill at
    /// `previewGlide` when Slide is on and there is a word to slide from.
    static func previewReveals(tokens: Int, looks: CaptionLooks) -> [RecipeReveal] {
        let fill = looks.fill ? previewFill : nil
        let glide = looks.slide && tokens >= 2 ? previewGlide : nil
        return [
            RecipeReveal(word: 1, wordPop: 1, wordFill: fill),
            RecipeReveal(word: min(2, tokens), wordPop: 1, wordGlide: glide, wordFill: fill),
        ]
    }

    /// The sample page drawn by the renderer: two frames for a word style
    /// (`previewReveals`), one for Subtitles, each
    /// scaled to fit a 258×36 slot, stacked 8 pt apart over the plate, at 2×.
    func preview() -> NSImage? {
        let canvas = CGSize(width: snapshot.canvas.width, height: snapshot.canvas.height)
        let frame = max(snapshot.canvas.fps.frameDuration, 1)
        guard
            let cue = CaptionPages.samplePage(
                sampleWords(), request: pagesRequest, frame: frame)
        else { return nil }
        let props = previewProps(for: cue, canvas: canvas)
        let reveals =
            style.isWordStyle
            ? Self.previewReveals(tokens: props.tokenCount, looks: looks)
            : [RecipeReveal.whole]
        let size = Self.previewSize
        let scale: CGFloat = 2
        guard
            let context = LayerRenderers.bitmap(
                CGSize(width: size.width * scale, height: size.height * scale))
        else { return nil }
        context.setFillColor(DS.captionPreviewPlate.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        context.scaleBy(x: scale, y: scale)
        context.interpolationQuality = .high

        let slot = CGSize(width: size.width, height: 36)
        let gap: CGFloat = 8
        let count = CGFloat(reveals.count)
        // From the TOP, in points; the context is y-up.
        var top = (size.height - count * slot.height - (count - 1) * gap) / 2
        for reveal in reveals {
            if let bitmap = LayerRenderers.textBitmap(props, reveal: reveal),
                let image = bitmap.makeImage()
            {
                let fit = min(
                    slot.width / CGFloat(image.width), slot.height / CGFloat(image.height))
                let drawn = CGSize(
                    width: CGFloat(image.width) * fit, height: CGFloat(image.height) * fit)
                context.draw(
                    image,
                    in: CGRect(
                        x: (size.width - drawn.width) / 2,
                        y: size.height - top - slot.height + (slot.height - drawn.height) / 2,
                        width: drawn.width, height: drawn.height))
            }
            top += slot.height + gap
        }
        guard let image = context.makeImage() else { return nil }
        return NSImage(cgImage: image, size: size)
    }
}
