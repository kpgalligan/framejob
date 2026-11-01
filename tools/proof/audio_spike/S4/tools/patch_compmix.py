import os
os.chdir(os.path.dirname(os.path.abspath(__file__)))
p = 'main.swift'
s = open(p).read()
cmd = '''case "compmix":  // compmix <mono file>: the export's reader over a composition of the file
    let url = URL(fileURLWithPath: arg(2))
    let asset = AVURLAsset(url: url)
    let source = asset.tracks(withMediaType: .audio)[0]
    let comp = AVMutableComposition()
    let track = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
    try! track.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: source, at: .zero)
    let params = AVMutableAudioMixInputParameters(track: track)
    params.setVolume(1, at: .zero)
    let mix = AVMutableAudioMix()
    mix.inputParameters = [params]
    let reader = try! AVAssetReader(asset: comp)
    let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM), AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]
    let out = AVAssetReaderAudioMixOutput(audioTracks: comp.tracks(withMediaType: .audio), audioSettings: settings)
    out.audioMix = mix
    reader.add(out)
    reader.startReading()
    var samples: [Float] = []
    while let sb = out.copyNextSampleBuffer() {
        guard let block = CMSampleBufferGetDataBuffer(sb) else { continue }
        let n = CMBlockBufferGetDataLength(block) / 4
        let base = samples.count
        samples.append(contentsOf: repeatElement(0, count: n))
        samples.withUnsafeMutableBytes { raw in
            _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: n * 4, destination: raw.baseAddress! + base * 4)
        }
    }
    let st = PCM(samples: samples, rate: 48000, channels: 2)
    let mono = decode(url)
    var maxLR: Float = 0, maxLM: Float = 0
    for f in 0..<min(st.frames, mono.frames) {
        maxLR = max(maxLR, abs(st.samples[2 * f] - st.samples[2 * f + 1]))
        maxLM = max(maxLM, abs(st.samples[2 * f] - mono.samples[f]))
    }
    let m = direct(st, fa: 0, fb: st.frames, coefficients: KWeight.table48)
    let mm = direct(mono, fa: 0, fb: mono.frames, coefficients: KWeight.table48)
    print("composition mix: frames \\(st.frames), max |L-R| \\(maxLR), max |L-mono| \\(maxLM); stereo mix \\(fmt(m.lufs, 4)) LUFS vs mono \\(fmt(mm.lufs, 4)) LUFS")

'''
s = s.replace('case "mirror":', cmd + 'case "mirror":', 1)
open(p, 'w').write(s)
print("patched")
