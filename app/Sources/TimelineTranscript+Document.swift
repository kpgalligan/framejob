import Foundation

/// The document read `get_timeline_transcript` does, factored out unchanged
/// so the Transcript tab (road map "creator-jobs" TX2a) and the tool share
/// it (spec §11 TX-10, TX-12, TX-22): the edited container's instances and
/// clips with no words, each heard media's record and URL, the media the
/// fill needs in order, a media's cloud words, and a stored whole-file run.
extension TimelineTranscript {

    /// What one main-thread read of a document holds.
    struct DocumentRead {
        let snapshot: ProjectSnapshot
        let instances: [Instance]
        let noWords: [NoWords]
        let records: [UInt32: MediaSnapshot]
        let urls: [UInt32: URL]
        let cacheDir: URL?
        let playhead: Ticks
    }

    /// A plan with nothing in it, for a container the core gave none.
    private static let noPlan = ReelJSON.decode(CompositionPlan.self, from: "{}")

    /// The edited container's read. Main only; nil when no plan can be read.
    static func read(document: ProjectDocument) -> DocumentRead? {
        let edited = document.editedProject
        let snapshot = edited.snapshot
        let urls = document.mediaURLs()
        var scoped: [UInt32: ReelProject] = [:]
        guard let plan = edited.plan ?? noPlan else { return nil }
        let read = read(
            plan: plan, snapshot: snapshot, urls: urls,
            maps: { clip, nestPath in
                guard !nestPath.isEmpty else { return edited.sourceMap(clip) }
                guard let nest = snapshot.nests.first(where: { $0.clips.contains { $0.id == clip } })
                else { return nil }
                if scoped[nest.id] == nil { scoped[nest.id] = document.project.scoped(nest.id) }
                return scoped[nest.id]?.sourceMap(clip)
            })
        var records: [UInt32: MediaSnapshot] = [:]
        for instance in read.instances {
            let id = instance.job.media
            guard records[id] == nil, let record = snapshot.media(id) else { continue }
            records[id] = record
        }
        return DocumentRead(
            snapshot: snapshot, instances: read.instances, noWords: read.noWords,
            records: records, urls: urls, cacheDir: document.cacheDirectory,
            playhead: document.playhead)
    }

    /// The media the instances meeting `window` need, in the fill's order:
    /// the one under the playhead first, then by first start (TX-12).
    static func neededMedia(
        _ instances: [Instance], window: TranscriptReader.Window?, playhead: Ticks
    ) -> [UInt32] {
        var order: [(media: UInt32, first: Ticks, underPlayhead: Bool)] = []
        for instance in instances {
            let start = instance.segment.start
            let end = start + instance.segment.duration
            if let window, !(start < window.to && end > window.from) { continue }
            let under = start <= playhead && playhead < end
            if let at = order.firstIndex(where: { $0.media == instance.job.media }) {
                order[at].first = min(order[at].first, start)
                order[at].underPlayhead = order[at].underPlayhead || under
            } else {
                order.append((instance.job.media, start, under))
            }
        }
        order.sort { ($0.underPlayhead ? 0 : 1, $0.first, $0.media) < ($1.underPlayhead ? 0 : 1, $1.first, $1.media) }
        return order.map(\.media)
    }

    /// A media's cached cloud transcript as words, when its marker serves
    /// captions (TR-11); nil otherwise.
    static func cloudWords(_ record: MediaSnapshot, url: URL, cacheDir: URL) -> MediaWords? {
        guard let cached = TranscriptReader.cached(for: record, url: url, in: cacheDir) else {
            return nil
        }
        return MediaWords(
            media: record.id, engine: .assemblyai, language: cached.file.header.languageCode,
            fillersReported: cached.fillersReported, words: sourceWords(cloud: cached.file))
    }

    /// The fill's item for a media read whole in `language`; nil when the
    /// file cannot be stamped (it cannot be read).
    static func fillItem(
        _ record: MediaSnapshot, url: URL, cacheDir: URL, language: Transcriber.Language
    ) -> TranscriptFill.Item? {
        guard
            let stamp = DeviceTranscriptCache.currentStamp(
                record, url: url, language: language.identifier)
        else { return nil }
        return TranscriptFill.Item(
            media: record.id, url: url, name: record.name, duration: record.duration, stamp: stamp,
            cacheDir: cacheDir, language: language, record: record)
    }

    /// A stored whole-file run of `item`'s media as words, engine `.apple`;
    /// nil when none is stored.
    static func deviceWords(_ item: TranscriptFill.Item) -> MediaWords? {
        guard
            let heard = DeviceTranscriptCache.lookup(
                item.job, media: item.media, stamp: item.stamp, in: item.cacheDir)
        else { return nil }
        return MediaWords(
            media: item.media, engine: .apple, language: item.language.identifier,
            fillersReported: false, words: sourceWords(device: heard))
    }
}
