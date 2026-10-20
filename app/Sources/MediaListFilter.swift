import AppKit

/// How the Media tab's list is narrowed and ordered (road map 2's phase 8c):
/// a search over names, a sort, and the "unused only" switch.
///
/// A VALUE, in `AudioNormalize.swift`'s and `CaptionLayout.swift`'s shape —
/// media in, ids out — for the reason those two are values: the arithmetic is
/// then a function anybody can read, run and check without a panel, and the
/// pane above it does nothing but hand rows to the answer. It is also the
/// only way the ordering rules below can ever be measured, since a list of
/// rows in a scroll view is not something a proof script can interrogate.
///
/// **It is view state and it is not persisted**, which is a decision rather
/// than an omission. Three arguments, in the order they were made:
/// a search is an act of FINDING and not a preference, and a panel that comes
/// back tomorrow showing two of a project's forty files — because of what
/// somebody typed once — is a bug report about missing media; the pane is
/// rebuilt per document window, so two open projects filter independently,
/// which is what "the Media tab of THIS project" means; and a `UserDefaults`
/// key would have to be pinned in the offscreen harness's `pinDefaults` or
/// every chrome render of this pane would depend on whatever the machine
/// happened to store (app/CLAUDE.md's rule for the keys the chrome reads).
/// Nothing here writes a default and nothing reads one.
struct MediaListFilter: Equatable {
    /// The sort popup's rows, in menu order; the raw value IS the row index,
    /// so the order is API for the popup that reads it.
    ///
    /// **`importOrder` is spelled "Import Order" and not "Added"**, which the
    /// road map's own wording ("name, duration, added, kind") would have
    /// suggested, because the app knows an ORDER and does not know a TIME.
    /// Nothing records when a media entry arrived: `MediaSnapshot` and the
    /// core's `Media` are the same eleven keys and none of them is a
    /// timestamp. What the media array carries instead is insertion order —
    /// `add_media` pushes after `allocate_id` (`core/src/edit_track.rs`),
    /// `absorb_media` does the same (`edit_paste.rs`), `remove_media` retains
    /// and `relink_media` mutates in place, so nothing ever reorders it — and
    /// for any project built by ops that is also ascending id order. A real
    /// "date added" would be a persisted field, which is a version-7 schema
    /// bump, and phase 8 is declared "no schema; view state throughout": a
    /// row that says what the app actually knows is worth more than a row
    /// that says what the road map wished it knew.
    enum Order: Int, CaseIterable {
        case importOrder, name, duration, kind

        var title: String {
            switch self {
            case .importOrder: return "Import Order"
            case .name: return "Name"
            case .duration: return "Duration"
            case .kind: return "Kind"
            }
        }
    }

    /// What was typed in the search field, verbatim. Not trimmed: the field
    /// is on screen beside the list, and a filter that quietly ignored a
    /// space somebody typed would disagree with what they can see. Empty is
    /// the only value that means "no search".
    var search = ""
    var order = Order.importOrder
    var unusedOnly = false

    /// Whether the list is showing less than the project holds — what the
    /// item count says out loud, so "3 of 40 items" never appears over a
    /// list that is showing everything.
    var isNarrowing: Bool { !search.isEmpty || unusedOnly }

    /// Whether one entry survives the two filters.
    ///
    /// The name test is `localizedStandardContains`, which is the comparison
    /// Finder searches with: case-insensitive, diacritic-insensitive and
    /// width-insensitive against the current locale, so `resume` finds
    /// `Résumé.mov` and `KEYNOTE` finds `keynote.mov`. Spelling it out as
    /// `range(of:options:)` would be the same three options with a fourth
    /// chance to forget one.
    ///
    /// "Unused" is `ProjectSnapshot.usesMedia`, which walks the nests as well
    /// as the timeline (`MediaUsage.swift`) — so a file that appears only
    /// inside a compound clip is USED and is not offered up for deletion by
    /// this filter, which is exactly what `remove_media` will say if it is
    /// asked.
    func admits(_ entry: MediaSnapshot, in snapshot: ProjectSnapshot) -> Bool {
        if unusedOnly, snapshot.usesMedia(entry.id) { return false }
        guard !search.isEmpty else { return true }
        return entry.name.localizedStandardContains(search)
    }

    /// The ids of `media` in the order the list should show them — every id,
    /// filtered or not, because hiding a row and moving it are two different
    /// jobs and the pane does them separately.
    ///
    /// **Every order is ascending and every tie falls back to import order**,
    /// which is one rule rather than four opinions: a list of a few dozen
    /// files reads as well from either end, and "longest first" versus
    /// "shortest first" is an argument with no answer that would then have to
    /// be re-had for kind. The tiebreak is not decoration —
    /// `Array.sort` is not documented stable, so without it two files of the
    /// same duration could swap places between two runs of the same sort,
    /// which is the kind of thing nobody reports and everybody notices.
    func ordered(_ media: [MediaSnapshot]) -> [UInt32] {
        guard order != .importOrder else { return media.map { $0.id } }
        return media.enumerated().sorted { a, b in
            switch order {
            case .importOrder:
                return a.offset < b.offset
            case .name:
                let compared = a.element.name.localizedStandardCompare(b.element.name)
                if compared == .orderedSame { return a.offset < b.offset }
                return compared == .orderedAscending
            case .duration:
                return a.element.duration == b.element.duration
                    ? a.offset < b.offset : a.element.duration < b.element.duration
            case .kind:
                let left = a.element.kind.displayName
                let right = b.element.kind.displayName
                return left == right ? a.offset < b.offset : left < right
            }
        }.map { $0.element.id }
    }
}

