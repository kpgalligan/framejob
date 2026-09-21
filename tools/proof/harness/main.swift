// tools/proof/harness/main.swift — the offscreen chrome harness.
//
// This is the program CLAUDE.md's "Seeing the chrome" section describes:
// every file in `app/Sources` except the app's own `main.swift` is compiled
// together with THIS file (`build.sh` has the swiftc line), linked against
// `core/target/release/libreelcut_core.a`, and the result opens a `.reelcut`
// package from disk through `ProjectDocument.read(from:ofType:)`, puts an
// `EditorViewController` in an `NSWindow`, spins the runloop a few turns and
// `cacheDisplay(in:to:)`s the content view into a PNG. That is the same paint
// path the window uses, it needs no Screen Recording grant (`screencapture`
// silently writes a black PNG without one), and it renders either appearance
// on demand. The preview well comes out black — a Metal layer has no drawable
// offscreen — which does not matter, because the chrome is the point.
//
// Selection, the playhead and the S/M/L size are VIEW state and are not in
// the package, so the arguments set them:
//
//   harness <project.reelcut|welcome> <out.png> <light|dark>
//           [w] [h] [selectIndex] [playheadSec] [sizeIndex 0-2] [clip|media|document]
//           [candidateSpans] [expandSections] [mediaFilter]
//
// `selectIndex` picks the clip at that index in START order (-1 for none).
// The PNG is written at the main screen's backing scale (2x on a Retina
// Mac: a 1440x862 window is a 2880x1724 image), 8-bit RGBA.
//
// The last two arguments were added for `tools/proof/phase3_chrome.py`, and
// they are the SAME kind of thing as `selectIndex` and `playheadSec`: view
// state a package cannot carry, so the render has to be told it. Both default
// to "-" (nothing), which is exactly what every earlier caller got, so a
// nine-argument invocation renders the bytes it always did.
//
//   `candidateSpans`   Remove Silences' candidate wash (road map 2 phase 3a):
//                      comma-separated `start-end` pairs in SECONDS, e.g.
//                      "1-2,6-7". The sheet is the only thing that sets
//                      `TimelineView.candidateSpans` in the app and a sheet
//                      cannot be put up offscreen, so without this the wash
//                      could not be photographed at all.
//   `expandSections`   comma-separated `InspectorSection` ids to open, e.g.
//                      "video.obscure". A section's collapsed state is a
//                      `UserDefaults` key this file already pins (it CLEARS
//                      them, so `defaultExpanded` decides), and a section
//                      built `defaultExpanded: false` therefore shows nothing
//                      but its header — its rows cannot be seen at all. Each
//                      id here pins its key to "not collapsed".
//   `mediaFilter`      the Media tab's find band (road map 2 phase 8c):
//                      `search|order|unusedOnly`, e.g. "beta|1|0" or
//                      "|3|1". `search` is the text (empty = leave the field
//                      alone), `order` is `MediaListFilter.Order`'s raw value
//                      0–3 (empty = leave), `unusedOnly` is "1" to turn the
//                      switch on. Added for `tools/proof/phase8_chrome.py`
//                      and APPENDED, so every earlier caller's positions hold.
//
//                      It is here for `candidateSpans`' reason exactly: the
//                      band's state is view state no package carries, and the
//                      only thing that writes it in the app is a person typing
//                      into a field and clicking two controls, neither of which
//                      an offscreen render can do. Without it the NARROWED
//                      pane — a filtered list, "2 of 6 items", the "No media
//                      matches" line — cannot be photographed at all, and the
//                      narrowed pane is the whole of what phase 8c added.
//
//                      **It drives the app's own controls and sets nothing
//                      itself**: `MediaPane.filter` is private and stays that
//                      way, so this walks the pane for the three views
//                      `MediaListFilter.controls` built and calls what AppKit
//                      would have called — `controlTextDidChange(_:)` on the
//                      search field after its `stringValue` is set,
//                      `itemPicked:` on the popup (the selector its own menu
//                      items carry; a popped-up `NSMenu` cannot be chosen from
//                      offscreen), and `mouseDown(with:)` on the checkbox. So
//                      what the render shows went through `apply` and
//                      `arrange()` the way a keystroke does. The field is NOT
//                      made first responder: a caret blinks, and a blinking
//                      caret would make the settle capture below a race.
//
// TWO MORE MODES, which render nothing:
//
//   harness cues <words.json> <out.json>
//
// reads a word list and writes the cues `CaptionCues.build` makes of it. It
// belongs in this program and nowhere else, for one reason: this is the only
// binary in the tree that links `app/Sources` outside the app, and the four
// cue rules — at most two lines, at most 42 characters a line, at most six
// seconds a cue, at least a frame of gap between cues — cannot be reached any
// other way without a person at the machine. Nothing in the app calls
// `CaptionCues` until a recogniser has produced words, and
// `SFSpeechRecognizer` will not produce any without a Speech Recognition
// grant that only a frontmost app can be given, so over MCP those rules are
// unreachable and `phase4_proof.py` says so out loud rather than pretending
// otherwise. The arithmetic itself has no `Speech` in it at all — words with
// times in, cues out — so the way to test it is to hand it words with times,
// and this is the one place from which that can be done.
//
// It is a MODE and not a fifth render argument because it shares nothing with
// a render: no window, no pinned defaults, no fonts, no appearance. It is
// answered before any of that is set up, the way `welcome` is answered before
// a package is opened, and every render argument below keeps the position it
// had — `phase2_chrome.py`, `phase3_chrome.py`, `phase4_chrome.py` and
// `phase5_chrome.py` all depend on that order, so this file grows by addition
// and never by rearrangement.
//
//   harness meter <request.json> <out.json>
//
// measures buffers of samples through the level meter's MODEL (road map 2
// phase 5b: `LevelMeterSink`, `LevelMeterReading`, `LevelMeterEnvelope`,
// `LevelMeter`) and writes what the model published. It is here for the cue
// mode's reason, one step further on: nothing in the app reaches the meter
// without a PLAYING transport — `Playback` installs the sinks on a metering
// composition build and reads them off a 30 Hz timer — and an offscreen
// process has no player, no output device and no window, so over MCP and in
// every chrome render the meter is silent by construction. The measurement
// itself is arithmetic over plain float buffers with no AVFoundation in it at
// all (`LevelMeter.swift`'s header says why the model was separated from the
// view for exactly this), so the way to test it is to hand it buffers, and
// this is the one place from which that can be done.
//
// **Phase 5 first tried to reach it WITHOUT touching this file**, by compiling
// `app/Sources/LevelMeter.swift` on its own against a two-type stand-in — and
// that is worth recording, because it worked until wave 6 moved
// `LevelMeterEnvelope`'s search into `MediaPeaks.envelope` so the app would
// have one spelling of the plan's mix rule instead of two. `MediaPeaks` needs
// `ProjectSnapshot`, `ReelTime` and `MediaImporter`, and a stand-in for THAT
// would be a proof measuring its own arithmetic rather than the app's. So the
// mode is here, where every type is the real one.
//
// `request.json` is
//
//   {"at": 300000, "then_stop": "same"|"other"|null,
//    "tracks": [{"id": 1, "samples": "tone.f32", "channels": 2, "frames": 4096,
//                "ramps": [{"start": 0, "duration": 600000,
//                           "from": 0.0, "to": 1.0}]}]}
//
// and `samples` names a raw little-endian float32 file holding `channels ×
// frames` samples, PLANAR — channel 0's frames, then channel 1's — which is
// the shape `AudioTap` hands `LevelMeterSink.measure` off the composition
// track's buffer list. The signal is a FILE rather than numbers in the JSON
// because the caller must author it: a tone this program synthesized would be
// a fixture nobody could check, and the phase's claim is that a −20 dBFS tone
// SOMEBODY ELSE wrote reads as −20 dBFS here. `ramps` is the plan's envelope
// over that track (absent or null = the plan gave none = unity, `audio.rs`'s
// meaning of an unmodified track) and `at` is the playhead tick it is read at.
//
// A track may carry `"store": {"peak_left": …, "peak_right": …, "rms_left": …,
// "rms_right": …}` INSTEAD of `samples`, and then those four magnitudes go
// straight into `LevelMeterSink.store` with nothing measured. It is there for
// the one reading a buffer cannot produce — an RMS above a peak, which is what
// the two relaxed words being written and read separately can hand a reader —
// and the struct's own doc says why a check over a measured buffer cannot
// stand in for it.
//
// The output carries, per track, the sink's own `raw` reading, the `gain` the
// envelope is applying at `at`, and the `scaled` product; then `published`,
// which is read back off `LevelMeter.shared` AFTER the total has been
// published into it, so it is the model's answer and not a local variable's.
// Each reading is reported as linear magnitude AND in dBFS, the model's own
// accessors, because the phase's tolerance is stated in dB.
//
// The fold from per-track readings to the total is `Playback.meterReading()`'s
// own three lines, and they are QUOTED here rather than called for the one
// reason `meterReading` cannot be called at all: it reads `built`, the
// AVFoundation composition, which needs a player. Everything they are made of
// — `LevelMeterEnvelope.value`, `.scaled(by:)`, `.adding(_:)` — is the model's
// and is what is under test; if that loop ever grows a rule, this copy has to
// grow it too, and `phase5_chrome.py` says so where it reports the number.
//
// **The mode compiles out under `-D HARNESS_REFERENCE_BUILD`**, and that flag
// exists for one caller: `phase5_chrome.py` builds a SECOND harness out of an
// older `app/Sources` — the tree from before the level meter existed — and
// compares the two renders, which is the only way to say "this is what the
// phase added to the chrome, and this is all of it". That older tree has none
// of the meter's types in it. With the flag, every other line of this file,
// the whole render path included, is the same source compiled twice, so a
// byte comparison between the two binaries is a comparison of the APP and
// never of two instruments.
//
// **The flag is GENERAL, and its name says so on purpose.** It was
// `HARNESS_WITHOUT_METER` for the length of phase 5 and that was the wrong
// name: the next phase to add a mode naming a type an older tree lacks would
// either have to guard it with a flag about the level meter or invent a
// second one, and a reference build passing only the flags it happens to know
// would stop compiling the day it did not. So there is ONE flag, meaning "this
// is a reference build against an older `app/Sources`; compile out every mode
// that names a type newer than the tree" — put every future non-render mode
// inside the same `#if !HARNESS_REFERENCE_BUILD` rather than pinning that
// tree's copy of this file, which would let the instrument drift a phase at a
// time. (`build_reference` will fall back to the reference commit's own
// `main.swift` if this one refuses to compile against it, and says so in its
// report — but that fallback is the apology, not the plan.)
//
// `words.json` is `{"fps": [30, 1], "words": [{"text": "…", "start": 0,
// "end": 300000, "speaker": null}, …]}`, in TICKS rather than seconds — with
// `speaker` OPTIONAL, read when it is there and nil when it is not, which is
// road map 6 §5f's fifth rule and is why a fixture written before it exists
// still produces byte-identical cues. Ticks because the rules are
// measured in ticks and a frame at 30 fps is 20 000 of them and 0.0333… of a
// second: a fixture written in seconds could not say "exactly one frame"
// exactly. `fps` defaults to 30/1 and is what the gap is one frame OF. The
// output is `{"fps", "frame", "cues"}`, and each cue carries its `start`,
// `end`, `text` and `tag` plus `snapped_start` and `snapped_end` — those two
// times put on the frame grid by the same `ReelTime.snapToFrame` that
// `CaptionLayout.place` will call on them next, since the gap rule's whole
// point is that it is still there after the snap.
//
// Determinism: the app persists its pane sizes, the inspector's collapsed
// state, the track height, snapping and the Document tab's one checkbox in
// `UserDefaults`, and a bare binary shares the "harness" defaults domain
// with anything else called harness. So every key the CHROME reads — and
// AppKit's scroller-style switch — is pinned in the volatile ARGUMENT
// domain before the first view loads: that domain is searched first, and
// nothing the run writes back (`splitViewDidResizeSubviews` stores the pane
// sizes) can change the next run's answer. Two renders of one package are
// byte-identical; `tools/proof/phase2_chrome.py` checks that first. The
// keys the app reads and the chrome does NOT draw (`ReelcutCompositorTiming`,
// `RCFFmpegImport`, `RCFFmpegPath`) are left alone — with the exception
// `pinDefaults` argues one key at a time: a key nothing draws is pinned anyway
// when ORDINARY USE of the app writes it, since the render would then start
// moving with whatever the developer last did the day some chrome grew a
// readout of it. `ReelcutExportChoice` (phase 7) and phase 8's two are those.
import AppKit
import CoreText

