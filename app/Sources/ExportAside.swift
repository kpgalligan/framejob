import Foundation

/// Where an export writes before it is the file at its path (spec §11 #531, the
/// owner's "Write aside, swap" of 2026-11-06).
///
/// Every export writes a hidden sibling in the destination's folder and only
/// `Exporter.finish` touches the destination: on a success it renames the
/// sibling over it, and on any other end it removes the sibling. So a file at
/// the path stays byte for byte until the new one is whole, and a partly
/// written file is never at the path. The same folder, because `rename(2)` is
/// atomic only within one volume; the cost is room for both files while the
/// export runs. A crash during the write leaves a `.framejob-export-*` partial
/// beside the path, which nothing removes at launch.
enum ExportAside {
    /// The sibling's name starts with this.
    static let prefix = ".framejob-export-"

    /// A fresh sibling of `url`: its folder, `prefix` + a UUID, and `url`'s
    /// extension when it has one, so a writer that reads the extension sees
    /// the one the destination has.
    static func temporary(for url: URL) -> URL {
        let ext = url.pathExtension
        let name = prefix + UUID().uuidString + (ext.isEmpty ? "" : "." + ext)
        return url.deletingLastPathComponent().appendingPathComponent(name)
    }

    /// Renames `temporary` over `url` in one step, replacing any file there.
    /// On failure `url` is untouched and the error names the file.
    static func swap(_ temporary: URL, into url: URL) throws {
        guard rename(temporary.path, url.path) != 0 else { return }
        let reason = String(cString: strerror(errno))
        throw Exporter.ExportError.failed(
            "“\(url.lastPathComponent)” could not be replaced with the new export: "
                + "\(reason). The file there is as it was.")
    }

    /// Removes `temporary`, if any, and ImageIO's own part-file beside it; a
    /// failure is ignored (nothing may be there). `CGImageDestinationCreateWithURL`
    /// writes into `.<name>-XXXX` beside its URL and renames it only when
    /// finalized, so a GIF or APNG cancelled midway left
    /// `..framejob-export-<UUID>.gif-XXXX` behind (measured, ai-docs b2 K2).
    static func discard(_ temporary: URL?) {
        guard let temporary else { return }
        try? FileManager.default.removeItem(at: temporary)
        let folder = temporary.deletingLastPathComponent()
        let part = "." + temporary.lastPathComponent + "-"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names where name.hasPrefix(part) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }
}
