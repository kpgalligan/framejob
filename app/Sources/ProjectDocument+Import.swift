// app/Sources/ProjectDocument+Import.swift — File > Add Media… and every drop
// into an open project: the probe chain and the one grouped commit.
//
// A pure move out of `ProjectDocument.swift` (road map 10, G3a), which is
// over the ~600-line cap and gave this up before taking the `graphics/`
// store's lines. `present(_:)` became internal so this file can reach it.

import AppKit

extension ProjectDocument {
    // MARK: - Media import

    /// File > Add Media… and every drop that adds files to an OPEN project.
    /// Probing is asynchronous, so the files are probed one at a time and the
    /// whole batch commits as ONE undo step; `completion` gets the new media
    /// ids in the order the files were given, on the main thread.
    func importMedia(_ urls: [URL], completion: (([UInt32]) -> Void)? = nil) {
        guard !urls.isEmpty else {
            completion?([])
            return
        }
        probeNext(urls, index: 0, descriptors: [], completion: completion)
    }

    private func probeNext(
        _ urls: [URL], index: Int, descriptors: [MediaDescriptor],
        completion: (([UInt32]) -> Void)?
    ) {
        guard index < urls.count else {
            // Two statements, never `completion?(commitImport(descriptors))`:
            // optional chaining skips the ARGUMENT too, so with no completion
            // — File ▸ Add Media… and a Media-tab drop pass none — the files
            // were probed and never added, with no beep and no error.
            let added = commitImport(descriptors)
            completion?(added)
            return
        }
        MediaImporter.probe(url: urls[index]) { [weak self] result in
            guard let self = self else { return }
            var collected = descriptors
            switch result {
            case .success(let descriptor):
                collected.append(descriptor)
            case .failure(let error):
                // One unreadable file must not lose the rest of the drop.
                self.present(error)
            }
            self.probeNext(
                urls, index: index + 1, descriptors: collected, completion: completion)
        }
    }

    private func commitImport(_ descriptors: [MediaDescriptor]) -> [UInt32] {
        guard !descriptors.isEmpty else { return [] }
        let before = Set(project.snapshot.media.map { $0.id })
        performGroupedEdit(
            descriptors.count == 1 ? "Add Media" : "Add \(descriptors.count) Media Files",
            descriptors.map { ReelOp.addMedia(descriptor: $0) })
        let added = project.snapshot.media.filter { !before.contains($0.id) }
        generateCaches()
        return added.map { $0.id }
    }
}
