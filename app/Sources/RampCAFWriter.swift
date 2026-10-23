import AudioToolbox

/// 32-bit float LPCM CAF at 48 kHz, interleaved, through `ExtAudioFile`
/// (the file type named, since the path ends `.partial`).
final class RampCAFWriter {
    let channels: Int
    private var file: ExtAudioFileRef?

    init(url: URL, channels: Int) throws {
        self.channels = channels
        var format = AudioStreamBasicDescription(
            mSampleRate: Float64(RampAudioRenderer.sampleRate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(4 * channels), mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(4 * channels), mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 32, mReserved: 0)
        var made: ExtAudioFileRef?
        let status = ExtAudioFileCreateWithURL(
            url as CFURL, kAudioFileCAFType, &format, nil, AudioFileFlags.eraseFile.rawValue,
            &made)
        guard status == noErr, let made = made else {
            throw RampAudioRenderer.RenderError.failed("the CAF could not be created (\(status))")
        }
        file = made
        let set = ExtAudioFileSetProperty(
            made, kExtAudioFileProperty_ClientDataFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &format)
        guard set == noErr else {
            abandon()
            throw RampAudioRenderer.RenderError.failed("the CAF refused its format (\(set))")
        }
    }

    /// The first `frames` interleaved frames of `samples`.
    func write(_ samples: [Float], frames: Int) throws {
        guard let file = file, frames > 0 else { return }
        var copy = samples
        let status = copy.withUnsafeMutableBytes { raw -> OSStatus in
            var list = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: UInt32(channels),
                    mDataByteSize: UInt32(frames * channels * 4), mData: raw.baseAddress))
            return ExtAudioFileWrite(file, UInt32(frames), &list)
        }
        guard status == noErr else {
            throw RampAudioRenderer.RenderError.failed("a CAF write failed (\(status))")
        }
    }

    func close() throws {
        guard let file = file else { return }
        self.file = nil
        let status = ExtAudioFileDispose(file)
        guard status == noErr else {
            throw RampAudioRenderer.RenderError.failed("the CAF did not close (\(status))")
        }
    }

    func abandon() {
        if let file = file { ExtAudioFileDispose(file) }
        file = nil
    }
}