/// Offscreen render of the editor chrome. Screen capture needs a TCC grant this
/// process does not have, so the views are asked to draw themselves instead:
/// `cacheDisplay(in:to:)` is the same paint path the window uses, minus the
/// compositor's Metal layer (which has no drawable offscreen and comes out
/// empty — the chrome is what this is for).
enum Harness {
    static func registerFonts(_ directory: URL) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return }
        for name in names where name.hasSuffix(".ttf") || name.hasSuffix(".otf") {
            CTFontManagerRegisterFontsForURL(
                directory.appendingPathComponent(name) as CFURL, .process, nil)
        }
    }

    /// The editor's persisted view state, pinned so a render never depends on
    /// what an earlier run (or another program sharing the defaults domain)
    /// left behind. The keys are `EditorViewController`'s, `InspectorPane`'s
    /// and `DocumentPane`'s; the values are the app's own defaults.
    static func pinDefaults(sizeIndex: Int, expand: [String]) {
        var pinned: [String: Any] = [
            "ReelcutInspectorWidth": 304.0,       // DS.panelWidth
            "ReelcutTimelineHeight": 300.0,       // EditorViewController.defaultTimelineHeight
            "ReelcutInspectorCollapsed": false,
            "ReelcutTimelineTrackHeight": sizeIndex,
            "ReelcutSnappingEnabled": true,
            "ReelcutSafeGuidesVisible": false,
            // The Document tab's "Resize clips proportionally" checkbox is
            // drawn from this key at paint time (`DocumentPane.rescaleClipsKey`),
            // so a `document` render moved with the machine's stored value
            // until it was pinned. `false` is `bool(forKey:)` of an absent key.
            "ReelcutInspectorRescaleClips": false,
            // The export sheet's remembered choice (`ExportChoice`, phase 7).
            // "" is what `string(forKey:)` of an absent key reads as here —
            // the store treats an empty string as "nothing remembered" — so
            // pinning it is pinning the first-run card.
            //
            // **Nothing the harness photographs reads this key today**, and
            // that is worth saying rather than leaving to be rediscovered: the
            // harness renders the EDITOR's content view, a sheet is not in it,
            // and a sheet cannot be put up offscreen at all (which is why
            // phase 3's Remove Silences candidates arrive as an ARGUMENT). It
            // is pinned anyway because this key is unlike every other one
            // here — it is written by ORDINARY USE of the app on the machine
            // that runs the proofs, once per export, so the day any chrome
            // grows a "last export" affordance the renders would start moving
            // with whatever the developer last exported, and the symptom of
            // that (identical, stable, DIFFERENT output across processes) is
            // the one phase 4 spent a gate learning to read.
            "ReelcutExportChoice": "",
            // View ▸ Preview Quality (`PreviewQuality.defaultsKey`, phase 8a).
            // 0 is Full, which is what `integer(forKey:)` of an absent key
            // reads as and what `PreviewQuality.stored()` answers for one.
            // NOTHING the harness photographs reads it — it scales the
            // PLAYER's video composition, and the preview well is black
            // offscreen because a Metal layer has no drawable there — so this
            // is pinned for the `ReelcutExportChoice` reason above it rather
            // than for a render: it is written by ORDINARY USE of the app on
            // the machine that runs the proofs, so the day the chrome grows a
            // readout of the current quality (a toolbar badge, say) the renders
            // would start moving with whatever the developer last chose.
            "ReelcutPreviewQuality": 0,
            // The preview window's saved frame (phase 8b). AppKit spells the
            // key `"NSWindow Frame " + setFrameAutosaveName`'s name — measured,
            // not assumed — and "" is what an unsaved frame reads as, which is
            // the first-run window: `setFrameUsingName` answers false and the
            // panel centres itself. Pinned on the same terms as the two above:
            // the harness renders the EDITOR's content view and never makes a
            // preview window at all, but ordinary use of the app writes this
            // key on every move and resize of one.
            "NSWindow Frame ReelcutPreviewWindow": "",
            // The recorder panel's six remembered choices (road map 3, R1c:
            // `RecorderPanelController.<key>` — spelled as LITERALS here, because this
            // file must also compile against a tree from before the recorder existed
            // under `-D HARNESS_REFERENCE_BUILD`, the phase-5 cross-build), pinned to their first-run
            // values — the display 0 (the main one), no microphone, system
            // audio ON (the one of the six whose absent-key reading is not
            // the default, which the panel tests by name), clicks off, 60,
            // nominal. NOTHING the harness photographs reads them: the panel
            // is a floating `NSPanel` and never in the editor's content
            // view. Pinned on `ReelcutExportChoice`'s terms — written by
            // ORDINARY USE of the app on the machine that runs the proofs,
            // every time a person changes a row — so that the day a chrome
            // grows a readout of the recorder's state the renders cannot
            // start moving with whatever the developer last recorded. The
            // panel keeps NO frame autosave name, so there is no
            // "NSWindow Frame …" key to pin for it.
            "ReelcutRecordingDisplay": 0,
            "ReelcutRecordingMicrophone": "",
            "ReelcutRecordingSystemAudio": true,
            "ReelcutRecordingShowClicks": false,
            "ReelcutRecordingRate": 60,
            "ReelcutRecordingSize": "nominal",
            "AgentServerEnabled": false,
            // AppKit picks legacy (16 pt, always visible) or overlay scrollers
            // by whether a MOUSE is attached, and the inspector pane is 16 pt
            // narrower under the legacy kind, which moves its header's right
            // end. Pinned to the legacy kind so the same package renders the
            // same bytes on a laptop alone as on a desk. Measured: this key is
            // honoured from the argument domain — `WhenScrolling` changes the
            // render, `Always` and `Automatic`-with-a-mouse are identical.
            "AppleShowScrollBars": "Always",
        ]
        // `InspectorSection` stores COLLAPSED, so `false` is "open". The loop
        // below drops every such key from the persistent domain and the
        // argument domain is searched first, so these decide.
        for id in expand where !id.isEmpty {
            pinned[InspectorSection.collapsedKeyPrefix + id] = false
        }
        UserDefaults.standard.setVolatileDomain(pinned, forName: UserDefaults.argumentDomain)
        // A section's collapsed state is stored per section id; any such key
        // left in the persistent domain would re-collapse one section on one
        // machine. Drop them so `defaultExpanded` applies everywhere.
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("ReelcutInspectorSection.") {
            defaults.removeObject(forKey: key)
        }
    }

    /// Every descendant of `view` of one type, in front-to-back subview
    /// order. The Media tab's find band holds exactly one of each of the
    /// three types `applyMediaFilter` looks for, and it asserts that.
    static func descendants<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
        var found: [T] = []
        for subview in view.subviews {
            if let hit = subview as? T { found.append(hit) }
            found.append(contentsOf: descendants(type, in: subview))
        }
        return found
    }

    /// The Media tab's find band, driven through the app's own controls —
    /// see the header for why this exists and why it does not touch
    /// `MediaPane.filter`.
    ///
    /// A part that names nothing leaves that control alone, so "beta||" and
    /// "beta" are the same request. A control this cannot find is a WARNING
    /// on stderr rather than a silent no-op: a render that quietly ignored
    /// the argument would come back as the resting band, which is exactly the
    /// picture the caller is comparing against.
    static func applyMediaFilter(_ spec: String, in controller: EditorViewController) {
        // `MediaSearchField`, `OptionPopupControl` and `OptionCheckboxControl` are
        // phase 8's, so this mode compiles out under -D HARNESS_REFERENCE_BUILD
        // (the cross-build convention above): a reference tree from before
        // the find band existed must still compile THIS instrument, or the
        // phase-5 comparison silently falls back to two builds of it.
        #if !HARNESS_REFERENCE_BUILD
        let parts = spec.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        let search = parts.count > 0 ? parts[0] : ""
        let order = parts.count > 1 ? Int(parts[1]) : nil
        let unused = parts.count > 2 && parts[2] == "1"
        guard let pane = descendants(MediaPane.self, in: controller.view).first else {
            warn("mediaFilter: the Media tab is not showing a MediaPane")
            return
        }
        if !search.isEmpty {
            guard let field = descendants(MediaSearchField.self, in: pane).first else {
                warn("mediaFilter: no MediaSearchField in the pane")
                return
            }
            field.stringValue = search
            // What AppKit calls when the field editor changes, and the only
            // thing `MediaSearchField` does with it.
            field.controlTextDidChange(
                Notification(name: NSControl.textDidChangeNotification, object: field))
        }
        if let order = order {
            let popups = descendants(OptionPopupControl.self, in: pane)
            guard popups.count == 1 else {
                warn("mediaFilter: expected one OptionPopupControl, found \(popups.count)")
                return
            }
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            item.tag = order
            let picked = NSSelectorFromString("itemPicked:")
            guard popups[0].responds(to: picked) else {
                warn("mediaFilter: OptionPopupControl no longer answers itemPicked:")
                return
            }
            popups[0].perform(picked, with: item)
        }
        if unused {
            let boxes = descendants(OptionCheckboxControl.self, in: pane)
            guard boxes.count == 1 else {
                warn("mediaFilter: expected one OptionCheckboxControl, found \(boxes.count)")
                return
            }
            guard let event = NSEvent.mouseEvent(
                with: .leftMouseDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: controller.view.window?.windowNumber ?? 0,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
            else {
                warn("mediaFilter: could not synthesize a mouse event")
                return
            }
            boxes[0].mouseDown(with: event)
        }
        #else
        warn("mediaFilter: this harness was built -D HARNESS_REFERENCE_BUILD, which compiles the mode out")
        #endif
    }

    static func warn(_ message: String) {
        FileHandle.standardError.write("warning: \(message)\n".data(using: .utf8)!)
    }

    /// A comma-separated argument. "-" and "" both mean nothing, so an
    /// omitted argument and an explicit "no" are the same thing — every
    /// other argument here reads that way too.
    static func list(_ text: String) -> [String] {
        guard text != "-", !text.isEmpty else { return [] }
        return text.split(separator: ",").map { String($0) }
    }

    /// `list`'s entries as `start-end` pairs in SECONDS. A pair that is not
    /// two numbers is DROPPED rather than clamped: the caller is a proof
    /// script, and a silently mis-parsed span would show up as a missing
    /// wash, which is a failing check rather than a passing lie.
    static func spans(_ text: String) -> [SilenceDetector.Span] {
        list(text).compactMap { pair in
            let parts = pair.split(separator: "-")
            guard parts.count == 2, let from = Double(parts[0]), let to = Double(parts[1])
            else { return nil }
            return SilenceDetector.Span(
                start: Ticks(from * 600_000), end: Ticks(to * 600_000))
        }
    }

    /// The cue builder, run over a word list from a file — the second mode of
    /// the header, and the only way `CaptionCues.build` can be reached without
    /// a Speech Recognition grant.
    ///
    /// Everything here is a translation: JSON into `CaptionCues.Word`s, the
    /// cues back into JSON. Nothing is computed that the app does not compute,
    /// which is the point — a proof that re-implemented the rules in order to
    /// check them would be checking itself. The one addition is the pair of
    /// snapped times, and even those are `ReelTime.snapToFrame`'s over
    /// `CaptionLayout.place`'s own `max(0, start)`: they are the first thing
    /// the placement does to a cue, before it has had any say of its own about
    /// one shorter than a frame or one that overlaps its successor.
    static func cues(from input: URL, to output: URL) throws {
        struct Request: Decodable {
            struct Word: Decodable {
                let text: String
                let start: Ticks
                let end: Ticks
                /// Road map 6 §5f's fifth rule. Absent in every fixture
                /// written before it existed, which is the point: with every
                /// speaker nil the output is byte-identical to what it was.
                let speaker: String?
            }
            /// `[num, den]`, the model's own spelling of a rate (§5.2).
            let fps: [Int]?
            let words: [Word]
        }
        let request = try JSONDecoder().decode(Request.self, from: Data(contentsOf: input))
        let rate = request.fps ?? [30, 1]
        let fps = Fps(num: rate.first ?? 30, den: rate.count > 1 ? rate[1] : 1)
        // `max(_, 1)` is `CaptionLayout.place`'s own guard against a
        // degenerate rate, and the builder is handed the same number the
        // placement will use.
        let frame = max(fps.frameDuration, 1)
        // `speaker:` is inside the guard because `phase5_chrome.py` and
        // `recording_probe.py` compile THIS file against OLDER trees under
        // `-D HARNESS_REFERENCE_BUILD`, and `CaptionCues.Word` had no such
        // argument before road map 6's C1. The three-argument call below is
        // what those builds take.
        #if !HARNESS_REFERENCE_BUILD
        let built = CaptionCues.build(
            from: request.words.map {
                CaptionCues.Word(
                    text: $0.text, start: $0.start, end: $0.end, speaker: $0.speaker)
            }, frame: frame)
        #else
        let built = CaptionCues.build(
            from: request.words.map {
                CaptionCues.Word(text: $0.text, start: $0.start, end: $0.end)
            }, frame: frame)
        #endif
        let rows = built.map { cue -> [String: Any] in
            [
                "start": cue.start,
                "end": cue.end,
                "snapped_start": ReelTime.snapToFrame(max(0, cue.start), fps: fps),
                "snapped_end": ReelTime.snapToFrame(cue.end, fps: fps),
                "text": cue.text,
                "tag": cue.tag,
            ]
        }
        let json: [String: Any] = ["fps": [fps.num, fps.den], "frame": frame, "cues": rows]
        try JSONSerialization
            .data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            .write(to: output)
    }

    #if !HARNESS_REFERENCE_BUILD
    /// The level meter's model, run over buffers from a file — the third mode
    /// of the header, and the only way `LevelMeterSink` can be reached without
    /// a playing transport.
    ///
    /// Like the cue mode, everything here is a translation: a planar float
    /// file into the pointers `AudioTap` hands the sink, and the readings back
    /// into JSON. The one thing that is not a translation is the fold, and it
    /// is `Playback.meterReading()`'s, quoted (the header says why it cannot
    /// be called): each track's last buffer, multiplied by the mix envelope
    /// over it at `at`, summed — which is what makes the number POST-fader
    /// even though every tap is PreEffects.
    static func meter(from input: URL, to output: URL) throws {
        struct Request: Decodable {
            /// Four magnitudes written STRAIGHT into the sink, instead of a
            /// file being measured into it.
            ///
            /// It exists for one claim, and for a claim no measured buffer can
            /// carry: `rms ≤ peak` is arithmetic over any real buffer, so a
            /// check that a measured reading obeys it passes against a build
            /// whose clamp has been deleted. The skew the clamp is actually
            /// there for comes from the crossing — `LevelMeterSink` stores peak
            /// and RMS in two separate relaxed words and reads them back
            /// separately, so a reader can catch this buffer's RMS beside the
            /// previous, quieter buffer's peak. This is the only way to hand
            /// the model that pair.
            struct Store: Decodable {
                let peakLeft: Float
                let peakRight: Float
                let rmsLeft: Float
                let rmsRight: Float

                enum CodingKeys: String, CodingKey {
                    case peakLeft = "peak_left"
                    case peakRight = "peak_right"
                    case rmsLeft = "rms_left"
                    case rmsRight = "rms_right"
                }
            }

            struct Track: Decodable {
                let id: Int?
                /// A raw little-endian float32 file of `channels × frames`
                /// samples, planar. Relative paths resolve against the
                /// request's own directory. Absent only when `store` is given.
                let samples: String?
                let channels: Int?
                let frames: Int?
                /// Decoded by `PlanRamp`'s OWN decoder — the one the plan
                /// itself arrives through — rather than rebuilt from four
                /// numbers here, which its hand-written `init(from:)` would
                /// not have allowed anyway.
                let ramps: [PlanRamp]?
                /// Set instead of `samples` to write the sink directly.
                let store: Store?
            }
            let at: Ticks?
            /// After the total is published, publish silence from the SAME
            /// transport identity or from ANOTHER one — the model's one guard
            /// (a second document's stop may not blank a live meter).
            let thenStop: String?
            let tracks: [Track]

            enum CodingKeys: String, CodingKey {
                case at, tracks
                case thenStop = "then_stop"
            }
        }
        let request = try JSONDecoder().decode(Request.self, from: Data(contentsOf: input))
        let at = request.at ?? 0

        /// One reading, both ways round: linear magnitude (what the samples
        /// are) and dBFS (what the phase's tolerance is written in).
        func describe(_ reading: LevelMeterReading) -> [String: Any] {
            [
                "peak_left": Double(reading.peakLeft),
                "peak_right": Double(reading.peakRight),
                "rms_left": Double(reading.rmsLeft),
                "rms_right": Double(reading.rmsRight),
                "peak_left_db": Double(reading.peakLeftDB),
                "peak_right_db": Double(reading.peakRightDB),
                "rms_left_db": Double(reading.rmsLeftDB),
                "rms_right_db": Double(reading.rmsRightDB),
                "peak_db": Double(reading.peakDB),
                "is_silent": reading.isSilent,
            ]
        }

        var rows: [[String: Any]] = []
        var total = LevelMeterReading.silent
        for (index, track) in request.tracks.enumerated() {
            let sink = LevelMeterSink()
            if let stored = track.store {
                // The audio thread's own two stores, called directly — the one
                // path that can put a skewed pair in front of the model.
                sink.store(
                    peakLeft: stored.peakLeft, peakRight: stored.peakRight,
                    rmsLeft: stored.rmsLeft, rmsRight: stored.rmsRight)
            } else {
                guard let samples = track.samples,
                    let channels = track.channels, let frames = track.frames
                else {
                    throw NSError(
                        domain: "harness", code: 5,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "track \(index) has neither `samples` with `channels` "
                                + "and `frames` nor `store`"
                        ])
                }
                let url = URL(
                    fileURLWithPath: samples,
                    relativeTo: input.deletingLastPathComponent())
                let data = try Data(contentsOf: url)
                let wanted = channels * frames * MemoryLayout<Float>.size
                guard channels > 0, frames > 0, data.count >= wanted else {
                    throw NSError(
                        domain: "harness", code: 5,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "\(url.lastPathComponent) holds \(data.count) bytes, "
                                + "\(channels) × \(frames) floats want \(wanted)"
                        ])
                }
                // The planar file becomes one base pointer per channel, which
                // is exactly what the tap rebases out of the buffer list.
                data.withUnsafeBytes { raw in
                    let base = raw.bindMemory(to: Float.self).baseAddress
                    var pointers: [UnsafeMutablePointer<Float>?] = (0..<channels).map {
                        UnsafeMutablePointer(mutating: base?.advanced(by: $0 * frames))
                    }
                    pointers.withUnsafeMutableBufferPointer { buffer in
                        sink.measure(buffer, count: channels, frames: frames)
                    }
                }
            }
            let metered = LevelMeterTrack(id: track.id ?? index, ramps: track.ramps, sink: sink)

            // Playback.meterReading()'s own three lines.
            let gain = Float(LevelMeterEnvelope.value(metered.ramps, at: at))
            let raw = metered.sink.read()
            let scaled = raw.scaled(by: gain)
            total = total.adding(scaled)

            rows.append([
                "id": metered.id, "gain": Double(gain),
                "raw": describe(raw), "scaled": describe(scaled),
            ])
        }

        // The publish, and the read BACK — `published` is the model's own
        // state, not the local total, so a model that dropped a publish on the
        // floor would be caught here rather than flattered.
        let transport = ObjectIdentifier(Harness.self)
        LevelMeter.shared.publish(total, from: transport)
        var json: [String: Any] = [
            "at": at,
            "tracks": rows,
            "total": describe(total),
            "published": describe(LevelMeter.shared.reading),
            "floor_db": Double(LevelMeterMath.floorDB),
        ]
        if let stop = request.thenStop {
            let other = ObjectIdentifier(NSObject.self)
            LevelMeter.shared.publish(.silent, from: stop == "same" ? transport : other)
            json["stopped_from"] = stop
            json["published_after_stop"] = describe(LevelMeter.shared.reading)
        }
        try JSONSerialization
            .data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            .write(to: output)
    }
    #endif

    /// One capture of the view, as PNG bytes.
    private static func capture(_ view: NSView) throws -> Data {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw NSError(domain: "harness", code: 1)
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "harness", code: 2)
        }
        return data
    }

    /// Captures the view once it has STOPPED MOVING, rather than after a fixed
    /// number of runloop turns.
    ///
    /// A fixed spin count is a guess about how long the last relayout takes,
    /// and waiting for the answer is better than guessing at it whatever else
    /// is true.
    ///
    /// It is NOT, however, what makes a render reproducible, and the history
    /// is worth keeping so nobody re-reads it the same way. This was landed
    /// in phase 4 as the cure for a bistable inspector — the Actions pane
    /// sometimes at its intrinsic height and sometimes stretched, a render
    /// deterministic within a process and different across processes — and it
    /// cured nothing, because a settle can only wait out a layout that is
    /// still MOVING and both of those layouts had already stopped. The cause
    /// was an ambiguous constraint in `InspectorPane.swift` (a bottom pin at
    /// `.defaultLow` tying with a section's own default hugging of 250), and
    /// it is fixed there. Keep this loop for what it actually buys — no magic
    /// number to re-tune when a view is added — and do not reach for it again
    /// when two runs disagree: identical, stable, DIFFERENT output is an
    /// ambiguity to find, not a race to out-wait.
    ///
    /// So the instrument waits for its subject: capture, spin, capture again,
    /// and only write when two consecutive captures are byte-identical. A
    /// layout that has stopped changing produces the same bytes twice; one
    /// still settling does not. The bound is generous because the cost of an
    /// extra turn is milliseconds and the cost of a flaky proof is a person
    /// re-running it and learning to distrust it.
    static func png(_ view: NSView, to url: URL) throws {
        var previous = try capture(view)
        for _ in 0..<40 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            view.layoutSubtreeIfNeeded()
            let next = try capture(view)
            if next == previous {
                try next.write(to: url)
                return
            }
            previous = next
        }
        FileHandle.standardError.write(
            "warning: the layout never settled; writing the last capture\n".data(using: .utf8)!)
        try previous.write(to: url)
    }
}

