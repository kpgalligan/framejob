import AppKit

/// File ▸ Consolidate Media… — copies every file the project references into
/// `media/` inside the `.reelcut` package and relinks the project at the
/// copies (spec §5.6, road map Phase 6).
///
/// Reelcut REFERENCES media by default (§4.2, §11): a project is a small
/// JSON file pointing at whatever the footage happens to live on. Consolidate
/// is the one command that trades that for self-containment — the package
/// becomes the whole edit, so it can be handed to someone else or archived
/// with its sources deleted.
///
/// This type is the engine and nothing else: it plans, it copies, and it
/// hands back the `relink_media` ops it earned. Applying them is the
/// caller's job — `EditorViewController+Consolidate.swift` through
/// `ProjectDocument`, `AgentServer+Media.swift` through `editResult` — so
/// there is still exactly one mutation point.
///
/// **Four traps, all of them load-bearing.**
///
/// 1. *An untitled project has no package to copy into.* `plan` refuses it
///    rather than inventing a destination: `ProjectDocument`'s temporary
///    cache directory is documented as orphanable, and orphaning a cache
///    costs a filmstrip where orphaning MEDIA loses the file.
/// 2. *Two files can share a basename.* Names are claimed against the
///    directory's existing contents and against each other, case-insensitively
///    (the volume usually is), so `intro.mov` and `b-roll/intro.mov` become
///    `intro.mov` and `intro-2.mov`.
/// 3. *A file already inside the package must not be copied onto itself.*
///    Those entries are relinked but never copied — and relinking them still
///    matters, because a stale BOOKMARK pointing outside the package wins
///    over the path in `mediaURL(for:)`.
/// 4. *A failure part-way through must leave the project openable.* Nothing
///    is relinked until its copy is on disk, so a run that dies half way
///    leaves half the media consolidated and the rest still pointing at the
///    originals — every clip still resolves. Cancelling is the same story
///    with a friendlier name.
///
/// **Bookmarks are deliberately cleared** for a consolidated entry. NSDocument
/// writes a package by building a new one beside the old and swapping it in,
/// so a `URL.bookmarkData()` made for a file INSIDE the package is a bookmark
/// to a file a later save may replace; the path — which `ProjectDocument`
/// re-anchors to the package on open — is the durable half.
enum MediaConsolidator {

    /// One file to bring inside. `source` has already been resolved through
    /// `mediaURL(for:)`, so it exists at plan time.
    struct Copy {
        let media: UInt32
        let name: String
        let source: URL
        let destination: URL
        let bytes: Int64
    }

    /// What a run will do, computed before anything is touched.
    struct Plan {
        /// `<package>/media`, which may not exist yet.
        let directory: URL
        let copies: [Copy]
        /// Media already inside `media/` that needs only its link corrected
        /// — a stale bookmark, or a path spelled differently from the file.
        /// Its destination is on disk before the run starts.
        let relinks: [Copy]
        /// The second and later rows of two media entries that resolve to
        /// ONE file: they are relinked at another row's copy rather than
        /// copying the footage twice, so their op waits until that copy has
        /// really landed.
        let aliases: [Copy]
        /// Names of media with no file anywhere. Consolidate cannot copy
        /// what it cannot find; Relink… is the fix and the report says so.
        let missing: [String]
        let bytes: Int64

        /// True when there is nothing to do — every file is already inside
        /// the package and correctly linked.
        var isEmpty: Bool { copies.isEmpty && relinks.isEmpty && aliases.isEmpty }
    }

    /// What a run actually did.
    struct Outcome {
        let ops: [ReelOp]
        let copied: Int
        let bytes: Int64
        let missing: [String]
        /// One line per file that could not be copied, with the reason.
        let failures: [String]
        let cancelled: Bool

