// Road map "creator-jobs" CJ7, spike SW-S1 (f) on a real file: what
// AVFoundation makes of every audio track of a movie (S-IP1's question,
// answered from S-TH1's iPhone movie, recorded with Spatial Audio on).
//
// Built alone (as `main.swift`) through `tools/proof/swift_build.py` by
// `audio_tracks.py`:
//
//   audio_tracks_probe <movie>
//
// Prints one JSON line: `audio`, one row per track of
// `tracks(withMediaType: .audio)` in that order — `track_id`, `codec` (the
// FourCC of the format description's `mediaSubType`), `channels` and
// `sample_rate` (from its ASBD), `title` (the common-key title, else the
// user-data name, else null), `enabled`, `decodes` (an
// `AVAssetReaderTrackOutput` asked for 32-bit float LPCM returns one sample
// buffer), `decodes_error` — and `other`, the count of tracks of every other
// media type.
import AVFoundation
import CoreMedia
import Foundation

func fourCC(_ code: FourCharCode) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8((code >> UInt32($0)) & 0xff) }
    let printable = bytes.allSatisfy { $0 >= 0x20 && $0 < 0x7f }
    return printable ? String(decoding: bytes, as: UTF8.self) : String(format: "0x%08x", code)
}

func title(of track: AVAssetTrack) -> String? {
    let common = AVMetadataItem.metadataItems(
        from: track.commonMetadata, filteredByIdentifier: .commonIdentifierTitle)
    if let value = common.first?.stringValue { return value }
    for format in track.availableMetadataFormats {
        for item in track.metadata(forFormat: format) {
            if let key = item.key as? String, key == "name" || key == "©nam",
               let value = item.stringValue {
                return value
            }
            if item.identifier == .quickTimeUserDataFullName || item.identifier == .quickTimeMetadataDisplayName,
               let value = item.stringValue {
                return value
            }
        }
    }
    return nil
}

func decodes(_ asset: AVAsset, _ track: AVAssetTrack) -> (Bool, String?) {
    do {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        guard reader.canAdd(output) else { return (false, "the reader cannot add the output") }
        reader.add(output)
        guard reader.startReading() else {
            return (false, reader.error.map { "\($0)" } ?? "startReading failed")
        }
        defer { reader.cancelReading() }
        if output.copyNextSampleBuffer() != nil { return (true, nil) }
        return (false, reader.error.map { "\($0)" } ?? "no sample buffer")
    } catch {
        return (false, "\(error)")
    }
}

let args = CommandLine.arguments
guard args.count == 2 else {
    FileHandle.standardError.write(Data("usage: audio_tracks_probe <movie>\n".utf8))
    exit(2)
}
let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
var rows: [[String: Any]] = []
for track in asset.tracks(withMediaType: .audio) {
    var row: [String: Any] = ["track_id": Int(track.trackID), "enabled": track.isEnabled]
    let descriptions = track.formatDescriptions as! [CMFormatDescription]
    if let description = descriptions.first {
        row["codec"] = fourCC(CMFormatDescriptionGetMediaSubType(description))
        if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee {
            row["channels"] = Int(asbd.mChannelsPerFrame)
            row["sample_rate"] = asbd.mSampleRate
        }
    }
    row["title"] = title(of: track) ?? NSNull()
    let (ok, error) = decodes(asset, track)
    row["decodes"] = ok
    row["decodes_error"] = error ?? NSNull()
    rows.append(row)
}
var other: [String: Int] = [:]
for track in asset.tracks where track.mediaType != .audio {
    other[track.mediaType.rawValue, default: 0] += 1
}
let data = try! JSONSerialization.data(
    withJSONObject: ["audio": rows, "other": other], options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