let arguments = CommandLine.arguments
guard arguments.count >= 4 else {
    FileHandle.standardError.write(
        ("usage: harness <project.reelcut|welcome> <out.png> <light|dark> "
            + "[w] [h] [selectIndex] [playheadSec] [sizeIndex 0-2] [clip|media|document] "
            + "[candidateSpans] [expandSections] [mediaFilter]\n"
            + "       harness cues <words.json> <out.json>\n"
            + "       harness meter <request.json> <out.json>\n")
            .data(using: .utf8)!)
    exit(64)
}

// The two non-rendering modes, answered first and answered here: neither opens
// a package, wakes AppKit or reads a default, so none of the setup below them
// applies. Their three arguments sit inside the render form's own count, so
// the guard above serves all three and no render argument moved.
if arguments[1] == "cues" {
    do {
        try Harness.cues(
            from: URL(fileURLWithPath: arguments[2]), to: URL(fileURLWithPath: arguments[3]))
        print("wrote \(arguments[3])")
        exit(0)
    } catch {
        FileHandle.standardError.write("cues failed: \(error)\n".data(using: .utf8)!)
        exit(4)
    }
}
if arguments[1] == "meter" {
    #if HARNESS_REFERENCE_BUILD
    FileHandle.standardError.write(
        "meter: this harness was built -D HARNESS_REFERENCE_BUILD\n".data(using: .utf8)!)
    exit(5)
    #else
    do {
        try Harness.meter(
            from: URL(fileURLWithPath: arguments[2]), to: URL(fileURLWithPath: arguments[3]))
        print("wrote \(arguments[3])")
        exit(0)
    } catch {
        FileHandle.standardError.write("meter failed: \(error)\n".data(using: .utf8)!)
        exit(5)
    }
    #endif
}

