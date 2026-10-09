import AVFoundation

// `ExportWriter`'s chapter half: the chapter list an export writes, the text track that
// carries it, its pump, and the text samples themselves. A pure move out of
// `ExporterWriter.swift` at its size cap (issue batch B92); the members each file calls in
// the other lost `private`, and nothing else changed.

// MARK: - Chapters

/// One entry of the chapter list an export writes (spec §7.8).
///
/// Chapters come from the PROJECT, never from the composition plan: the plan
/// says what to decode and where to put it, and markers decode nothing, so
/// `evaluate.rs` emits no marker key at all. `Exporter` reads them off the
/// snapshot of the handle it was given and hands them over here, which is
/// also why an export shows the chapters the timeline had when the sheet was
/// confirmed rather than the ones it has when the write ends.
struct ExportChapter: Equatable {
    /// Timeline ticks, in the project's own time. Clamping into the exported
    /// range and rebasing to a zero-based file both happen when the samples
    /// are built, because only then is the range known.
    let start: Ticks
    /// What the chapter is called. Never empty — an unnamed marker becomes
    /// "Chapter <n>", because a chapter list of blank rows is worse in every
    /// player than no chapter list at all.
    let name: String

    /// The project's `chapter` markers, in time order and named.
    ///
    /// Numbering is over the CHAPTER markers only, so deleting a plain marker
    /// cannot renumber the chapters around it.
    static func list(from markers: [MarkerSnapshot]) -> [ExportChapter] {
        markers
            .filter(\.chapter)
            .sorted { $0.time < $1.time }
            .enumerated()
            .map { index, marker in
                let name = marker.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return ExportChapter(
                    start: marker.time, name: name.isEmpty ? "Chapter \(index + 1)" : name)
            }
    }
}

extension ExportWriter {

    /// The chapter track: a text track carrying one sample per chapter,
    /// associated with the movie's own track through
    /// `AVTrackAssociationTypeChapterList`, which is what writes the `chap`
    /// track reference every reader (QuickTime, `ffprobe -show_chapters`)
    /// looks for.
    ///
    /// Additive, never fatal: a build of macOS that will not take the text
    /// track loses the chapters, not the movie. The track is marked disabled
    /// so no player tries to draw the names over the picture.
    ///
    /// **A container that cannot hold a chapter track is refused HERE, not
    /// left to `canAdd`.** A chapter list is a second track associated with
    /// the first, which is a QuickTime-family idea; a RIFF or an IFF file is
    /// a header followed by samples with nowhere to put one. `canAdd` is the
    /// wrong guard for that because the failure it would let through is the
    /// expensive one: a `true` followed by a refusal at `finishWriting`
    /// loses the whole file, which is exactly what a malformed text format
    /// description already cost once (see `textFormat`).
    func addChapters(_ chapters: [ExportChapter], settings: ExportSettings) {
        guard Self.carriesChapters(settings), !chapters.isEmpty,
            let host = videoInput ?? audioInput, let format = Self.textFormat()
        else { return }
        let samples = Self.chapterSamples(chapters, in: range, format: format)
        guard !samples.isEmpty else { return }

        let input = AVAssetWriterInput(
            mediaType: .text, outputSettings: nil, sourceFormatHint: format)
        input.expectsMediaDataInRealTime = false
        input.marksOutputTrackAsEnabled = false
        guard writer.canAdd(input) else { return }
        writer.add(input)
        host.addTrackAssociation(
            withTrackOf: input, type: AVAssetTrack.AssociationType.chapterList.rawValue)
        chapterInput = input
        chapterSamples = samples
    }

    /// The chapter samples are a handful of tiny text buffers, all known
    /// before the write starts, so this pump has nothing to read — it drains
    /// its own array.
    func pumpChapters(
        _ input: AVAssetWriterInput, on queue: DispatchQueue, group: DispatchGroup
    ) {
        group.enter()
        var pending = chapterSamples
        var finished = false
        let stop: () -> Void = {
            guard !finished else { return }
            finished = true
            input.markAsFinished()
            group.leave()
        }
        input.requestMediaDataWhenReady(on: queue) { [weak self] in
            guard let self = self else { return }
            while input.isReadyForMoreMediaData {
                guard !finished else { return }
                guard !self.isStopping, !pending.isEmpty else {
                    stop()
                    return
                }
                let sample = pending.removeFirst()
                guard input.append(sample) else {
                    // A chapter that will not write is not worth losing the
                    // movie over: the text track simply ends here.
                    stop()
                    return
                }
            }
        }
    }

    // MARK: - Chapter samples

