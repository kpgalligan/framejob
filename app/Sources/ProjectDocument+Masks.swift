import Foundation

/// The document's wants of person masks (road map creator-jobs CO2b, spec §11 CO-22 (a)–(c)):
/// after every edit, at the open, when a reverse lands and when a ramp settles —
/// `ensureRampAudio()` ends with `ensureMasks()` — the analysed ranges its cut-out clips' windows
/// need are wanted at once (CO-15), under one lane owner per document, so `ProjectDocument.swift`
/// takes nothing. Main reads the handles, the media files and the cache folder; the serial
/// `CutoutWants.queue` builds the requests and wants them, so wants land in the order they were
/// asked. The owner is alive while the document's `RecipeSource` slot holds a project, which
/// `close()` drops.
extension ProjectDocument {

    /// One document's lane owner and whether it wants anything now. Main only.
    private struct MaskWants {
        let owner: Int
        var wanting: Bool
    }

    /// Keyed by `recipeKey`. Main only.
    private static var maskWants: [Int: MaskWants] = [:]

    /// Wants the masks the cut-out clips of `project` and, with a nest open, `editedProject`
    /// need; with no cut-out clip, withdraws a want made before. Never during a live gesture.
    /// Main thread.
    func ensureMasks() {
        guard !isLiveEditing else { return }
        let key = recipeKey
        let handles = scope == nil ? [project] : [project, editedProject]
        let cutOut = handles.contains { handle in
            let snapshot = handle.snapshot
            return (snapshot.clips + snapshot.nests.flatMap(\.clips)).contains {
                $0.video?.cutout != nil
            }
        }
        guard cutOut else {
            guard let state = Self.maskWants[key], state.wanting else { return }
            Self.maskWants[key]?.wanting = false
            CutoutWants.queue.async { AnalysisLane.shared.release(owner: state.owner) }
            return
        }
        let owner = Self.maskWants[key]?.owner ?? AnalysisLane.shared.newOwner()
        Self.maskWants[key] = MaskWants(owner: owner, wanting: true)
        let snapshot = project.snapshot
        let urls = mediaURLs()
        guard let cacheDir = cacheDirectory else { return }
        CutoutWants.queue.async { [weak self] in
            var windows: [CutoutWindow] = []
            for handle in handles {
                guard let plan = handle.plan else { continue }
                for window in CutoutWants.windows(plan: plan, snapshot: handle.snapshot, range: nil)
                where !windows.contains(window) {
                    windows.append(window)
                }
            }
            let previous = AnalysisLane.shared.openRequests(kind: .masks, cacheDir: cacheDir)
            let kept = CutoutWants.kept(
                previous: previous,
                need: CutoutWants.needs(windows: windows, snapshot: snapshot, urls: urls),
                state: CutoutWants.state)
            let (requests, failures) = CutoutWants.requests(
                windows: windows, snapshot: snapshot, urls: urls, cacheDir: cacheDir,
                keeping: kept)
            for failure in failures {
                NSLog("ProjectDocument: clip %u's person masks cannot be made: %@", failure.clip,
                    failure.message)
            }
            AnalysisLane.shared.want(
                requests, owner: owner,
                alive: { RecipeSource.shared.project(for: key) != nil },
                settled: { self?.masksDidSettle() })
            #if FRAMEJOB_DEV_TOOLS
            CutoutWants.log(.document, owner: owner, requests)
            #endif
        }
    }

    /// This document's lane owner; nil before its first want. Main only (road map creator-jobs
    /// CO3: the Background section's Status and `analyze_cutout` read its runs).
    var maskOwner: Int? { Self.maskWants[recipeKey]?.owner }

    /// The Background section's Analyze Now and `analyze_cutout` (spec §11 CO-30 (c)): the
    /// wants made again (`ensureMasks()`, the one want path), then — on `CutoutWants.queue`,
    /// after that want — a failed or cancelled run of this document's owner runs again
    /// (`AnalysisLane.retry`). Main thread.
    func analyzeMasksNow() {
        ensureMasks()
        guard let owner = maskOwner else { return }
        CutoutWants.queue.async { AnalysisLane.shared.retry(owner: owner) }
    }

    /// A masks job this document wants landed or failed: the package's date re-read (the job
    /// may have created `cache/analysis/`), then the wants made again — what is still missing.
    /// The redraw is `.analysisDidPublish`'s (CO-22 (d)). Main thread.
    func masksDidSettle() {
        packageContentsDidChangeOnDisk()
        ensureMasks()
    }
}
