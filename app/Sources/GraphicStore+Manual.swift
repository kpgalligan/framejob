// app/Sources/GraphicStore+Manual.swift — the graphics reference written
// into a package's `graphics/` (road map 10's G4a): `API.md` and `API.d.ts`,
// copies of the app's bundled `GraphicsAPI.md` and `GraphicsAPI.d.ts`, so an
// agent or a person editing the folder has the API beside the modules.
//
// **The manual is never a reason to create `graphics/`** (spec §11 G-14):
// `writeManual()` writes nothing unless the folder already exists, and
// `holdsContent` does not count the manual, so an untitled root holding only
// the manual is not carried by a save.

import Foundation

extension GraphicStore {
    /// What the manual is called inside `graphics/`.
    static let manualNames = ["API.md", "API.d.ts"]
    /// What it is called in the app's Resources, in `manualNames`' order.
    static let bundledManualNames = ["GraphicsAPI.md", "GraphicsAPI.d.ts"]

    /// The directory holding `Fonts/`, which holds the manual too. The
    /// harness copies the manual there; the probes copy none, so for them
    /// `writeManual()` is a no-op.
    static func manualDirectory(besideFonts fonts: URL) -> URL {
        fonts.deletingLastPathComponent()
    }

    var manualDirectory: URL { Self.manualDirectory(besideFonts: bundledFonts) }

    /// The app bundle's own `GraphicsAPI.md`, no document involved:
    /// `graphic_reference` answers it and Help ▸ Graphics Reference opens it.
    static var bundledReferenceURL: URL {
        manualDirectory(besideFonts: ProjectDocument.bundledFontsDirectory)
            .appendingPathComponent(bundledManualNames[0])
    }

    /// Main. Nothing unless `folderURL` exists; each file written
    /// (`.atomic`) only when its bytes differ from the bundled one; a
    /// bundled file that is absent is skipped silently.
    func writeManual() {
        let files = FileManager.default
        guard files.fileExists(atPath: folderURL.path) else { return }
        for (bundled, name) in zip(Self.bundledManualNames, Self.manualNames) {
            guard let bytes = try? Data(
                contentsOf: manualDirectory.appendingPathComponent(bundled))
            else { continue }
            let target = folderURL.appendingPathComponent(name)
            if let current = try? Data(contentsOf: target), current == bytes { continue }
            try? bytes.write(to: target, options: .atomic)
        }
    }

    /// True when `folder` holds ANY entry, file or directory, that is
    /// neither hidden, one of `manualNames`, nor a `.partial`. A `fonts/` or
    /// `assets/` subfolder counts; `listing(_:)`'s regular-files rule is not
    /// this.
    static func holdsContent(_ folder: URL) -> Bool {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []
        return entries.contains {
            !manualNames.contains($0.lastPathComponent) && $0.pathExtension != "partial"
        }
    }
}
