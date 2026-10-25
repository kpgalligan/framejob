import AppKit

/// The Clip tab's TEXT sections (spec §4.3): content, face, colour,
/// alignment, spacing, outline, backdrop, the box mode, how the words arrive
/// and leave, and the four presets.
///
/// **This pane is never shown**: since the six tabs became three it is a
/// factory `ClipPane` holds and calls, right after Transform, when EVERY
/// selected clip is a text clip. Shadow is not in the list any more — it is
/// one field (`video.shadow`) shared with the video and shape sections, so the
/// Clip tab carries it once, in the effects group.
///
/// The model stores ONE font string — a PostScript name (§5.2's
/// `"SourceSans3-SemiBold"`) — while the panel offers the two popups people
/// expect, family and style. `TextFace` is the whole translation between
/// them, and it is deliberately tolerant: a project made on another machine
/// can name a face this one does not have, and the pane must still open.
final class TextPane: InspectorPaneView {
    /// Whether the text sections apply: they write `set_text`, which errors on
    /// any other kind, so a mixed selection gets none of them.
    var allText: Bool {
        !binding.clips.isEmpty && binding.textClips.count == binding.clips.count
    }

    /// A family change replaces the style popup's ITEMS, so it has to be part
    /// of the rebuild signature — refreshing alone would leave the old
    /// family's styles listed.
    override var structureSignature: String {
        super.structureSignature + "|" + TextFace.family(of: binding.textProps.font)
    }

    // MARK: Content

    /// The footnote on a word-styled page whose timings a content edit
    /// dropped (road map 8 §5e), and the Animation section's on a styled
    /// page, whose reveal the word style replaces (spec §11 W-5). The second
    /// is short on purpose: its row is 244 pt at the 280 pt narrowest
    /// inspector (`DocumentPane.transparencyNote` has the arithmetic, #70).
    static let untimedNote = "Not timed — regenerate to time it again"
    static let wordStyleNote = "Word style wins; the reveal does not apply."

    func contentSection() -> InspectorSection {
        let binding = self.binding
        let area = InspectorTextArea(
            read: { binding.textProps.content },
            // Per clip: a timed page keeps its words while the count holds
            // and sends `words: []` beside the content when it does not.
            write: { value in binding.apply("Edit Text", binding.ops(textContent: value)) },
            enabled: { !binding.textClips.isEmpty },
            onEdit: { binding.edited() })
        return InspectorSection(
            id: "text.content", title: "Content",
            summary: {
                let line = binding.textProps.content
                    .split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
                return line.isEmpty ? "empty" : line
            },
            note: {
                binding.textProps.isUntimedPage ? Self.untimedNote : nil
            },
            rows: [inspectorRow(nil, [area], binding: binding,
                                writes: binding.ops(textContent: binding.textProps.content),
                                discrete: true)])
    }

    // MARK: Face

    func fontSection() -> InspectorSection {
        let binding = self.binding
        let families = TextFace.families
        let family = TextFace.family(of: binding.textProps.font)
        let members = TextFace.members(of: family)
        let font = binding.ops(text: TextPatch(font: binding.textProps.font))

        let familyPopup = OptionPopupControl(
            width: 150, items: families,
            read: { families.firstIndex(of: TextFace.family(of: binding.textProps.font)) ?? 0 },
            write: { index in
                guard families.indices.contains(index) else { return }
                let current = binding.textProps.font
                let name = TextFace.postScriptName(
                    family: families[index], style: TextFace.style(of: current))
                binding.apply("Font", text: TextPatch(font: name))
            },
            enabled: { true },
            onEdit: { binding.edited() })

        let stylePopup = OptionPopupControl(
            width: 116, items: members.map { $0.style },
            read: {
                let name = binding.textProps.font
                return members.firstIndex { $0.name == name } ?? 0
            },
            write: { index in
                guard members.indices.contains(index) else { return }
                binding.apply("Font", text: TextPatch(font: members[index].name))
            },
            enabled: { !members.isEmpty },
            onEdit: { binding.edited() })

        return InspectorSection(
            id: "text.font", title: "Font",
            summary: { String(format: "%.0f px", binding.textProps.size) },
            defaultExpanded: false,
            rows: [
                inspectorRow(
                    "Family", [familyPopup], mixed: { binding.mixedText { $0.font } },
                    binding: binding, writes: font),
                inspectorRow("Style", [stylePopup], binding: binding, writes: font),
                inspectorValueRow(
                    "Size", binding, name: "Font Size", unit: " px", decimals: 0, min: 6,
                    max: 800, quick: [24, 36, 48, 72, 96, 144], slider: false,
                    read: { binding.textProps.size },
                    ops: { binding.ops(text: TextPatch(size: $0)) },
                    mixed: { binding.mixedText { $0.size } }),
            ])
    }

