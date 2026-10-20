import AppKit
import UniformTypeIdentifiers

/// The Media tab (spec §4.3): every imported file with its thumbnail, name,
/// duration, dimensions, rate and badges; Add Media… (⇧⌘I); Finder drops onto
/// the panel; a drag from a row to a timeline track or onto the canvas; the
/// find band road map 2's phase 8c added — a search, a sort and an "unused
/// only" switch (`MediaListFilter.swift`) — and the row menu: Insert at
/// Playhead, Overwrite at Playhead, Reveal in Timeline, Reveal in Finder,
/// Relink…, Remove.
///
/// There is no left panel in this app (§11), so this list IS the library.
/// Files are referenced, never copied (path + bookmark, §11), which is why a
/// row can be "missing" and why Relink… lives here.
///
/// **The find band does not rebuild the pane, and that is the whole design of
/// it.** `InspectorPaneView.rebuild()` removes every arranged subview and
/// asks `makeSections()` for a new set, `InspectorViewController.refresh` runs
/// it whenever `structureSignature` changes, and nothing in the inspector
/// preserves the first responder across one — so a search field built inside
/// `makeSections()` with the filtered set in the signature would be destroyed
/// by the first keystroke that changed the list, taking the field editor and
/// the caret with it (measured: removing a text field's ancestor leaves
/// `currentEditor()` nil and the window itself as first responder). So the
/// signature stays what it always was — a statement about the MODEL's shape —
/// and `arrange()` applies the search, the sort and the switch to the rows
/// that are already built, by hiding and re-ordering the list stack's
/// arranged subviews. Both are measured, not assumed: an `isHidden` arranged
/// subview leaves an `NSStackView`'s layout entirely (four 20 pt rows measure
/// 89 pt, three of them 66), and `insertArrangedSubview(_:at:)` MOVES a view
/// that is already arranged rather than duplicating it (the subview count
/// does not change) while leaving the window's first responder and the
/// caret's offset exactly where they were.
final class MediaPane: InspectorPaneView {
    override var tab: InspectorTab { .media }

    /// The Media tab always has something to show — including when there is
    /// nothing imported yet, which is when Add Media… matters most.
    override var emptyMessage: String? { nil }

    /// The rows, in the order the model lists them, each with the id it
    /// draws. The id is kept beside the view rather than read back off it so
    /// that `arrange()` can look the CURRENT entry up in the snapshot: a
    /// relink changes a file's name without changing this pane's signature,
    /// and a cached `MediaSnapshot` would sort and search against the name
    /// the row no longer shows.
    ///
    /// Internal rather than private for one caller: `select(_:)` redraws them
    /// and lives in `MediaPaneCommands.swift`, which is where the row's seven
    /// commands went when this file crossed the size cap. That is the whole
    /// cost of the split.
    var rows: [(media: UInt32, view: MediaRowView)] = []

    /// The find band's state. View state, not persisted, and not part of the
    /// signature below — `MediaListFilter` argues both.
    private var filter = MediaListFilter()

    /// The three things `arrange()` changes without a rebuild. Weak, because
    /// the view hierarchy owns them and a rebuild replaces all three;
    /// `InspectorPaneView.rebuild()` holds the previous generation one build
    /// longer, so a stale strong reference here would outlive the pane's own
    /// rule about that.
    private weak var listStack: NSStackView?
    private weak var tallyLabel: InspectorRowLabel?
    private weak var noMatchesRow: NSView?

    /// The order `arrange()` last put the rows in, so it can leave the stack
    /// alone when nothing has moved — it runs on every refresh, and a live
    /// canvas drag refreshes this panel thirty times a second.
    private var arrangedOrder: [UInt32] = []

    /// The MODEL's shape: which media exist and whether each one's file is
    /// there. Deliberately says nothing about the search text, the sort or
    /// the unused-only switch — see the class doc: putting the filtered set
    /// in here is precisely the bug this pane is built to avoid.
    override var structureSignature: String {
        let media = binding.snapshot.media.map { entry -> String in
            "\(entry.id):\(mediaURL(for: entry) == nil ? "missing" : "ok")"
        }
        return "media|" + media.joined(separator: ",")
    }

