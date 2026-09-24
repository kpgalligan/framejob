// Road map 9, phase 3a — the row marks' probe (`clip_inspector3_proof.py`
// builds and runs it).
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own
// `main.swift`, module `Reelcut`, against `libreelcut_core.a` —
// `tools/proof/harness/build.sh`'s swiftc line — so every row drives the
// app's own `ProjectDocument`, `InspectorViewController`, `ClipPane`,
// `InspectorSection` and `InspectorMarkGutter`. Nothing private is widened:
// a row is found by what it HOLDS (its label's text, its section's id), and
// a header's click is its `onToggle`, which is what `mouseDown` calls.
//
//   clip_inspector3_probe <request.json> <answer.json>
//   clip_inspector3_probe --convert <png> <answer.json>
//
// `request.json` names the packages the proof wrote: `chrome` (one shape card
// of 6 s at 0 with two linear actions, id 3 at 0.5–1.5 s {video: {opacity:
// 0.5}} and id 4 at 2.5–4.0 s {video: {x: 100}}), `av` (a video with sound,
// clip 2, action 10 at 1–2 s {audio: {volume: 0.5}}), and `keyed` (a shape
// card with one half-strength blur and action 5 at 1–2 s {video: {blend:
// multiply, filters: [blur 1.0]}}). One JSON object out: `rows`, each a name,
// ok and detail. Row names start with their M-number, which is what the
// mutant mode reads.
import AppKit

// `--convert <png> <out.json>`: the three inks the harness rows look for, in
// the PNG's OWN colour space, resolved in the DARK appearance the renders use.
if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--convert" {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])),
          let rep = NSBitmapImageRep(data: data),
          let dark = NSAppearance(named: .darkAqua)
    else { exit(4) }
    var inks: [String: Any] = ["space": rep.colorSpace.localizedName ?? "?"]
    dark.performAsCurrentDrawingAppearance {
        for (name, color) in [("mint", DS.action), ("accent", DS.accent), ("coral", DS.playhead)] {
            guard let there = color.usingColorSpace(rep.colorSpace) else { continue }
            inks[name] = [there.redComponent, there.greenComponent, there.blueComponent].map {
                Double($0) * 255
            }
        }
    }
    guard let json = try? JSONSerialization.data(withJSONObject: inks) else { exit(5) }
    try? json.write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
    exit(0)
}

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()

let request = (try? JSONSerialization.jsonObject(
    with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))) as? [String: Any]
    ?? [:]
let out = URL(fileURLWithPath: CommandLine.arguments[2])
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let delegate = AppDelegate()
delegate.applicationWillFinishLaunching(
    Notification(name: NSApplication.willFinishLaunchingNotification, object: app))

var rows: [[String: Any]] = []
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    rows.append(["name": name, "ok": ok, "detail": String(detail.prefix(1200))])
}

let ticks: Ticks = 600_000
func at(_ seconds: Double) -> Ticks { Ticks(seconds * Double(ticks)) }

/// Every section key this probe pins, dropped at the start and at the end so
/// a run leaves the probe's defaults domain as it found it.
let pinnedIDs = ["video.transform", "video.shadow", "doc.canvas", "audio.volume", "audio.mix",
                 "audio.noise", "video.motion", "clip.timing", "video.filters"]
func key(_ id: String) -> String { InspectorSection.collapsedKeyPrefix + id }
func unpin() { for id in pinnedIDs { UserDefaults.standard.removeObject(forKey: key(id)) } }
unpin()
/// Every section open, so rows lay out and headers fold; M4 pins its own.
for id in pinnedIDs { UserDefaults.standard.set(false, forKey: key(id)) }

func opened(_ name: String) -> ProjectDocument? {
    guard let path = request[name] as? String else { return nil }
    let document = ProjectDocument()
    do {
        try document.read(
            from: URL(fileURLWithPath: path), ofType: "com.kgalligan.reelcut-project")
    } catch {
        check("M0 the \(name) fixture opens", false, "\(error)")
        return nil
    }
    return document
}

