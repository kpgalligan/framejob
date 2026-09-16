# Silero VAD v6.2.1 — Core ML provenance

- Upstream model: [snakers4/silero-vad](https://github.com/snakers4/silero-vad), tag `v6.2.1`.
- Core ML conversion: [aufklarer/Silero-VAD-v6.2.1-CoreML](https://huggingface.co/aufklarer/Silero-VAD-v6.2.1-CoreML),
  revision `523876545a57961474fee9df913e833e130560b8`.
- Fetched: 2026-09-13.
- License: MIT (`LICENSE` beside this file, `snakers4/silero-vad`'s `v6.2.1` copy —
  the conversion repo carries none of its own).

## sha256

```
b777c3751d72b7430eac7f8544769a3d918faf77c15db184fec30e44c56007a3  silero_vad.mlmodelc/analytics/coremldata.bin
f6fcd92c3132c9c718e5f54e0e770a8c8075beaa50a5b212a6287273b4ddae67  silero_vad.mlmodelc/coremldata.bin
1b953eb3818e7092deedd96e976c05354f77beb2ddc2976fe416af17e47f62d2  silero_vad.mlmodelc/metadata.json
b0a1384c4a664697989d9eb9cfb166b4b85f151206aeefd1bfa391ef9e5ad08f  silero_vad.mlmodelc/model.mil
83210545de90c65195e8d6db1b349b7e5c31f989f48d0a908a8dc0e2f586e5f9  silero_vad.mlmodelc/weights/weight.bin
```

`metadata.json` names inputs `audio` [1,1,576], `h` [1,1,128], `c` [1,1,128] and
outputs `probability` [1], `h_out` [1,1,128], `c_out` [1,1,128] — the streaming
32 ms variant `SileroVAD.swift` drives.
