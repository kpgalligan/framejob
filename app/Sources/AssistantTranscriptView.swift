import AppKit

/// The Assistant tab's transcript: a scroll view owning ONE non-editable,
/// selectable text view (TextKit 1), the entries in order with one "\n"
/// between them, so a selection and a plain-text copy cross entries (spec
/// §11 AI-17). Each entry is a range of that text, kept in `spans`; a reply
/// that is still extending edits only its own range. Scrolled to the newest
/// line whenever an entry is appended or extended. It draws the transcript
/// it is handed and keeps none of it (spec §11 AI-4: the entries are
/// `EditorViewController.assistantTranscript`'s). Road map 12 A2.
///
/// One text view has no subview per entry, so the layout dump reads the
/// entries as parts this view names (`UISnapshotParts`, dev only): the
/// `assistant.entry.<kind>` records the proofs read.
final class AssistantTranscriptView: NSScrollView {
    private static let inset: CGFloat = 10
    let textView: NSTextView
    /// Each entry's kind and its UTF-16 range in the text, in order.
    private var spans: [(kind: AssistantEntry.Kind, range: NSRange)] = []

    init() {
        textView = TranscriptTextView(usingTextLayoutManager: false)
        super.init(frame: .zero)
        hasVerticalScroller = true
        autohidesScrollers = true
        drawsBackground = false
        borderType = .noBorder
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: Self.inset, height: 8)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.frame = NSRect(origin: .zero, size: contentSize)
        documentView = textView
        // Adopting it runs the text view's `sizeToFit`, which leaves its
        // origin at minus its new height (measured, #182); put it back at 0.
        textView.setFrameOrigin(.zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("AssistantTranscriptView does not support NSCoder")
    }