    // MARK: Style

    func styleSection() -> InspectorSection {
        let binding = self.binding
        let aligns = ["left", "center", "right"]
        let valigns = ["top", "middle", "bottom"]
        let text = binding.textProps
        let align = OptionSegmentedControl(
            segments: [
                ("text.alignleft", "L", "Align left"),
                ("text.aligncenter", "C", "Align center"),
                ("text.alignright", "R", "Align right"),
            ],
            read: { aligns.firstIndex(of: binding.textProps.align) ?? 1 },
            write: { index in
                guard aligns.indices.contains(index) else { return }
                binding.apply("Alignment", text: TextPatch(align: aligns[index]))
            },
            segmentEnabled: nil, enabled: { true },
            onEdit: { binding.edited() })
        let valign = OptionSegmentedControl(
            segments: [
                ("align.vertical.top", "⤒", "Align to the top of the box"),
                ("align.vertical.center", "↕", "Center in the box"),
                ("align.vertical.bottom", "⤓", "Align to the bottom of the box"),
            ],
            read: { valigns.firstIndex(of: binding.textProps.valign) ?? 1 },
            write: { index in
                guard valigns.indices.contains(index) else { return }
                binding.apply("Alignment", text: TextPatch(valign: valigns[index]))
            },
            segmentEnabled: nil, enabled: { true },
            onEdit: { binding.edited() })

        return InspectorSection(
            id: "text.style", title: "Style",
            summary: { binding.textProps.align },
            reset: {
                let defaults = TextProps()
                binding.apply(
                    "Text Style",
                    text: TextPatch(
                        color: defaults.color, align: defaults.align, valign: defaults.valign,
                        lineSpacing: defaults.lineSpacing, tracking: defaults.tracking,
                        textCase: defaults.textCase))
            },
            defaultExpanded: false,
            rows: [
                inspectorColorRow(
                    "Color", binding, name: "Text Color", read: { binding.textProps.color },
                    ops: { binding.ops(text: TextPatch(color: $0)) },
                    mixed: { binding.mixedText { $0.color } }),
                inspectorRow("Align", [align], mixed: { binding.mixedText { $0.align } },
                    binding: binding, writes: binding.ops(text: TextPatch(align: text.align)),
                    default: .derived(binding, name: "Alignment", read: { binding.textProps.align },
                                      ops: { binding.ops(text: TextPatch(align: $0)) })),
                inspectorRow("Vertical", [valign], mixed: { binding.mixedText { $0.valign } },
                    binding: binding, writes: binding.ops(text: TextPatch(valign: text.valign)),
                    default: .derived(
                        binding, name: "Alignment", read: { binding.textProps.valign },
                        ops: { binding.ops(text: TextPatch(valign: $0)) })),
                inspectorCheckRow(
                    "UPPERCASE", binding, name: "Case",
                    read: { binding.textProps.textCase == .upper },
                    ops: { binding.ops(text: TextPatch(textCase: $0 ? .upper : .asWritten)) },
                    mixed: { binding.mixedText { $0.textCase } }),
                inspectorValueRow(
                    "Line spacing", binding, name: "Line Spacing", unit: "×", decimals: 2,
                    min: 0.5, max: 4,
                    read: { binding.textProps.lineSpacing },
                    ops: { binding.ops(text: TextPatch(lineSpacing: $0)) },
                    mixed: { binding.mixedText { $0.lineSpacing } }),
                inspectorValueRow(
                    "Tracking", binding, name: "Tracking", unit: " px", decimals: 1, min: -20,
                    max: 100,
                    read: { binding.textProps.tracking },
                    ops: { binding.ops(text: TextPatch(tracking: $0)) },
                    mixed: { binding.mixedText { $0.tracking } }),
            ])
    }

    // MARK: Outline

