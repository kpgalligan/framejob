# Frame Job User Guide

Frame Job is a native macOS video editor for Apple Silicon Macs running
macOS 26 or later. You open a movie, arrange it on layered tracks over a fixed
canvas, then trim, cut, grade, caption, animate and export it. Every edit you
make in the window can also be made by an AI agent over MCP, or by the built-in
Assistant.

The quickest way in: **File ▸ Open…** (⌘O) on a movie makes an untitled project
sized and timed to it, with the movie on Track 1, ready to cut. Save writes a
`.framejob` package.

## The pages

Read the first four in order to learn the editor; the rest stand alone.

1. [Projects and media](projects-and-media.md) — starting, saving and opening projects, the `.framejob` package, the Document tab's canvas settings, importing files, the Media tab and relinking.
2. [The timeline and playback](timeline.md) — the editor window, tracks and their switches, the ruler and playhead, zoom, selection, snapping, markers, the in/out range and playback.
3. [Editing clips](editing.md) — placing, moving, trimming, slipping, splitting, deleting and closing gaps, copy and paste, and nests.
4. [Canvas, layers, text and shapes](canvas-and-layers.md) — placing a picture on the canvas, opacity, blend modes, shadows and filters, text, shape, image and background clips, and matte tracks.
5. [Motion, actions and transitions](motion-and-transitions.md) — actions that animate a clip's properties over time, motion presets, and transitions between clips.
6. [Speed, reverse and freeze frames](speed.md) — constant speed, fitting a clip to a length, rate stretch, speed ramps and their presets, reversing and freeze frames.
7. [Audio](audio.md) — clip levels, fades, ducking, noise reduction, compression, pan, mute and solo, Normalize and Synchronize Audio.
8. [Remove Silences and Remove Filler Words](cleanup-tools.md) — cutting dead air and filler words out of a spoken recording in one step.
9. [Captions and transcription](captions.md) — importing and exporting captions, and transcribing speech on this Mac or with AssemblyAI into subtitles or word-by-word captions.
10. [Colour grading](color-grading.md) — the Color tab, wheels, curves, looks and LUTs, adjustment clips and qualifiers, Show Ungraded and the scopes.
11. [HDR and colour management](hdr-and-color.md) — how sources are read, camera log, SDR and HDR (HLG) projects, blending, and HDR and SDR deliverables.
12. [Motion graphics](graphics.md) — graphic clips, the built-in graphics, their properties in the inspector, and bringing in your own.
13. [Screen recording](screen-recording.md) — recording a display or a window with system audio, microphone and click rings, and recording voice-overs.
14. [Exporting](export.md) — the export sheet, its formats and settings, presets, the Export Queue, and saving single frames.
15. [The Assistant](assistant.md) — chatting with Claude in the inspector to edit the open project, on your own Anthropic key.
16. [Driving Frame Job from an AI agent (MCP)](mcp.md) — connecting an MCP client such as Claude Code, how calls behave, and every tool.
17. [Settings](settings.md) — the Settings window, the View choices Frame Job remembers, and where it keeps its files.
18. [Menus and keyboard shortcuts](menus-and-shortcuts.md) — every menu command with its shortcut, and the keys, gestures and context menus that have no menu item.

Writing your own graphic module is covered by the
[graphics API reference](../graphics-api.md).
