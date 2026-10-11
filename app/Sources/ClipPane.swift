import AppKit

/// The Clip tab: a pinned block — the selection header, the action lane and
/// the sub-tabs (spec §11 CI-5) — over the sections of the ACTIVE sub-tab.
///
/// **It owns almost no controls.** The rows are the ones the Video, Audio,
/// Text and Shape panes have always built, so this pane holds one instance of
/// each — never added to any view hierarchy — and uses them purely as section
/// factories. That is safe because a pane holds no state of its own: it reads
/// and writes through the shared `InspectorBinding` this inspector handed it,
/// and the sections it makes are plain `NSView`s that keep working wherever
/// they are added. What this file adds is the header, the Timing section, and
/// `makeSections()` — the function from the selection's kind and the active
/// sub-tab to the ordered list of sections.
///
/// **Why the sections are the ones that already existed.** The handoff's table
/// draws five groups (TRANSFORM · VIDEO · AUDIO · EFFECTS · TIMING) of four or
/// five rows each, but the same document says the pane contents move "into
/// sections largely as-is" and that the work is "the shell and the
/// kind-to-sections function, not the rows". Those two readings disagree, and
/// this is the one that loses nothing: today's twenty-odd sections each carry
/// their own Reset button and their own evaluated-action note ("Editing action
/// 2's end state"), both of which are per-section by construction
/// (`InspectorSection`), and folding five of them into one VIDEO group would
/// have to throw away four Resets and four notes. So the existing sections
/// stay the unit, the Clip tab lists them all, and the section SUMMARY the
/// design asks for — plus Transform open and the rest closed — is what keeps
/// the panel readable at that length.
final class ClipPane: InspectorPaneView {
    /// The five factories. Constructed once and kept: their sections capture
    /// them (a Reset closure holds `binding`, a button holds `inspector`), and
    /// they are cheap — an `NSView` with a stack view nobody ever lays out.
    let videoPane: VideoPane
    private let audioPane: AudioPane
    private let textPane: TextPane
    private let shapePane: ShapePane
    private let graphicPane: GraphicPane
    /// The sub-tab picked by hand, if any. Forgotten by the CONTROLLER when
    /// the selection's ids change (`forgetSubTab()`), never here.
    private var chosen: ClipSubTab?
    /// The sections the selected action keys, opened once per selection (CI-8).
    private let reveal = KeyedReveal()
    /// The Look section's gallery model (spec §11 GR-7 [b]), kept here rather
    /// than in the section so its thumbnails outlive a rebuild.
    let lookGallery = LookGallery()

    override init(inspector: InspectorViewController) {
        videoPane = VideoPane(inspector: inspector)
        audioPane = AudioPane(inspector: inspector)
        textPane = TextPane(inspector: inspector)
        shapePane = ShapePane(inspector: inspector)
        graphicPane = GraphicPane(inspector: inspector)
        super.init(inspector: inspector)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ClipPane does not support NSCoder")
    }

    // MARK: - Shape of the panel

    /// The four panes' signatures, composed. Each of them knows something this
    /// one cannot see — a filter added, a text family changed, a shape kind
    /// switched — and a signature that missed any of it would leave the pane
    /// refreshed but not rebuilt, which shows up as controls that never
    /// appear.
    ///
    /// The two halves are added on top of them all, because whether the
    /// selection has PIXELS and whether it has AUDIO each add or remove a
    /// whole group of sections while every clip id stays exactly as it was.
    /// The audio half is the one that moves under an edit: `hasAudio` reads
    /// `clip.enabled.audio`, so Detach Audio and the clip menu's toggle change
    /// it (`set_enabled`, §6). The video half does NOT track that flag —
    /// `hasPixels` asks the MEDIA whether it has a video track, not the clip
    /// whether its video is on — so what moves it is a relink or a consolidate
    /// that puts different media under the clip. Both are cheap to ask and
    /// neither is visible in the four panes' own signatures.
    override var structureSignature: String {
        [
            super.structureSignature,
            videoPane.structureSignature,
            textPane.structureSignature,
            shapePane.structureSignature,
            graphicPane.structureSignature,
            audioPane.structureSignature,
            (binding.videoClips.isEmpty ? "-" : "px") + (binding.audioClips.isEmpty ? "-" : "au"),
            activeSubTab.rawValue, subTabs.map(\.rawValue).joined(separator: ","),
            matteNote == nil ? "-" : "matte",
            // Whether every clip has a look adds or removes Look's Amount row.
            videoPane.allLooked ? "look" : "-",
            // The LUTs are the Look gallery's Imported tiles (GR-8 [b]).
            LookGallery.luts(in: binding.snapshot).map { "\($0.id)=\(LookGallery.lutName($0))" }
                .joined(separator: ","),
        ].joined(separator: "|")
    }

    override func makeHeader() -> (any OptionControl)? {
        let binding = self.binding
        let strip = ClipSubTabsView(
            tabs: subTabs, active: activeSubTab,
            badge: { [videoPane] tab in
                binding.selectedAction.map {
                    tab.keyedCount(in: $0.end, adjustment: videoPane.allAdjustment)
                } ?? 0
            },
            onSelect: { [weak inspector] in inspector?.selectClipSubTab($0) })
        return ClipHeaderBlock(
            binding: binding, inspector: inspector, subTabs: strip,
            note: matteNote == nil ? nil : { [weak self] in self?.matteNote })
    }

    // MARK: - Sub-tabs

