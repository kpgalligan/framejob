import AppKit

/// The Color sub-tab's last section, **Look** (spec §11 GR-7 [b], grading
/// GR5b): the gallery of the eight built-in looks and None, the
/// imported LUTs and Import LUT… (GR-8 [b], GR6b), and an Amount row when
/// every selected clip has a look.
///
/// A tile (a LUT's too), None and Reset write the clips' OWN look in one
/// `set_video`, even with an action selected (GR-7 [b] (1)): in an action's
/// end `look: null` only stops animating the look, so it could not remove
/// one, and the kind switches at the end anyway. The Amount row is the one
/// that animates: it goes through `binding.ops(video:)` like every number.
extension VideoPane {
    // MARK: Look

    /// Every selected clip that draws has a look (evaluated, as the rows
    /// read); false for no such clip. `ClipPane`'s structure signature reads
    /// it, since it adds or removes the Amount row.
    var allLooked: Bool {
        let clips = binding.videoClips
        return !clips.isEmpty && clips.allSatisfy { binding.video($0).look != nil }
    }

    func lookSection(_ gallery: LookGallery) -> InspectorSection {
        let binding = self.binding
        func ids() -> [UInt32] { binding.videoClips.map(\.id) }
        func looks() -> [LookProps?] { binding.videoClips.map { binding.video($0).look } }
        func names() -> [UInt32: String] {
            var names: [UInt32: String] = [:]
            for lut in LookGallery.luts(in: binding.snapshot) {
                names[lut.id] = LookGallery.lutName(lut)
            }
            return names
        }
        let view = LookGalleryView(
            gallery: gallery, binding: binding,
            onPick: { binding.apply("Look", [LookGallery.op($0, clips: ids())]) },
            onPickLUT: { binding.apply("Look", [LookGallery.op(lut: $0, clips: ids())]) },
            onImport: { [weak self] in
                self?.inspector?.onCommand?(#selector(EditorViewController.importLUT(_:)))
            })
        var rows: [NSView] = [view]
        rows += allLooked ? [
            inspectorValueRow(
                "Amount", binding, name: "Amount", unit: "%", decimals: 0, min: 0, max: 100,
                quick: [0, 25, 50, 75, 100],
                read: { (binding.videoProps.look?.amount ?? 1) * 100 },
                ops: { binding.ops(video: VideoPatch(look: .some(LookPatch(amount: $0 / 100)))) },
                mixed: { binding.mixedVideo { $0.look?.amount } }),
        ] : []
        return InspectorSection(
            id: "video.look", title: "Look",
            summary: { LookGallery.summary(looks(), names: names()) },
            reset: { binding.apply("Look", [LookGallery.op(nil, clips: ids())]) },
            differs: { looks().contains { $0 != nil } },
            defaultExpanded: false,
            rows: rows)
    }
}
