# Vorbis WebM fixtures

Two real encoders' Vorbis in WebM, read by `core/tests/container_vorbis.rs`
and `container_vorbis_headers.rs` (issue batch B77, spec §11 #228-V). Made
by the B77 scout on 2026-10-03 (macOS 26.5.1 25F80, M2 Max) and copied here
unchanged from its handoff folder, under new names.

| File | Was | Made by |
|---|---|---|
| `ffmpeg.webm` | `vorbis_ffmpeg.webm` | ffmpeg 9.0.2's native Vorbis encoder (`-c:a vorbis -strict -2 -ac 2`; the stream's ENCODER tag reads `Lavc63.1.102 vorbis`), 48 kHz stereo, 48 packets, 1.021 s. ffmpeg's encoder is stereo only and uses 2048-sample blocks only. |
| `libvorbis.webm` | `vorbis_libvorbis.webm` | Homebrew libvorbis 1.3.7 through a minimal libvorbisenc writer (`venc.c`: f32le stereo 48 kHz on stdin, `vorbis_encode_init_vbr(…, 2, 48000, 0.4)`, Ogg on stdout), then `ffmpeg -c copy` into WebM; 88 packets, 1.5 s, 256/2048 blocks mixed. This ffmpeg has no libvorbis, which is why the encoder was driven directly. |

The input signals are measurement signals; no test reads the decoded sound,
only the headers, the packets' first bytes and the Block times.

`expected.json` holds, per file, what ffmpeg itself reads:

- `packets` — the WebM's audio packet count;
- `counts_but_last` — `ffprobe`'s packet durations on the SOURCE Ogg (ffmpeg's
  own Vorbis parser), every packet's but the last, whose duration the Ogg
  granule trims and the copy does not (spec §11 #228-V, no end trim);
- `block_ms` — `ffprobe`'s packet pts on the WebM, in milliseconds (its
  TimestampScale), in file order.

The keys were renamed from the handoff's `vorbis_ffmpeg.webm` and
`vorbis_libvorbis.webm` to these files' names; the values are unchanged.