    /// The format one chapter sample is written in: a QuickTime text
    /// (`'text'`) description, in every container this build writes.
    ///
    /// **Why the byte structure and not `CMFormatDescriptionCreate`.** A
    /// description created from a media type and a subtype alone carries no
    /// extensions, and `AVAssetWriter` cannot serialise that into a sample
    /// description — it fails the whole write at `finishWriting` with
    /// `kCMFormatDescriptionBridgeError_InvalidParameter` (-12712), losing
    /// the movie, not just the chapters (measured). Handing the bridge the
    /// big-endian `TextDescription` the QuickTime file format specifies is
    /// exactly the shape it will write back out, so there is nothing left to
    /// guess at.
    ///
    /// **Why QuickTime text rather than 3GPP `tx3g` in the MPEG-4 family.**
    /// A `'text'` sample entry is what Apple's own chapter tracks use inside
    /// `.m4a`/`.m4v`/`.mp4`, and both QuickTime and `ffprobe`'s MOV demuxer
    /// read chapters from it; `tx3g` would mean a second byte layout and a
    /// font table for no gain.
    private static func textFormat() -> CMFormatDescription? {
        var description = Data()
        func be16(_ value: UInt16) { description.append(contentsOf: [
            UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]) }
        func be32(_ value: UInt32) { be16(UInt16(truncatingIfNeeded: value >> 16))
            be16(UInt16(truncatingIfNeeded: value)) }

        be32(60)                                   // descSize, this whole record
        be32(0x7465_7874)                          // 'text'
        be32(0)                                    // reserved
        be16(0)                                    // reserved
        be16(1)                                    // data reference index
        be32(0)                                    // display flags: none
        be32(0)                                    // text justification: left
        be16(0); be16(0); be16(0)                  // background colour: black
        be16(0); be16(0); be16(0); be16(0)         // default text box: empty
        be32(0)                                    // default style: start char
        be16(0); be16(0)                           // height, ascent
        be16(0); be16(0); be16(12)                 // font, face, size
        be16(0xFFFF); be16(0xFFFF); be16(0xFFFF)   // foreground colour: white
        description.append(0)                      // font name, an empty
        description.append(0)                      //   Pascal string, padded

        var format: CMFormatDescription?
        let status = description.withUnsafeBytes { bytes -> OSStatus in
            guard let base = bytes.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            // A nil flavor is the QuickTime Movie one.
            return CMTextFormatDescriptionCreateFromBigEndianTextDescriptionData(
                allocator: kCFAllocatorDefault, bigEndianTextDescriptionData: base,
                size: description.count, flavor: nil, mediaType: kCMMediaType_Text,
                formatDescriptionOut: &format)
        }
        return status == noErr ? format : nil
    }

    /// The chapters as samples, clamped into `range` and rebased to zero.
    ///
    /// Each chapter runs until the next one, and the last until the end of
    /// the range — a chapter list is a partition of the movie, not a set of
    /// points. A chapter that began BEFORE an in/out range is not dropped:
    /// the last of them is pinned to the start of the range, because the
    /// exported piece really is inside that chapter and a file whose first
    /// minutes belong to no chapter reads as a bug.
    private static func chapterSamples(
        _ chapters: [ExportChapter], in range: CMTimeRange, format: CMFormatDescription
    ) -> [CMSampleBuffer] {
        let start = CompositionBuilder.ticks(range.start)
        let end = start + CompositionBuilder.ticks(range.duration)
        guard end > start else { return [] }

        var inside: [ExportChapter] = []
        for chapter in chapters where chapter.start < end {
            if chapter.start <= start {
                inside = [ExportChapter(start: start, name: chapter.name)]
            } else {
                inside.append(chapter)
            }
        }
        guard !inside.isEmpty else { return [] }

        var samples: [CMSampleBuffer] = []
        for (index, chapter) in inside.enumerated() {
            let next = index + 1 < inside.count ? inside[index + 1].start : end
            guard next > chapter.start else { continue }
            let timeRange = CMTimeRange(
                start: CompositionBuilder.time(chapter.start - start),
                duration: CompositionBuilder.time(next - chapter.start))
            guard let sample = chapterSample(chapter.name, timeRange: timeRange, format: format)
            else { continue }
            samples.append(sample)
        }
        return samples
    }

    /// One text sample: a 16-bit big-endian byte count followed by the UTF-8
    /// name, which is the payload both QuickTime text and 3GPP timed text
    /// carry. Names are truncated at the length that count can express —
    /// 64 KB of chapter title is not a case worth failing an export over.
    private static func chapterSample(
        _ name: String, timeRange: CMTimeRange, format: CMFormatDescription
    ) -> CMSampleBuffer? {
        var text = Array(name.utf8)
        if text.count > 0xFFFF { text = Array(text.prefix(0xFFFF)) }
        var payload: [UInt8] = [UInt8(text.count >> 8), UInt8(text.count & 0xFF)]
        payload.append(contentsOf: text)

        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: payload.count,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: payload.count, flags: 0, blockBufferOut: &block) == kCMBlockBufferNoErr,
            let buffer = block,
            CMBlockBufferReplaceDataBytes(
                with: payload, blockBuffer: buffer, offsetIntoDestination: 0,
                dataLength: payload.count) == kCMBlockBufferNoErr
        else { return nil }

        var timing = CMSampleTimingInfo(
            duration: timeRange.duration, presentationTimeStamp: timeRange.start,
            decodeTimeStamp: .invalid)
        var size = payload.count
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreate(
            allocator: kCFAllocatorDefault, dataBuffer: buffer, dataReady: true,
            makeDataReadyCallback: nil, refcon: nil, formatDescription: format, sampleCount: 1,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1,
            sampleSizeArray: &size, sampleBufferOut: &sample) == noErr
        else { return nil }
        return sample
    }
}
