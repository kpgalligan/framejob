import Foundation

/// Switch by Speaker's values, as both doors take them (spec §11 SW-26 (d)): the ranges the sheet
/// clamps to and `switch_by_speaker` refuses outside of, the four values the sheet remembers, and
/// the summary the sheet shows. Pure but for the `UserDefaults` it is handed; names no `rc_*`.
extension SpeakerSwitch.Settings {
    /// Seconds.
    static let minShotRange: ClosedRange<Double> = 0.5...30
    /// Seconds; the tool's alone (SW-26 (d)).
    static let minTurnRange: ClosedRange<Double> = 0.2...10
    /// Seconds.
    static let leadRange: ClosedRange<Double> = 0...1
    /// dB below a speaker's own level.
    static let bleedRange: ClosedRange<Double> = 3...40
    /// dB; the tool's alone (SW-26 (d)).
    static let dominanceRange: ClosedRange<Double> = 0...30
    /// Seconds.
    static let wideAfterRange: ClosedRange<Double> = 2...600
    /// The sheet's field when "Cut to the wide after" is first ticked (the owner: offered, off).
    static let wideAfterOffered = 20.0

    static let minShotKey = "FrameJobSwitchSpeakerMinShot"
    static let leadKey = "FrameJobSwitchSpeakerLead"
    /// "wide" or "hold".
    static let crosstalkKey = "FrameJobSwitchSpeakerCrosstalk"
    static let bleedKey = "FrameJobSwitchSpeakerBleed"

    /// The sheet's opening values: each remembered key clamped into its range, an absent or
    /// unreadable key the default. Read through `double(forKey:)`, so a launch argument counts.
    static func remembered(_ d: UserDefaults) -> SpeakerSwitch.Settings {
        var s = SpeakerSwitch.Settings()
        func number(_ key: String, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            guard d.object(forKey: key) != nil else { return fallback }
            let v = d.double(forKey: key)
            guard v.isFinite else { return fallback }
            return min(max(v, range.lowerBound), range.upperBound)
        }
        s.minShot = number(minShotKey, minShotRange, s.minShot)
        s.lead = number(leadKey, leadRange, s.lead)
        s.bleedDB = number(bleedKey, bleedRange, s.bleedDB)
        if let raw = d.string(forKey: crosstalkKey), let crosstalk = SpeakerSwitch.Crosstalk(rawValue: raw) {
            s.crosstalk = crosstalk
        }
        return s
    }

    /// Writes only the remembered keys whose value differs from the sheet's opening values, so a
    /// sheet pressed as it opened moves no default (mcp.py's DEFAULTS MOVED guard).
    func remember(changedFrom opened: SpeakerSwitch.Settings, in d: UserDefaults) {
        if minShot != opened.minShot { d.set(minShot, forKey: Self.minShotKey) }
        if lead != opened.lead { d.set(lead, forKey: Self.leadKey) }
        if crosstalk != opened.crosstalk { d.set(crosstalk.rawValue, forKey: Self.crosstalkKey) }
        if bleedDB != opened.bleedDB { d.set(bleedDB, forKey: Self.bleedKey) }
    }
}

extension SpeakerSwitch {
    /// "N shots: k on <name>, …. Adds M clips." — the angles in the order they first show,
    /// each named by `names` (a track id when it has none).
    static func summary(_ shots: [Shot], added: Int, names: [UInt32: String]) -> String {
        var order: [UInt32] = []
        var counts: [UInt32: Int] = [:]
        for shot in shots {
            if counts[shot.angle] == nil { order.append(shot.angle) }
            counts[shot.angle, default: 0] += 1
        }
        let each = order.map { "\(counts[$0] ?? 0) on \(names[$0] ?? "track \($0)")" }
        let count = shots.count == 1 ? "1 shot" : "\(shots.count) shots"
        let adds = added == 1 ? "1 clip" : "\(added) clips"
        return "\(count): \(each.joined(separator: ", ")). Adds \(adds)."
    }

    /// The name each of `tracks` is listed by: its own, with " (n)" — n its 1-based position
    /// from the back — when two of them share it (SW-13's rule, `SwitchAngle.angles`).
    static func titles(_ tracks: [UInt32], in snapshot: ProjectSnapshot) -> [UInt32: String] {
        let names = tracks.map { snapshot.track($0)?.name ?? "Track" }
        var out: [UInt32: String] = [:]
        for (track, name) in zip(tracks, names) {
            if names.filter({ $0 == name }).count > 1 {
                out[track] = "\(name) (\((snapshot.trackIndex(of: track) ?? 0) + 1))"
            } else {
                out[track] = name
            }
        }
        return out
    }

    /// The sheet's Microphone choices, front first: every track holding a selected `.media`
    /// clip with its sound on and a media with audio, a detached camera sound included (SW-20).
    static func microphoneChoices(_ selection: [ClipSnapshot], in snapshot: ProjectSnapshot)
        -> [UInt32]
    {
        snapshot.tracks.reversed().map(\.id).filter { track in
            selection.contains { clip in
                guard clip.track == track, case .media = clip.source, clip.enabled.audio else {
                    return false
                }
                return snapshot.media(for: clip)?.hasAudio == true
            }
        }
    }
}