    func outlineSection() -> InspectorSection {
        let binding = self.binding
        func current() -> OutlineProps { binding.textProps.outline ?? OutlineProps() }
        func on() -> Bool { binding.textProps.outline != nil }
        return InspectorSection(
            id: "text.outline", title: "Outline",
            summary: { on() ? String(format: "%.1f px", current().width) : "off" },
            reset: { binding.apply("Outline", text: TextPatch(outline: .some(nil))) },
            defaultExpanded: false,
            rows: [
                inspectorCheckRow(
                    "Outline", binding, name: "Outline", read: on,
                    ops: { value in
                        binding.ops(
                            text: TextPatch(outline: value ? .some(OutlineProps()) : .some(nil)))
                    },
                    mixed: { binding.mixedText { $0.outline != nil } }),
                inspectorValueRow(
                    "Width", binding, name: "Outline Width", unit: " px", decimals: 1, min: 0,
                    max: 40, quick: [1, 2, 4, 8],
                    read: { current().width },
                    ops: { value in
                        var o = current()
                        o.width = value
                        return binding.ops(text: TextPatch(outline: .some(o)))
                    },
                    mixed: { binding.mixedText { $0.outline?.width } },
                    enabled: on),
                inspectorColorRow(
                    "Color", binding, name: "Outline Color", read: { current().color },
                    ops: { color in
                        var o = current()
                        o.color = color
                        return binding.ops(text: TextPatch(outline: .some(o)))
                    },
                    mixed: { binding.mixedText { $0.outline?.color } },
                    enabled: on),
            ])
    }

    // MARK: Backdrop

    func backdropSection() -> InspectorSection {
        let binding = self.binding
        func current() -> BackdropProps { binding.textProps.backdrop ?? BackdropProps() }
        func on() -> Bool { binding.textProps.backdrop != nil }
        func ops(_ next: BackdropProps) -> [ReelOp] {
            binding.ops(text: TextPatch(backdrop: .some(next)))
        }
        return InspectorSection(
            id: "text.backdrop", title: "Backdrop",
            summary: { on() ? String(format: "%.0f px", current().padding) : "off" },
            reset: { binding.apply("Backdrop", text: TextPatch(backdrop: .some(nil))) },
            defaultExpanded: false,
            rows: [
                inspectorCheckRow(
                    "Backdrop", binding, name: "Backdrop", read: on,
                    ops: { value in
                        binding.ops(
                            text: TextPatch(backdrop: value ? .some(BackdropProps()) : .some(nil)))
                    },
                    mixed: { binding.mixedText { $0.backdrop != nil } }),
                inspectorColorRow(
                    "Fill", binding, name: "Backdrop Color", read: { current().color },
                    ops: { color in
                        var b = current()
                        b.color = color
                        return ops(b)
                    },
                    mixed: { binding.mixedText { $0.backdrop?.color } },
                    enabled: on),
                inspectorValueRow(
                    "Padding", binding, name: "Backdrop Padding", unit: " px", decimals: 0,
                    min: 0, max: 200, quick: [0, 8, 12, 24, 48],
                    read: { current().padding },
                    ops: { value in
                        var b = current()
                        b.padding = value
                        return ops(b)
                    },
                    mixed: { binding.mixedText { $0.backdrop?.padding } },
                    enabled: on),
                inspectorValueRow(
                    "Radius", binding, name: "Backdrop Radius", unit: " px", decimals: 0, min: 0,
                    max: 200, quick: [0, 4, 8, 16, 32],
                    read: { current().radius },
                    ops: { value in
                        var b = current()
                        b.radius = value
                        return ops(b)
                    },
                    mixed: { binding.mixedText { $0.backdrop?.radius } },
                    enabled: on),
            ])
    }

    // MARK: Box

    /// Auto-size or a fixed width that wraps (§4.3). `width` is the model's
    /// three-state field: an explicit null restores auto-sizing, which is why
    /// the patch uses the double optional.
    func boxSection() -> InspectorSection {
        let binding = self.binding
        func fixed() -> Bool { binding.textProps.width != nil }
        func currentWidth() -> Double {
            binding.textProps.width ?? Double(binding.canvas.width) * 0.6
        }
        let mode = OptionPopupControl(
            width: 132, items: ["Auto-size", "Fixed width"],
            read: { fixed() ? 1 : 0 },
            write: { index in
                let patch = TextPatch(width: index == 1 ? .some(currentWidth()) : .some(nil))
                binding.apply("Text Box", text: patch)
            },
            enabled: { true },
            onEdit: { binding.edited() })
        return InspectorSection(
            id: "text.box", title: "Box",
            summary: { fixed() ? String(format: "%.0f px", currentWidth()) : "auto" },
            reset: { binding.apply("Text Box", text: TextPatch(width: .some(nil))) },
            defaultExpanded: false,
            rows: [
                inspectorRow("Mode", [mode], mixed: { binding.mixedText { $0.width != nil } },
                    binding: binding,
                    writes: binding.ops(text: TextPatch(width: .some(binding.textProps.width))),
                    default: .derived(binding, name: "Text Box", read: { binding.textProps.width },
                                      ops: { binding.ops(text: TextPatch(width: .some($0))) })),
                inspectorValueRow(
                    "Width", binding, name: "Text Width", unit: " px", decimals: 0, min: 20,
                    max: 20000, slider: false,
                    read: currentWidth,
                    ops: { binding.ops(text: TextPatch(width: .some($0))) },
                    mixed: { binding.mixedText { $0.width } },
                    enabled: fixed, resets: false),
            ])
    }