    override init(inspector: InspectorViewController) {
        super.init(inspector: inspector)
        // Finder drops land on the panel (§4.3). The editor's root view takes
        // file drops too, but it OPENS them as documents; a drop on this
        // panel means "add to this project", so the pane claims the type
        // first by being the deeper registered view.
        registerForDraggedTypes([.fileURL])
        NotificationCenter.default.addObserver(
            self, selector: #selector(cacheChanged(_:)), name: .mediaCacheDidChange, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MediaPane does not support NSCoder")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Sections

    /// The redesign makes this tab a real LIST rather than a stack of button
    /// rows (handoff README, Part 2 §5): a 38 pt action row, the rows 3 pt
    /// apart, and a 40 pt footer carrying Consolidate… and one line saying
    /// what it does. It is still ONE `InspectorSection`, because the panel's
    /// shell builds every pane from sections and this one has no business
    /// forking that.
    override func makeSections() -> [InspectorSection] {
        rows = []
        listStack = nil
        noMatchesRow = nil
        arrangedOrder = []
        var content: [NSView] = [actionRow()]
        if binding.snapshot.media.isEmpty {
            // No find band with nothing to find: the band would be three dead
            // controls over a line saying the list is empty, and the pane is
            // rebuilt the moment the first file lands.
            content.append(
                inspectorRow(nil, [InspectorRowLabel("Drop files here, or use Add Media….")]))
        } else {
            content.append(findRow())
            content.append(listView())
            content.append(noMatchesView())
        }
        content.append(footerRow())
        // The rows exist and the band's controls hold the state, so the
        // filter can be applied to this build before it is ever shown — which
        // is what carries a search across the rebuild an import causes.
        arrange()
        let files = InspectorSection(id: "media.files", title: "Media", rows: content)
        // Camera Log (spec §11 GR-16) acts on a video file, so it is there
        // once the project has one (`MediaPane+CameraLog.swift`); HDR10 (spec
        // §11 HD-12) on a PQ file, once the project has one
        // (`MediaPane+HDR10.swift`).
        let media = binding.documentSnapshot.media
        let video = media.contains { $0.kind == .video }
        let pq = media.contains { $0.color?.pq != nil }
        return (video ? [files, cameraLogSection()] : [files]) + (pq ? [hdr10Section()] : [])
    }

    /// Add Media…, its ⇧⌘I hint, and the item count at the trailing edge.
    ///
    /// The count used to be a plain label built once per rebuild, because it
    /// changed only when the media list did. It changes with the FILTER now —
    /// "3 of 40 items" is the one line that stops a narrowed list reading as a
    /// lost library — so the label is held and `arrange()` writes it. It is
    /// still not an `OptionControl`: those read the model, and this reads the
    /// pane's own view state.
    private func actionRow() -> NSView {
        let add = OptionButtonControl(
            title: "Add Media…",
            action: { [weak self] in
                self?.inspector?.onCommand?(#selector(EditorViewController.addMediaFiles(_:)))
            },
            enabled: { true }, onEdit: {})
        add.toolTip = "Import files into this project (⇧⌘I)"

        let count = binding.snapshot.media.count
        let label = MediaPane.caption(MediaPane.tally(shown: count, of: count))
        tallyLabel = label
        return MediaPane.bar(
            height: 38, border: .bottom,
            views: [add, MediaPane.caption("⇧⌘I"), MediaPane.spacer(), label])
    }

    /// The item count, and the one place it is spelled.
    ///
    /// **One rule, not two**, and the shape is the fix. This used to return
    /// early with `"\(shown) of \(total) items"` whenever the list was
    /// narrowed and only then fall through to a `switch` that spelled "No
    /// media" / "1 item" / "N items" — so the plural logic lived in the ONE
    /// branch that could never reach `total == 1`, and a one-file library
    /// with the search on read "0 of 1 items". Splitting a spelling across
    /// two branches is what invites that back, so the noun is built once and
    /// the narrowed line is that same noun with a prefix.
    ///
    /// The plural agrees with `total`, because `total` is the count the noun
    /// qualifies: "0 of 1 item" is one item, none of it shown. (English is
    /// not universal about that — "0 items" is plural where "1 item" is not,
    /// which is exactly why the number the noun belongs to has to be named
    /// rather than assumed.)
    private static func tally(shown: Int, of total: Int) -> String {
        if total == 0 { return "No media" }
        let items = total == 1 ? "1 item" : "\(total) items"
        return shown == total ? items : "\(shown) of \(items)"
    }

    /// The find band: the search field on its own line, the sort popup and
    /// the unused-only switch under it.
    ///
    /// **Two lines because three controls do not fit on one**, measured
    /// rather than felt: the popup is 116 pt (the `InspectorMetrics` width
    /// that holds "Import Order" in `DS.mono(11)` with its chevron), the
    /// checkbox is 77 (13 pt box, 6 pt gap, 58 pt of `DS.sans(11)`), and the
    /// field wants about 110 to show its own placeholder — 319 pt against the
    /// 284 the default 304 pt panel leaves inside the section inset, and 260
    /// at the 280 pt minimum width. One line "fits" only at a width nobody is
    /// guaranteed to have, and the failure mode is the search box shrinking
    /// to nothing while the two controls beside it stay whole.
    private func findRow() -> NSView {
        let controls = MediaListFilter.controls(
            current: { [weak self] in self?.filter ?? MediaListFilter() },
            apply: { [weak self] next in self?.apply(next) })
        return MediaPane.bar(
            height: 60, border: .bottom,
            lines: [
                [controls.search],
                [MediaPane.caption("Sort"), controls.sort, MediaPane.spacer(),
                 controls.unusedOnly],
            ])
    }

    /// A control wrote a new filter: keep it and re-arrange, unless it says
    /// exactly what the old one said (every keystroke in the search field
    /// arrives here, and most of them are `guard`ed out by this line).
    ///
    /// The controls are refreshed on the way out because
    /// `OptionCheckboxControl` and `OptionPopupControl` redraw from
    /// `refresh()` alone: they write through their closure and trust the panel
    /// to come back round, which it does for a document edit and does not for
    /// view state. It belongs here rather than in `arrange()` — this is the
    /// path a control WROTE on, and on the other two paths the panel has
    /// refreshed them already.
    private func apply(_ next: MediaListFilter) {
        guard next != filter else { return }
        filter = next
        arrange()
        refreshOptionControls(in: self)
    }

    /// The rows themselves, in their own stack so they sit 3 pt apart — the
    /// section's own row spacing is 6 and is shared with every other pane.
    ///
    /// Built in the MODEL's order every time; `arrange()` is what puts them in
    /// the sort's order, and it runs before this build is ever on screen.
    private func listView() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        for media in binding.snapshot.media {
            let row = MediaRowView(media: media.id, pane: self)
            rows.append((media: media.id, view: row))
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        listStack = stack
        return stack
    }

    /// The line under a list every row of which the filter has hidden. Built
    /// with the list and shown by `arrange()`, because a filter change must
    /// not rebuild anything — and a list that has silently gone blank is the
    /// worst thing a search can do to a library.
    ///
    /// The sentence measures 191 pt in `DS.sans(11)` against the 264 pt a row
    /// has in the default panel and 240 at the 280 pt minimum, so it is whole
    /// at every width — the footer's own line records what happens when that
    /// is not checked.
    private func noMatchesView() -> NSView {
        let row = inspectorRow(
            nil, [InspectorRowLabel("No media matches the search or the filter.")])
        row.isHidden = true
        noMatchesRow = row
        return row
    }

    /// The search, the sort and the unused-only switch applied to the rows
    /// this pane already holds — no rebuild, so the field being typed into
    /// keeps its caret (the class doc says why that is the point).
    ///
    /// The order is applied to EVERY row and the hiding to every row
    /// separately: moving a row and hiding one are different jobs, and a
    /// hidden row that keeps its place in the sort comes back where it
    /// belongs when the search is cleared. Nothing is written that does not
    /// have to be — this runs on every refresh, including a live gesture's
    /// thirty a second.
    private func arrange() {
        // The DOCUMENT's snapshot, and only one of the three things read off
        // it needs to be (road map 2's phase 9): `filter.admits` asks
        // `usesMedia`, and inside a nest a scoped view holds the NEST's clips
        // at top level and the timeline's nowhere — so a file used only by a
        // timeline clip would read as unused and "Unused only" would offer to
        // remove it. `media` itself is the same list either way (the view
        // carries the parent's `media[]` unchanged), so the order and the
        // tally are unaffected; this is written as one local so the question
        // cannot be asked two ways in one method.
        let snapshot = binding.documentSnapshot
        let order = filter.ordered(snapshot.media)
        if let stack = listStack, order != arrangedOrder {
            var index = 0
            for id in order {
                guard let row = rows.first(where: { $0.media == id })?.view else { continue }
                stack.insertArrangedSubview(row, at: index)
                index += 1
            }
            arrangedOrder = order
        }
        var shown = 0
        for row in rows {
            let visible = snapshot.media(row.media).map { filter.admits($0, in: snapshot) } ?? false
            if row.view.isHidden == visible { row.view.isHidden = !visible }
            row.view.syncToolTip()
            if visible { shown += 1 }
        }
        let empty = shown == 0 && !rows.isEmpty
        if noMatchesRow?.isHidden == empty { noMatchesRow?.isHidden = !empty }
        let tally = MediaPane.tally(shown: shown, of: snapshot.media.count)
        if tallyLabel?.stringValue != tally { tallyLabel?.stringValue = tally }
        dropHiddenSelection()
        refreshOptionControls(in: self)
    }

    /// The panel's own per-change refresh, plus a re-arrangement.
    ///
    /// The second half is not tidiness: "unused only" is a question about the
    /// CLIPS, and deleting the last clip that used a file changes no part of
    /// `structureSignature` — the media list is the same list — so without
    /// this the row that has just become unused would not appear until
    /// something else rebuilt the pane. A relink from one present file to
    /// another is the same shape: the name the sort reads changes and the
    /// signature does not. Everything above writes only what it has to, so
    /// the ordinary case — nothing moved, nothing hidden, the same count —
    /// costs one sort and a walk of a few dozen rows.
    override func refresh() {
        super.refresh()
        arrange()
    }

    /// Consolidate belongs beside the list it acts on: this pane is where the
    /// "files are referenced, never copied" rule is visible (a row can be
    /// missing, and Relink… lives here), so it is where the one command that
    /// ends the rule should be reachable. The menu item is the same action;
    /// both validate through the editor.
    ///
    /// The design puts it in a footer with a line saying what it does, so the
    /// one command in the app that copies gigabytes is never a mystery
    /// button. The line is the SHORT one; the sentence is the tooltip on both
    /// halves of the row.
    private func footerRow() -> NSView {
        let binding = self.binding
        let consolidate = OptionButtonControl(
            title: "Consolidate…",
            action: { [weak self] in
                self?.inspector?.onCommand?(#selector(EditorViewController.consolidateMedia(_:)))
            },
            enabled: { !binding.snapshot.media.isEmpty }, onEdit: {})
        consolidate.toolTip = MediaPane.consolidateNote

        let note = MediaPane.caption(MediaPane.consolidateLine, font: DS.sans(11))
        note.toolTip = MediaPane.consolidateNote
        note.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        return MediaPane.bar(height: 40, border: .top, views: [consolidate, note])
    }

    /// The line the footer SHOWS — the mock's own wording.
    ///
    /// **Pitfall:** the sentence below measures 251.2 pt in `DS.sans(11)`,
    /// against the 192 pt left beside the 84 pt Consolidate… button in the
    /// 304 pt panel and 168 pt at the 280 pt minimum (all measured) — so it
    /// truncated at the default width and at every width below it, and only
    /// came out whole past about 363 pt, which nobody but a user who has
    /// dragged the panel nearly to its 440 pt maximum ever sees. A
    /// half-sentence is a poor description of the one command that copies
    /// gigabytes. This line is 146.7 pt and fits the whole range.
    private static let consolidateLine = "Copies sources into the package"

    /// The whole sentence, kept as the tooltip on the button and on the line
    /// so the short version is never the only thing said.
    private static let consolidateNote = "Copies every referenced file into this project's package."

    /// A machine-face caption — the ⇧⌘I hint, the item count, the footer's
    /// one-liner. `InspectorRowLabel` is the shared label; only its face
    /// changes, so the pane does not grow a label class of its own.
    private static func caption(_ text: String, font: NSFont = DS.mono(10)) -> InspectorRowLabel {
        let label = InspectorRowLabel(text)
        label.font = font
        label.textColor = DS.textFaint
        return label
    }

    /// The stretchy gap that pushes a bar's trailing cluster out — the same
    /// low-hugging filler `inspectorRow` uses.
    private static func spacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        view.setContentCompressionResistancePriority(
            NSLayoutConstraint.Priority(1), for: .horizontal)
        return view
    }

    /// One of the pane's two chrome bands, drawn EDGE TO EDGE.
    ///
    /// **Pitfall:** a `BarView` fills `DS.chromeBackground`, which is exactly
    /// what `InspectorViewController` paints the panel with — so the band
    /// itself is invisible and its 1 pt hairline is the whole of it. And a
    /// section's rows are inset by `InspectorMetrics.inset`, so that hairline
    /// stopped 10 pt short at each end and read as a floating stub rather than
    /// a rule; the 38 pt action row and the 40 pt footer were structurally
    /// there and visually absent.
    ///
    /// The fix keeps `BarView` and overhangs the inset instead: the bar is a
    /// subview of the section row pinned 10 pt PAST each side, and the content
    /// stack takes those 10 pt back as padding, so the rule spans the panel
    /// while the controls stay on the panel's gutter — the mock's own
    /// arrangement (a band with `padding: 0 10px`). The alternative was to
    /// inset the section's rows less, and the section shell is shared with
    /// every other pane, so it is not this one's to change.
    ///
    /// The overhang is legal because nothing between the row and the pane
    /// clips to its bounds — measured by rendering the same hierarchy
    /// offscreen (layer-backed root → scroll view → pane stack → section
    /// stack → row), where the bar paints the full panel width.
    private static func bar(height: CGFloat, border: BarView.Border, views: [NSView]) -> NSView {
        bar(height: height, border: border, lines: [views])
    }

    /// The same band with more than one LINE of controls in it — phase 8c's
    /// find band, which needs two.
    ///
    /// One band rather than two stacked ones: two would each carry a hairline
    /// and each take one of the section's 7 pt row gaps, which is 15 pt of
    /// chrome and a second rule for no extra meaning. A single line is still
    /// built exactly as it was — the horizontal stack IS the content, with no
    /// wrapper around it — so the two existing bands are laid out to the pixel
    /// they always were.
    private static func bar(
        height: CGFloat, border: BarView.Border, lines: [[NSView]]
    ) -> NSView {
        let row = NSView()
        let bar = BarView(border: border)
        bar.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(bar)
        let rows = lines.map { views -> NSStackView in
            let line = NSStackView(views: views)
            line.orientation = .horizontal
            line.alignment = .centerY
            line.spacing = 8
            return line
        }
        let stack: NSView
        if rows.count == 1 {
            stack = rows[0]
        } else {
            let column = NSStackView(views: rows)
            column.orientation = .vertical
            column.alignment = .leading
            column.spacing = 6
            // Each line spans the band, so a spacer on any of them pushes to
            // the same trailing edge and a flexible field on another fills the
            // same width.
            for line in rows {
                line.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
            }
            stack = column
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)
        let inset = InspectorMetrics.inset
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: height),
            bar.topAnchor.constraint(equalTo: row.topAnchor),
            bar.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            bar.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: -inset),
            bar.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: inset),
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -inset),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        return row
    }

    /// Thumbnails and waveforms land after the import returns
    /// (`MediaImporter` posts repeatedly as they arrive), so this only marks
    /// the rows dirty — never a rebuild.
    @objc private func cacheChanged(_ note: Notification) {
        for row in rows { row.view.invalidateThumbnail() }
    }

    // MARK: - Finder drops

    private func droppedURLs(_ sender: any NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options)
        return (urls as? [URL]) ?? []
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        droppedURLs(sender).isEmpty ? [] : .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        droppedURLs(sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = droppedURLs(sender)
        guard !urls.isEmpty else { return false }
        inspector?.onImportFiles?(urls)
        return true
    }
}
