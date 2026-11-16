import Foundation

/// Where one offline audio render is written before it is published (spec
/// §11 SR-12 (e) as amended by #553): `<name>.landing` in a folder of its
/// own OUTSIDE every package, moved into `cache/<folder>/` only inside the
/// cache ledger's `publish`.
///
/// **Why outside.** A save of a titled document lists `cache/` and later
/// swaps the new package in, and a file written into the old package between
/// the two goes with it (#429). A render can take minutes, so its landing
/// file, its renderer's `.partial` and `.input.caf` beside it, and the
/// destination's folder itself were all such writes while they were made in
/// the package. Here nothing is written into the package but by `publish`.
///
/// **Which folder.** The system's item-replacement folder for the
/// destination's volume, so the move is a rename; when the system gives
/// none, a fresh folder under the temporary directory, and the move is then
/// a copy beside the destination followed by a rename, so `<name>` never
/// exists half-written (a render is READY when its file exists).
struct RenderLanding {
    /// The folder, this render's alone; `remove()` deletes it.
    let folder: URL
    /// `<name>.landing`: what the renderer is handed as its destination.
    let url: URL

    init(for destination: URL) {
        let fm = FileManager.default
        var made: URL?
        // The nearest ancestor that exists names the volume.
        var ancestor = destination.deletingLastPathComponent()
        while !fm.fileExists(atPath: ancestor.path), ancestor.path != "/" {
            ancestor = ancestor.deletingLastPathComponent()
        }
        made = try? fm.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: ancestor,
            create: true)
        if made == nil {
            let fallback = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("FrameJob/landing/\(UUID().uuidString)")
            try? fm.createDirectory(at: fallback, withIntermediateDirectories: true)
            made = fallback
        }
        folder = made!
        url = folder.appendingPathComponent(destination.lastPathComponent + ".landing")
    }

    /// Makes `destination`'s folder and moves the landing file to
    /// `destination`; 0, or the errno of the step that failed. Called only
    /// inside `CacheLedger.publish`'s body.
    func publish(to destination: URL) -> Int32 {
        let fm = FileManager.default
        do {
            try fm.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            return Self.code(of: error)
        }
        if rename(url.path, destination.path) == 0 { return 0 }
        guard errno == EXDEV else { return errno }
        // Another volume: a copy beside the name, then the rename.
        let beside = URL(fileURLWithPath: destination.path + ".landing")
        try? fm.removeItem(at: beside)
        do {
            try fm.copyItem(at: url, to: beside)
        } catch {
            try? fm.removeItem(at: beside)
            return Self.code(of: error)
        }
        if rename(beside.path, destination.path) == 0 { return 0 }
        let failed = errno
        try? fm.removeItem(at: beside)
        return failed
    }

    /// Removes the folder and whatever a renderer left in it. Every way out
    /// of a render calls it.
    func remove() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// The POSIX code under a Foundation file error, else `EIO`.
    private static func code(of error: Error) -> Int32 {
        var next: NSError? = error as NSError
        while let current = next {
            if current.domain == NSPOSIXErrorDomain { return Int32(current.code) }
            next = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return EIO
    }
}
