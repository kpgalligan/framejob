// app/Sources/GraphicSchema.swift — a graphic module's schema as the
// Graphic sub-tab reads it (road map 10 §5j, G5a): one entry per key, in the
// MODULE's key order. A pure move out of `GraphicSchemaRows.swift`.

import Foundation

/// One schema entry, as `describe` published it.
struct GraphicSchemaEntry: Equatable {
    let key: String, type: String, `default`: GraphicPropValue, label: String, help: String?
    let min: Double?, max: Double?, step: Double?, multiline: Bool, options: [String]
    /// The module's `animate` (spec §11 G-41); absent is true.
    var animate: Bool = true
    /// Whether an action's end may name this prop: the one test the
    /// inspector's split and the end's stale rows use.
    var animatable: Bool { animate && type != "asset" }
}

/// A module's schema, in the module's own key order.
struct GraphicSchema: Equatable {
    let entries: [GraphicSchemaEntry]

    var keys: [String] { entries.map(\.key) }

    /// The order from `describeJSON`'s text, the values from `schema` (the
    /// registry's parse, which lost the order through `JSONSerialization`).
    /// A key the dictionary lacks is dropped; a dictionary key the text
    /// lacks is appended, sorted.
    init(describeJSON: String, schema: [String: Any]) {
        var seen = Set<String>()
        var order: [String] = []
        for key in Self.orderedKeys(describeJSON: describeJSON)
        where schema[key] != nil && !seen.contains(key) {
            seen.insert(key)
            order.append(key)
        }
        order += schema.keys.filter { !seen.contains($0) }.sorted()
        entries = order.map { key in
            let entry = schema[key] as? [String: Any] ?? [:]
            func number(_ name: String) -> Double? {
                guard let value = entry[name] as? NSNumber,
                      CFGetTypeID(value) != CFBooleanGetTypeID()
                else { return nil }
                return value.doubleValue
            }
            return GraphicSchemaEntry(
                key: key, type: entry["type"] as? String ?? "",
                default: GraphicSchemaRows.value(entry["default"]),
                label: entry["label"] as? String ?? key, help: entry["help"] as? String,
                min: number("min"), max: number("max"), step: number("step"),
                multiline: (entry["multiline"] as? NSNumber)?.boolValue ?? false,
                options: entry["options"] as? [String] ?? [],
                animate: (entry["animate"] as? NSNumber)?.boolValue ?? true)
        }
    }

    /// The keys of the top-level `"schema"` object in `describe`'s JSON
    /// text, in the order the text has them — the core serialises with
    /// `preserve_order`. A scanner rather than a parser: string state with
    /// `\` escapes, a stack of `{` and `[`, and a key is a string followed
    /// by `:` directly inside an object.
    static func orderedKeys(describeJSON text: String) -> [String] {
        let bytes = Array(text.utf8)
        let quote = UInt8(ascii: "\""), backslash = UInt8(ascii: "\\")
        let colon = UInt8(ascii: ":"), comma = UInt8(ascii: ",")
        let openBrace = UInt8(ascii: "{"), closeBrace = UInt8(ascii: "}")
        let openBracket = UInt8(ascii: "["), closeBracket = UInt8(ascii: "]")
        var stack: [UInt8] = []
        var lastString: [UInt8]?
        var armed = false  // the top-level key just read is "schema"
        var inSchema = false  // inside the schema's own object (depth 2)
        var keys: [String] = []
        var i = 0
        while i < bytes.count {
            let byte = bytes[i]
            if byte == quote {
                var j = i + 1
                var string: [UInt8] = []
                while j < bytes.count, bytes[j] != quote {
                    if bytes[j] == backslash, j + 1 < bytes.count {
                        string.append(bytes[j])
                        j += 1
                    }
                    string.append(bytes[j])
                    j += 1
                }
                lastString = string
                i = j + 1
                continue
            }
            switch byte {
            case colon:
                if stack.last == openBrace, let string = lastString {
                    let key = String(decoding: string, as: UTF8.self)
                    if stack.count == 1 {
                        armed = key == "schema"
                    } else if inSchema, stack.count == 2 {
                        keys.append(key)
                    }
                }
                lastString = nil
            case openBrace, openBracket:
                if armed, stack.count == 1, byte == openBrace { inSchema = true }
                armed = false
                stack.append(byte)
            case closeBrace, closeBracket:
                _ = stack.popLast()
                if stack.count < 2 { inSchema = false }
            case comma:
                lastString = nil
                if stack.count == 1 { armed = false }
            default:
                break
            }
            i += 1
        }
        return keys
    }
}
