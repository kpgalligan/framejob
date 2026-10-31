import Foundation

/// Normalize's chosen mode and loudness target (spec §11 AU-15): app-wide in
/// UserDefaults, set by the Volume section's Mode popup and Target field, and
/// followed by its Normalize button and by Clip ▸ Normalize, whose title stays
/// "Normalize". Loudness and −16 LUFS by default (AU-4, AU-25: from AP2's
/// limiter). `normalize_clip` does not read it: the tool names its mode.
enum NormalizeChoice {
    static let modeKey = "FrameJobNormalizeMode"
    static let targetKey = "FrameJobNormalizeTargetLUFS"

    static var mode: AudioNormalize.Mode {
        get {
            UserDefaults.standard.string(forKey: modeKey).flatMap(AudioNormalize.Mode.init)
                ?? .loudness
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: modeKey) }
    }

    /// An unreadable or out-of-range stored value reads as the default.
    static var targetLUFS: Double {
        get {
            guard let stored = UserDefaults.standard.object(forKey: targetKey) as? NSNumber
            else { return AudioNormalize.defaultTargetLUFS }
            let value = stored.doubleValue
            guard value.isFinite, AudioNormalize.targetLUFSRange.contains(value) else {
                return AudioNormalize.defaultTargetLUFS
            }
            return value
        }
        set { UserDefaults.standard.set(newValue, forKey: targetKey) }
    }
}