let projectURL = URL(fileURLWithPath: arguments[1])
let outURL = URL(fileURLWithPath: arguments[2])
let appearanceName: NSAppearance.Name = arguments[3] == "dark" ? .darkAqua : .aqua
let width = arguments.count > 4 ? Double(arguments[4]) ?? 1440 : 1440
let height = arguments.count > 5 ? Double(arguments[5]) ?? 862 : 862
/// Selection and the playhead are VIEW state and never reach the package, so
/// the render has to be told what to pick.
let selectIndex = arguments.count > 6 ? Int(arguments[6]) ?? -1 : -1
let playheadSeconds = arguments.count > 7 ? Double(arguments[7]) ?? 0 : 0
let sizeIndex = arguments.count > 8 ? min(max(Int(arguments[8]) ?? 1, 0), 2) : 1
let tabName = arguments.count > 9 ? arguments[9] : "clip"
/// Two more pieces of view state a package cannot carry — see the header.
let candidateSpans = Harness.spans(arguments.count > 10 ? arguments[10] : "-")
let expandSections = Harness.list(arguments.count > 11 ? arguments[11] : "-")
/// The Media tab's find band — the twelfth argument, appended for
/// `phase8_chrome.py`. See the header: view state a package cannot carry, and
/// the only thing that writes it in the app is a person at the controls.
let mediaFilterSpec = arguments.count > 12 && arguments[12] != "-" ? arguments[12] : ""