/// A Clip pane over a document with clip 2 selected, the playhead at
/// `seconds` and `action` selected, and no window. The pane's inspector and
/// the inspector's document are both weak, so each pair is kept.
var kept: [AnyObject] = []
func clipPane(
    _ name: String, playhead seconds: Double, action: UInt32?
) -> (ProjectDocument, InspectorViewController, ClipPane)? {
    guard let document = opened(name) else { return nil }
    let inspector = InspectorViewController()
    inspector.document = document
    document.selection = [2]
    document.playhead = at(seconds)
    document.selectAction(action)
    inspector.binding.invalidate()
    kept += [document, inspector]
    return (document, inspector, ClipPane(inspector: inspector))
}

func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }

func sections(_ pane: ClipPane, _ tab: ClipSubTab) -> [InspectorSection] {
    pane.choose(tab)
    pane.rebuild()
    pane.refresh()
    return pane.sections
}

func section(_ list: [InspectorSection], _ id: String) -> InspectorSection? {
    list.first { $0.id == id }
}

/// The gutter of the row whose label reads `label`, inside `section`.
func gutter(_ section: InspectorSection?, _ label: String) -> InspectorMarkGutter? {
    guard let section else { return nil }
    for view in walk(section) {
        guard let row = view as? NSStackView,
              let first = row.arrangedSubviews.first as? InspectorMarkGutter,
              row.arrangedSubviews.contains(where: {
                  ($0 as? InspectorRowLabel)?.stringValue == label
              })
        else { continue }
        return first
    }
    return nil
}

func gutters(_ section: InspectorSection?) -> [InspectorMarkGutter] {
    section.map { walk($0).compactMap { $0 as? InspectorMarkGutter } } ?? []
}

func describe(_ mark: RowMark?) -> String { mark.map { "\($0)" } ?? "no row" }

/// A section's PHASE-3A marks — `keyed`, `other`, `allNotAnimatable` — with
/// phase 3b's `differs` and `editing` (spec §11 CI-9) left at their
/// defaults, so M2 compares what this phase measured (2026-09-23, 3b).
func marks3a(_ marks: SectionMarks?) -> SectionMarks? {
    marks.map {
        SectionMarks(keyed: $0.keyed, other: $0.other, allNotAnimatable: $0.allNotAnimatable)
    }
}

func visibleNote(_ section: InspectorSection?, _ text: String) -> Bool {
    guard let section else { return false }
    return walk(section).contains {
        guard let label = $0 as? NSTextField else { return false }
        return label.stringValue == text && !label.isHidden
    }
}

let inertText = "Actions don't animate this. Edits here change the clip."

// MARK: - M1 marks per row, M2 header marks, M5 three read times, M6 the count

if let (document, inspector, pane) = clipPane("chrome", playhead: 1.0, action: 3) {
    let picture = sections(pane, .picture)
    let transform = section(picture, "video.transform")
    let opacity = gutter(transform, "Opacity")?.mark
    check("M1 chrome, action 1 selected: Opacity is ◆ (keyed)", opacity == .keyed,
          describe(opacity))
    let x = gutter(transform, "Position X")?.mark
    check("M1 … Position X is ◇ naming action 2", x == .other(2), describe(x))
    let blend = gutter(transform, "Blend")?.mark
    check("M1 … Blend is blank (.none)", blend == RowMark.none, describe(blend))
    let marks = transform?.marks
    check("M2 Transform's header: ◆1 and ◇, not ⊘",
          marks3a(marks) == SectionMarks(keyed: 1, other: true, allNotAnimatable: false),
          "\(marks.map { "\($0)" } ?? "no section")")
    let count = document.selectedActionSnapshot.map { ClipSubTab.picture.keyedCount(in: $0.end) }
    check("M6 Transform's marks.keyed equals the Picture sub-tab's ◆N (\(count ?? -1))",
          marks?.keyed == count && count == 1, "section \(marks?.keyed ?? -1)")
    let shadow = section(picture, "video.shadow")?.marks
    check("M2 Shadow's header: nothing", marks3a(shadow) == .empty,
          "\(shadow.map { "\($0)" } ?? "no section")")

    let clip = sections(pane, .clip)
    let motion = section(clip, "video.motion")
    let writing = gutters(motion).filter { !$0.writes.isEmpty }
    check("M1 … every Motion presets row that writes is ⊘ (at least In, Out, During)",
          writing.count >= 3 && writing.allSatisfy { $0.mark == .notAnimatable },
          writing.map { "\($0.writes) \($0.mark)" }.joined(separator: "; "))
    check("M2 Motion presets' header is ⊘ and its note is showing",
          motion?.marks.allNotAnimatable == true && visibleNote(motion, inertText),
          "\(motion.map { "\($0.marks)" } ?? "no section")")
    let timing = section(clip, "clip.timing")
    let duration = gutter(timing, "Duration")?.mark
    check("M1 … Timing's Duration readout is blank (.none) with an action selected",
          duration == RowMark.none, describe(duration))
    check("M2 Timing carries no ⊘ note",
          timing?.marks.allNotAnimatable == false && !visibleNote(timing, inertText),
          "\(timing.map { "\($0.marks)" } ?? "no section")")

    let binding = inspector.binding
    binding.invalidate()
    let start = binding.at(.start) { binding.videoProps.opacity }
    let end = binding.at(.end) { binding.videoProps.opacity }
    let now = binding.at(.playhead) { binding.videoProps.opacity }
    check("M5 opacity at(.start) 1.0, at(.end) 0.5, at(.playhead) 0.75 at 1.0 s",
          abs(start - 1) < 1e-6 && abs(end - 0.5) < 1e-6 && abs(now - 0.75) < 1e-6
            && binding.mode == .end,
          "start \(start), end \(end), playhead \(now), mode after \(binding.mode)")
}

