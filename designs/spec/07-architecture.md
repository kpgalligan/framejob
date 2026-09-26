# 7. Architecture — Rust decides, AVFoundation and Metal do

All pixel and sample work happens on the platform, except a graphic's
rasterization, which is the `graphic` crate's (G-2). Pure-Rust decoding of
H.264 / HEVC / ProRes does not exist at production quality, and linking
ffmpeg is a 60 MB dependency with licensing questions and no VideoToolbox
by default. AVFoundation gives hardware decode and encode, synchronized
audio/video playback, scrubbing, and export for free.

Everything that *decides* what to show is Rust and testable without a GPU
or a video file: the model, every edit, the evaluation of the timeline at
a time, the plan for playback and export, the file format, the agent
server.

```
   AppKit UI ──apply(op json)──▶ Project (immutable) ──evaluate──▶ Composition plan ──▶ AVMutableComposition
   (timeline, canvas,           ▲ undo = old handle               Frame recipe(t)          + AudioMix + VideoComposition
    inspector, agent)           │                                      │                          │
                                │                                      ▼                          ▼
                                └──── new handle + snapshot ◀──  Metal compositor ◀── decoded frames ── AVPlayer / ExportWriter
                                                                 (AVVideoCompositing)
                                                                       │
                                                                       ▼
                                                               screen / .mp4 .mov
```