Harness.pinDefaults(sizeIndex: sizeIndex, expand: expandSections)
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
NSApp.appearance = NSAppearance(named: appearanceName)
Harness.registerFonts(URL(fileURLWithPath: arguments[0]).deletingLastPathComponent()
    .appendingPathComponent("Fonts"))

// "welcome" renders the no-document window instead of an editor.
if arguments[1] == "welcome" {
    WelcomeWindowController.shared.show()
    for _ in 0..<10 { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    guard let root = WelcomeWindowController.shared.window?.contentView else { exit(3) }
    root.layoutSubtreeIfNeeded()
    do {
        try Harness.png(root, to: outURL)
        print("wrote \(outURL.path)")
        exit(0)
    } catch {
        FileHandle.standardError.write("render failed: \(error)\n".data(using: .utf8)!)
        exit(2)
    }
}

let document = ProjectDocument()
do {
    try document.read(from: projectURL, ofType: "com.kgalligan.reelcut-project")
    document.fileURL = projectURL
} catch {
    FileHandle.standardError.write("read failed: \(error)\n".data(using: .utf8)!)
    exit(1)
}

let clips = document.project.snapshot.clips.sorted { $0.start < $1.start }
if selectIndex >= 0, clips.indices.contains(selectIndex) {
    document.selection = [clips[selectIndex].id]
}
document.playhead = Ticks(playheadSeconds * 600_000)
let controller = EditorViewController(document: document)
controller.trackHeight = sizeIndex
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: width, height: height),
    styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
