# 1. What this is

A screencast editor without a recorder — and, since road map 3,
a recorder of the SCREEN, and since §11 CAM-1 of a camera beside it or on its
own, whose output is ordinary media. Open one or
more video files from disk, arrange them on layered tracks over a fixed canvas, trim,
split, annotate, animate, and export. Today it runs on the Mac only, Apple Silicon, macOS 26+.

The bar was a balance: enough to make a real cut with text, shapes,
transitions and simple animation. Since §11 CJ-1 (2026-11-01) the spec names
no non-goal. Everything this paragraph once excluded is lifted: multicam
(taken up by road map 'creator-jobs' as a program track over angle tracks,
§11 SW-3); colour grading beyond per-clip controls (GR-1 onward), with the
features once marked not wanted (GR-20, GR-27…GR-30); a plugin system, and
scripting beyond a graphic's own module (G-1); hosting third-party Audio
Unit plug-ins (AU-2); motion blur, stabilisation and optical-flow retiming;
auto-reframe (taken up as Vision analysis plus ordinary actions, §11 VR-1);
ML or heavy pixel work outside the compositor's one pass; callouts
reconstructed after a recording; and any platform but macOS. Screen
recording (road map 3), camera recording (CAM-1) and audio beyond what
shipped (AU-2) were lifted before them. Lifting makes a thing allowed, not
scheduled: what is built is what a road map builds, and the documentation
site (`docs/site/`) says what is built today. Four decisions shape what is built
and stand until a road map amends them: a graphic is a source (G-1), no
third-party Audio Unit is hosted (AU-2), effects are closed vocabularies
(R5-1), and a recording is ordinary media (`recording.md`, as CU-2 amends
it).

**The opening flow is the point.** File > Open on a `.mov` or `.mp4` (or a
drop on the Dock icon, or the welcome window's Open Video…) creates an
*untitled* project sized to that file, with the file as the first clip on
Track 1, ready to cut. Save then writes a `.framejob` package next to the
source. The app is also the Alternate handler for movie, audio and image
types so Open With… works from the Finder.
