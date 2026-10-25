# Remove Silences and Remove Filler Words

Frame Job has two commands for cleaning up a spoken recording such as a screencast, a tutorial or a talking-head take. **Remove Silences** finds the dead air and cuts it. **Remove Filler Words** finds the ums and uhs and cuts them on the words' own timings. Both show what they would cut before they cut anything, and both make the whole cut as one undo step. An agent can read the same answers, and it can read a clip's transcript to cut false starts.

Both commands are in the **Clip** menu, after **Close Gap**. Neither has a keyboard shortcut.

## How a clean-up cut works

The two commands cut the same way:

- **Preview first.** While the sheet is open, each span it would remove is shaded on the timeline ruler and lanes, and the sheet reads, for example, "23 cuts · removes 00:00:04:12". With nothing to cut it reads "No cuts" and **Remove** is disabled. The shading goes away when the sheet closes.
- **One edit.** **Remove** cuts every span and closes the timeline over each one, all as a single undo step: **Undo Remove Silences** or **Undo Remove Filler Words**. One ⌘Z restores everything.
- **Across the timeline.** A cut is a ripple delete across every **unlocked** track, not just the clips that were analysed, so the picture above a voice-over is cut with it. Locked tracks are neither cut nor moved.
- **Markers stay where they are.** The sheet's footnote says "markers keep their place."
- **Frame-accurate edges.** Each cut's start rounds up to the next frame and its end rounds down. That way a cut can leave up to a frame of room tone behind, but it never clips the start of the next word.
- **Nests and transitions are protected.** A cut never reaches into a nest clip, because a nest always plays from its first frame and cutting into one would strand the rest of it. A cut also never reaches into a transition's overlap or the area around it. To clean up the audio inside a nest, open it first (**Clip ▸ Open Nest**, ⌘↓) and run the command there, or un-nest it (**Clip ▸ Un-nest**, ⇧⌘G). With a nest open, both commands work on the nest's own timeline.
- **The rest of the editor waits.** Playback pauses when a sheet opens, and other editing commands are unavailable until you close it.

## Remove Silences

**Clip ▸ Remove Silences…** opens the Remove Silences sheet. The command is available whenever the timeline has a clip whose sound is switched on.

### What "silent" means

Silence is measured in the **mix**, as you hear it, not in the raw file:

- A clip you have turned down, faded out, ducked, muted, or silenced by soloing another track is quiet. It never keeps a cut from happening.
- A stretch where *every* clip in scope is quiet counts as silent. A music bed under a voice-over therefore keeps the pauses in the speech from being cut, unless you limit the scope to the voice clip (see **In:** below).
- A gap with nothing audible in it is left alone. Remove Silences takes dead air out of a recording; it does not close the gaps you placed between clips. **Clip ▸ Close Gap** does that.
- A muted clip is left out of the analysis entirely. A muted music bed is never read as one long silence covering the whole song.

### Judge by Voice or Level

**Judge by:** picks how a moment is tested.

| Mode | What counts as quiet | Default |
|---|---|---|
| Voice | Nobody is talking. An on-device voice-activity model listens to each media file once and keeps its answer with the project. A quiet microphone isn't mistaken for silence, and a hum isn't mistaken for speech. | Yes |
| Level | The sound in the mix is quieter than the threshold. | Used when the voice model can't be used |

In Voice mode, a clip with no voice in it at all, such as music or a tone, is judged by level instead. The sheet names each such clip, for example "Intro music at 00:00:12:00 holds no voice and is judged by level." That is why, in Voice mode, the threshold row is labelled **Level if no voice:**.

If the voice model can't be used on this Mac, the sheet opens in Level mode with Voice greyed out and says "The voice model could not be used, so quiet is judged by level." This lasts until you relaunch Frame Job.

Voice analysis runs on your Mac. Nothing is uploaded.

### The controls