if let (_, _, pane) = clipPane("av", playhead: 1.5, action: 10) {
    let sound = sections(pane, .sound)
    let volume = gutter(section(sound, "audio.volume"), "Volume")?.mark
    check("M1 av, action 1 selected: Volume is ◆", volume == .keyed, describe(volume))
    let gain = gutter(section(sound, "audio.volume"), "Gain")?.mark
    check("M1 … Gain is ○ (follows Volume)", gain == .follows, describe(gain))
    let pan = gutter(section(sound, "audio.mix"), "Pan")?.mark
    check("M1 … Pan is ⊘ (the clip's, spec §11 CI-3)", pan == .notAnimatable, describe(pan))
    let depth = gutter(section(sound, "audio.noise"), "Depth")?.mark
    check("M1 … Depth, a readout, is blank (.none)", depth == RowMark.none, describe(depth))
}

// MARK: - M1 the filter row, M3 "at end"

if let (_, _, pane) = clipPane("keyed", playhead: 1.5, action: 5) {
    let picture = sections(pane, .picture)
    let filters = section(picture, "video.filters")
    let row = gutters(filters).first
    check("M1 keyed: the filter row (its popups, discrete) is ◆ at end when the action keys "
            + "filters",
          row?.mark == .keyedAtEnd && row?.writes == ["video.filters"],
          "\(row.map { "\($0.writes) \($0.mark)" } ?? "no row")")
    let transform = section(picture, "video.transform")
    let blend = gutter(transform, "Blend")
    let tag = blend?.superview.map { walk($0).compactMap { $0 as? InspectorRowTag } }?.first
    check("M3 a keyed Blend is ◆ with its \"at end\" tag showing",
          blend?.mark == .keyedAtEnd && tag?.stringValue == "at end" && tag?.isHidden == false,
          "\(describe(blend?.mark)), tag \(tag.map { "'\($0.stringValue)' hidden \($0.isHidden)" } ?? "none")")
    let opacity = gutter(transform, "Opacity")
    let quiet = opacity?.superview.map { walk($0).compactMap { $0 as? InspectorRowTag } } ?? []
    check("M3 … and an unkeyed Opacity's tags are all hidden",
          opacity?.mark == RowMark.none && !quiet.isEmpty && quiet.allSatisfy { $0.isHidden },
          "\(describe(opacity?.mark)), \(quiet.count) tag(s)")
}

// MARK: - M4 auto-open

