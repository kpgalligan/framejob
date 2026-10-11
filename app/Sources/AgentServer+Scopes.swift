import AppKit

/// `render_frame`'s scope writers: each measures the frame the tool just
/// wrote through the panel's own analyser and writes its counts beside the
/// image, so the panel and the tool cannot count differently (spec §11 GR-5,
/// GR-10). Today it holds `writeWaveform`; the parade, vectorscope and
/// histogram writers of grading-2's G2-1 land here beside it.
///
/// A pure move out of `AgentServer+Render.swift`, which stood at 584 lines
/// against app/CLAUDE.md's ~600 cap with no seam named: grading-2's G2-0,
/// paid first and alone. `writeWaveform` came here whole, its body
/// untouched, and `renderFrame` calls it as before; nothing arrived widened,
/// since both are members of the same internal extension of `AgentServer`.
extension AgentServer {

    /// `render_frame {waveform}`: the frame's trace written to
    /// `<path>.waveform.json`, and the sentence that says so.
    static func writeWaveform(of image: CGImage, beside url: URL) throws -> String {
        guard let trace = WaveformAnalyzer.shared?.analyze(image: image) else {
            throw ToolError(
                message: "Wrote \(url.path), but its waveform could not be measured: the GPU "
                    + "pass did not run.")
        }
        let file = URL(fileURLWithPath: url.path + ".waveform.json")
        do {
            let data = try JSONSerialization.data(
                withJSONObject: trace.json(), options: [.sortedKeys])
            try data.write(to: file)
        } catch {
            throw ToolError(message: "Could not write \(file.path): \(error.localizedDescription)")
        }
        let high = String(format: "%.1f", trace.highlightsPercent)
        let low = String(format: "%.1f", trace.shadowsPercent)
        return "Waveform: highlights clipped in \(high) % of pixels, shadows in \(low) %; "
            + "its 256 × 256 counts are in \(file.path)."
    }
}