| Control | What it does | Default | Range |
|---|---|---|---|
| **Judge by:** | Voice or Level, as above. | Voice | n/a |
| **Quieter than:** (Level mode) / **Level if no voice:** (Voice mode) | A slider in whole dBFS, with the value shown beside it. In Level mode, sound at or below it is quiet. In Voice mode, it judges clips that hold no voice, and a clip the mix turns down below it is quiet whatever it contains. | −40 dBFS | −80 to −10 dBFS |
| **Longer than:** | The shortest quiet stretch worth cutting, in seconds. Shorter pauses, such as the gap between two words, are kept. | 0.5 s | 0.05 to 10 s |
| **Keep at ends:** | How much of each quiet stretch to keep at each end, in seconds, so speech doesn't start or end abruptly. A stretch shorter than twice this value is not cut. | 0.1 s | 0 to 2 s |
| **In:** | **Selected clips** analyses only the selected clips. **All audible clips** analyses everything you can hear. | Selected clips when the selection includes something audible, otherwise All audible clips | n/a |

**Selected clips** is greyed out when nothing selected makes a sound. A number outside a field's range is refused: the field keeps the text and won't accept it, and **Remove** beeps, until you type a number inside the range (0.05–10 s for **Longer than:**, 0–2 s for **Keep at ends:**). The count and the shading update as you change any control.

The voice model's confidence level is not in the sheet. Agents can set it (see below).

### Notes the sheet can show

A second line explains results that a bare count would hide:

- **Nothing to analyse.** "Nothing the selected clips play is audible in the mix…" or "Nothing in this timeline is audible…"
- **Analysis still running.** "The waveform is still being analysed for …" or "Speech is still being analysed for …", naming the files. Right after you import or open a project, the app may still be analysing its files. In Level mode, nothing inside a file is proposed until its waveform is ready. In Voice mode, nothing inside a file is proposed until its voice analysis is ready, and a clip with no voice in it also waits for the waveform. Either way, a part the mix has turned down far enough to be quiet can still be proposed. The sheet updates on its own as each file finishes, so you can wait with it open. Relinking a file starts its analysis again; an open sheet drops the old answers at once and updates when the new ones land.
- **Judged by level.** In Voice mode, the clips that hold no voice.
- **Nests.** "Quiet inside a nest is left alone… Open the nest (⌘↓) and remove its silences there to take the dead air out." This appears when a nest held enough quiet to have been cut.

