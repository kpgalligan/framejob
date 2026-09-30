// app/Sources/ProjectDocument+Import.swift — File > Add Media… and every drop
// into an open project, and the Media tab's and the missing-media sheet's
// relinks: the probe chain and the one grouped commit, for both.
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

    // MARK: - Relink (spec §11, #63)

    /// The Media tab's Relink… and the missing-media sheet's Relink: each
    /// chosen file is probed in order through import's own
    /// `MediaImporter.probe` (ffmpeg's opt-in step included), an unreadable
    /// one is presented and skipped, and every probed relink commits as ONE
    /// undo step, then the cache pass. The path and bookmark are the
    /// descriptor's — the rewrapped `.mov` when ffmpeg converted — and the
    /// core takes the file's duration, size, rate and flags from its probe,
    /// refuses a file of another kind in its own sentence, and holds a clip
    /// that runs past a shorter file's end to it.
    ///
    /// `alertingRefusals` is the sheet's (#180): #88's fold answers a list
    /// that applied with no refusal, so the ops are tried first on the
    /// project as it stands, and after the commit and the cache pass each
    /// refused sentence is presented, verbatim and in order, after each
    /// unreadable file's error, which the sheet holds for the same chain.
    /// The Media tab passes one op and keeps the default: the fold's beep
    /// and CI-10 strip, and an unreadable file presented at once.
    func relinkMedia(_ choices: [(media: UInt32, url: URL)], alertingRefusals: Bool = false) {
        relinkNext(choices, index: 0, ops: [], unreadable: [], alertingRefusals: alertingRefusals)
    }

    private func relinkNext(
        _ choices: [(media: UInt32, url: URL)], index: Int, ops: [ReelOp],
        unreadable: [any Error], alertingRefusals: Bool
    ) {
        guard index < choices.count else {
            guard !ops.isEmpty else { return presentRelinkRefusals(unreadable) }
            let refusals = alertingRefusals ? relinkRefusals(ops) : []
            // The probe's completion is not an AppKit event: the grouped
            // entry point is mandatory (app/CLAUDE.md's undo pitfall).
            performGroupedEdit("Relink Media", ops)
            generateCaches()
            presentRelinkRefusals(unreadable + refusals.map { RelinkRefusalAlert(refusal: $0) })
            return
        }
        let choice = choices[index]
        MediaImporter.probe(url: choice.url) { [weak self] result in
            guard let self = self else { return }
            var collected = ops
            var failed = unreadable
            switch result {
            case .success(let descriptor):
                collected.append(
                    .relinkMedia(
                        media: choice.media, path: descriptor.path,
                        bookmark: descriptor.bookmark, probe: descriptor))
            case .failure(let error):
                // One unreadable file must not lose the rest of the sheet;
                // the sheet's is held for the one-at-a-time chain, since an
                // error sheet asked for while this one is up is dropped.
                if alertingRefusals { failed.append(error) } else { self.present(error) }
            }
            self.relinkNext(
                choices, index: index + 1, ops: collected, unreadable: failed,
                alertingRefusals: alertingRefusals)
        }
    }

    /// Every refusal `ops` would meet, in order: walked over `project` as
    /// `ReelProject.applying(_:)` walks a list, each op on the last applied
    /// result. A throw ends the walk; the commit presents it.
    private func relinkRefusals(_ ops: [ReelOp]) -> [ReelRefusal] {
        var current = project
        var refusals: [ReelRefusal] = []
        for op in ops {
            guard let edit = try? current.applying(op) else { break }
            switch edit {
            case .applied(let next): current = next
            case .identity: break
            case .refused(let refusal): refusals.append(refusal)
            }
        }
        return refusals
    }

    /// Each alert (an unreadable file's error or a refusal), in order, one at
    /// a time: AppKit drops an error sheet asked for while another is
    /// attached (measured, `relink_sheet_probe.py` S2 and S4), so the next is
    /// asked for when the last ends. With no window, `present(_:)` is
    /// app-modal and so sequential.
    private func presentRelinkRefusals(_ refusals: [any Error]) {
        guard let alert = refusals.first else { return }
        let rest = Array(refusals.dropFirst())
        guard let window = windowForSheet else {
            present(alert)
            return presentRelinkRefusals(rest)
        }
        let context = Unmanaged.passRetained(RelinkRefusalsLeft(rest)).toOpaque()
        presentError(alert, modalFor: window, delegate: self,
                     didPresent: #selector(relinkRefusalDidEnd(_:contextInfo:)),
                     contextInfo: context)
    }

    @objc private func relinkRefusalDidEnd(
        _ didRecover: Bool, contextInfo: UnsafeMutableRawPointer?
    ) {
        guard let contextInfo else { return }
        presentRelinkRefusals(Unmanaged<RelinkRefusalsLeft>.fromOpaque(contextInfo)
            .takeRetainedValue().refusals)
    }

    /// The alerts still to show, carried through `contextInfo`.
    private final class RelinkRefusalsLeft {
        let refusals: [any Error]
        init(_ refusals: [any Error]) { self.refusals = refusals }
    }

    /// One refused relink as an alert: the core's sentence, verbatim.
    struct RelinkRefusalAlert: LocalizedError {
        let refusal: ReelRefusal
        var errorDescription: String? { refusal.reason }
    }
}
