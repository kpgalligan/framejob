// app/Sources/GraphicPackageImport.swift — a `.fjgraphic` copied into a
// project's `graphics/` (spec §11 G-47): what the package holds, where each
// file goes, the copy, and what it answers. No UI: the sheet
// (`GraphicImportSheetController.swift`) and `import_graphic`
// (`AgentServer+GraphicImports.swift`) both call these bodies, so the two
// doors refuse in the same sentences.
//
// **The checks** (G-47 (c)) are the core's first — `ReelGraphicPackage.read`,
// the archive and its manifest — then the app's: a font must load in a
// throwaway library, as `importFont` does, and an asset must be a name
// `asset(name)` can use. Every refusal is "<file name> cannot be imported:
// <sentence>", and none writes anything.
//
// **The plan** (G-47 (d)) puts each file under the manifest's name: written
// when the name is free, reused when the file there holds the same bytes;
// otherwise a module or a font takes `-2`, `-3`, … and an asset refuses the
// import, because the module reaches it by name. A name is matched exactly:
// one that differs only in case is another file, and is never free.
//
// **The copy** (G-47 (e)) writes the fonts, then the assets, with
// `landNew` (never replacing), then the module with `write(name:bytes:)`; a
// throw removes every file it wrote, rescans and rethrows. One `rescan()` at
// the end, from the caller's handler or command — never from a
// `.graphicsDidChange` observer. Not undoable and never dirty (G-3).

import Foundation

/// One font or asset of a package, under the manifest's `name`.
struct GraphicPackageFile {
    let name: String
    let bytes: Data
}

/// A package read and checked, ready to plan.
struct GraphicPackageContents {
    let module: String
    let title: String
    let category: String
    let description: String?
    let appVersion: String
    let source: Data
    let fonts: [GraphicPackageFile]
    let assets: [GraphicPackageFile]

    /// Reads the file at `url` and checks it, the core's checks then the app's.
    static func read(at url: URL) throws -> GraphicPackageContents {
        let refuse = { (sentence: String) in
            ReelCoreError(message: "\(url.lastPathComponent) cannot be imported: \(sentence)")
        }
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values?.isRegularFile == true else { throw refuse("it is not a file") }
        let size = values?.fileSize ?? 0
        guard size > 0 else { throw refuse("it is empty (0 bytes)") }
        guard UInt64(size) <= UInt64(UInt32.max) else {
            throw refuse("it is \(size) bytes, more than a .fjgraphic holds (\(UInt32.max))")
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw refuse("it could not be read: \(error.localizedDescription)")
        }
        let answer: String
        do {
            answer = try ReelGraphicPackage.read(data)
        } catch let error as ReelCoreError {
            throw refuse(error.message)
        }
        guard let manifest = (try? JSONSerialization.jsonObject(with: Data(answer.utf8)))
            as? [String: Any], let files = manifest["files"] as? [[String: Any]],
            let first = files.first
        else { throw refuse("the core's answer could not be read") }
        func bytes(_ file: [String: Any]) -> Data {
            let offset = file["offset"] as? Int ?? 0, length = file["size"] as? Int ?? 0
            return data.subdata(in: offset..<(offset + length))
        }
        var fonts: [GraphicPackageFile] = [], assets: [GraphicPackageFile] = []
        for file in files.dropFirst() {
            let entry = GraphicPackageFile(name: file["name"] as? String ?? "", bytes: bytes(file))
            let path = file["path"] as? String ?? ""
            if path.hasPrefix(GraphicStore.fontsFolderName + "/") {
                fonts.append(entry)
            } else {
                assets.append(entry)
            }
        }
        for font in fonts {
            let ext = (font.name as NSString).pathExtension.lowercased()
            guard GraphicStore.fontExtensions.contains(ext) else {
                throw refuse("the font \"\(font.name)\" is not a .ttf or .otf file")
            }
            do {
                try GraphicLibrary().addFont(font.bytes)
            } catch let error as ReelCoreError {
                throw refuse("the font \"\(font.name)\": \(error.message)")
            }
        }
        for asset in assets {
            let ext = (asset.name as NSString).pathExtension.lowercased()
            guard GraphicStore.assetExtensions.contains(ext) else {
                throw refuse(
                    "the picture \"\(asset.name)\" is not a \(GraphicStore.assetKinds) file")
            }
            guard GraphicAssetName.isLegal(asset.name) else {
                throw refuse("the picture \"\(asset.name)\" \(GraphicAssetName.rule)")
            }
            guard !asset.bytes.isEmpty else {
                throw refuse("the picture \"\(asset.name)\" is empty (0 bytes)")
            }
        }
        return GraphicPackageContents(
            module: manifest["module"] as? String ?? "", title: manifest["title"] as? String ?? "",
            category: manifest["category"] as? String ?? "",
            description: manifest["description"] as? String,
            appVersion: manifest["app_version"] as? String ?? "", source: bytes(first),
            fonts: fonts, assets: assets)
    }
}

/// What an import does with one file.
enum GraphicImportAction: String {
    case written, reused
}

/// One file's place: `name` the manifest's, `target` the name on disk.
struct GraphicImportPlacement {
    let name: String
    let target: String
    let action: GraphicImportAction
}

/// Where every file of a package goes in one project, and the copy.
struct GraphicImportPlan {
    let contents: GraphicPackageContents
    let module: GraphicImportPlacement
    let fonts: [GraphicImportPlacement]
    let assets: [GraphicImportPlacement]

