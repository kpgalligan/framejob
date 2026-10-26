# 1. What this is

A screencast editor without a recorder — and, since road map 3,
a recorder of the SCREEN, and since §11 CAM-1 of a camera beside it or on its
own, whose output is ordinary media. Open one or
more video files from disk, arrange them on layered tracks over a fixed canvas, trim,
split, annotate, animate, and export. Mac only, Apple Silicon, macOS 26+.

The bar is a balance: enough to make a real cut with text,
shapes, transitions and simple animation, without Final Cut's magnetic
timeline, roles, multicam, scopes, or a plugin ecosystem.

Deliberate non-goals: multicam, color grading beyond
per-clip controls (§11 GR-1: tier 1 of grading — tone, adjustment clips,
looks, LUT import, an ungraded switch and one luma waveform — is in, kept by
the owner's verdict of 2026-10-10, and tier 2's scopes, colour wheels,
curves and qualifiers beside it, GR-10…GR-13; tier 3's HDR→SDR conversion
and camera log are in, GR-15, GR-16; the HDR road map's HLG timeline, its
HLG, HDR10 and SDR-version deliverables, HDR scopes, the PQ peak, Canon Log
2 and 3 and opt-in linear-light blending are in, HD-1…HD-17; a wide-gamut
working space for SDR projects is not wanted, GR-20; tier 4's vectorscope zoom,
hue curves, the blend between curves of different point counts and the
qualifier's cleanup blur are in, GR-24, GR-31…GR-35, while an Offset
wheel, a qualifier on picture clips, 1,024-level scopes and a histogram
behind the curves are not wanted, GR-27…GR-30), audio beyond what shipped
(volume, fades, duck, pan, compressor, noise reduction, peak normalize, the
transition crossfade and the export's loudness target — M3 and §11 R5-2; so
no EQ, mix buses or Audio Units, while offline voice effects are deferred
rather than out), a plugin system (a clip may draw itself from a JavaScript
module in its package, road map 10; nothing else is scriptable — §11 G-1),
motion blur, stabilisation, optical-flow retiming and auto-reframe (heavy
pixel work or ML, outside the compositor's one-pass shape — road map 2 §4),
any platform but macOS. **Screen recording was on this list until road map 3
reversed it** (§11): the app records a display or a window through
ScreenCaptureKit into a file it then imports exactly as File ▸ Open would —
paused and resumed from the menu bar, each stretch its own file and its own
clip; callouts reconstructed after the fact stay out. **Camera recording
was on it too until §11 CAM-1** (road map "camera-recording") reversed it: a
camera alone or beside a screen recording, each its own file and clip.

**The opening flow is the point.** File > Open on a `.mov` or `.mp4` (or a
drop on the Dock icon, or the welcome window's Open Video…) creates an
*untitled* project sized to that file, with the file as the first clip on
Track 1, ready to cut. Save then writes a `.framejob` package next to the
source. The app is also the Alternate handler for movie, audio and image
types so Open With… works from the Finder.
