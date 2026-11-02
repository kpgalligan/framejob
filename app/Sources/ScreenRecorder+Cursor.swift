import AppKit
import ScreenCaptureKit

/// Every screen recording's cursor file (road map creator-jobs CU1b1, spec §11 CU-11…CU-13,
/// CU-18): the segments' header and opening geometry, the capture's start with segment 0 open,
/// and the walker's cursor step, which writes one `<stem>.fjcursor` beside each landed movie
/// (`CursorFileWriter`, CU-15). `CursorCapture.swift` is the capture itself.
///
/// **The anchor is E1** (CU-12): a segment's times count from its screen did-start's host time,
/// stamped on every segment by `+Delegates.swift`; E2 is never used for a cursor file. A landed
/// segment with no E1 gets no file. **The geometry** comes from the frame watch (CU-13); a watch
/// that could not go on the stream (at the start, with no camera, or at the segment's resume)
/// leaves the file only its opening geometry, and the segment says so. **A cursor failure never
/// fails or reorders a segment** (CU-14): the walker's order is movie → microphone → camera →
/// cursor, and this step always hands its segment on.
extension ScreenRecorder {
    /// The header and opening geometry every segment's file starts from (CU-13), before any
    /// frame: `scale_factor` the filter's `pointPixelScale`; `content_scale` the stream's
    /// configured pixel width ÷ (scale factor × point width); `content_rect` (0, 0, the point
    /// size × content scale); `screen_rect` the source's frame — `CGDisplayBounds` for a
    /// display, the window list's `kCGWindowBounds` for a window (the filter's `contentRect`
    /// when the list has none, whose origin may be window-local rather than global points
    /// until the first frame's geometry replaces it), the filter's `contentRect` for a picked
    /// source. The header's
    /// `pixels_per_point` is the configured width ÷ the point width; `in_picture` true, since
    /// the pointer is still burned in (CU3c); `cursor_image` none (CU-S1).
    static func cursorStart(
        filter: SCContentFilter, choice: RecordingChoice, stream: SCStreamConfiguration
    ) -> CursorSegmentStart {
        let points = filter.contentRect.size
        let width = Double(max(stream.width, 1))
        let height = Double(max(stream.height, 1))
        let scaleFactor = positive(Double(filter.pointPixelScale))
        let pixelsPerPoint = positive(points.width > 0 ? width / Double(points.width) : 1)
        let contentScale = positive(
            points.width > 0 ? width / (scaleFactor * Double(points.width)) : 1)
        let source: CursorSourceKind
        let displayID: UInt32?
        let frame: CGRect
        switch choice.source {
        case .display(let id):
            source = .display
            displayID = id
            frame = CGDisplayBounds(id)
        case .window(let id):
            source = .window
            displayID = nil
            frame = windowBounds(id) ?? filter.contentRect
        case .picked, .voiceOver, .camera:
            source = .picked
            displayID = nil
            frame = filter.contentRect
        }
        let geometry = CursorGeometry(
            screenRect: frame,
            contentRect: CGRect(
                x: 0, y: 0, width: Double(points.width) * contentScale,
                height: Double(points.height) * contentScale),
            contentScale: contentScale, scaleFactor: scaleFactor)
        return CursorSegmentStart(
            inPicture: true, source: source, displayID: displayID, sourceFrame: frame,
            pointSize: points, pixelsPerPoint: pixelsPerPoint,
            contentSize: CursorPixelSize(
                width: min(Int(width), 16384), height: min(Int(height), 16384)),
            cursorImage: .none, geometry: geometry)
    }

    /// A segment's `cursorProblem` once its file was attempted: the writer's sentence when it
    /// has one (no file was kept); else, when the frames could not be watched, CU-13's
    /// sentence naming the movie and the reason; else nil.
    static func cursorProblem(writer: String?, watchLost: String?, movieName: String) -> String? {
        if let writer { return writer }
        guard let watchLost else { return nil }
        return "The cursor file for \(movieName) has only the geometry the screen had when it "
            + "began: its frames could not be watched (\(watchLost)), so a move or resize of "
            + "what was recorded after that is not in it."
    }

    /// CU-12's sentence for a landed segment with no E1.
    static func cursorNoAnchorProblem(movieName: String) -> String {
        "The cursor file for \(movieName) was not written: the screen never reported its start, "
            + "so its times have nothing to count from."
    }

    /// MAIN, from `launchScreen`: segment 0 opened, then the poll and the monitors started.
    /// Nothing for a session without a capture.
    func startCursorCapture() {
        guard let current = session, let cursor = current.cursor, let start = current.cursorStart
        else { return }
        cursor.openSegment(0, start)
        cursor.start()
    }

    /// The walker's cursor step for segment `index`, after its camera's: the buffer closed
    /// with the movie's track size and E1, written beside the movie on the capture's queue,
    /// and `landed` handed to `then` on main with its cursor fields. A session without a
    /// capture hands `landed` on unchanged.
    func saveCursor(
        _ done: Session, at index: Int, _ landed: RecordingSegment,
        then: @escaping (RecordingSegment) -> Void
    ) {
        guard let cursor = done.cursor else { return then(landed) }
        let segment = done.segments[index]
        let movie = segment.movieURL
        let name = movie.lastPathComponent
        guard let host = segment.screenHost else {
            return then(
                landed.withCursor(
                    url: nil, problem: Self.cursorNoAnchorProblem(movieName: name), image: nil))
        }
        let watchLost = segment.cursorWatchProblem ?? done.cursorWatchLost
        let size = CursorPixelSize(
            width: landed.descriptor.width, height: landed.descriptor.height)
        cursor.closeSegment(index, movieSize: size, anchor: CursorAnchor(kind: .e1, host: host)) {
            body in
            var url: URL?
            var writer: String?
            if let body {
                do {
                    url = try CursorFileWriter.write(body, forMovie: movie)
                } catch let problem as CursorFileProblem {
                    writer = problem.message
                } catch {
                    writer = "The cursor file for \(name) was not written: "
                        + error.localizedDescription
                }
            } else {
                writer = "The cursor file for \(name) was not written: no cursor was captured "
                    + "for it."
            }
            let problem = Self.cursorProblem(
                writer: writer, watchLost: watchLost, movieName: name)
            // The written file attached to the segment's media (spec §11 CU-34 (c)): the settle
            // probe ran before it existed. A failed attach leaves the segment as CU-18 left it.
            var attached: MediaCursor?
            if let url, case .success(let attachment) = MediaImporter.cursorAttachment(
                at: url, to: landed.descriptor)
            {
                attached = attachment.cursor
            }
            DispatchQueue.main.async {
                then(
                    landed.withCursor(
                        url: url, problem: problem,
                        image: url == nil ? nil : CursorImageMode.none, attached: attached))
            }
        }
    }

    /// A window's frame in global points from the window list, or nil.
    private static func windowBounds(_ id: CGWindowID) -> CGRect? {
        guard
            let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, id)
                as? [[String: Any]],
            let bounds = list.first?[kCGWindowBounds as String] as? NSDictionary
        else { return nil }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }

    /// A finite value above 0, else 1, so the header and the geometry always pass the core's
    /// check.
    private static func positive(_ value: Double) -> Double {
        value.isFinite && value > 0 ? value : 1
    }
}
