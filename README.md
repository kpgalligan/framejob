<p align="center">
  <img src="designs/frame-job/frame-job-icon-1024.png" alt="Frame Job icon" width="128">
</p>

# Frame Job

[![Frame Job in 90 seconds: watch on YouTube](https://img.youtube.com/vi/An7KjPoofzI/maxresdefault.jpg)](https://www.youtube.com/watch?v=Uftht-HkKy8)

A native macOS video editor. Open a movie, arrange it on layered tracks over a
fixed canvas, then trim, cut, grade, caption, animate and export it. Every edit
you make in the window can also be made by an AI agent over MCP, or by the
built-in Assistant, and each one is an ordinary undo step.

Apple Silicon, macOS 26 or later. There is no account to make: every
AI feature runs on your own API key (Anthropic for the Assistant, AssemblyAI
for cloud transcription), and everything else works without one.

## Open a movie and start cutting

**File ▸ Open…** (⌘O) on a `.mov` or `.mp4` — or a drop on the Dock icon, or
**Open Video…** in the Welcome window — creates an *untitled* project sized and
rated to that file, with the file as the first clip on Track 1, ready to cut. A
portrait phone clip opens portrait, and a 29.97 fps file stays 29.97. **Save**
then writes a `.framejob` package, offered next to the source.

## Features

**Projects and media.** Movies, sound and pictures from everything macOS plays,
plus WebM and MKV copied in without re-encoding; missing files relinked;
Consolidate Media copies footage into the package.
→ [Projects and media](docs/guide/projects-and-media.md)

**Timeline.** One kind of track that holds any clip; a frame-accurate ruler,
filmstrips and waveforms, zoom about the cursor, snapping, markers, an in/out
range, track mute, solo and lock, clip names and colour labels.
→ [The timeline and playback](docs/guide/timeline.md)

**Editing.** Move, nudge, trim, slip, roll, split, lift, ripple delete, close
gap, insert time, insert and overwrite, copy and paste, Paste Attributes, and
nests that group clips into one.
→ [Editing clips](docs/guide/editing.md)

**Canvas and layers.** Move, scale, rotate and crop on the preview; opacity,
blend modes, shadows, filters, chroma key, spotlight and obscure; text, shape,
image and background clips; matte tracks that cut the track behind them.
→ [Canvas, layers, text and shapes](docs/guide/canvas-and-layers.md)

**Motion and transitions.** Actions that ease any property to a new state over
a span — Zoom to Region for screencasts — motion presets for entrances, exits
and continuous movement, and thirteen transition styles.
→ [Motion, actions and transitions](docs/guide/motion-and-transitions.md)

**Speed.** Constant speed or fit to a length, ⌥-drag rate stretch, keep pitch,
reverse, freeze frame, and speed ramps — **Clip ▸ Speed Ramp…** makes a Ramp
Up, Ramp Down, Speed Dip or Speed Burst in one step.
→ [Speed, reverse and freeze frames](docs/guide/speed.md)

**Audio.** Per-clip volume, fades, ducking, noise reduction, compressor, pan and
mono; Normalize; Synchronize Audio lines up a camera and a separate recorder by
their sound, drift included.
→ [Audio](docs/guide/audio.md)

**Clean-up tools.** Remove Silences cuts dead air by voice or by level; Remove
Filler Words cuts the ums and uhs on their own timings. Both preview the cuts
and make them as one undo step.
→ [Remove Silences and Remove Filler Words](docs/guide/cleanup-tools.md)

**Captions.** Import SubRip, export SubRip or WebVTT; generate captions on this Mac
or with AssemblyAI, as two-line subtitles or word-by-word captions in five
styles. Every caption is an ordinary text clip.
→ [Captions and transcription](docs/guide/captions.md)

**Colour grading.** Light and colour controls, three wheels, curves, eight
built-in looks and your own `.cube` LUTs, adjustment clips with qualifiers,
Show Ungraded, and waveform, parade, vectorscope and histogram scopes.
→ [Colour grading](docs/guide/color-grading.md)

**HDR and colour management.** iPhone HDR, HDR10, wide gamut and camera log
read as what they are; SDR or HDR (HLG) projects; HLG, HDR10 and SDR-version
deliverables, with Show SDR Version to preview the last.
→ [HDR and colour management](docs/guide/hdr-and-color.md)

**Motion graphics.** Graphic clips drawn every frame by a small JavaScript
module: six built-ins (Bar Chart, Callout, Counter, Kinetic Type, Lower Third,
Title Card), properties as inspector controls, your own modules too.
→ [Motion graphics](docs/guide/graphics.md)

**Screen recording.** A display or a window, with system audio, microphone and
click rings, at 30 or 60 fps, into a new project or at the playhead; a camera,
on its own or beside the screen as a corner talking head; or a
microphone-only voice-over.
→ [Screen recording](docs/guide/screen-recording.md)

**Export.** H.264, HEVC (8-bit, 10-bit, with alpha), ProRes 422 and 4444,
M4A, WAV, AIFF, GIF and animated PNG; loudness targets, presets, an Export
Queue that runs while you edit, and single frames as stills.
→ [Exporting](docs/guide/export.md)

**The Assistant.** A conversation with Claude in the inspector that edits the
open project with the same tools an agent uses, asks before it writes a file,
and shows what each turn cost.
→ [The Assistant](docs/guide/assistant.md)

**Agents over MCP.** The whole editor as MCP tools — one per edit plus open,
save, render a frame, export and the rest — for Claude Code or any MCP client.
→ [Driving Frame Job from an AI agent](docs/guide/mcp.md)

Also: [Settings](docs/guide/settings.md) and
[Menus and keyboard shortcuts](docs/guide/menus-and-shortcuts.md).

## Getting Frame Job

The newest signed and notarized build is always at
<https://github.com/kpgalligan/framejob/releases/latest/download/FrameJob.dmg>.
While the repository is private, the link works only for people with access to
it. Open the DMG and drag Frame Job to Applications. An installed copy
updates itself (Frame Job ▸ Check for Updates…, [Settings](docs/guide/settings.md#updates)).

To build it yourself, see [Developing Frame Job](docs/developing.md).

## Using it with an AI agent

Frame Job serves its editor as MCP tools on a local socket only programs you
run can open. An MCP client reaches it through `framejob-mcp`, a helper inside
the app, which starts Frame Job in the background on the first tool call if it
is not running. **Frame Job ▸ Settings… ▸ MCP ▸ Copy MCP Command** puts the
Claude Code registration line on the clipboard, with your copy's path:

```sh
claude mcp add --scope user framejob -- '/Applications/Frame Job.app/Contents/Helpers/framejob-mcp'
```

[MCP](docs/guide/mcp.md) covers other clients and every tool;
[the Assistant](docs/guide/assistant.md) is the same tools inside the window.

## Documentation

- [The user guide](docs/guide/README.md) — every feature, by task.
- [The graphics API](docs/graphics-api.md) — writing a graphic module.
- [Manual checks](docs/manual-checks.md) — what only a person at the machine
  can confirm, run before each release.
- [The spec](designs/spec/README.md) — the normative design, one file per
  section.
- [Developing Frame Job](docs/developing.md) — building, testing, the
  architecture and publishing a release.

## Building

Xcode 26, Rust, xcodegen and bun; then `make app`. Everything else is in
[docs/developing.md](docs/developing.md).

## License

Frame Job is licensed under the [Apache License, Version 2.0](LICENSE). The
bundled fonts and the voice-activity model carry their own licences, beside
them in `app/Resources/Fonts/` and `app/Resources/Models/`, and the patched
copy of tiny-skia in `graphic/vendor/tiny-skia/` keeps its BSD-3-Clause
licence.