*Agents:* `detect_silence` answers the same ranges the sheet would cut and changes nothing. It takes `clips` (the Selected clips scope; leave it out to use the sheet's opening rule), `mode` (`voice` or `level`), `voice_confidence` (0.1–0.9, default 0.5, Voice mode only), `threshold_db` (at or below 0), and `min_length` and `padding` (in ticks, 600,000 per second). Pass its `ranges` to `ripple_delete_ranges` to make the cut. It also answers `count`, `removes` (ticks), `scope` (`selected` or `audible`), `clips`, `mode`, `judged_by_level_clips`, `voice_pending`, `proposed_by_mix_clips` when the mix alone makes a waiting clip quiet, and `protected_nests` (the nest clips a quiet run crossed, left uncut; open one with `set_scope` and call again to look for dead air inside it). Files still being analysed are listed under `pending_peaks`; call again shortly. `voice_confidence` is refused in Level mode, and `mode: "voice"` is refused when the voice model can't be used.

## Remove Filler Words

**Clip ▸ Remove Filler Words…** finds filler words in your speech and cuts them. It is available when the timeline has a clip that plays sound from a media file.

### Which words are fillers

A word counts as a filler when, lowercased and with punctuation stripped from its ends, it is one of:

um · uh · hmm · mhm · uh-huh · ah · huh · hm · m · er · erm

"Uh huh" written as two words matches as two fillers. The list is fixed, so a real "ah", "er" or the letter "M" is also treated as a filler.

### What it cuts

There is nothing to tune. Each run of consecutive fillers becomes one cut:

- The cut widens outward to a 32 ms speech grid so the whole filler goes, but it never reaches into the words on either side.
- Its edges then snap inward to the frame grid, as Remove Silences does. A tiny filler can end up too short to cut.
- A filler is **left in whole**, never trimmed, when cutting it would reach into a word spoken in another clip on any unlocked track, into a nest clip, or into a transition. The sheet counts these: "2 fillers are left in: too short to cut, or cutting would reach another clip's word, a nest or a transition."
- A clip on a locked track isn't read, because the cut can neither cut nor move it. The sheet says how many such clips there are.
- A clip that plays in reverse, whose sound is switched off, whose media file is missing, or whose media has no audio track has no words to read. When nothing in scope plays speech from a media file, the sheet says "Nothing in scope plays speech from a media file, so nothing was read."

**Which clips:** the selected clips when the selection includes speech from a media file (the sheet then says "Only the selected clips are read."), otherwise every clip. There is no scope menu.

### Filler words need a cloud transcript

Filler words come only from an **AssemblyAI** transcript made with filler words. Transcription on your Mac doesn't report them reliably. This makes filler removal a cloud feature: you need an AssemblyAI API key, set in **Frame Job ▸ Settings…** (⌘,) under **Transcription**.

Every AssemblyAI transcription Frame Job makes asks for filler words. Any file you caption with AssemblyAI (**File ▸ Generate Captions…**, AssemblyAI engine) is therefore already ready for Remove Filler Words, with no second upload. Only files never transcribed in the cloud, or transcribed before filler words were requested, are listed in the sheet.

When a file in scope has no such transcript, the sheet lists it under "Filler words are found only in an AssemblyAI transcript made with filler words — transcription on this Mac does not report them. These files have none yet:". Each listed file gets a row with:

- its name;
- the estimate: what would be uploaded and what it would cost, at the rate shown in the tooltip;
- a **Transcribe** button.

Above the rows, the sheet says where the audio goes: "The audio of these files is uploaded to AssemblyAI (United States), transcribed with Universal-3.5 Pro, and deleted from AssemblyAI once the words have been read back. Nothing is uploaded until Transcribe is pressed." It names European Union instead when that region is set in Settings.

Pressing **Transcribe** sends one file:

- It reuses that file's earlier transcription choices (language, speaker labels and vocabulary) and adds filler words. A file never transcribed before uses language detection, no speakers and no vocabulary.
- A file listed here that already has a caption transcript is uploaded again: that older transcript was made without filler words, so this is a second paid transcription.
- It only updates the project's saved transcript for that file. It places no captions and adds no undo step.
- The new transcript also serves captions: a later **File ▸ Generate Captions…** with AssemblyAI reuses it for that file instead of uploading again.
- While it runs, the row shows its progress, its button reads **Stop**, the other rows' buttons are disabled, and **Remove** is disabled. Return can't make a cut in the middle of a paid upload.
- When it finishes, the file drops off the list and its fillers join the count. If the run failed, the reason appears in the note.

**Transcribe** is disabled with no API key (the note points to **Frame Job ▸ Settings…**), for a file no clip plays, and while another file's run is going. A project you haven't saved yet can be transcribed; its transcript is kept with the project when you save. Closing the sheet stops a run in progress.

### Captions stay clean

Filler words never reach your captions. **File ▸ Generate Captions…** removes them from every transcript before making captions, so a transcript made with filler words produces the same captions as one made without them. See [Captions](captions.md).

*Agents:* `detect_fillers` answers the ranges the sheet would cut and changes nothing. It takes `clips` and lists each kept run under `fillers`, each left-in run under `dropped` with its reason, files with no filler transcript under `needs_transcript`, and locked clips under `locked`. It also answers `count`, `removes`, `scope` and `clips`, plus `skipped` when `clips` is given (each named clip it couldn't read, with the reason). Pass its `ranges` to `ripple_delete_ranges`. `transcribe_for_fillers` (`media`) is the Transcribe button: a paid upload that answers `ready` when `detect_fillers` can read that file. On a media that already has a filler transcript it uploads nothing and answers `ready: true`; otherwise it answers `uploaded`, `cached`, `audio_seconds`, `engine` and `language`. It is refused with no AssemblyAI key and for a media no clip plays. The built-in assistant can't use it.

## Reading a clip's transcript

An agent can read the words of any clip that plays speech from a media file, each with its start and end in timeline time. The times can be passed directly to a cut.

- **Where the words come from.** The file's saved AssemblyAI transcript when it has a current one. Otherwise this Mac's own speech recogniser runs over the clip, which takes a few seconds per minute of speech. Reading a transcript never uses the network and never uploads anything.
- **Fillers are flagged.** Each word says whether it is a filler. The answer also says whether the transcript was made with filler words at all. An on-device transcript never is, so a filler can be in the audio but missing from the words.
- **A part of the clip.** A `from`/`to` window in timeline time returns only the words that overlap it; a word crossing an edge comes back whole. With a window, the on-device recogniser hears only that part plus 2 seconds on each side. It is faster, but with less context a windowed answer can differ slightly from a whole-clip one. Either end may be given alone: a missing `from` is the clip's start and a missing `to` its end. The window is clamped to the clip and echoed back as `from`/`to`. An empty window, or one outside the clip, is refused.
- **Saved for next time.** What the on-device recogniser heard is saved in the project, per media file and language. A later request inside a stretch it has already heard comes back at once, even from another clip of the same file at any speed. A saved on-device transcript is used only while the media file and the macOS version are unchanged (the recogniser ships with macOS).
- **Speed and ramps.** Words are placed through the clip's speed, including a speed ramp, so their times match what plays on the timeline.
- **Stopping a read.** An on-device read can be long. The assistant's **Stop** ends it, and nothing is saved from a stopped read.
- **Language.** On-device recognition uses this Mac's language unless another tag (such as `en-US`) is given. A language whose speech model isn't installed is refused. Agents never download one; you can install it from **File ▸ Generate Captions…**.

*Agents:* `get_transcript` (`clip`, optional `language`, `from`, `to`) answers `words` (`text`, `start`, `end`, `filler`, and `speaker` when known), `fillers_reported`, `engine` and, for an on-device answer, `cached`. It edits nothing.

## Cutting false starts with the assistant

A false start is a phrase the speaker abandoned or said again. Deciding what counts is a judgement about meaning, so there is no menu command for it. Ask the assistant in the inspector's Assistant tab instead, for example "cut the false start at the beginning of this clip." The assistant:

1. reads the clip's words and their times;
2. tells you which words it will cut;
3. cuts them in one step, each cut running from the first cut word's start to the last cut word's end.

It cuts false starts only when you ask. It can also remove fillers the same way **Remove Filler Words** does, and take out silences the way **Remove Silences** does (`detect_silence`, then one `ripple_delete_ranges`). Any cut an agent makes this way, whether silences, fillers or false starts, is one undo step labelled **Undo Ripple Delete**, not the sheet's name. The assistant can't start a paid filler transcription: press **Transcribe** in the sheet yourself. See [The assistant](assistant.md).

## Limits

- **Filler removal is cloud-only.** Without an AssemblyAI key, filler words can't be found. A project transcribed before filler words were requested is transcribed again, and billed again, before its fillers can be cut.
- **The service can miss a filler.** A filler AssemblyAI doesn't return isn't cut. A filler it returns that isn't on the list stays in, both in the cut and in captions.
- **Protection needs a transcript.** A filler cut is kept away from speech in another clip only when that clip's file has a transcript. Speech on another unlocked track with no transcript isn't protected.
- **Up to a frame can remain.** Inward frame snapping can leave a frame of room tone, or of a filler, behind.
- **Wait for analysis.** After import, Remove Silences proposes nothing inside a file until its analysis is ready: the waveform in Level mode, the voice analysis in Voice mode (and the waveform too for a clip with no voice), except where the mix already makes it quiet.
- **Voice mode can miss a soft first word** in a quiet recording; raise **Keep at ends:** if a word is clipped.
- **Singing and voice-like instruments** may read as speech.
- **A clip that holds any voice is judged by voice for its whole length**, so a long music clip with a little speech in it isn't judged by level. Limit the scope (**In:** Selected clips) to keep music out.
- **A voice panned hard to one side** sounds quieter to the voice model.
- **In a reversed clip** a cut edge can be off by up to 32 ms.
- **Nests and transitions block cuts.** Quiet or fillers inside a nest, or in a transition's overlap, are never cut from outside the nest. Open the nest first.

See also: [Editing](editing.md) for ripple delete and Close Gap, [Audio](audio.md) for volume, fades, ducking, mute and solo, which all affect what Remove Silences hears, and [MCP](mcp.md) for the full tool reference.