if let (document, inspector, pane) = clipPane("chrome", playhead: 1.0, action: 3) {
    UserDefaults.standard.set(true, forKey: key("video.transform"))
    UserDefaults.standard.set(true, forKey: key("video.shadow"))
    func picture() -> [InspectorSection] {
        inspector.binding.invalidate()
        return sections(pane, .picture)
    }
    func stored() -> Bool? { UserDefaults.standard.object(forKey: key("video.transform")) as? Bool }
    var list = picture()
    check("M4a collapsed keys pinned: the keyed Transform opens, its key still true, the "
            + "unkeyed Shadow stays shut",
          section(list, "video.transform")?.isExpanded == true && stored() == true
            && section(list, "video.shadow")?.isExpanded == false,
          "transform \(section(list, "video.transform")?.isExpanded ?? false), key "
            + "\(stored().map { "\($0)" } ?? "nil"), shadow "
            + "\(section(list, "video.shadow")?.isExpanded ?? true)")

    let before = pane.structureSignature
    document.applyEdit(
        "Add Filter", inspector.binding.ops(video: VideoPatch(filters: [FilterProps()])))
    list = picture()
    check("M4b a filter added under the same action rebuilds, and Transform stays open",
          pane.structureSignature != before && document.selectedAction == 3
            && section(list, "video.transform")?.isExpanded == true,
          "signature changed \(pane.structureSignature != before), action "
            + "\(document.selectedAction.map { "\($0)" } ?? "nil")")

    let header = section(list, "video.transform").map {
        walk($0).compactMap { $0 as? InspectorSectionHeader }.first
    } ?? nil
    header?.onToggle?()
    let closed = section(list, "video.transform")?.isExpanded == false
    list = picture()
    check("M4c the header's click closes it, and a further rebuild keeps it closed",
          header != nil && closed && section(list, "video.transform")?.isExpanded == false,
          "header \(header != nil), closed \(closed), after rebuild "
            + "\(section(list, "video.transform")?.isExpanded ?? true)")

    document.selectAction(nil)
    list = picture()
    let away = section(list, "video.transform")?.isExpanded == false
    document.selectAction(3)
    list = picture()
    check("M4d deselect, then select the action again: Transform opens again",
          away && section(list, "video.transform")?.isExpanded == true,
          "deselected open \(!away), reselected "
            + "\(section(list, "video.transform")?.isExpanded ?? false)")
}

// MARK: - M7 the Document tab's rows moved by exactly the gutter

if let (_, inspector, _) = clipPane("chrome", playhead: 5, action: nil) {
    let pane = DocumentPane(inspector: inspector)
    let host = NSView(frame: NSRect(x: 0, y: 0, width: 304, height: 2000))
    pane.translatesAutoresizingMaskIntoConstraints = false
    host.addSubview(pane)
    NSLayoutConstraint.activate([
        pane.topAnchor.constraint(equalTo: host.topAnchor),
        pane.leadingAnchor.constraint(equalTo: host.leadingAnchor),
        pane.widthAnchor.constraint(equalTo: host.widthAnchor),
    ])
    pane.rebuild()
    pane.refresh()
    host.layoutSubtreeIfNeeded()
    let canvas = pane.sections.first { $0.id == "doc.canvas" }
    let preset = gutter(canvas, "Preset")
    let row = preset?.superview as? NSStackView
    let popup = row?.arrangedSubviews.first { $0 is OptionPopupControl }
    let x = popup?.frame.minX ?? -1
    // Phase 2's column: the 76 pt label and the row's 6 pt spacing.
    let phase2 = InspectorMetrics.labelWidth + 6
    check("M7 Document ▸ Canvas ▸ Preset: the popup sits at \(phase2 + 14) pt, exactly 14 pt "
            + "right of phase 2's \(phase2), and its gutter is blank",
          abs(x - (phase2 + InspectorMetrics.markGutter)) < 0.01 && preset?.mark == RowMark.none
            && preset?.frame.width == InspectorMetrics.markGutter,
          "popup x \(x), gutter \(describe(preset?.mark)) \(preset?.frame.width ?? -1) pt wide")
    let check2 = canvas.map { walk($0).compactMap { $0 as? OptionCheckboxControl }.first } ?? nil
    let bare = check2?.frame.minX ?? -1
    check("M7 … an unlabelled row's checkbox sits at 14 pt (phase 2: 0)",
          abs(bare - InspectorMetrics.markGutter) < 0.01, "checkbox x \(bare)")
}

unpin()
let answer: [String: Any] = ["rows": rows]
if let data = try? JSONSerialization.data(
    withJSONObject: answer, options: [.prettyPrinted, .sortedKeys])
{
    try? data.write(to: out)
}
exit(0)
