import AppKit

/// Clip ▸ Look ▸ (spec §11 GR-7 [b], grading GR5b): the eight
/// looks, a separator and None — the menu half of the Color sub-tab's Look
/// section (`VideoPane+Look.swift`), and a UI path `set_video`'s `look`
/// mirror names.
///
/// The targets are `LookGallery.targets`: the selected clips that take a
/// grade (video, image, still, adjustment). A choice is ONE `set_video` over
/// all of them — a kind alone keeps each clip's amount (1 on a clip with
/// none), None is `look: null` — on the clips' own look, whatever action is
/// selected (GR-7 [b] (1)), one undo step "Look". The tags are the Motion
/// idiom: an index into `LookKind.allCases`, −1 None, −2 an imported LUT
/// whose `representedObject` is its media id (GR-8 [b], filled by
/// `LookMenuFiller`), and any other tag — or a LUT item with no id — a
/// stranger that beeps and writes nothing. Import LUT… (the Look section's
/// button) is here too.
extension EditorViewController {

    /// The selected clips a look applies to.
    private var lookTargets: [ClipSnapshot] {
        guard let document = document else { return [] }
        return LookGallery.targets(selectedClips, in: document.editedProject.snapshot)
    }

    /// The one tag that means None, as `lookMenu()` writes it.
    private static let lookNoneTag = -1
    /// The tag of an imported LUT's item, as `LookMenuFiller` writes it.
    static let lookLUTTag = -2

    /// The sender's tag indexes `LookKind.allCases`; −1 is None; −2 a LUT.
    @objc func setLook(_ sender: Any?) {
        let targets = lookTargets
        let item = sender as? NSMenuItem
        guard let document = document, let tag = item?.tag, !targets.isEmpty else {
            NSSound.beep()
            return
        }
        if tag == Self.lookLUTTag, let lut = (item?.representedObject as? NSNumber)?.uint32Value {
            document.applyEdit("Look", [LookGallery.op(lut: lut, clips: targets.map(\.id))])
        } else if let kind = lookKind(tag) {
            document.applyEdit("Look", [LookGallery.op(kind, clips: targets.map(\.id))])
        } else {
            NSSound.beep()
        }
    }

    /// Import LUT…: a `.cube` chosen in a sheet panel, then
    /// `importLUT(from:into:clips:)` for the clips selected now.
    @objc func importLUT(_ sender: Any?) {
        let targets = lookTargets.map(\.id)
        guard let document = document, let window = view.window, !targets.isEmpty else {
            NSSound.beep()
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [MediaImporter.lutType]
        panel.message = "Choose a .cube LUT to apply to the selected clips."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.importLUT(from: url, into: document, clips: targets)
        }
    }

    /// The probe, then ONE undo step "Import LUT": `add_media` and the look,
    /// the id learned as Add Background ▸ Image… learns it
    /// (`backgroundMedia(for:in:)`: the id `add_media` mints, or the row a
    /// file already in the list holds). Off-event, so grouped explicitly. A
    /// refused file is the document's error sheet and changes nothing.
    func importLUT(from url: URL, into document: ProjectDocument, clips: [UInt32]) {
        MediaImporter.probe(url: url, mayAsk: true) { result in
            do {
                let descriptor = try result.get()
                let add = ReelOp.addMedia(descriptor: descriptor)
                guard let id = try Self.backgroundMedia(for: descriptor, in: document.project)
                else {
                    NSSound.beep()
                    return
                }
                let look = LookGallery.op(lut: id, clips: clips)
                document.performGroupedEdit("Import LUT", [add, look])
            } catch {
                document.present(error)
            }
        }
    }

    /// What a tag SAYS: `.some(kind)` for an index into the vocabulary,
    /// `.some(nil)` for None, nil for a tag no builder writes.
    private func lookKind(_ tag: Int) -> LookKind?? {
        if tag == Self.lookNoneTag { return .some(nil) }
        return LookKind.builtIns.indices.contains(tag) ? .some(LookKind.builtIns[tag]) : nil
    }

    // MARK: - Validation

    /// The half of `validateUserInterfaceItem` this file owns; nil is "not
    /// mine". An item is on when every target's OWN look is its kind (None:
    /// no look; a LUT's item: that LUT), dashed when some but not all are
    /// (GR-7 [b] (3)), off otherwise; enabled exactly when there is a target.
    func validateLookAction(_ action: Selector, item: any NSValidatedUserInterfaceItem) -> Bool? {
        guard action == #selector(setLook(_:)) else { return nil }
        let targets = lookTargets
        let menuItem = item as? NSMenuItem
        if menuItem?.tag == Self.lookLUTTag {
            let lut = (menuItem?.representedObject as? NSNumber)?.uint32Value
            let carrying = targets.filter {
                $0.videoProps.look?.kind == .lut && $0.videoProps.look?.media == lut
            }.count
            menuItem?.state = carrying == 0 ? .off : (carrying < targets.count ? .mixed : .on)
        } else if let tagged = lookKind(menuItem?.tag ?? Int.min) {
            let carrying = targets.filter { $0.videoProps.look?.kind == tagged }.count
            menuItem?.state =
                carrying == 0 ? .off : (carrying == targets.count ? .on : .mixed)
        } else {
            menuItem?.state = .off
        }
        return !targets.isEmpty
    }
}
