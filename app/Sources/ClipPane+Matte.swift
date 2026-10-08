import AppKit

/// The Clip tab's matte note (spec §11 MT-7, MT-4): every sub-tab opens with
/// it when the selection is all matte clips of one mode, because a matte
/// clip's blend mode, drop shadow and reflection are kept in the model but
/// not drawn (the core emits `normal`, `null`, `null`). The note says so and
/// changes nothing: every control stays live, and its values come back into
/// play when the track stops being a matte. `ClipHeaderBlock` shows it under
/// the sub-tab strip; whether it shows is part of `structureSignature`.
extension ClipPane {
    /// The note for `clips` — the selection — over `tracks`, the container
    /// the Clip tab reads (the open nest's tracks inside one): nil unless
    /// every clip sits on a matte track and those tracks share one mode;
    /// then "Nothing is behind…" when none of them has a target (MT-2), else
    /// "Matte for the track below (<mode>)…".
    static func matteNote(clips: [ClipSnapshot], tracks: [TrackSnapshot]) -> String? {
        guard !clips.isEmpty else { return nil }
        var matteTracks: [TrackSnapshot] = []
        for clip in clips {
            guard let track = tracks.first(where: { $0.id == clip.track }),
                  track.matte != .none
            else { return nil }
            if !matteTracks.contains(where: { $0.id == track.id }) { matteTracks.append(track) }
        }
        let mode = matteTracks[0].matte
        guard matteTracks.allSatisfy({ $0.matte == mode }) else { return nil }
        if matteTracks.allSatisfy({ TrackMatte.target(of: $0.id, in: tracks) == nil }) {
            return "Nothing is behind this matte track, so it cuts nothing."
        }
        return "Matte for the track below (\(mode.displayName)). Not drawn: its blend mode, "
            + "drop shadow and reflection have no effect."
    }

    /// The note for the current selection, read where the pane reads it.
    var matteNote: String? {
        Self.matteNote(clips: binding.clips, tracks: binding.snapshot.tracks)
    }
}