        /// The sentence the sheet and the agent both report.
        var summary: String {
            var parts: [String] = []
            parts.append(
                copied == 0
                    ? "No files needed copying." : "Copied \(copied) file\(copied == 1 ? "" : "s")"
                        + " (\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)))"
                        + " into the package.")
            if cancelled { parts.append("Stopped before the rest.") }
            if !failures.isEmpty {
                parts.append(
                    "\(failures.count) file\(failures.count == 1 ? "" : "s") could not be copied.")
            }
            if !missing.isEmpty {
                parts.append(
                    "\(missing.count) missing file\(missing.count == 1 ? "" : "s") "
                        + "\(missing.count == 1 ? "was" : "were") left alone — relink "
                        + missing.prefix(3).joined(separator: ", ")
                        + (missing.count > 3 ? ", …" : "") + ".")
            }
            return parts.joined(separator: " ")
        }
    }

    enum ConsolidateError: LocalizedError {
        case untitled
        case noMedia
        case unwritable(URL, String)

        var errorDescription: String? {
            switch self {
            case .untitled:
                return "Save the project first — Consolidate Media copies files into the "
                    + ".reelcut package, and a project that has never been saved does not have "
                    + "one yet."
            case .noMedia:
                return "This project references no media files."
            case .unwritable(let url, let reason):
                return "“\(url.lastPathComponent)” could not be created: \(reason)"
            }
        }
    }

    /// A cancel flag the sheet sets on the main thread and the copy loop
    /// reads on its own queue. An `NSLock` rather than a plain `Bool`
    /// because that is a data race, and rather than a queue hop because the
    /// loop has to ask between every file.
    final class CancelToken {
        private let lock = NSLock()
        private var flag = false

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return flag
        }