// MARK: - The controls that write one

extension MediaListFilter {
    /// The three controls of the Media tab's find band, built over a filter
    /// somebody else owns: `current` hands the value over, `apply` takes the
    /// new one back and is expected to re-arrange the list.
    ///
    /// They live beside the value rather than in `MediaPane.swift` for the
    /// reason `OptionControls.swift` exists at all — a control here stores
    /// nothing, so a control and the value it edits are one idea — and
    /// because the pane was at its size cap before this phase and this is the
    /// half of the band that is about the FILTER rather than about the panel's
    /// chrome. What the pane keeps is the layout: which line each control
    /// sits on, and the caption and the spacer around them.
    ///
    /// Each control writes THROUGH `apply` rather than mutating and then
    /// telling somebody — one path in, so a re-arrangement can never be
    /// skipped by a control that forgot to call back.
    static func controls(
        current: @escaping () -> MediaListFilter, apply: @escaping (MediaListFilter) -> Void
    ) -> (search: NSView, sort: NSView, unusedOnly: NSView) {
        let search = MediaSearchField(
            text: current().search,
            changed: { text in
                var next = current()
                next.search = text
                apply(next)
            })
        search.toolTip = "Show only files whose name contains this text"

        let sort = OptionPopupControl(
            width: InspectorMetrics.popupWidth,
            items: Order.allCases.map { $0.title },
            read: { current().order.rawValue },
            write: { index in
                guard let order = Order(rawValue: index) else { return }
                var next = current()
                next.order = order
                apply(next)
            },
            enabled: { true }, onEdit: {})
        // The offscreen harness finds this popup by the tooltip's opening words
        // (`tools/proof/harness/main.swift`'s `mediaFilter`): reword both.
        sort.toolTip =
            "Import Order is the order the files were added — what this list shows "
            + "unless another row is chosen."

        let unused = OptionCheckboxControl(
            label: "Unused only",
            read: { current().unusedOnly },
            write: { value in
                var next = current()
                next.unusedOnly = value
                apply(next)
            },
            enabled: { true }, onEdit: {})
        unused.toolTip = "Show only files no clip uses — inside a compound clip counts as used."

        return (search: search, sort: sort, unusedOnly: unused)
    }
}

// MARK: - The search field

/// The Media tab's search box — and **the app's first as-you-type control**,
/// which is worth saying because everything else in this panel commits.
/// `InspectorNameField` and `InspectorTimecodeField` both write on
/// `controlTextDidEndEditing`, and `OptionFieldControl` is the same shape
/// with a number in it; all three are editing the MODEL, where a keystroke
/// would be an undo step per letter. This one edits nothing — it narrows a
/// list of rows that are already built — so it reports every keystroke
/// through `controlTextDidChange` and the list follows the caret.
///
/// It holds no state of its own. The pane owns the string
/// (`MediaListFilter.search`); this field is handed the current one at build
/// time and hands back what was typed, which is the same "controls store no
/// value" rule the rest of the inspector is built on (`InspectorPane.swift`).
/// That matters for one reason beyond tidiness: the pane is REBUILT whenever
/// the media list changes, which destroys this view, and a search that lived
/// in the field would be lost with it while the list stayed narrowed.
///
/// Escape clears rather than reverting. AppKit's default for a text field is
/// to put back the value the field started editing with and end editing,
/// which for a search box means "undo my typing" where every other app on
/// this machine means "show me everything again".
///
/// **Not an `NSSearchField`**, though this is exactly what one is for: that
/// class draws its own bezel, magnifier and cancel button and would be the
/// only system-looking control in a panel whose every field is
/// `DSField.style` (`Controls.swift` — "a 7px rectangle means: type here"),
/// and it sends its action on a TIMER by default, which is a second answer to
/// "when does the list narrow" living somewhere this file cannot see. What it
/// would have brought for free is the cancel button and the recent-searches
/// menu; the first is Escape here and the second is not wanted in a list of a
/// few dozen files.
final class MediaSearchField: NSTextField, NSTextFieldDelegate {
    private let changed: (String) -> Void

    init(text: String, changed: @escaping (String) -> Void) {
        self.changed = changed
        super.init(frame: .zero)
        DSField.style(self, height: 24, radius: DS.controlRadius, font: DS.sans(11))
        placeholderString = "Search by name"
        stringValue = text
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MediaSearchField does not support NSCoder")
    }

    func controlTextDidChange(_ obj: Notification) {
        changed(stringValue)
    }

    func control(
        _ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector
    ) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        // Handled here rather than by letting the field editor end: an empty
        // field with the caret still in it is what a person pressing Escape in
        // a search box is asking for.
        guard !stringValue.isEmpty else { return false }
        stringValue = ""
        changed("")
        return true
    }
}
