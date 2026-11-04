import Foundation

/// `reframe_clip`'s `subjects` (spec §11 VR-26, VR-28; road map
/// "creator-jobs" VR2a2), built from the analysis store: the JSON the core's
/// strict reader takes, `{samples: [{t, faces, people, salient}], shots: [t]}`
/// in forward-media source ticks, boxes `{x, y, w, h, c}` 0…1 of the upright
/// picture from its top-left (CJ-22, VR-10), a face's with its `mouth` — its
/// mouth gap over its width, SW-81's opening — when both were read, the width
/// is above 0 and the gap at least 0 (VR6a, spec §11 VR-60 (b)); only
/// `follow: speaker` reads it.
///
/// - **Samples.** The `faces` grid (VR-11), which `subjects` shares: each
///   index inside `windows` that BOTH kinds' markers cover is one sample at
///   `grid.ticks(of: k)`, with that index's faces, people and salient boxes.
/// - **Boxes.** Each is clamped into the picture and dropped when no area is
///   left — Vision's edge faces reach outside 0…1, and the core refuses a
///   coordinate there — and each kind keeps its first `maxBoxes` in stored
///   order (CJ-31's).
/// - **Shots.** `AnalysisShots.cuts` over each window's indices that the
///   `shots` marker covers, answered as each cut's frame pts.
///
/// Reads files only, so it runs off main (`AgentServer+Framing.swift`); names
/// no `rc_*`.
enum FramingSubjects {
    /// The most boxes of a kind per sample: the core's `MAX_SUBJECT_BOXES`.
    static let maxBoxes = 8

    static func read(media: MediaSnapshot, windows: [ClosedRange<Ticks>], cacheDir: URL)
        -> [String: Any]
    {
        let grid = AnalysisKind.faces.grid(of: media)
        let facesMarker = AnalysisStore.readMarker(.faces, media: media.id, in: cacheDir)
        let subjectsMarker = AnalysisStore.readMarker(.subjects, media: media.id, in: cacheDir)
        let faces = payload(.faces, facesMarker, media, cacheDir)
            .flatMap(AnalysisFaces.decode)?.samples ?? []
        let subjects = payload(.subjects, subjectsMarker, media, cacheDir)
            .flatMap(AnalysisSubjects.decode)?.samples ?? []
        let both = (facesMarker?.ranges ?? [], subjectsMarker?.ranges ?? [])
        var samples: [[String: Any]] = []
        for window in windows {
            guard let indices = grid.indices(from: window.lowerBound, to: window.upperBound)
            else { continue }
            for k in indices where holds(both.0, k) && holds(both.1, k) {
                var sample: [String: Any] = ["t": grid.ticks(of: k)]
                let found = k < faces.count ? faces[k].faces : []
                sample["faces"] = boxes(
                    found.map { ($0.x, $0.y, $0.width, $0.height, $0.confidence) },
                    mouths: found.map(mouth))
                let there = k < subjects.count ? subjects[k].subjects : .init(people: [], salient: [])
                sample["people"] = boxes(there.people.map {
                    ($0.x, $0.y, $0.width, $0.height, $0.confidence)
                })
                sample["salient"] = boxes(there.salient.map {
                    ($0.x, $0.y, $0.width, $0.height, $0.confidence)
                })
                samples.append(sample)
            }
        }
        return ["samples": samples, "shots": shots(media: media, windows: windows, cacheDir)]
    }

    /// Each cut's pts among the windows' indices the `shots` marker covers,
    /// ascending, once each.
    private static func shots(media: MediaSnapshot, windows: [ClosedRange<Ticks>], _ cacheDir: URL)
        -> [Ticks]
    {
        let grid = AnalysisKind.shots.grid(of: media)
        let marker = AnalysisStore.readMarker(.shots, media: media.id, in: cacheDir)
        guard let marker, let data = payload(.shots, marker, media, cacheDir) else { return [] }
        let records = AnalysisShots.decode(data, count: grid.count)
        var found = Set<Ticks>()
        for window in windows {
            guard let indices = grid.indices(from: window.lowerBound, to: window.upperBound)
            else { continue }
            for covered in marker.ranges where covered.overlaps(indices) {
                let piece = max(covered.lowerBound, indices.lowerBound)...min(
                    covered.upperBound, indices.upperBound)
                for k in AnalysisShots.cuts(records, in: piece) where k < records.count {
                    found.insert(records[k].pts)
                }
            }
        }
        return found.sorted()
    }

    /// The kind's first payload file, as the marker names it.
    private static func payload(
        _ kind: AnalysisKind, _ marker: AnalysisMarker?, _ media: MediaSnapshot, _ cacheDir: URL
    ) -> Data? {
        guard let file = marker?.files.first else { return nil }
        return AnalysisStore.readPayload(kind, media: media.id, file: file, in: cacheDir)
    }

    private static func holds(_ ranges: [ClosedRange<Int>], _ k: Int) -> Bool {
        ranges.contains { $0.contains(k) }
    }

    /// A face's mouth gap over its width; nil when either is unread, the width
    /// is not above 0 or the gap is below 0 (VR-60 (b)).
    static func mouth(_ face: AnalysisFaces.Face) -> Double? {
        let gap = Double(face.mouthGap), width = Double(face.mouthWidth)
        guard gap.isFinite, width.isFinite, width > 0, gap >= 0 else { return nil }
        return gap / width
    }

    /// Boxes clamped into the picture, the empty ones dropped, the first
    /// `maxBoxes` kept; a face's `mouth` when `mouths` gives one.
    private static func boxes(
        _ raw: [(Float, Float, Float, Float, Float)], mouths: [Double?] = []
    ) -> [[String: Any]] {
        var out: [[String: Any]] = []
        for (index, (x, y, w, h, c)) in raw.enumerated() {
            let values = [x, y, w, h, c].map(Double.init)
            guard values.allSatisfy(\.isFinite) else { continue }
            let (x0, y0) = (max(0, values[0]), max(0, values[1]))
            let (x1, y1) = (min(1, values[0] + values[2]), min(1, values[1] + values[3]))
            guard x1 > x0, y1 > y0 else { continue }
            var box: [String: Any] = [
                "x": x0, "y": y0, "w": x1 - x0, "h": y1 - y0, "c": min(1, max(0, values[4])),
            ]
            if index < mouths.count, let mouth = mouths[index] { box["mouth"] = mouth }
            out.append(box)
            if out.count == maxBoxes { break }
        }
        return out
    }
}
