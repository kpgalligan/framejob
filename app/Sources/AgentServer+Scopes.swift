import AppKit

/// `render_frame`'s scope writers: `writeScopes` measures the frame the tool
/// just wrote through the panel's own analyser, once for every kind asked,
/// and writes each kind's counts beside the image, so the panel and the tool
/// cannot count differently (spec §11 GR-5, GR-10).
///
/// A pure move out of `AgentServer+Render.swift` in grading-2's G2-0 (then
/// `writeWaveform`, whose sentence the waveform's still is byte for byte);
/// G2-1 widened it to the parade, the vectorscope and the histogram.
extension AgentServer {

    /// `render_frame {waveform, parade, vectorscope, histogram}`: one analyse
    /// of `image` for every kind in `kinds`, each kind's trace written to
    /// `<path>.<kind>.json`, and one sentence per kind in `ScopeKind.allCases`
    /// order.
    static func writeScopes(_ kinds: [ScopeKind], of image: CGImage, beside url: URL) throws
        -> String
    {
        let asked = Set(kinds)
        guard let traces = WaveformAnalyzer.shared?.analyze(image: image, kinds: asked),
            asked.allSatisfy({ traces[$0] != nil })
        else {
            let names = ScopeKind.allCases.filter(asked.contains).map(\.rawValue)
            throw ToolError(
                message: "Wrote \(url.path), but its \(names.joined(separator: ", ")) could not "
                    + "be measured: the GPU pass did not run.")
        }
        var sentences: [String] = []
        for kind in ScopeKind.allCases {
            guard let trace = traces[kind] else { continue }
            let file = URL(fileURLWithPath: url.path + ".\(kind.rawValue).json")
            do {
                let data = try JSONSerialization.data(
                    withJSONObject: trace.json(), options: [.sortedKeys])
                try data.write(to: file)
            } catch {
                throw ToolError(
                    message: "Could not write \(file.path): \(error.localizedDescription)")
            }
            sentences.append(sentence(trace, file: file))
        }
        return sentences.joined(separator: " ")
    }

    /// The sentence `render_frame` says for one kind's trace.
    private static func sentence(_ trace: ScopeTrace, file: URL) -> String {
        func spelled(_ percent: Double) -> String { String(format: "%.1f", percent) }
        switch trace {
        case .waveform(let trace):
            return "Waveform: highlights clipped in \(spelled(trace.highlightsPercent)) % of "
                + "pixels, shadows in \(spelled(trace.shadowsPercent)) %; its 256 × 256 counts "
                + "are in \(file.path)."
        case .parade(let trace):
            let channels = (0..<3).map { trace.channel($0) }.map {
                (spelled($0.highlightsPercent), spelled($0.shadowsPercent))
            }
            return "Parade: red clips high in \(channels[0].0) % of pixels and low in "
                + "\(channels[0].1) %, green in \(channels[1].0) % and \(channels[1].1) %, blue in "
                + "\(channels[2].0) % and \(channels[2].1) %; its 3 × 256 × 256 counts are in "
                + "\(file.path)."
        case .vectorscope(let trace):
            return "Vectorscope (Rec. 709 Cb and Cr of the encoded values): "
                + "\(spelled(trace.neutralPercent)) % of pixels are neutral; its 256 × 256 "
                + "counts are in \(file.path)."
        case .histogram(let trace):
            return "Histogram: highlights clipped in \(spelled(trace.highlightsPercent)) % of "
                + "pixels, shadows in \(spelled(trace.shadowsPercent)) % (by Y′); its R′, G′, B′ "
                + "and Y′ counts per 256 levels are in \(file.path)."
        }
    }
}
