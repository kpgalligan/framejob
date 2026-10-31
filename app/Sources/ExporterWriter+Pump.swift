import AVFoundation

// `ExportWriter`'s pump: the loop that moves one output's samples into one input, and the
// master's tail. A pure move out of `ExporterWriter.swift` at its size cap (road map audio
// AP10c); the members each file calls in the other lost `private` (`pump`, `appendTail`,
// `fault`, `stopped`, `readFailure`, `advance`), and nothing else changed.
extension ExportWriter {
    /// Moves one output's samples into one input until the output runs dry,
    /// the write fails, or the export is cancelled. `read` is the output's
    /// next buffer: the video output's, or the mix's (`ExportMixRead`, spec
    /// §11 AU-152), which may throw.
    ///
    /// `requestMediaDataWhenReady` re-enters this block whenever the encoder
    /// has room, so the "have I already finished?" flag lives outside it and
    /// is only ever touched on `queue`, which is serial.
    ///
    /// `master` is the audio pump's alone (spec §11 AU-27): each buffer goes
    /// through it first, and its latency's tail (`finish`) before the padding.
    /// `frames` is non-nil only for the video pump of a row `frameForm`
    /// names: each frame is then converted by it (`ExportFrames`). `reader` is
    /// the output's own, which `stop` cancels after the last read when the
    /// write is stopping (#378). `-RCDevExportFault` reaches the audio pump
    /// before a read and the video pump before an append.
    func pump(
        _ input: AVAssetWriterInput, read: @escaping () throws -> CMSampleBuffer?,
        reading reader: AVAssetReader, on queue: DispatchQueue, group: DispatchGroup,
        tracksProgress: Bool, master: ExportAudioMaster? = nil, frames: ExportFrames? = nil,
        end: ExportAudioEnd? = nil
    ) {
        group.enter()
        var finished = false
        var reads = 0
        var appends = 0
        let stop: () -> Void = { [weak self] in
            guard !finished else { return }
            finished = true
            // Its own reader, on its own queue, after its own last read (G-17).
            if self?.isStopping ?? true { reader.cancelReading() }
            input.markAsFinished()
            group.leave()
        }
        input.requestMediaDataWhenReady(on: queue) { [weak self] in
            guard let self = self else { return }
            while input.isReadyForMoreMediaData {
                guard !finished else { return }
                guard !self.isStopping else {
                    stop()
                    return
                }
                if end != nil, end?.isPadding != true {
                    reads += 1
                    do { try self.fault?.beforeAudioRead(reads) } catch {
                        self.stopped(with: error)
                        stop()
                        return
                    }
                }
                let next: CMSampleBuffer?
                do { next = end?.isPadding == true ? nil : try read() } catch {
                    self.stopped(with: error)
                    stop()
                    return
                }
                guard let decoded = next else {
                    // Dry: the range is written, or the read failed — and only
                    // the last is ours to name.
                    if let error = self.readFailure(of: reader) {
                        self.stopped(with: error)
                    } else if let end = end, !self.isStopping {
                        // The master's tail, once, then silence up to the range's end,
                        // while the input has room (#337).
                        if !end.isPadding, !self.appendTail(of: master, to: input, end: end) {
                            stop()
                            return
                        }
                        guard let padded = end.pad(input) else { return }
                        if !padded {
                            self.stopped(with: self.writer.error
                                ?? Exporter.ExportError.failed("The file could not be written."))
                        }
                    }
                    stop()
                    return
                }
                // The master makes a NEW integer buffer from the float one,
                // placed by its stamp (nil while its head is in the latency).
                let sample: CMSampleBuffer
                do {
                    guard let mastered = try master.map({ try $0.apply(to: decoded) }) ?? decoded
                    else { continue }
                    sample = mastered
                } catch {
                    self.stopped(with: error)
                    stop()
                    return
                }
                let time = CMSampleBufferGetPresentationTimeStamp(sample) - self.range.start
                // A sample that starts before the range does not belong to
                // this file. The reader clips to `timeRange`, so this is a
                // boundary frame, not a common case.
                guard time.isNumeric, time >= .zero else { continue }
                // A `frameForm` row's frame, converted (spec §11 G-35, PR-3),
                // before `retimed`; any other goes on as read.
                guard let ready = frames == nil ? sample : frames?.convert(sample) else {
                    self.stopped(
                        with: Exporter.ExportError.failed(
                            frames?.failure ?? "A frame could not be prepared for the encoder."))
                    stop()
                    return
                }
                guard let rebased = Self.retimed(ready, by: self.range.start) else {
                    self.stopped(
                        with: Exporter.ExportError.failed(
                            "A sample could not be re-timed for the file."))
                    stop()
                    return
                }
                // A buffer past the range's end is cut or dropped (#337).
                guard let fitted = end == nil ? rebased : end?.fit(rebased) else { continue }
                if end == nil {
                    appends += 1
                    if let error = self.fault?.videoPacket(appends) {
                        self.stopped(with: error)
                        stop()
                        return
                    }
                }
                guard input.append(fitted) else {
                    self.stopped(
                        with: self.writer.error
                            ?? Exporter.ExportError.failed("The file could not be written."))
                    stop()
                    return
                }
                if tracksProgress { self.advance(to: time) }
            }
        }
    }

    /// The master's tail (`ExportAudioMaster.finish`) through `retimed` and
    /// `end.fit` into `input`: true when it is in or there is none, false
    /// after recording the failure.
    func appendTail(
        of master: ExportAudioMaster?, to input: AVAssetWriterInput, end: ExportAudioEnd
    ) -> Bool {
        do {
            guard let tail = try master?.finish() else { return true }
            guard let rebased = Self.retimed(tail, by: range.start) else {
                throw Exporter.ExportError.failed("A sample could not be re-timed for the file.")
            }
            guard let fitted = end.fit(rebased) else { return true }
            guard input.append(fitted) else {
                throw writer.error ?? Exporter.ExportError.failed("The file could not be written.")
            }
            return true
        } catch {
            stopped(with: error)
            return false
        }
    }
}