window.contentViewController = controller
window.appearance = NSAppearance(named: appearanceName)
window.setContentSize(NSSize(width: width, height: height))
// The view tree needs a few runloop turns: the splits restore their positions
// from viewDidAppear, and the timeline's thumbnails land through a notification.
controller.viewWillAppear()
controller.viewDidAppear()
controller.refreshFromDocument(isLive: false)
for _ in 0..<12 {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    controller.view.layoutSubtreeIfNeeded()
}
// The candidate wash is the sheet's own view state and is deliberately not
// part of `TimelineView.update(...)`, so it is pushed in here — after the
// refresh that would otherwise have run over it — and the last few runloop
// turns below let its `didSet` redisplay land.
if !candidateSpans.isEmpty {
    controller.timeline?.candidateSpans = candidateSpans
}
switch tabName {
case "media": controller.inspector?.select(.media)
case "document": controller.inspector?.select(.document)
default: break
}
for _ in 0..<4 {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    controller.view.layoutSubtreeIfNeeded()
}
// The find band, after the pane it lives in exists — a control cannot be
// driven before it has been built, and `select(.media)` is what builds it.
if !mediaFilterSpec.isEmpty {
    Harness.applyMediaFilter(mediaFilterSpec, in: controller)
    for _ in 0..<4 {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        controller.view.layoutSubtreeIfNeeded()
    }
}
do {
    try Harness.png(controller.view, to: outURL)
    print("wrote \(outURL.path)")
} catch {
    FileHandle.standardError.write("render failed: \(error)\n".data(using: .utf8)!)
    exit(2)
}
exit(0)