    /// The text view is never shorter than the clip view, so a click below a
    /// short transcript lands in the text (#182).
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.sizeToFit()
    }

    // MARK: - Drawing the transcript

    func reload(_ entries: [AssistantEntry]) {
        storage?.setAttributedString(NSAttributedString())
        spans = []
        for entry in entries { add(entry) }
        scrollToNewest()
    }

    func apply(_ change: AssistantTranscriptChange) {
        switch change {
        case .appended(let entry):
            add(entry)
            scrollToNewest()
        case .extended(let index, let text):
            guard spans.indices.contains(index) else { return }
            extend(index, to: text)
            scrollToNewest()
        case .cleared:
            reload([])
        case .usage, .conversationCost:
            break
        }
    }

    /// Each entry's kind, text and rect, in order, in THIS view's coordinates.
    func entryLayout() -> [(kind: AssistantEntry.Kind, text: String, rect: NSRect)] {
        guard let storage, let layout = textView.layoutManager,
            let container = textView.textContainer
        else { return [] }
        layout.ensureLayout(for: container)
        let origin = textView.textContainerOrigin
        let text = storage.string as NSString
        return spans.map { span in
            let glyphs = layout.glyphRange(forCharacterRange: span.range, actualCharacterRange: nil)
            var rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
            rect.origin.x += origin.x
            rect.origin.y += origin.y
            return (span.kind, text.substring(with: span.range), convert(rect, from: textView))
        }
    }

    private var storage: NSTextStorage? { textView.textStorage }

    private func add(_ entry: AssistantEntry) {
        guard let storage else { return }
        storage.beginEditing()
        if !spans.isEmpty {
            // The separator ends the previous entry's last paragraph, so it
            // takes that paragraph's attributes.
            let attributes = storage.length > 0
                ? storage.attributes(at: storage.length - 1, effectiveRange: nil)
                : Self.attributes(entry.kind, first: false, index: spans.count)
            storage.append(NSAttributedString(string: "\n", attributes: attributes))
        }
        let start = storage.length
        let styled = Self.styled(entry.text, entry.kind, index: spans.count)
        storage.append(styled)
        storage.endEditing()
        spans.append((entry.kind, NSRange(location: start, length: styled.length)))
    }

    /// Entry `index`'s text is now `text`: only the new suffix is inserted
    /// when the old text is a non-empty prefix of it; otherwise the entry's
    /// range is replaced. The spans after it shift.
    private func extend(_ index: Int, to text: String) {
        guard let storage else { return }
        let span = spans[index]
        let old = (storage.string as NSString).substring(with: span.range)
        let styled = Self.styled(text, span.kind, index: index)
        let replaced: NSRange
        let inserted: NSAttributedString
        if !old.isEmpty, text.hasPrefix(old) {
            let oldLength = (old as NSString).length
            replaced = NSRange(location: NSMaxRange(span.range), length: 0)
            inserted = styled.attributedSubstring(
                from: NSRange(location: oldLength, length: styled.length - oldLength))
        } else {
            replaced = span.range
            inserted = styled
        }
        guard replaced.length > 0 || inserted.length > 0 else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: replaced, with: inserted)
        storage.endEditing()
        let delta = inserted.length - replaced.length
        spans[index].range.length += delta
        for later in spans.indices where later > index {
            spans[later].range.location += delta
        }
    }

    /// `text` in `kind`'s font and colour; its first paragraph carries the
    /// gap above the entry, the rest none.
    private static func styled(
        _ text: String, _ kind: AssistantEntry.Kind, index: Int
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: text, attributes: attributes(kind, first: false, index: index))
        let whole = text as NSString
        let firstEnd = whole.paragraphRange(for: NSRange(location: 0, length: 0))
        if firstEnd.length > 0 {
            result.setAttributes(attributes(kind, first: true, index: index), range: firstEnd)
        }
        return result
    }

    /// The person's line opens a new exchange: a wider gap above it.
    private static func attributes(
        _ kind: AssistantEntry.Kind, first: Bool, index: Int
    ) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacingBefore = !first || index == 0 ? 0 : (kind == .person ? 14 : 6)
        let font: NSFont
        let colour: NSColor
        switch kind {
        case .person:
            font = DS.sans(12, weight: .semibold)
            colour = DS.textStrong
        case .reply:
            font = DS.sans(12)
            colour = DS.textStrong
        case .progress:
            font = DS.sans(11)
            colour = DS.textFaint
        case .meta:
            font = DS.mono(10)
            colour = DS.textMuted
        case .error:
            font = DS.sans(11)
            colour = DS.meterClip
        }
        return [.font: font, .foregroundColor: colour, .paragraphStyle: paragraph]
    }

    /// The newest line into view. The text view is flipped, so the end is
    /// its full height less what the clip view shows.
    private func scrollToNewest() {
        layoutSubtreeIfNeeded()
        if let layout = textView.layoutManager, let container = textView.textContainer {
            layout.ensureLayout(for: container)
        }
        textView.sizeToFit()
        let clip = contentView
        let y = max(0, textView.frame.height - clip.bounds.height)
        clip.scroll(to: NSPoint(x: 0, y: y))
        reflectScrolledClipView(clip)
    }
}

/// The transcript's text view: it copies plain text only. The type is the
/// legacy string name NSTextView writes by (`writeSelection` answers false
/// for `.string`, measured on macOS 26), which the pasteboard also offers as
/// `public.utf8-plain-text`.
private final class TranscriptTextView: NSTextView {
    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [NSPasteboard.PasteboardType("NSStringPboardType")]
    }
}

#if FRAMEJOB_DEV_TOOLS
extension AssistantTranscriptView: UISnapshotParts {
    /// One `assistant.entry.<kind>` part per entry, for the layout dump.
    func snapshotParts() -> [UISnapshotPart] {
        entryLayout().map { entry in
            UISnapshotPart(
                id: "assistant.entry.\(entry.kind.rawValue)", text: entry.text, rect: entry.rect)
        }
    }
}
#endif