    /// G-47 (d) over the store's scan and the disk. Throws, writing nothing, for an asset
    /// whose name holds a different picture, or with no store.
    static func make(_ contents: GraphicPackageContents, document: ProjectDocument) throws
        -> GraphicImportPlan
    {
        guard let store = document.graphicStore else {
            throw ReelCoreError(message: ProjectDocument.noGraphicsFolderSentence)
        }
        let folder = store.folderURL
        let free = { (name: String) in
            !store.holdsModule(named: name) && document.graphicClips(named: name).isEmpty
        }
        let module: GraphicImportPlacement
        let held = try? Data(contentsOf: folder.appendingPathComponent(contents.module + ".js"))
        if free(contents.module) {
            module = .init(name: contents.module, target: contents.module, action: .written)
        } else if held == contents.source {
            module = .init(name: contents.module, target: contents.module, action: .reused)
        } else {
            let root = String(String.UnicodeScalarView(contents.module.unicodeScalars.prefix(60)))
            var n = 2
            while !free("\(root)-\(n)") { n += 1 }
            module = .init(name: contents.module, target: "\(root)-\(n)", action: .written)
        }
        var fonts = Names(folder.appendingPathComponent(GraphicStore.fontsFolderName))
        let fontPlaces = contents.fonts.map { font -> GraphicImportPlacement in
            var target = font.name
            var n = 2
            while true {
                if let action = fonts.place(target, font.bytes) {
                    return .init(name: font.name, target: target, action: action)
                }
                target = GraphicAssetName.withSuffix(font.name, n)
                n += 1
            }
        }
        var assets = Names(folder.appendingPathComponent(GraphicStore.assetsFolderName))
        let assetPlaces = try contents.assets.map { asset -> GraphicImportPlacement in
            guard let action = assets.place(asset.name, asset.bytes) else {
                throw ReelCoreError(
                    message: "graphics/assets/\(asset.name) already holds a different picture, "
                        + "and this graphic reaches its own by asset(\"\(asset.name)\"), so it "
                        + "cannot be renamed; rename or remove the project's file and import "
                        + "again")
            }
            return .init(name: asset.name, target: asset.name, action: action)
        }
        return GraphicImportPlan(
            contents: contents, module: module, fonts: fontPlaces, assets: assetPlaces)
    }

    /// One folder's names, as the disk holds them and as this plan claims them.
    private struct Names {
        let folder: URL
        var taken: [String]

        init(_ folder: URL) {
            self.folder = folder
            taken = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        }

        /// `.written` when `name` is free (and claims it), `.reused` when a file of exactly
        /// that name holds `bytes`, nil otherwise — a name that differs only in case is taken.
        mutating func place(_ name: String, _ bytes: Data) -> GraphicImportAction? {
            let url = folder.appendingPathComponent(name)
            if taken.contains(name) {
                return (try? Data(contentsOf: url)) == bytes ? .reused : nil
            }
            let folded = name.lowercased()
            guard !taken.contains(where: { $0.lowercased() == folded }),
                !FileManager.default.fileExists(atPath: url.path)
            else { return nil }
            taken.append(name)
            return .written
        }
    }

    /// The copy: fonts, assets, then the module, none replacing a file; a throw removes what
    /// it wrote and rescans. One `rescan()` at the end. Main.
    func apply(to store: GraphicStore) throws {
        var written: [URL] = []
        var current = ""
        do {
            try store.ensureFolder()
            for (folder, places, files) in [
                (GraphicStore.fontsFolderName, fonts, contents.fonts),
                (GraphicStore.assetsFolderName, assets, contents.assets),
            ] {
                for (place, file) in zip(places, files) where place.action == .written {
                    current = "\(folder)/\(place.target)"
                    written.append(try store.landNew(file.bytes, into: folder, as: place.target))
                }
            }
            if module.action == .written {
                current = "\(module.target).js"
                try store.write(name: module.target, bytes: contents.source)
            }
        } catch {
            for url in written { try? FileManager.default.removeItem(at: url) }
            store.rescan()
            let why = (error as? ReelCoreError)?.message ?? error.localizedDescription
            throw ReelCoreError(message: "graphics/\(current) could not be written: \(why)")
        }
        store.rescan()
    }

    /// `Imported <title> as <module>. Added: …. Already here: ….`
    var sentence: String {
        let all = [("\(module.target).js", module.action)]
            + fonts.map { ("\(GraphicStore.fontsFolderName)/\($0.target)", $0.action) }
            + assets.map { ("\(GraphicStore.assetsFolderName)/\($0.target)", $0.action) }
        var text = "Imported \(contents.title) as \(module.target)."
        for (label, action) in [("Added", GraphicImportAction.written), ("Already here", .reused)] {
            let names = all.filter { $0.1 == action }.map(\.0)
            if !names.isEmpty { text += " \(label): " + names.joined(separator: ", ") + "." }
        }
        return text
    }

    /// `import_graphic`'s answer (spec §11 G-47 (i)).
    var reply: [String: Any] {
        var out: [String: Any] = [
            "name": module.target, "title": contents.title, "module": module.action.rawValue,
            "fonts": fonts.map { font -> [String: Any] in
                var row: [String: Any] = ["name": font.target, "action": font.action.rawValue]
                if font.target != font.name { row["renamed_from"] = font.name }
                return row
            },
            "assets": assets.map { ["name": $0.target, "action": $0.action.rawValue] },
            "note": AgentServer.notUndoableNote,
        ]
        if module.target != module.name { out["renamed_from"] = module.name }
        return out
    }
}

extension ProjectDocument {
    /// Plans `contents` against this project and copies it in; the plan it carried out.
    func importGraphicPackage(_ contents: GraphicPackageContents) throws -> GraphicImportPlan {
        let plan = try GraphicImportPlan.make(contents, document: self)
        guard let store = graphicStore else {
            throw ReelCoreError(message: Self.noGraphicsFolderSentence)
        }
        try plan.apply(to: store)
        return plan
    }
}