    /// The selection's tabs, in display order: Text or Shape first for those
    /// kinds, Picture for clips that draw unless an adjustment clip is among
    /// them (spec §11 GR-6: it draws nothing of its own), Color when every
    /// one of those has source pixels or is an adjustment clip (GR-2, GR-6:
    /// never text, shape, graphic, nest or an audio-only file's clip, which
    /// draws nothing), Sound for clips with audio, and Clip always, last.
    var subTabs: [ClipSubTab] {
        var tabs: [ClipSubTab] = []
        if textPane.allText { tabs.append(.text) }
        if shapePane.allShape { tabs.append(.shape) }
        if graphicPane.allGraphic { tabs.append(.graphic) }
        if !binding.videoClips.isEmpty && !videoPane.anyAdjustment { tabs.append(.picture) }
        if !binding.videoClips.isEmpty && videoPane.allGradable { tabs.append(.color) }
        if !binding.audioClips.isEmpty { tabs.append(.sound) }
        tabs.append(.clip)
        return tabs
    }

    /// The tab picked by hand while the selection has it, else the first.
    var activeSubTab: ClipSubTab {
        let tabs = subTabs
        if let chosen, tabs.contains(chosen) { return chosen }
        return tabs.first ?? .clip
    }

    /// Records a pick; triggers nothing (`selectClipSubTab` refreshes).
    func choose(_ tab: ClipSubTab) { chosen = tab }

    /// Back to the default tab; triggers nothing. The controller calls it
    /// when the selection's ids change.
    func forgetSubTab() { chosen = nil }

    // MARK: - Kind → sections

    /// The active sub-tab's sections, in the handoff's order. A section that
    /// does not apply is absent rather than disabled — the pane is rebuilt
    /// when the selection's kinds or the tab change, so there is nothing
    /// stale to grey out.
    ///
    /// Picture exists only for a selection with PIXELS: every control in it
    /// writes a `set_video` patch, and `InspectorBinding` addresses those to
    /// the clips that draw.
    override func makeSections() -> [InspectorSection] {
        let hasPixels = !binding.videoClips.isEmpty
        var sections: [InspectorSection] = []
        switch activeSubTab {
        case .text:
            sections = [
                textPane.contentSection(), textPane.fontSection(), textPane.styleSection(),
                textPane.outlineSection(), textPane.backdropSection(), textPane.boxSection(),
                textPane.animationSection(), textPane.presetSection(),
            ]
        case .shape:
            sections = [
                shapePane.shapeSection(), shapePane.strokeSection(), shapePane.fillSection(),
                // Immediately after Fill, because a gradient REPLACES a fill
                // when it is set and the two rows are read together.
                shapePane.gradientSection(), shapePane.arrowSection(),
            ]
        case .graphic:
            sections = [graphicPane.sourceSection()]
            if graphicPane.shared() != nil { sections.append(graphicPane.propertiesSection()) }
            sections.append(graphicPane.sizeSection())
            if binding.isSingle, let clip = binding.primary {
                sections.append(graphicPane.timelineSection(clip.id))
            }
        case .picture:
            sections = [videoPane.transformSection()]
            // `allSourcePixels` asks about the SOURCE KIND, so it says yes to
            // an audio-only file's clip too; the tab itself is what keeps a
            // crop off a clip that draws nothing.
            if videoPane.allSourcePixels {
                sections += [
                    videoPane.cropSection(), videoPane.cornerSection(), videoPane.chromaSection(),
                ]
            }
            // Shadow is shared by all three drawing kinds, so it is here once.
            sections += [
                inspectorShadowSection(binding), videoPane.filtersSection(),
                videoPane.reflectionSection(), videoPane.spotlightSection(),
                videoPane.obscureSection(),
            ]
        case .color:
            // Light, then the Color section Picture used to hold (GR-2), then
            // Wheels (GR-11), then Look (GR-7); Adjustment's Strength first
            // when every clip is an adjustment clip (GR-6).
            sections = [
                videoPane.lightSection(), videoPane.colorSection(), videoPane.wheelsSection(),
            ]
            if videoPane.allAdjustment { sections.insert(videoPane.adjustmentSection(), at: 0) }
            sections.append(videoPane.lookSection(lookGallery))
        case .sound:
            sections = [
                audioPane.volumeSection(), audioPane.fadeSection(), audioPane.duckSection(),
                audioPane.noiseSection(), audioPane.compressorSection(), audioPane.mixSection(),
            ]
        case .clip:
            if binding.isSingle, let clip = binding.primary {
                sections.append(timingSection(clip.id))
            } else if videoPane.allMedia {
                // The half of Timing a MULTI-clip selection can still answer
                // for: Reverse is a per-clip op that fans out happily, where
                // In, Out and Duration genuinely need one clip.
                sections.append(reverseTimingSection())
            }
            if videoPane.allMedia {
                sections.append(videoPane.speedSection())
            }
            if binding.isSingle, let clip = binding.primary,
               videoPane.overlap(before: clip) != nil {
                sections.append(videoPane.transitionSection(clip.id))
            }
            if hasPixels {
                sections.append(videoPane.motionSection())
            }
        }
        // A tab that would open as a column of shut headers opens its first
        // section with no stored preference instead. `expandByDefault` defers
        // to a section the user has closed themselves, so this is a default
        // and not an override — and it is offered to each section in TURN
        // because an id can be shared (`video.speed`, `clip.timing`), and a
        // group closed once elsewhere would otherwise leave the tab shut.
        if !sections.contains(where: { $0.isExpanded }) {
            for section in sections {
                if section.expandByDefault() { break }
            }
        }
        reveal.apply(sections, action: binding.selectedAction?.id, subTab: activeSubTab.rawValue)
        return sections
    }
}
