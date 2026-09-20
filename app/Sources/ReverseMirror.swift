import CoreMedia
import Foundation

/// The reversed mirror — the app's ONE spelling of "what does this clip show
/// there, when it plays backwards?" (spec §11, D4-6).
///
/// **The convention.** `Source::Media.reversed` measures the `in` point in the
/// REVERSED stream (`Source::Media` in `core/src/model.rs`), so a reversed
/// clip keeps its `in` and shows different frames. Everything the app holds
/// about the file — the peaks cache, the thumbnails, the decoded asset — is of
/// the FORWARD one, and nothing ever generates either for `cache/reversed/…`,
/// which is not a media entry at all. So a tick `p` measured in the played
/// stream reads the forward file at `pivot − p`, and the pivot is the media's
/// MODEL duration `T`: the number `in` is measured against, and the number
/// `ReverseRenderer` renders against, which is what makes the two line up.
///
/// **Why the core has none, and why this is not it.** `edit_clip.rs`'s
/// `set_reversed` argues the refusal: advancing `in` to keep the same frames
/// would be a second convention, and every trim, split and source-length
/// reader in the crate would have to know which one was in force. The mirror
/// is therefore a PRESENTATION question — which cached bucket, which decoded
/// stamp — and it belongs on this side. §10.6's fourth decision.
///
/// **Its three readers, which agreed by convention only until this file.**
/// `MediaPeaks.window` mirrors a bucket window (`lo = pivot − last`,
/// `hi = pivot − first`); `TimelineView.sourceTime` mirrors the tick a
/// filmstrip tile and a waveform column index the caches at; and
/// `ReverseRenderer.walkBackwards` mirrors the presentation stamps it writes.
/// Nothing asserted that the three matched, and `TimelineView` in fact did not
/// mirror at all until road map 7 §10's phase C.
/// `CompositionBuilder` deliberately has no mirror and needs none: it
/// substitutes the pre-rendered reversed asset, whose times already run in the
/// played direction.
///
/// **One tick high, on purpose.** A reversed tick `p` covers the forward
/// file's tick `T − 1 − p`, and this answers `T − p`. The cost is an extra
/// bucket at an exactly aligned window end and one blank waveform column at
/// the head of a whole-file reversed clip whose `T` is a bucket multiple; the
/// reason it stays is that `tools/proof/silence2_proof.py`'s claim 9 walks
/// these numbers tick-exact, so moving them would move a reference walk that
/// exists to catch this arithmetic drifting. Recorded in road map 7 §10.9.
///
/// Nothing here is AppKit, nothing reads a file and nothing decides anything:
/// it is one subtraction, in the three units its callers hold it in.
enum ReverseMirror {

    /// The pivot a clip's source times are mirrored about — the media's model
    /// duration — or nil when the clip plays forwards or its media is unknown.
    ///
    /// This function finds the pivot for ANY clip it is handed. What cannot
    /// reach it is a clip inside a CLOSED nest: `Project::clip` searches the
    /// top level only, so a caller that looked the clip up there has nothing
    /// to hand here. Such a clip is measured unmirrored while the nest
    /// is closed — a recorded limit with an escape since road map 2's phase 9:
    /// OPEN the nest (⌘↓) and the scoped view puts that clip at the top level,
    /// where the pivot is found.
    ///
    /// No check of the source KIND beyond `isReversed`, which only a `media`
    /// source can be true for.
    static func pivot(for clip: ClipSnapshot, in snapshot: ProjectSnapshot) -> Ticks? {
        guard clip.source.isReversed else { return nil }
        return snapshot.media(for: clip)?.duration
    }

    /// The forward file's tick under a tick of the reversed stream.
    ///
    /// May go negative — a reversed clip whose window runs past the media's
    /// start produces one, which `MediaPeaks.bucketIndex` is spelled out for.
    static func mirrored(_ tick: Ticks, about pivot: Ticks) -> Ticks {
        pivot - tick
    }

    /// A whole window mirrored: the ends swap, because the mirror reverses
    /// order. `MediaPeaks.window`'s `lo` and `hi`, exactly.
    static func mirrored(_ window: ClosedRange<Ticks>, about pivot: Ticks) -> ClosedRange<Ticks> {
        (pivot - window.upperBound)...(pivot - window.lowerBound)
    }

    /// The same subtraction in `CMTime`, for the renderer: the frame shown
    /// from `p` until `p'` in the source is written at `T − p'`, so the
    /// source's last frame lands at zero and the stamps ascend.
    ///
    /// `CMTime` subtraction carries its own timescale arithmetic, so the two
    /// sides need not share one — the pivot is in tick scale and a source
    /// stamp is in its track's.
    static func mirrored(_ time: CMTime, about pivot: CMTime) -> CMTime {
        pivot - time
    }
}
