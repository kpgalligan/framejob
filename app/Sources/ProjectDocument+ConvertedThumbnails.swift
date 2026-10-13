import Foundation

/// A converting media's filmstrip follows its Camera Log (spec §11 GR-21):
/// every committed change that moves a media's converting `color` — set,
/// clear, another LUT, undo, redo, `remove_media` of its LUT — starts a cache
/// pass for that media, which supersedes one already running for it
/// (`CacheLedger`'s generation rule) and rebuilds the strip through step 0 or
/// plain, as the new setting draws it.
extension ProjectDocument {

    /// From `makeWindowControllers()`, in place of `generateCaches()`:
    /// observes this document's own `.projectDocumentDidChange`, then asks
    /// for every media's caches. `stopGraphicStore()`, from `close()`, removes
    /// every observation of that name by this document, this one with the
    /// rename repair's.
    func startCaches() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(mediaColorsMayHaveChanged(_:)),
            name: .projectDocumentDidChange, object: self)
        generateCaches()
    }

    /// `.projectDocumentDidChange` for this document: every committed change
    /// (an edit, an undo, a redo), never a live gesture's tick. A media
    /// whose converting Camera Log differs from the input its last pass was
    /// asked with gets a pass; nothing else does, so an ordinary edit costs a
    /// ledger read per media.
    @objc func mediaColorsMayHaveChanged(_ note: Notification) {
        guard note.userInfo?["isLive"] as? Bool != true,
            let directory = intendedCacheDirectory
        else { return }
        let ledger = MediaImporter.CacheLedger.shared
        let changed = project.snapshot.media.filter {
            ThumbnailInput.convertingColor(of: $0)
                != ledger.lastInput(cacheDir: directory, media: $0.id)
        }
        guard !changed.isEmpty, let cache = cacheDirectory else { return }
        let urls = mediaURLs()
        for media in changed {
            guard let url = urls[media.id] else { continue }
            MediaImporter.generateCaches(for: media, url: url, in: cache, urls: urls)
        }
    }
}
