import Foundation
import UniformTypeIdentifiers

/// `.cube` 3D LUTs as media (spec §11 GR-8): the file type File ▸ Add Media…
/// lists, the probe `MediaImporter.probe(url:)` dispatches a `.cube` to, and
/// the one read of a LUT's bytes, which the import probe and the
/// compositor's `LutTextures` share — both parse through the core
/// (`ReelCube.parse`), so a file the import accepted is the file that draws.
///
/// A LUT has no picture, sound or duration of its own: its descriptor is
/// kind `lut`, 0×0, duration 0, no flags, which is what `add_media` holds a
/// `lut` row to. It gets no caches (`generateCaches(for:url:in:)` returns at
/// once for one).
extension MediaImporter {
    /// The `.cube` file type: the system's when one is declared for the
    /// extension, else the dynamic type the extension names, which an open
    /// panel matches by the same extension.
    static let lutType: UTType = UTType(filenameExtension: "cube") ?? .data

    /// Whether `url` names a `.cube` file, by its extension in any case.
    static func isLUT(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "cube"
    }

    /// The file's lattice. Reads at most `ReelCube.maxBytes + 1` bytes, so a
    /// larger file is refused in the core's own sentence without being read
    /// whole. Throws the reading error, or the core's `ReelCoreError`.
    static func readLUT(_ url: URL) throws -> CubeLattice {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: ReelCube.maxBytes + 1) ?? Data()
        return try ReelCube.parse(data)
    }

    /// The `media[]` descriptor of a `.cube` file, once the core has read it
    /// whole. A file it refuses is `ImportError.undecodable` in GR-8's words
    /// — `“Film.cube” is not a LUT Reelcut reads: line 2: LUT_3D_SIZE 200 is
    /// outside 2–65.` — and so is a file that cannot be opened, in
    /// `unreadable`'s words: `undecodable` is final, where `unreadable` would
    /// offer the file to the ffmpeg step (`invitesFFmpeg`).
    static func probeLUT(_ url: URL) throws -> MediaDescriptor {
        do {
            _ = try readLUT(url)
        } catch let refused as ReelCoreError {
            throw ImportError.undecodable(
                url,
                sentence: "“\(url.lastPathComponent)” is not a LUT Reelcut reads: "
                    + "\(refused.message).")
        } catch {
            throw ImportError.undecodable(
                url, sentence: "Could not read \(url.lastPathComponent).")
        }
        return MediaDescriptor(
            path: url.path, bookmark: bookmarkString(for: url), kind: .lut, duration: 0,
            width: 0, height: 0, fps: .thirty, hasVideo: false, hasAudio: false,
            hasAlpha: false)
    }
}
