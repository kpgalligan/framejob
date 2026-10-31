import Foundation

/// A clip's voice effect as Swift reads it (format 34, spec §11 AU-140):
/// the core's `audio.voice`, `{kind, amount, pitch}`. The chains are
/// `VoiceChain.swift`'s, the render `VoiceRenderer.swift`'s.

/// The four groups E8 sorts the kinds into, in its order (AU-146: the popup
/// carries them in its titles).
enum VoiceGroup: String, CaseIterable {
    case voice, tone, character, space

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

    /// "Voice: Pitch" … "Space: Cathedral" (AU-146).
    var title: String {
        let name: String
        switch self {
        case .pitch: name = "Pitch"
        case .high: name = "High"
        case .deep: name = "Deep"
        case .robot: name = "Robot"
        case .bass: name = "Bass"
        case .treble: name = "Treble"
        case .bright: name = "Bright"
        case .telephone: name = "Telephone"
        case .radio: name = "Radio"
        case .lofi: name = "Lo-Fi"
        case .distorted: name = "Distorted"
        case .echo: name = "Echo"
        case .room: name = "Room"
        case .hall: name = "Hall"
        case .plate: name = "Plate"
        case .cathedral: name = "Cathedral"
        }
        return "\(group.title): \(name)"
    }

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
}
