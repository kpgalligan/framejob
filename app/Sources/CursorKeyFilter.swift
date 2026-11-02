import CoreGraphics

/// The modifiers a key-down held that CU-60's rule and spelling read: ⌘, ⌃, ⌥ and ⇧, nothing else
/// (⇪ and fn are never part of a shortcut's spelling).
struct CursorKeyModifiers: OptionSet, Equatable {
    let rawValue: Int
    static let cmd = CursorKeyModifiers(rawValue: 1 << 0)
    static let ctrl = CursorKeyModifiers(rawValue: 1 << 1)
    static let opt = CursorKeyModifiers(rawValue: 1 << 2)
    static let shift = CursorKeyModifiers(rawValue: 1 << 3)

    init(rawValue: Int) { self.rawValue = rawValue }

    /// The four from a `CGEvent`'s flags.
    init(flags: CGEventFlags) {
        var held: CursorKeyModifiers = []
        if flags.contains(.maskCommand) { held.insert(.cmd) }
        if flags.contains(.maskControl) { held.insert(.ctrl) }
        if flags.contains(.maskAlternate) { held.insert(.opt) }
        if flags.contains(.maskShift) { held.insert(.shift) }
        self = held
    }
}

/// One key-down as the filter sees it. `character` is the layout's character with no modifier
/// applied, and it is filled ONLY for a key-down `CursorKeyFilter.isShortcut` calls a shortcut:
/// a typed key's character is never read (spec §11 CU-60).
struct CursorKeyEvent: Equatable {
    var keyCode: Int
    var modifiers: CursorKeyModifiers
    var isRepeat: Bool
    var character: String?
}

/// What a key-down puts in the cursor file: a spelled shortcut and its key code, a time-only
/// typed mark, or nothing.
enum CursorKeyEntry: Equatable {
    case shortcut(keys: String, code: Int)
    case typed
    case none
}

/// CU-7 as CU-60 amends it, PURE (road map creator-jobs CU6): which key-down is a shortcut and
/// how it is spelled; `CursorCapture+Keys.swift` is the live source that feeds it.
///
/// **The rule**, in order: secure input held by any process (read at delivery) → nothing, not
/// even a time; an auto-repeat → a typed mark; ⌘ or ⌃ held, or ⌥ held with an arrow, Delete,
/// Forward Delete, Return, Enter, Tab or Esc (`optionKeyCodes`, the owner's answer of
/// 2026-11-01) → a shortcut; anything else → a typed mark. ⇧ alone never makes a shortcut, and
/// ⌥ with any other key types a character (⌥E is é), so it is typed.
///
/// **The spelling**: the held modifiers in the order `cmd`, `ctrl`, `opt`, `shift`, then the
/// key — `namedKeys` by its virtual key code, else the character lowercased, `+` spelled `plus`,
/// and an empty, whitespace or control character `key<code>` — joined by `+`, so the core's
/// check (`cursor_file_check.rs`) accepts every one this writes.
enum CursorKeyFilter {
    /// ← → ↓ ↑ (123 124 125 126), Delete (51), Forward Delete (117), Return (36), keypad Enter
    /// (76), Tab (48) and Esc (53): the keys ⌥ alone makes a shortcut of. Their spellings are
    /// the core's `OPTION_SHORTCUT_KEYS`.
    static let optionKeyCodes: Set<Int> = [123, 124, 125, 126, 51, 117, 36, 76, 48, 53]

    /// The keys spelled by name, by their kVK codes (Carbon's `Events.h`).
    static let namedKeys: [Int: String] = [
        36: "return", 76: "enter", 48: "tab", 49: "space", 51: "delete", 117: "forwarddelete",
        53: "esc", 123: "left", 124: "right", 125: "down", 126: "up", 115: "home", 119: "end",
        116: "pageup", 121: "pagedown", 114: "help",
        122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6", 98: "f7", 100: "f8",
        101: "f9", 109: "f10", 103: "f11", 111: "f12", 105: "f13", 107: "f14", 113: "f15",
        106: "f16", 64: "f17", 79: "f18", 80: "f19", 90: "f20",
    ]

    /// Whether the key-down is a shortcut: not an auto-repeat, and ⌘ or ⌃ held, or ⌥ held with
    /// one of `optionKeyCodes`. The source reads a character only when this is true.
    static func isShortcut(_ event: CursorKeyEvent) -> Bool {
        guard !event.isRepeat else { return false }
        if event.modifiers.contains(.cmd) || event.modifiers.contains(.ctrl) { return true }
        return event.modifiers.contains(.opt) && optionKeyCodes.contains(event.keyCode)
    }

    /// The shortcut's `+`-joined spelling (the type doc).
    static func spelled(_ event: CursorKeyEvent) -> String {
        var tokens: [String] = []
        if event.modifiers.contains(.cmd) { tokens.append("cmd") }
        if event.modifiers.contains(.ctrl) { tokens.append("ctrl") }
        if event.modifiers.contains(.opt) { tokens.append("opt") }
        if event.modifiers.contains(.shift) { tokens.append("shift") }
        tokens.append(keyName(event))
        return tokens.joined(separator: "+")
    }

    /// The key's own token: its name, else its character, else `key<code>`.
    private static func keyName(_ event: CursorKeyEvent) -> String {
        if let name = namedKeys[event.keyCode] { return name }
        let character = (event.character ?? "").lowercased()
        let plain =
            !character.isEmpty
            && character.unicodeScalars.allSatisfy { scalar in
                !scalar.properties.isWhitespace
                    && scalar.properties.generalCategory != .control
                    && scalar.properties.generalCategory != .format
            }
        guard plain else { return "key\(event.keyCode)" }
        return character.replacingOccurrences(of: "+", with: "plus")
    }

    /// The whole rule (the type doc): `secure` is `IsSecureEventInputEnabled()` at delivery.
    static func entry(for event: CursorKeyEvent, secure: Bool) -> CursorKeyEntry {
        if secure { return .none }
        if event.isRepeat { return .typed }
        guard isShortcut(event) else { return .typed }
        return .shortcut(keys: spelled(event), code: event.keyCode)
    }
}
