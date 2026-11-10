import AppKit

/// Clip ▸ Voice ▸'s decisions (spec §11 AU-158, #390): what a tag says, which
/// clips a choice goes to, what it writes and what mark an item carries. The
/// menu is built by `AppDelegate.voiceMenu()` from `VoiceGroup` and
/// `VoiceKind`, the list the Sound tab's Voice Effect popup is built from
/// (`AudioPane+Voice.swift`); the action and the validator arm are
/// `EditorViewController+Voice.swift`. `set_audio`'s `voice` is the MCP
/// mirror.
enum VoiceMenu {
    /// The one tag that means None, as `voiceMenu()` writes it.
    static let noneTag = -1

    /// A kind's tag: its index in `VoiceKind.allCases`.
    static func tag(of kind: VoiceKind) -> Int {
        VoiceKind.allCases.firstIndex(of: kind) ?? Int.min
    }

    /// What a tag SAYS: `.some(kind)` for an index into the vocabulary,
    /// `.some(nil)` for None, nil for a tag no builder writes.
    static func kind(tag: Int) -> VoiceKind?? {
        if tag == noneTag { return .some(nil) }
        let kinds = VoiceKind.allCases
        return kinds.indices.contains(tag) ? .some(kinds[tag]) : nil
    }

    /// The selected clips a voice effect goes to: the Voice Effect section's,
    /// the clips with sound (`InspectorTab.hasAudio`). The core has no audio
    /// properties to patch on any other clip.
    static func targets(_ clips: [ClipSnapshot], in snapshot: ProjectSnapshot) -> [ClipSnapshot] {
        clips.filter { InspectorTab.hasAudio($0, in: snapshot) }
    }

    /// What a choice sends. None is one `set_audio {voice: null}` over the
    /// targets. A kind is one `set_audio` per target, because each clip keeps
    /// its OWN amount (1 with none; Look ▸'s rule) and a patch carries one
    /// amount; the stored pitch goes, so the kind starts at its own
    /// (`VoiceProps.choosing`). Nothing for no target.
    static func ops(_ kind: VoiceKind?, targets: [ClipSnapshot]) -> [ReelOp] {
        guard !targets.isEmpty else { return [] }
        guard let kind else {
            return [.setAudio(clips: targets.map(\.id), patch: AudioPatch(voice: .some(nil)))]
        }
        return targets.map { clip in
            let voice = VoiceProps.choosing(kind, over: clip.audioProps.voice)
            return .setAudio(clips: [clip.id], patch: AudioPatch(voice: .some(voice)))
        }
    }

    /// An item's mark, Look ▸'s rule (GR-7 [b] (3)): on when every target's
    /// kind is `kind` (None: no effect), dashed when some but not all are,
    /// off otherwise. Amount and pitch are not read.
    static func state(_ kind: VoiceKind?, targets: [ClipSnapshot]) -> NSControl.StateValue {
        let carrying = targets.filter { $0.audioProps.voice?.kind == kind }.count
        if carrying == 0 { return .off }
        return carrying == targets.count ? .on : .mixed
    }
}