        func cancel() {
            lock.lock()
            flag = true
            lock.unlock()
        }
    }

    // MARK: - Planning

    /// Everything the run will do, decided on the main thread against the
    /// document's current snapshot — so the copy loop, which runs on another
    /// queue, never reads the model.
    static func plan(for document: ProjectDocument) throws -> Plan {
        guard let directory = document.mediaDirectory else { throw ConsolidateError.untitled }
        let media = document.project.snapshot.media
        guard !media.isEmpty else { throw ConsolidateError.noMedia }

        // Names already spoken for by an earlier consolidate. Lower-cased
        // because the volume under a package is usually case-insensitive,
        // and "Intro.mov" landing on "intro.mov" would be a lost file.
        var claimed = Set(
            ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
                .map { $0.lowercased() })
        // Two media entries can resolve to ONE file (different rows, the
        // same footage). The first row earns the copy; the rest are relinked
        // at it, so the package holds the footage once.
        var bySource: [String: URL] = [:]

        var copies: [Copy] = []
        var relinks: [Copy] = []
        var aliases: [Copy] = []
        var missing: [String] = []
        var bytes: Int64 = 0
        for entry in media {
            guard let url = mediaURL(for: entry)?.resolvingSymlinksInPath().standardizedFileURL
            else {
                missing.append(entry.name)
                continue
            }
            if isInside(url, directory) {
                // Already consolidated. It still needs an op when a stale
                // bookmark or a differently-spelled path could send
                // `mediaURL(for:)` back outside the package.
                if entry.bookmark != nil || entry.path != url.path {
                    relinks.append(
                        Copy(
                            media: entry.id, name: url.lastPathComponent, source: url,
                            destination: url, bytes: 0))
                }
                continue
            }
            if let shared = bySource[url.path] {
                aliases.append(
                    Copy(
                        media: entry.id, name: shared.lastPathComponent, source: url,
                        destination: shared, bytes: 0))
                continue
            }
            let destination = directory.appendingPathComponent(
                uniqueName(for: url, claimed: &claimed))
            bySource[url.path] = destination
            let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            bytes += size
            copies.append(
                Copy(
                    media: entry.id, name: destination.lastPathComponent, source: url,
                    destination: destination, bytes: size))
        }
        return Plan(
            directory: directory, copies: copies, relinks: relinks, aliases: aliases,
            missing: missing, bytes: bytes)
    }

    /// Whether `url` already lives in the package's `media/` directory —
    /// both sides standardized, so `/tmp` and `/private/tmp` spellings of
    /// the same path agree.
    private static func isInside(_ url: URL, _ directory: URL) -> Bool {
        let root = directory.resolvingSymlinksInPath().standardizedFileURL.path
        return url.path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    /// A file name nothing else in the directory has taken. Path separators
    /// cannot appear in a `lastPathComponent`, but a colon can (it is a
    /// separator in the Finder's own spelling), so it goes too.
    private static func uniqueName(for source: URL, claimed: inout Set<String>) -> String {
        let raw = source.lastPathComponent.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let base = raw.isEmpty ? "media" : raw
        let stem = (base as NSString).deletingPathExtension
        let ext = (base as NSString).pathExtension
        var candidate = base
        var suffix = 2
        while claimed.contains(candidate.lowercased()) {
            let root = stem.isEmpty ? "media" : stem
            candidate = ext.isEmpty ? "\(root)-\(suffix)" : "\(root)-\(suffix).\(ext)"
            suffix += 1
        }
        claimed.insert(candidate.lowercased())
        return candidate
    }

    // MARK: - Running

    /// Copies the planned files and returns the ops that record where they
    /// went. **Blocking** — the UI path calls it on a background queue with
    /// a progress sheet up (the one `DispatchQueue` seam this feature adds),
    /// the agent calls it inline.
    ///
    /// `progress` is called with a 0…1 fraction and the file being copied,
    /// on whatever thread this runs on; the sheet hops to main itself.
    ///
    /// An op is emitted only for a file that is really on disk, which is the
    /// whole of the "a failure part-way through leaves the project openable"
    /// promise.
    static func run(
        _ plan: Plan, cancel: CancelToken? = nil,
        progress: ((Double, String) -> Void)? = nil
    ) -> Outcome {
        var ops: [ReelOp] = []
        var failures: [String] = []
        var copied = 0
        var written: Int64 = 0

        // The entries whose file is already inside cost nothing and go
        // first, so even a cancelled run leaves the package tidier.
        for entry in plan.relinks {
            ops.append(.relinkMedia(media: entry.media, path: entry.destination.path))
        }

        let manager = FileManager.default
        do {
            try manager.createDirectory(at: plan.directory, withIntermediateDirectories: true)
        } catch {
            return Outcome(
                ops: ops, copied: 0, bytes: 0, missing: plan.missing,
                failures: [plan.directory.lastPathComponent + " — " + error.localizedDescription],
                cancelled: false)
        }

        var cancelled = false
        for entry in plan.copies {
            if cancel?.isCancelled == true {
                cancelled = true
                break
            }
            progress?(plan.bytes > 0 ? Double(written) / Double(plan.bytes) : 0, entry.name)
            do {
                // A destination left behind by an interrupted run holds a
                // half-written file AND its name; removing it first is what
                // makes a second Consolidate finish the job instead of
                // making a duplicate beside the stub.
                if manager.fileExists(atPath: entry.destination.path) {
                    try manager.removeItem(at: entry.destination)
                }
                try manager.copyItem(at: entry.source, to: entry.destination)
                ops.append(.relinkMedia(media: entry.media, path: entry.destination.path))
                copied += 1
                written += entry.bytes
            } catch {
                failures.append(entry.name + " — " + error.localizedDescription)
                try? manager.removeItem(at: entry.destination)
            }
        }
        // An alias points at another row's copy, so it may only be recorded
        // once that copy is really on disk — a failed or skipped copy leaves
        // both rows pointing at the original file, which still opens.
        for entry in plan.aliases where manager.fileExists(atPath: entry.destination.path) {
            ops.append(.relinkMedia(media: entry.media, path: entry.destination.path))
        }
        progress?(1, "")
        return Outcome(
            ops: ops, copied: copied, bytes: written, missing: plan.missing, failures: failures,
            cancelled: cancelled)
    }
}
