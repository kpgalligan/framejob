import sys

d = sys.argv[1]
p = d + '/src/OwnLimiter2.swift'
s = open(p).read()
rep = [
    ("    let vectorDetector: Bool\n",
     "    let vectorDetector: Bool\n"
     "    /// Also take BS.1770-4 Annex 2's own 4-phase 12-tap reading (the filter\n"
     "    /// `Loudness.swift` reports with), so the app's own meter can never read\n"
     "    /// above the ceiling either.\n"
     "    let annexToo: Bool\n"
     "    private var annex: UnsafeMutablePointer<Float>?  // 4 × 12, reversed for vDSP_conv\n"),
    ("    init(taps: Int = 32, beta: Double = 8, vectorDetector: Bool = true) {\n"
     "        self.taps = taps\n"
     "        self.beta = beta\n"
     "        self.vectorDetector = vectorDetector\n"
     "        name = \"own true-peak limiter (\\(taps) taps\\(vectorDetector ? \", vDSP_conv\" : \", scalar\"))\"\n",
     "    init(taps: Int = 32, beta: Double = 8, vectorDetector: Bool = true, annexToo: Bool = false) {\n"
     "        self.taps = taps\n"
     "        self.beta = beta\n"
     "        self.vectorDetector = vectorDetector\n"
     "        self.annexToo = annexToo\n"
     "        name = \"own true-peak limiter (\\(taps) taps\\(vectorDetector ? \", vDSP_conv\" : \", scalar\")\\(annexToo ? \" + Annex 2\" : \"\"))\"\n"
     "        let a = UnsafeMutablePointer<Float>.allocate(capacity: 48)\n"
     "        for ph in 0..<4 { for k in 0..<12 { a[ph * 12 + k] = Self.annex2[ph][11 - k] } }\n"
     "        annex = a\n"),
    ("    deinit { for p in [fir, hb, tmp, peakBuf, dline, dqVal, box] { p?.deallocate() }; dqIdx?.deallocate() }\n",
     "    deinit { for p in [fir, hb, tmp, peakBuf, dline, dqVal, box, annex] { p?.deallocate() }; dqIdx?.deallocate() }\n\n"
     "    static let annex2: [[Float]] = [\n"
     "        [0.0017089843750, 0.0109863281250, -0.0196533203125, 0.0332031250000, -0.0594482421875, 0.1373291015625,\n"
     "         0.9721679687500, -0.1022949218750, 0.0476074218750, -0.0266113281250, 0.0148925781250, -0.0083007812500],\n"
     "        [-0.0291748046875, 0.0292968750000, -0.0517578125000, 0.0891113281250, -0.1665039062500, 0.4650878906250,\n"
     "         0.7797851562500, -0.2003173828125, 0.1015625000000, -0.0582275390625, 0.0330810546875, -0.0189208984375],\n"
     "        [-0.0189208984375, 0.0330810546875, -0.0582275390625, 0.1015625000000, -0.2003173828125, 0.7797851562500,\n"
     "         0.4650878906250, -0.1665039062500, 0.0891113281250, -0.0517578125000, 0.0292968750000, -0.0291748046875],\n"
     "        [-0.0083007812500, 0.0148925781250, -0.0266113281250, 0.0476074218750, -0.1022949218750, 0.9721679687500,\n"
     "         0.1373291015625, -0.0594482421875, 0.0332031250000, -0.0196533203125, 0.0109863281250, 0.0017089843750],\n"
     "    ]\n"),
    ("            // Keep the last taps − 1 inputs for the next block.\n",
     "            if annexToo, let annex, H >= 6 {\n"
     "                // y_p at newest' = m + 6: x[m−5 ... m+6] = hb[i + H − 6 ...].\n"
     "                for ph in 0..<4 {\n"
     "                    vDSP_conv(h + H - 6, 1, annex + ph * 12, 1, tmp, 1, len, 12)\n"
     "                    vDSP_vabs(tmp, 1, tmp, 1, len)\n"
     "                    vDSP_vmax(peakBuf, 1, tmp, 1, peakBuf, 1, len)\n"
     "                }\n"
     "            }\n"
     "            // Keep the last taps − 1 inputs for the next block.\n"),
]
for a, b in rep:
    assert a in s, a[:60]
    s = s.replace(a, b)
open(p, 'w').write(s)

p = d + '/src/main.swift'
s = open(p).read()
rep = [
    ('    case ("own", "limiter64"): return OwnTruePeakLimiter2(taps: 64, beta: 10)',
     '    case ("own", "limiter64"): return OwnTruePeakLimiter2(taps: 64, beta: 10)\n'
     '    case ("own", "limiter64a"): return OwnTruePeakLimiter2(taps: 64, beta: 10, annexToo: true)'),
    ('        ("own64", { OwnTruePeakLimiter2(taps: 64, beta: 10) }),',
     '        ("own64", { OwnTruePeakLimiter2(taps: 64, beta: 10) }),\n'
     '        ("own64a", { OwnTruePeakLimiter2(taps: 64, beta: 10, annexToo: true) }),'),
]
for a, b in rep:
    assert a in s, a
    s = s.replace(a, b)
open(p, 'w').write(s)
print("patched")
