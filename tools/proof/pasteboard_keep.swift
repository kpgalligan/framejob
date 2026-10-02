// tools/proof/pasteboard_keep.swift — `agent_socket_proof.py`'s K13 keeper of
// the person's clipboard (road map 14's MC4). AppKit only, no app sources:
//
//   pasteboard_keep save <file>
//     Writes a binary plist to <file>: every `NSPasteboard.general` item, in
//     order, each an array of {type, data} in the item's own type order, the
//     data its `data(forType:)`. If any type's data is nil it prints
//     `unreadable <type>`, writes nothing and exits 3.
//
//   pasteboard_keep restore <file> <seen>
//     If the pasteboard's string (nil reads as "") is not <seen>, the person
//     wrote meanwhile: it restores nothing and exits 4. Otherwise it checks
//     every saved entry, then clears the pasteboard, writes every saved item
//     back with every type, and
//     reads them back: exit 0 only when every saved byte matches, else 5.
//
// Any other failure (a bad argument, an unreadable file) exits 2.

import AppKit

func stop(_ code: Int32, _ message: String) -> Never {
    print(message)
    exit(code)
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    stop(2, "usage: pasteboard_keep save <file> | restore <file> <seen>")
}
let board = NSPasteboard.general
let file = URL(fileURLWithPath: arguments[2])

switch arguments[1] {
case "save":
    var items: [[[String: Any]]] = []
    for item in board.pasteboardItems ?? [] {
        var pairs: [[String: Any]] = []
        for type in item.types {
            guard let data = item.data(forType: type) else { stop(3, "unreadable \(type.rawValue)") }
            pairs.append(["type": type.rawValue, "data": data])
        }
        items.append(pairs)
    }
    do {
        let data = try PropertyListSerialization.data(
            fromPropertyList: items, format: .binary, options: 0)
        try data.write(to: file, options: .atomic)
    } catch {
        stop(2, "could not write \(file.path): \(error.localizedDescription)")
    }
    print("saved \(items.count) items")
    exit(0)

case "restore":
    guard arguments.count == 4 else { stop(2, "usage: pasteboard_keep restore <file> <seen>") }
    let seen = arguments[3]
    let now = board.string(forType: .string) ?? ""
    guard now == seen else { stop(4, "the clipboard changed; nothing restored") }
    guard let data = try? Data(contentsOf: file),
        let saved = try? PropertyListSerialization.propertyList(from: data, format: nil)
            as? [[[String: Any]]]
    else { stop(2, "could not read \(file.path)") }
    var written: [NSPasteboardItem] = []
    for pairs in saved {
        let item = NSPasteboardItem()
        for pair in pairs {
            guard let type = pair["type"] as? String, let bytes = pair["data"] as? Data else {
                stop(2, "a malformed entry in \(file.path)")
            }
            item.setData(bytes, forType: NSPasteboard.PasteboardType(type))
        }
        written.append(item)
    }
    // Every entry is checked above, so a malformed file never empties it.
    board.clearContents()
    if !written.isEmpty, !board.writeObjects(written) { stop(5, "writeObjects answered false") }
    let back = board.pasteboardItems ?? []
    guard back.count == saved.count else {
        stop(5, "\(back.count) items read back, \(saved.count) saved")
    }
    for (index, pairs) in saved.enumerated() {
        for pair in pairs {
            guard let type = pair["type"] as? String, let bytes = pair["data"] as? Data,
                back[index].data(forType: NSPasteboard.PasteboardType(type)) == bytes
            else { stop(5, "item \(index) type \(pair["type"] ?? "?") differs") }
        }
    }
    print("restored \(saved.count) items")
    exit(0)

default:
    stop(2, "unknown mode \(arguments[1])")
}
