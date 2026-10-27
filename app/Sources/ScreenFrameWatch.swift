import AVFoundation
import ScreenCaptureKit

/// The screen's start by E2 (camera-recording CR3a, spec §11 CAM-9 (3)): an
/// `SCStreamOutput` for `.screen` frames, on the stream only when a camera
/// records beside the screen. CR0 chose E2 for camera + screen — the PTS of
/// the first COMPLETE frame at or after the did-start's arrival on the host
/// clock (E1) — because the did-start alone is stamped where a callback lands
/// and the frame is what the file begins with (`designs/camera-recording.md`,
/// CR0's S rows: E2 fell 9–22 ms after E1).
///
/// **What it keeps.** The PTS of every complete frame (seconds, as delivered;
/// CR0 measured them on the host clock) for `keptSeconds`, so a question that
/// arrives after its frame — the did-start's hop to main can land after the
/// frame did — is answered from what was kept. An incomplete frame (idle,
/// blank, suspended: a frame with no new picture) is never kept and never
/// answers.
///
/// **The bound.** A still screen sends no complete frame, so a segment's
/// question is answered only by a frame no more than `bound` after E1 — two
/// frame intervals at the recording's rate — and a complete frame past it
/// drops the question unanswered: that segment's offset then uses E1
/// (`ScreenRecorder.cameraBesideOffset`). A segment's question is dropped at
/// its close (`drop(segment:)`, from `pause()` and `beginFinishing`), so a
/// frame of a later segment never answers it.
///
/// **One queue and one lock**, forced by the framework as `CameraCapture`'s
/// two queues are: ScreenCaptureKit delivers a stream output's buffers on the
/// sample handler queue it is given (`queue`), and the questions come from
/// main. Everything the two sides share is read and written under `lock`;
/// an answer is hopped to main and delivered only when its question is still
/// open there, so nothing answers after `drop(segment:)` or `stop()`.
final class ScreenFrameWatch: NSObject, SCStreamOutput {
    /// Seconds of complete frames kept for a question that comes late.
    static let keptSeconds: Double = 2

    /// E2's window after E1: two frame intervals at `rate`, `2 / max(rate, 1)` s.
    static func bound(rate: Int) -> Double { 2 / Double(max(rate, 1)) }

    let bound: Double
    /// The sample handler queue the stream delivers `.screen` frames on.
    let queue = DispatchQueue(label: "com.kgalligan.FrameJob.screen.frames")

    private struct Question {
        let host: Double
        let answer: (Double) -> Void
    }

    private enum Verdict { case before, inside, past }

    private let lock = NSLock()
    /// Under `lock`: the complete frames' PTSs, ascending, within
    /// `keptSeconds` of the newest.
    private var kept: [Double] = []
    /// Under `lock`: each segment's open question.
    private var questions: [Int: Question] = [:]
    /// Under `lock`: each segment whose answer is on its way to main.
    private var answering: [Int: Double] = [:]
    /// Under `lock`: `stop()` was called.
    private var stopped = false

    init(bound: Double) {
        self.bound = bound
        super.init()
    }

    /// `queue`. A `.screen` frame: its PTS and whether it is complete
    /// (`SCStreamFrameInfo.status`, CR0's read).
    func stream(
        _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard pts.isValid else { return }
        var complete = false
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
            let raw = attachments.first?[.status] as? Int
        {
            complete = SCFrameStatus(rawValue: raw) == .complete
        }
        record(pts: pts.seconds, complete: complete)
    }

    /// Any thread. One frame: a complete one is kept, the frames older than
    /// `keptSeconds` before it let go, and each open question it answers or
    /// passes is settled.
    func record(pts: Double, complete: Bool) {
        guard complete else { return }
        lock.lock()
        defer { lock.unlock() }
        guard !stopped else { return }
        kept.append(pts)
        kept.removeAll { $0 < pts - Self.keptSeconds }
        for (segment, question) in questions {
            switch verdict(pts, after: question.host) {
            case .before:
                continue
            case .inside:
                questions[segment] = nil
                send(pts, to: segment, question.answer)
            case .past:
                questions[segment] = nil
            }
        }
    }

    /// MAIN THREAD. Segment `segment`'s question: `answer` on main, at most
    /// once, with the first kept or later complete frame at or after `host`
    /// and within `bound` of it. A kept frame past the bound, or a later one,
    /// leaves it unanswered.
    func firstComplete(
        for segment: Int, atOrAfter host: Double, answer: @escaping (Double) -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped else { return }
        questions[segment] = nil
        answering[segment] = nil
        for pts in kept {
            switch verdict(pts, after: host) {
            case .before:
                continue
            case .inside:
                return send(pts, to: segment, answer)
            case .past:
                return
            }
        }
        questions[segment] = Question(host: host, answer: answer)
    }

    /// MAIN THREAD. Segment `segment`'s question closes: nothing answers it
    /// after this, not even an answer already on its way to main.
    func drop(segment: Int) {
        lock.lock()
        questions[segment] = nil
        answering[segment] = nil
        lock.unlock()
    }

    /// Every question dropped and every frame let go; nothing answers after it.
    func stop() {
        lock.lock()
        stopped = true
        questions = [:]
        answering = [:]
        kept = []
        lock.unlock()
    }

    /// Where `pts` lies against a question asked at `host`.
    private func verdict(_ pts: Double, after host: Double) -> Verdict {
        if pts < host { return .before }
        if pts > host + bound { return .past }
        return .inside
    }

    /// Under `lock`: the answer marked on its way and hopped to main, where
    /// it is delivered only if its segment's question was not dropped since.
    private func send(_ pts: Double, to segment: Int, _ answer: @escaping (Double) -> Void) {
        answering[segment] = pts
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let live = !self.stopped && self.answering[segment] == pts
            if live { self.answering[segment] = nil }
            self.lock.unlock()
            if live { answer(pts) }
        }
    }
}