    // MARK: Animation

    /// How the words arrive and how they leave (§4.3, format version 5).
    ///
    /// Three controls for three keys: which reveal, how long it takes to
    /// arrive, and how long it takes to leave. The core turns them into one
    /// number per frame — nothing here draws or times anything, and the
    /// section cannot show the reveal's progress, because the progress is a
    /// fact about the frame under the playhead and not about the clip.
    ///
    /// `animation` is a whole OBJECT in the patch, so every row re-sends all
    /// three keys. The core MERGES a nested object key by key (§5.2), but a
    /// stored `null` is not an object — turning the reveal ON replaces the
    /// null with what this patch carries, and a key left out would then come
    /// from the struct's default and silently reset what the user did not
    /// touch. A section that knows all three keys is right in both cases.
    /// Turning the popup to None sends an explicit null, which is the
    /// model's "no animation".
    ///
    /// One thing worth knowing before animating this section from an action:
    /// `in` and `out` are numbers, so an action END patch would interpolate
    /// them and slide the animation's own timebase mid-reveal. The kind is a
    /// string and switches at the end, which is the sane half.
    func animationSection() -> InspectorSection {
        let binding = self.binding
        let kinds = TextAnimationKind.allCases
        let items = ["None"] + kinds.map { $0.displayName }
        func current() -> TextAnimation { binding.textProps.animation ?? TextAnimation() }
        func on() -> Bool { binding.textProps.animation != nil }
        func free() -> Bool { binding.textProps.wordStyle == nil }
        func ops(_ next: TextAnimation) -> [ReelOp] {
            binding.ops(text: TextPatch(animation: .some(next)))
        }
        return InspectorSection(
            id: "text.animation", title: "Reveal",
            summary: {
                guard let animation = binding.textProps.animation else { return "off" }
                return animation.kind.displayName.lowercased()
                    + String(format: " · %.2f s", ReelTime.seconds(animation.inDuration))
            },
            note: { free() ? nil : Self.wordStyleNote },
            reset: { binding.apply("Animation", text: TextPatch(animation: .some(nil))) },
            defaultExpanded: false,
            rows: [
                inspectorPopupRow(
                    "Reveal", binding, name: "Text Animation", items: items,
                    read: {
                        guard let kind = binding.textProps.animation?.kind else { return 0 }
                        return (kinds.firstIndex(of: kind) ?? 0) + 1
                    },
                    ops: { index in
                        guard index > 0, kinds.indices.contains(index - 1) else {
                            return binding.ops(text: TextPatch(animation: .some(nil)))
                        }
                        // The durations as they stand: switching the reveal
                        // must not reset the timing the user chose for it.
                        var a = current()
                        a.kind = kinds[index - 1]
                        return ops(a)
                    },
                    mixed: { binding.mixedText { $0.animation?.kind } }, enabled: free),
                inspectorValueRow(
                    "In", binding, name: "Animation In", unit: " s", decimals: 2, min: 0, max: 10,
                    quick: [0, 0.25, 0.5, 1, 2],
                    read: { ReelTime.seconds(current().inDuration) },
                    ops: { value in
                        var a = current()
                        a.inDuration = binding.frameTicks(seconds: value)
                        return ops(a)
                    },
                    mixed: { binding.mixedText { $0.animation?.inDuration } },
                    enabled: { on() && free() }),
                inspectorValueRow(
                    "Out", binding, name: "Animation Out", unit: " s", decimals: 2, min: 0,
                    max: 10, quick: [0, 0.25, 0.5, 1, 2],
                    read: { ReelTime.seconds(current().outDuration) },
                    ops: { value in
                        var a = current()
                        a.outDuration = binding.frameTicks(seconds: value)
                        return ops(a)
                    },
                    mixed: { binding.mixedText { $0.animation?.outDuration } },
                    enabled: { on() && free() }),
            ])
    }

    // MARK: Presets

