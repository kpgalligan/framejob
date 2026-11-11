import AppKit

/// What the Transcript pane holds for Find (spec §11 TX-37): view state,
/// never saved. The typed text lives in the bar's field.
struct TranscriptFindState {
    var isOpen = false
    /// The words as searched, built at the first search after a rebuild.
    var index: TranscriptFind.Index?
    var matches: [TranscriptFind.Match] = []
    var current: Int?
    /// The token the current match is looked for from (TX-37 (c)).
    var anchor = 0
    /// The transcript's text had the keys when the bar opened.
    var openedFromText = false
    /// The window the bar opened in: a pane being removed has none.
    weak var window: NSWindow?
}

/// Find in the Transcript tab (spec §11 TX-37): Edit ▸ Find… ⌘F opens the
/// bar above the text; typing marks every match and scrolls the current one
/// into sight; Return and ⇧Return step; Esc or Done closes it and hands the
/// keys back. **Find moves only the scroll position and its own marks** — no
/// selection, range, playhead or undo step — so it has no MCP mirror: it
/// edits nothing, like the Media tab's search. ⌘Return (TX-43) is a click on
/// the current match: that selection, seek and focus are the click's.
extension TranscriptPane {

    var isFindOpen: Bool { find.isOpen }

    /// The bar's callbacks and the view's Esc, wired once from `init`.
    func wireFind() {
        findBand.onQuery = { [weak self] _ in self?.findQueryChanged() }
        findBand.onStep = { [weak self] delta in self?.findStep(delta) }
        findBand.onSelect = { [weak self] in self?.findSelect() }
        findBand.onClose = { [weak self] in self?.closeFind() }
        transcriptView.onEscape = { [weak self] in
            guard let self, self.find.isOpen else { return false }
            self.closeFind()
            return true
        }
    }

    /// Whether the bar's field is the one being typed in.
    func findFieldHasKeys(in window: NSWindow?) -> Bool {
        guard let window, let editor = findBand.field.currentEditor() else { return false }
        return window.firstResponder === editor
    }

    /// Edit ▸ Find… (TX-37 (e)): the bar shown, its field given the keys with
    /// its text selected; the kept text is searched again. Open already, it
    /// only takes the keys again.
    func openFind() {
        guard isShown, let window else { return }
        if !find.isOpen {
            find.isOpen = true
            find.window = window
            find.openedFromText = window.firstResponder === transcriptView
            find.anchor = transcriptView.selection?.lowerBound ?? transcriptView.highlight
                ?? transcriptView.topVisibleToken() ?? 0
            findBand.isHidden = false
            findHeight.constant = TranscriptFindBand.height
            layoutSubtreeIfNeeded()
            search(reveal: true)
        }
        window.makeFirstResponder(findBand.field)
    }

    /// Esc, Done, or Esc in the text with nothing selected (TX-37 (e)): the
    /// bar and its marks gone. Keys the field holds go to the transcript's
    /// text when it had them as the bar opened, else to the content view
    /// (K-4's target); keys anything else holds stay where they are.
    func closeFind() {
        guard find.isOpen else { return }
        let window = self.window ?? find.window
        if findFieldHasKeys(in: window), let window {
            window.makeFirstResponder(find.openedFromText ? transcriptView : window.contentView)
        }
        endFind()
    }

    /// The tab is going out of sight (TX-37 (h)): the bar closes, and keys
    /// its field holds go to the content view, never to a view not shown.
    func hideFind() {
        guard find.isOpen else { return }  // nothing to close
        let window = self.window ?? find.window
        if findFieldHasKeys(in: window), let window {
            window.makeFirstResponder(window.contentView)
        }
        endFind()
    }

    private func endFind() {
        find.isOpen = false
        find.index = nil
        find.matches = []
        find.current = nil
        transcriptView.setFind([], current: nil)
        findBand.setCount("")
        findBand.isHidden = true
        findHeight.constant = 0
    }

    /// The field's text changed: the matches again, the current one the
    /// first at or after the anchor, scrolled into sight.
    func findQueryChanged() {
        guard find.isOpen else { return }
        search(reveal: true)
    }

    /// Return or Next (+1), ⇧Return or Previous (−1): the current match one
    /// on, wrapping, and the anchor with it; a beep with none (TX-37 (c)).
    func findStep(_ delta: Int) {
        guard find.isOpen else { return }
        guard let next = TranscriptFind.step(find.current, by: delta, count: find.matches.count)
        else {
            NSSound.beep()
            return
        }
        find.current = next
        find.anchor = find.matches[next].tokens.lowerBound
        publishFind(reveal: true)
    }

    /// ⌘Return in the field (spec §11 TX-43): the current match becomes the
    /// selection and the playhead goes to its first word, as a click on it
    /// does (`TranscriptView.select(match:)`), and the transcript's text
    /// takes the keys; the bar stays open. A beep with no current match.
    func findSelect() {
        guard find.isOpen, let window = self.window ?? find.window, let current = find.current,
            find.matches.indices.contains(current)
        else {
            NSSound.beep()
            return
        }
        window.makeFirstResponder(transcriptView)
        transcriptView.select(match: find.matches[current].tokens)
    }

    private func search(reveal: Bool) {
        let index = find.index ?? TranscriptFind.Index(model: source.model)
        find.index = index
        find.matches = index.matches(findBand.query)
        find.current = TranscriptFind.current(in: find.matches, atOrAfter: find.anchor)
        publishFind(reveal: reveal)
    }

    private func publishFind(reveal: Bool) {
        transcriptView.setFind(find.matches, current: find.current)
        findBand.setCount(
            TranscriptFind.label(
                query: findBand.query, current: find.current, count: find.matches.count))
        if reveal { transcriptView.revealFind() }
    }

    /// The current match's first word in the view's model as shown, read
    /// BEFORE a rebuild's `show`, for `refreshFind`.
    func findKeep() -> (id: TimelineTranscript.Identity, start: Ticks)? {
        guard find.isOpen, let current = find.current, find.matches.indices.contains(current)
        else { return nil }
        let tokens = transcriptView.model.tokens
        let first = find.matches[current].tokens.lowerBound
        guard tokens.indices.contains(first) else { return nil }
        return (tokens[first].word.id, tokens[first].word.start)
    }

    /// A rebuild landed (TX-37 (g)): the matches recomputed over the new
    /// words; the current one stays on its first word by identity, else the
    /// first match at or after that word's start; nothing scrolls.
    func refreshFind(keeping kept: (id: TimelineTranscript.Identity, start: Ticks)?) {
        guard find.isOpen else { return }
        find.index = nil
        let model = source.model
        if let kept, let index = model.index(of: kept.id) ?? model.firstIndex(atOrAfter: kept.start) {
            find.anchor = index
        }
        search(reveal: false)
    }
}
