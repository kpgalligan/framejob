import Foundation

/// `-RCDevWebMFault <spec>`, a dev-only launch default (dev tools only; codec-export C3 fix
/// pass 1, spec §11 CX-15 (6)): one fault put into every `av1_webm` export of the launch, so
/// a proof can show that a stop on either pump ends the export — each pump reads its own
/// `AVAssetReader`, so neither read can be starved by the other's stop (G-17).
///
///   `audio@N`       the audio pump fails at its Nth read, before it
///   `video@N`       the video sink fails at its Nth packet
///   `audio-hold@N`  the audio pump waits `holdSeconds` at its Nth read, before it, without
///                   looking at the stop flag — a read that is slow to return — then reads
///
/// Each firing is one log line, `framejob webm dev fault: …`, and with a fault set the
/// writer logs its readers' states once both pumps have left (`framejob webm dev readers:
/// video S, audio S`, with ` (one reader)` should the two ever be one object). Neither
/// carries the parity check's prefix. Nil in a build without dev tools.
final class ExportWebMDevFault {
    static let key = "RCDevWebMFault"
    static let holdSeconds = 3.0

    enum Kind: String { case audio, video, audioHold = "audio-hold" }

    let kind: Kind
    let at: Int

    private init(kind: Kind, at: Int) {
        self.kind = kind
        self.at = at
    }

    @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("ExportWebMDevFault does not support NSCoder")
    }

    /// The launch's fault, or nil (none set, malformed, or no dev tools).
    static func current() -> ExportWebMDevFault? {
        #if FRAMEJOB_DEV_TOOLS
        guard let spec = UserDefaults.standard.string(forKey: key) else { return nil }
        let parts = spec.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2, let kind = Kind(rawValue: parts[0]), let at = Int(parts[1]),
            at > 0
        else { return nil }
        return ExportWebMDevFault(kind: kind, at: at)
        #else
        return nil
        #endif
    }

    /// The audio pump, before its read number `read` (from 1): throws at `audio@N`, waits at
    /// `audio-hold@N`.
    func beforeAudioRead(_ read: Int) throws {
        guard read == at else { return }
        switch kind {
        case .audio:
            Self.log("fault: the audio pump fails at read \(read)")
            throw Exporter.ExportError.failed("A dev fault stopped the audio at read \(read).")
        case .audioHold:
            Self.log("fault: the audio read \(read) is held \(Self.holdSeconds) s")
            Thread.sleep(forTimeInterval: Self.holdSeconds)
            Self.log("fault: the audio read \(read) goes on")
        case .video:
            return
        }
    }

    /// The video sink, at its packet number `packet` (from 1): the failure at `video@N`.
    func videoPacket(_ packet: Int) -> (any Error)? {
        guard kind == .video, packet == at else { return nil }
        Self.log("fault: the video sink fails at packet \(packet)")
        return Exporter.ExportError.failed("A dev fault stopped the video at packet \(packet).")
    }

    static func log(_ line: String) {
        NSLog("framejob webm dev %@", line)
    }
}