    /// The four one-click looks of §4.3. A preset is two patches — the face
    /// and backdrop (text) plus where the box sits (video) — committed as ONE
    /// undo step, and it routes through the binding like everything else, so
    /// applying one inside an action sets that action's end state.
    func presetSection() -> InspectorSection {
        var buttons: [NSView] = []
        for preset in TextPreset.all {
            buttons.append(
                OptionButtonControl(
                    title: preset.name,
                    action: { [weak self] in self?.apply(preset) },
                    enabled: { true }, onEdit: {}))
        }
        return InspectorSection(
            id: "text.presets", title: "Presets",
            defaultExpanded: false,
            rows: [
                inspectorButtonRow(Array(buttons.prefix(2))),
                inspectorButtonRow(Array(buttons.dropFirst(2))),
            ])
    }

    private func apply(_ preset: TextPreset) {
        let canvas = binding.canvas
        let height = Double(canvas.height)
        let text = TextPatch(
            font: preset.font, size: (height * preset.sizeFraction).rounded(),
            align: preset.align, valign: "middle",
            backdrop: .some(preset.backdrop))
        let video = VideoPatch(
            x: preset.xFraction * Double(canvas.width), y: preset.yFraction * height, opacity: 1)
        binding.apply(preset.name, binding.ops(text: text) + binding.ops(video: video))
    }
}

// MARK: - Presets

/// One text preset (§4.3). Sizes and positions are FRACTIONS of the canvas so
/// a preset means the same thing on a 4K canvas as on a vertical one.
struct TextPreset {
    let name: String
    let font: String
    let sizeFraction: Double
    let xFraction: Double
    let yFraction: Double
    let align: String
    let backdrop: BackdropProps?

    static let all: [TextPreset] = [
        TextPreset(
            name: "Title", font: "SourceSans3-Bold", sizeFraction: 0.09, xFraction: 0,
            yFraction: 0, align: "center", backdrop: nil),
        TextPreset(
            name: "Subtitle", font: "SourceSans3-SemiBold", sizeFraction: 0.05, xFraction: 0,
            yFraction: 0.18, align: "center", backdrop: nil),
        TextPreset(
            name: "Lower Third", font: "SourceSans3-SemiBold", sizeFraction: 0.045,
            xFraction: -0.2, yFraction: 0.28, align: "left",
            backdrop: BackdropProps(color: [0, 0, 0, 0.55], padding: 18, radius: 6)),
        TextPreset(
            name: "Caption", font: "SourceSans3-Regular", sizeFraction: 0.035, xFraction: 0,
            yFraction: 0.38, align: "center",
            backdrop: BackdropProps(color: [0, 0, 0, 0.6], padding: 12, radius: 8)),
    ]
}

// MARK: - Faces

/// The model's one font string ↔ the panel's family + style pair.
///
/// Everything here tolerates a name this machine has no font for: a project
/// carries PostScript names, and the Text tab still has to open (and still has
/// to be able to change the face) on a machine missing that family.
enum TextFace {
    /// Installed families, sorted. Read once — `availableFontFamilies` walks
    /// the font registry, and this popup is rebuilt on every selection change.
    static let families: [String] = NSFontManager.shared.availableFontFamilies.sorted()

    /// One member of a family: its PostScript name and the style label.
    struct Member {
        let name: String
        let style: String
    }

    static func members(of family: String) -> [Member] {
        let raw = NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []
        return raw.compactMap { entry in
            guard entry.count >= 2, let name = entry[0] as? String,
                  let style = entry[1] as? String
            else { return nil }
            return Member(name: name, style: style)
        }
    }

    /// The family a stored PostScript name belongs to; the first installed
    /// family when the font is missing, so the popup always has a row.
    static func family(of postScriptName: String) -> String {
        if let font = NSFont(name: postScriptName, size: 12), let family = font.familyName {
            return family
        }
        return families.first ?? "Helvetica"
    }

    /// The style label of a stored name ("SemiBold"), or "Regular".
    static func style(of postScriptName: String) -> String {
        let family = family(of: postScriptName)
        return members(of: family).first { $0.name == postScriptName }?.style ?? "Regular"
    }

    /// The PostScript name for a family plus a style label, keeping the style
    /// across a family change when the new family has one by that name.
    static func postScriptName(family: String, style: String) -> String {
        let list = members(of: family)
        if let match = list.first(where: { $0.style == style }) { return match.name }
        if let regular = list.first(where: { $0.style == "Regular" }) { return regular.name }
        return list.first?.name ?? family
    }
}
