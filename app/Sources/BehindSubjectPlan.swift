import Foundation

/// Insert ▸ Text Behind Subject's planner (road map creator-jobs CO5, spec
/// §11 CO-53), pure over a snapshot: which clip the title goes behind, where
/// its new track goes, how long it lasts and the ops that make it in one
/// undo step. Both doors call it — the menu
/// (`EditorViewController+BehindSubject.swift`) and `text_behind_subject`
/// (`AgentServer+BehindSubject.swift`) — and both are top-level only.
///
/// - **Candidates at `at`:** top-level clips playing at `at` (start ≤ at <
///   end) that `CutoutStatus.canCutOut` — of a video file, or a picture
///   (spec §11 CO-108) — with their video on, on a track neither hidden nor
///   a matte track.
/// - **The pick:** the named clip; else the front-most selected candidate;
///   else the front-most candidate with a base cutout; else the front-most.
/// - **The track:** a new "Behind Subject" track directly above the clip's
///   track and above the unbroken run of matte tracks in front of it, so it
///   sits behind an ordinary track or at the front and no matte targets it
///   (MT-2): with `[V, M1→V, M2]` it goes to index 3, not 2.
/// - **The ops:** `add_track`, `add_text_clip` (the Title preset) at `at`
///   for min(4 s, the clip's rest), `set_video {behind_subject: true}` on the
///   title and, only when the clip has no base cutout, `set_video {cutout:
///   {background: keep}}` on it (a person's, a picture's too). A new track's
///   id is `next_id` from before the op, the title's the one after it
///   (`generatedClipOps`' contract).
enum BehindSubjectPlan {
    /// The undo step's name, both doors'.
    static let actionName = "Text Behind Subject"
    /// The new track's name.
    static let trackName = "Behind Subject"
    /// The longest title it places.
    static let longest: Ticks = 4 * ReelTime.perSecond

    /// What one run plans.
    struct Plan: Equatable {
        /// The clip the title goes behind.
        let clip: UInt32
        let at: Ticks
        let duration: Ticks
        /// Where `add_track` inserts the new track (0 is the back).
        let trackIndex: Int
        /// The new track's id and the title's.
        let track: UInt32
        let text: UInt32
        /// Whether the clip is given `cutout: {background: keep}`.
        let addsCutout: Bool
    }

    /// Why there is no plan, each in its own sentence.
    enum Refusal: Error, Equatable {
        case noClip(at: Ticks)
        case cannotHold(clip: UInt32)
        case notAt(clip: UInt32, at: Ticks)

        var sentence: String {
            switch self {
            case .noClip(let at):
                return "No clip of a video file or picture plays at \(at) on a shown track that "
                    + "is not a matte track, so there is no one to put the title behind."
            case .cannotHold(let id):
                return "Clip \(id) cannot have a title put behind its subject: it must be a "
                    + "clip of a video file or a picture on the timeline, on a shown track that "
                    + "is not a matte track."
            case .notAt(let id, let at):
                return "Clip \(id) does not play at \(at): pass an at inside it."
            }
        }
    }

    /// Whether `clip` is of a kind and on a track that can hold a title
    /// behind its subject, whatever the time.
    private static func canHold(_ clip: ClipSnapshot, in snapshot: ProjectSnapshot) -> Bool {
        guard clip.enabled.video, CutoutStatus.canCutOut(clip, in: snapshot),
            let track = snapshot.tracks.first(where: { $0.id == clip.track })
        else { return false }
        return !track.hidden && track.matte == .none
    }

    /// The candidates at `at`, front-most first (a later start first on one
    /// track, the incoming half of a dissolve).
    static func candidates(in snapshot: ProjectSnapshot, at: Ticks) -> [ClipSnapshot] {
        let index = trackIndices(snapshot)
        return snapshot.clips
            .filter { $0.start <= at && at < $0.end && canHold($0, in: snapshot) }
            .sorted {
                let (a, b) = (index[$0.track] ?? 0, index[$1.track] ?? 0)
                return a != b ? a > b : $0.start > $1.start
            }
    }

    /// The plan at `at` for `clip` when named, else by the pick order.
    static func plan(
        in snapshot: ProjectSnapshot, at: Ticks, selection: Set<UInt32>, clip: UInt32?
    ) -> Result<Plan, Refusal> {
        let chosen: ClipSnapshot
        if let clip {
            guard let found = snapshot.clips.first(where: { $0.id == clip }),
                canHold(found, in: snapshot)
            else { return .failure(.cannotHold(clip: clip)) }
            guard found.start <= at, at < found.end else {
                return .failure(.notAt(clip: clip, at: at))
            }
            chosen = found
        } else {
            let all = candidates(in: snapshot, at: at)
            guard
                let picked = all.first(where: { selection.contains($0.id) })
                    ?? all.first(where: { $0.video?.cutout != nil }) ?? all.first
            else { return .failure(.noClip(at: at)) }
            chosen = picked
        }
        let tracks = snapshot.tracks
        guard let own = tracks.firstIndex(where: { $0.id == chosen.track }) else {
            return .failure(.cannotHold(clip: chosen.id))
        }
        // Past the unbroken run of matte tracks in front of the clip's track.
        var index = own + 1
        while index < tracks.count, tracks[index].matte != .none { index += 1 }
        return .success(
            Plan(
                clip: chosen.id, at: at, duration: min(longest, chosen.end - at),
                trackIndex: index, track: snapshot.nextId, text: snapshot.nextId + 1,
                addsCutout: chosen.video?.cutout == nil))
    }

    /// The plan's ops, one undo step: three, or four with the cutout.
    static func ops(_ plan: Plan, content: String?) -> [ReelOp] {
        var ops: [ReelOp] = [
            .addTrack(index: plan.trackIndex, name: trackName),
            .addTextClip(
                track: plan.track, at: plan.at, duration: plan.duration,
                text: content.map { TextPatch(content: $0) }),
            .setVideo(clips: [plan.text], patch: VideoPatch(behindSubject: true)),
        ]
        if plan.addsCutout {
            ops.append(
                .setVideo(
                    clips: [plan.clip],
                    patch: VideoPatch(cutout: .some(CutoutProps(background: .keep)))))
        }
        return ops
    }

    /// Whether `clip`'s layer in `recipe` is cut by a subject — a group a
    /// subject copy is drawn into (CO-50); nil when the clip has no layer.
    static func isCutBySubject(clip: UInt32, in recipe: FrameRecipe) -> Bool? {
        guard
            let layer = recipe.layers.first(where: {
                $0.clip == clip && $0.cutout?.subjectCopy != true
            })
        else { return nil }
        let subjects = Set(
            recipe.layers.compactMap { $0.cutout?.subjectCopy == true ? $0.matte?.into : nil })
        return layer.matte?.cut.contains(where: { subjects.contains($0) }) ?? false
    }

    /// Each track's index, by id.
    private static func trackIndices(_ snapshot: ProjectSnapshot) -> [UInt32: Int] {
        Dictionary(
            snapshot.tracks.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { first, _ in first })
    }
}
