import Foundation

/// A clip's voice effect as Swift reads it (format 34, spec §11 AU-140):
/// the core's `audio.voice`, `{kind, amount, pitch}`. The chains are
/// `VoiceChain.swift`'s, the render `VoiceRenderer.swift`'s.

/// The four groups E8 sorts the kinds into, in its order (AU-146: the popup
/// carries them in its titles; AU-158: Clip ▸ Voice ▸ carries them as its
/// section headers).
enum VoiceGroup: String, CaseIterable {
    case voice, tone, character, space

    /// The group's kinds, in E8's order.
    var kinds: [VoiceKind] { VoiceKind.allCases.filter { $0.group == self } }

    var title: String {
        switch self {
        case .voice: return "Voice"
        case .tone: return "Tone"
        case .character: return "Character"
        case .space: return "Space"
        }
    }
}

/// The sixteen kinds, in E8's order — the core's `VoiceKind`, spelled as it
/// persists them.
enum VoiceKind: String, Codable, CaseIterable {
    case pitch, high, deep, robot, bass, treble, bright, telephone, radio, lofi, distorted, echo,
        room, hall, plate, cathedral

    var group: VoiceGroup {
        switch self {
        case .pitch, .high, .deep, .robot: return .voice
        case .bass, .treble, .bright, .telephone, .radio: return .tone
        case .lofi, .distorted: return .character
        case .echo, .room, .hall, .plate, .cathedral: return .space
        }
    }

    /// "Pitch" … "Cathedral": the kind's name alone, Clip ▸ Voice ▸'s item
    /// under its group's header (AU-158).
    var name: String {
        switch self {
        case .pitch: return "Pitch"
        case .high: return "High"
        case .deep: return "Deep"
        case .robot: return "Robot"
        case .bass: return "Bass"
        case .treble: return "Treble"
        case .bright: return "Bright"
        case .telephone: return "Telephone"
        case .radio: return "Radio"
        case .lofi: return "Lo-Fi"
        case .distorted: return "Distorted"
        case .echo: return "Echo"
        case .room: return "Room"
        case .hall: return "Hall"
        case .plate: return "Plate"
        case .cathedral: return "Cathedral"
        }
    }

    /// "Voice: Pitch" … "Space: Cathedral", the popup's titles (AU-146).
    var title: String { "\(group.title): \(name)" }

    /// Whether the kind reads `pitch` (AU-140): pitch, high and deep.
    var usesPitch: Bool { self == .pitch || self == .high || self == .deep }

    /// The semitones an absent `pitch` means: 0, +5 and −5 for the three
    /// that read it, else 0.
    var defaultPitch: Double {
        switch self {
        case .high: return 5
        case .deep: return -5
        default: return 0
        }
    }
}

/// `audio.voice`. Writes ALWAYS carry `pitch` — the value, or `NSNull()`
/// when nil — so a kind change drops a stored pitch back to the new kind's
/// own (AU-146).
struct VoiceProps: Codable, Equatable {
    var kind: VoiceKind
    var amount: Double = 1
    var pitch: Double? = nil

    init(kind: VoiceKind, amount: Double = 1, pitch: Double? = nil) {
        self.kind = kind
        self.amount = amount
        self.pitch = pitch
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(VoiceKind.self, forKey: .kind)
        amount = c.lenient(.amount, 1)
        pitch = c.lenient(.pitch)
    }

    /// The patch's body (`AudioPatch.dictionary`).
    var dictionary: [String: Any] {
        ["kind": kind.rawValue, "amount": amount, "pitch": pitch.map { $0 as Any } ?? NSNull()]
    }

    /// The semitones the chain shifts by: `pitch ??` the kind's own.
    var semitones: Double { pitch ?? kind.defaultPitch }

    /// What choosing `kind` writes over `current` — the popup's rule and the
    /// menu's (AU-146, AU-158): None clears; a kind keeps the amount (1 with
    /// none) and sends `pitch: null`, so every kind starts at its own pitch.
    static func choosing(_ kind: VoiceKind?, over current: VoiceProps?) -> VoiceProps? {
        guard let kind else { return nil }
        return VoiceProps(kind: kind, amount: current?.amount ?? 1, pitch: nil)
    }
}
