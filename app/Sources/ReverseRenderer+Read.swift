import AVFoundation

extension ReverseRenderer {
    // MARK: - Reading one slice

    /// One decoded frame, held until its turn to be written comes round.
    struct Frame {
        let time: CMTime
        let buffer: CVPixelBuffer
    }

    struct Slice {
        var frames: [Frame] = []
        /// Interleaved 16-bit LPCM, in source order; reversed on the way out.
        var audio: [UInt8] = []
    }

    /// Reads everything in `range` into memory.
    ///
    /// The two outputs are drained a sample at a time each rather than one
    /// after the other: an `AVAssetReader` decodes both tracks as it goes, and
    /// emptying one output while the other is untouched makes it buffer the
    /// second track's samples on our behalf, which is the one thing this
    /// method exists to avoid.
    ///
    /// Samples outside `[range.start, range.end)` are dropped rather than
    /// clipped. A reader may hand back a frame that begins before the range
    /// (the sync sample it had to decode from), and that frame belongs to the
    /// PREVIOUS slice, which has already written it — so admitting it here
    /// would write it twice and break the strictly-decreasing stamp the
    /// caller's arithmetic depends on.
    static func read(
        asset: AVURLAsset, range: CMTimeRange, limit: CMTime, videoTrack: AVAssetTrack?,
        audioTrack: AVAssetTrack?, pixelFormat: OSType, cancel: CancelToken?
    ) throws -> Slice {
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw ReverseError.failed(error.localizedDescription)
        }
        reader.timeRange = range

        var videoOutput: AVAssetReaderTrackOutput?
        if let track = videoTrack {
            let output = AVAssetReaderTrackOutput(
                track: track,
                outputSettings: [
                    // The intermediate's own format (`Intermediate`): 10-bit
                    // YCbCr in the source's matrix, so nothing converts
                    // between the decoder and the encoder and the frames
                    // keep their depth and their colour labels (PR-7).
                    kCVPixelBufferPixelFormatTypeKey as String: Int(pixelFormat),
                    kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
                ])
            if reader.canAdd(output) {
                reader.add(output)
                videoOutput = output
            }
        }
        var audioOutput: AVAssetReaderTrackOutput?
        if let track = audioTrack {
            let output = AVAssetReaderTrackOutput(
                track: track, outputSettings: decodedAudioSettings)
            if reader.canAdd(output) {
                reader.add(output)
                audioOutput = output
            }
        }
        guard reader.startReading() else {
            throw ReverseError.failed(
                reader.error?.localizedDescription ?? "the file could not be read")
        }

        var slice = Slice()
        var videoDone = videoOutput == nil
        var audioDone = audioOutput == nil
        while !videoDone || !audioDone {
            if cancel?.isCancelled == true {
                reader.cancelReading()
                throw ReverseError.cancelled
            }
            if !videoDone {
                if let sample = videoOutput?.copyNextSampleBuffer() {
                    let time = CMSampleBufferGetPresentationTimeStamp(sample)
                    if time.isNumeric, time >= range.start, time < range.end, time < limit,
                        let image = CMSampleBufferGetImageBuffer(sample),
                        let held = copyBuffer(image)
                    {
                        slice.frames.append(Frame(time: time, buffer: held))
                    }
                } else {
                    videoDone = true
                }
            }
            if !audioDone {
                if let sample = audioOutput?.copyNextSampleBuffer() {
                    appendAudioBytes(of: sample, to: &slice.audio)
                } else {
                    audioDone = true
                }
            }
        }
        let status = reader.status
        reader.cancelReading()
        guard status != .failed else {
            throw ReverseError.failed(
                reader.error?.localizedDescription ?? "the file could not be read to the end")
        }
        // Decompressed output arrives in display order on every path measured
        // here, but the reversal is only correct if it really is sorted, and a
        // slice is a few dozen frames.
        slice.frames.sort { $0.time < $1.time }
        return slice
    }

    /// A private copy of a decoded frame.
    ///
    /// The reader hands back buffers from a pool it means to recycle, and this
    /// renderer holds a whole slice of them at once — so they are copied out
    /// rather than retained, which is the difference between a bounded read
    /// and a reader that starves itself. A pool of our own would recycle
    /// nothing (every buffer in a slice is live at the same time), so these
    /// are plain allocations.
    ///
    /// Every plane is copied — the `x420` and `x422` frames are two — and the
    /// decoder's attachments go with them: the colour primaries, transfer
    /// function and matrix the writer labels the file by (spec §11 PR-7).
    static func copyBuffer(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        guard width > 0, height > 0 else { return nil }
        var created: CVPixelBuffer?
        guard CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, CVPixelBufferGetPixelFormatType(source),
            [
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
                kCVPixelBufferMetalCompatibilityKey as String: true,
            ] as CFDictionary, &created) == kCVReturnSuccess, let target = created
        else { return nil }
        guard CVPixelBufferLockBaseAddress(source, .readOnly) == kCVReturnSuccess else {
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
        guard CVPixelBufferLockBaseAddress(target, []) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(target, []) }
        let planes = CVPixelBufferGetPlaneCount(source)
        guard planes == CVPixelBufferGetPlaneCount(target) else { return nil }
        if planes == 0 {
            guard let from = CVPixelBufferGetBaseAddress(source),
                let to = CVPixelBufferGetBaseAddress(target)
            else { return nil }
            copyRows(
                from: from, stride: CVPixelBufferGetBytesPerRow(source), to: to,
                stride: CVPixelBufferGetBytesPerRow(target), rows: height)
        }
        for plane in 0..<planes {
            guard let from = CVPixelBufferGetBaseAddressOfPlane(source, plane),
                let to = CVPixelBufferGetBaseAddressOfPlane(target, plane)
            else { return nil }
            copyRows(
                from: from, stride: CVPixelBufferGetBytesPerRowOfPlane(source, plane), to: to,
                stride: CVPixelBufferGetBytesPerRowOfPlane(target, plane),
                rows: min(
                    CVPixelBufferGetHeightOfPlane(source, plane),
                    CVPixelBufferGetHeightOfPlane(target, plane)))
        }
        CVBufferPropagateAttachments(source, target)
        return target
    }

    /// `rows` rows from one buffer (or plane) to another, each the shorter of
    /// the two strides — the padding past a row's pixels is not picture.
    static func copyRows(
        from: UnsafeMutableRawPointer, stride fromStride: Int, to: UnsafeMutableRawPointer,
        stride toStride: Int, rows: Int
    ) {
        let rowBytes = min(fromStride, toStride)
        for row in 0..<rows {
            memcpy(to + row * toStride, from + row * fromStride, rowBytes)
        }
    }
}
