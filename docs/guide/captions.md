# Captions and transcription

Frame Job brings captions in from a SubRip file, writes them from the speech in your clips, and writes a caption track back out as `.srt` or `.vtt`. Speech is recognised either **on this Mac**, with nothing uploaded, or by **AssemblyAI** in the cloud, using your own API key. Captions come out as two-line subtitles or as large word-by-word captions in one of five styles, where each word lights up as it is said. Every caption is an ordinary text clip, so it plays in the preview, burns into an export, and can be dragged, trimmed and restyled like any other clip.

All three commands are in the **File** menu, next to each other:

| Command | What it does |
|---|---|
| **File ▸ Import Captions…** | Reads a SubRip (`.srt`) file onto a new caption track. |
| **File ▸ Generate Captions…** | Transcribes the speech in your clips onto a new caption track. |
| **File ▸ Export Captions…** | Writes one caption track out as SubRip (`.srt`) or WebVTT (`.vtt`). |

None of the three has a keyboard shortcut.

## Captions are text clips

However a caption gets onto the timeline, it ends up as a text clip on a track of its own at the front of the stack, so it draws over everything else. That has some useful effects:

- The preview, a rendered frame and an exported movie all show it. Burn-in needs no extra step.
- You can drag one to retime it, trim its edges, split it or delete it with the usual tools ([Editing](editing.md)).
- You can select a run of captions and restyle them together in the inspector's Clip tab, under **Text** ([Canvas and layers](canvas-and-layers.md)).
- Captions are not a soft-subtitle track that a player can switch on and off. To ship a separate subtitle file, use **Export Captions…**.

The first caption track is named **Captions**, then **Captions 2**, **Captions 3** and so on, so separate runs can be told apart in the track headers.

Every caption time snaps to the project's frame grid, so a caption can end up to a frame shorter than its source says. Captions on one track never overlap. When a cue starts before the previous one ends, the earlier cue is cut back to meet it, and the run reports how many were shortened. A cue that would be left shorter than one frame is skipped and reported.

The caption commands work on the timeline you have open. With a nest opened, **Import Captions…** and **Generate Captions…** put the new track at the front of that nest, and **Export Captions…** lists that nest's tracks. To caption the main timeline, close the nest first.

A project holds at most 4,096 clips. A caption run that would go over that limit is refused before anything changes, and the message says how many more clips would fit.

## Import a SubRip file

Choose **File ▸ Import Captions…** and pick a `.srt` file. The open panel reads "Choose a SubRip (.srt) caption file." and accepts `.srt` and any plain-text file, so a SubRip file saved as `.txt` imports too. A `.vtt` file is not read as WebVTT. Each cue becomes one text clip in the **Caption** preset, on a new track called **Captions** (or the next free number). The import is a single undo step, **Import Captions**.

The reader copes with the variations real caption files have:

- a UTF-8 byte-order mark; CRLF or bare-CR line endings
- a missing index line above the timing line
- a comma or a dot before the milliseconds, the `MM:SS` and `SS` shorthands, and any number of fraction digits
- position settings after the end time, which are ignored
- `<i>`, `<b>`, `<u>` and `<font>` tags and `{\an8}`-style overrides, which are removed, plus the common HTML entities (`&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;`, `&#39;`, `&nbsp;`)
- text in UTF-8, UTF-16, Windows-1252 or Latin-1

The file's own line breaks are kept. Long lines also wrap inside the caption box.

**Malformed entries are reported, not dropped silently.** If a block has no `-->` timing line, has a time that cannot be read, ends at or before its start, or has no text, it is skipped. When the import finishes, an alert lists what was skipped by line number (the first eight, then "…and N more"), along with how many captions were shortened to fit. A clean import shows no alert. A file in which no cue can be read is refused, and the message gives the first few reasons.

*Agents:* `import_captions` (`path`, plus an optional existing `track`; reports what landed and, under `skipped`, each malformed entry by line).

## Generate captions from speech

Choose **File ▸ Generate Captions…**. The item is greyed out when nothing in the project can be transcribed. Playback pauses and the **Generate Captions** sheet opens. It is one card: you set it up, press **Generate**, and the same card becomes the progress bar. The footnote reads "captions go on a new track".

### What can be transcribed

A clip can be transcribed only if it plays a movie or sound file that has an audio track, its audio is switched on, and its file is present. Clips that cannot be transcribed are skipped with a reason:

- its source is not a media file (text, shape, still, image, graphic or nest)
- it plays in reverse
- its media has no audio track
- its audio is switched off (for example, the picture half of a clip after Detach Audio, whose sound is on the audio-only clip below it)
- its media file is missing
- its speed ramps, and no speed map was read for it
- its speed or length is degenerate

Captions follow a clip's speed. On a sped-up, slowed or speed-ramped clip, each word lands where it is heard on the timeline ([Speed](speed.md)). They keep following it afterwards: change the speed or a ramp of a clip with sound and the captions over it move with its speech in the same undo step ([Speed](speed.md#captions-follow-a-speed-change)).

### The sheet

| Row | What it does | Default |
|---|---|---|
| **Language** | The spoken language. With **On this Mac**, every language this Mac's recogniser supports; a language whose model is not installed reads "— not installed". With **AssemblyAI**, **Detect automatically** and then 21 languages. | On this Mac: your Mac's own language. AssemblyAI: Detect automatically. |
| *(Download row)* | Appears when the chosen on-device language is not installed. See below. | — |
| **Engine** | **On this Mac** or **AssemblyAI**. | The engine you chose last time; On this Mac the first time. |
| **Speakers** | AssemblyAI only. "split by speaker, coloured in Subtitles". | Off |
| **Vocabulary** | AssemblyAI only. Names and jargon to expect, separated by commas. | Empty |
| **Transcribe again** | AssemblyAI only. "ignore any cached transcript" uploads again even when a usable transcript is cached. | Off |
| **From** | **Selected clips**, **In/out range** or **Whole timeline**. A choice that holds nothing transcribable is greyed. **In/out range** takes every clip that overlaps the range, whole. | Selected clips if the selection holds anything transcribable, else In/out range if one is marked, else Whole timeline. |
| **Style** | **Subtitles** or one of the five word caption styles. See [Caption styles](#caption-styles). | The style you chose last time; Subtitles the first time. |
| *(looks)* | **Slide the pill**, **Fill words as spoken**, **Dim in pauses**. See [Looks](#looks-for-word-captions). | Each one as you last left it; off the first time. |
| *(preview)* | A sample page drawn at this canvas's size. | — |
| **Replace** | "existing captions" swaps out earlier caption tracks over the same clips. See [Restyle a caption track](#restyle-a-caption-track). | Off |

The **Speakers**, **Vocabulary** and **Transcribe again** rows are hidden, not greyed, while Engine is **On this Mac**. They appear when you choose **AssemblyAI**.

Under the grid, a summary line gives the clip count and the length of audio (for example, `3 clips · 00:04:12.000 of audio`) or "Nothing to transcribe". Under the summary is a note explaining anything that is stopping the run. **Generate** is live only when the run can go ahead.

### On this Mac

The hint at the top of the sheet reads: "The words are recognised ON THIS MAC and land as ordinary text clips on a track of their own, so they show in the preview and burn into an export with no further step. Nothing is uploaded."

Each clip's own part of its media is extracted and recognised locally. There is no permission prompt and no length limit. Nothing is cached for captions on this Mac: every run, restyling included, recognises the audio again. That is free, but it takes the time again. The sheet's preview never uses on-device words.

**Installing a language.** Speech models are installed per Mac. If you choose a language marked "— not installed", a **Download** button appears below the Language popup, and **Generate** stays greyed until the model is in. While the download runs, the row shows "Downloading *language*… N%", the button becomes **Cancel**, and the Language and Engine popups are locked. The row shows a percentage, not a size, because the size isn't known before the download starts. When it finishes, the language is installed and selected. If the download fails, the note says why. This button is the only place a model is ever downloaded.

If this Mac's recogniser lists no language at all, the popup reads "No on-device language", and the note asks you to reopen the sheet to check again.

### With AssemblyAI

The hint reads: "The audio of these files is uploaded to AssemblyAI (*region*), transcribed with Universal-3.5 Pro, and deleted from AssemblyAI once the words have been read back. Nothing is uploaded until Generate is pressed." *Region* is **United States** or **European Union**, whichever is set in Settings.

**You need** an AssemblyAI API key, saved in **Frame Job ▸ Settings…** (⌘,) under **Transcription** ([below](#your-assemblyai-key)). Without one, the note reads "No AssemblyAI API key is set — Frame Job ▸ Settings…" and **Generate** is greyed (unless every file is already cached; see below). If no key is saved, Frame Job also accepts one from the `RC_ASSEMBLYAI_KEY` environment variable. An untitled project can be transcribed too: its transcripts are kept in a temporary folder until the project is saved, and then go into the project package.

**What is uploaded.** The audio of every media file behind the chosen clips is uploaded, and it is the whole file, not just the parts the clips use. AssemblyAI bills for the whole file, so a long recording that you use only briefly still costs its full length. A single file longer than 10 hours is refused before anything is sent: "“*name*” is longer than AssemblyAI's 10-hour limit for one file."

**The price, before you press Generate.** The summary line prices the run at AssemblyAI's published rate, for example:

`2 files to upload · 01:12:30.000 of audio · about $0.25 at AssemblyAI's published rate · 1 file already transcribed`

The rate is $0.21 an hour of audio, plus $0.02 an hour with **Speakers** on, as published on 2026-09-17. A very short run is priced "under $0.01". When every file is already cached, the line starts "Nothing to upload", for example `Nothing to upload · 2 files already transcribed`.

Hover over the summary to see the reason for each file, such as "has not been transcribed yet", "has changed since it was transcribed", "was transcribed with a different language", "was transcribed for a different request" or "is already transcribed, and Transcribe again was asked for", followed by the rate sentence. Two other counts can appear: a file "waiting on an earlier delete", which this run will not upload, and a file that "could not be read". A waiting file's hover line gives the price it would add: "It is waiting on an earlier delete and will not be uploaded in this run — about $X more if it does."

**The transcript cache.** Each media file's transcript is kept in the project package and reused by the next run. A file whose cached transcript matches the request (same file, model, language, Speakers and Vocabulary) is not uploaded again and costs nothing. The caption style does not count, so restyling never uploads. A transcript made for Remove Filler Words also serves Generate Captions, so that file is not uploaded or billed again. The cache is kept per media entry, so two media entries over the same file are uploaded and billed separately. When no API key is set and every file in the run already has a current transcript, the hint changes to "Current cached transcripts will be used without an API key or network request." and **Generate** works without a key. With a key set, the usual hint stays, and the summary says there is nothing to upload. To force a fresh upload anyway, tick **Transcribe again**.

**Filler words.** AssemblyAI's words include fillers such as um, uh, hmm, mhm, uh-huh, ah, er and erm. Captions, and the sheet's preview, leave them out, so a caption reads the same whether or not its transcript has them.

**Deletion at AssemblyAI.** Once the words have been read back, Frame Job asks AssemblyAI to delete its copy. If AssemblyAI does not confirm the delete, the result says so:

- Normally the delete is retried at the next run that has a key for the same account and region the transcript was made in.
- If no key is set when that next run starts, the result says cleanup was deferred because no API key is set.
- If the transcript could not be kept in the project, Frame Job has no record to retry from, and the result reads "…Frame Job cannot retry deleting it automatically. Delete it in your AssemblyAI dashboard."

While a delete is pending, that file is not uploaded again. Its current cached transcript is still used, but **Transcribe again** is refused for it until the delete goes through.

**Speakers.** With **Speakers** ticked, a change of speaker always starts a new cue or page. In the **Subtitles** style, each speaker's cues take their own colour, in the order the speakers first appear: white, yellow, cyan, green, then round again. Speakers are counted separately for each media file.

**Vocabulary.** Type the words and phrases to expect, such as product names, people and identifiers, separated by commas. Blank entries and repeats are dropped (the first spelling is kept), and the list is capped at 1,000 terms. If the cap cuts your list, the note says "Vocabulary was capped at 1000 terms (AssemblyAI's limit); N were given."

**Languages.** Detect automatically, English, English (Australia), English (United Kingdom), English (United States), Spanish, French, German, Italian, Portuguese, Arabic, Danish, Dutch, Finnish, Hebrew, Hindi, Japanese, Chinese, Norwegian, Swedish, Turkish and Vietnamese.

### Progress and the result

While a run is going, the card shows a progress bar, "Transcribing N clips…" ("…with AssemblyAI…" for the cloud), and a detail line. On this Mac, the detail is the clip being recognised. With AssemblyAI, it is the current stage: "Extracting *file*", "Uploading *file* · 12 MB of 40", "Submitting *file*", "Waiting for AssemblyAI · 35 s", "Saving *file*". **Cancel** stops the run, and closing the sheet mid-run also stops it. After Cancel, the detail line reads "Stopping…" until the run ends, and nothing is placed.

If one file cannot be transcribed, its clips are listed with the reason, and captions from the other files are still placed. With AssemblyAI, a key that AssemblyAI refuses ends the run straight away, so no more files are uploaded.

Placing the captions is one undo step, **Generate Captions**. A clean run closes the sheet by itself. If there is something to report, the card stays open with **Close**, saying how many captions were added on which track, how many were shortened, which clips were skipped and why, and any of these from a cloud run:

- a file transcribed with a fallback model instead of Universal-3.5 Pro
- with **Detect automatically**: the language detected for each file and how confident AssemblyAI was, for example "“interview.mov”: detected Spanish (97% confidence)"
- a delete AssemblyAI has not confirmed, or a transcript that could not be kept in the project

A failure shows the error on the same card.

*Agents:* `transcribe`. It takes `clips` (the scope), `engine` (`apple`, the default, or `assemblyai`), `language` (`auto` by default with AssemblyAI), `style`, `replace`, `slide`, `fill`, `dim`, and, for AssemblyAI only, `speakers`, `vocabulary` and `refresh`, each refused by name without `engine: "assemblyai"`. It answers the cues in timeline ticks (with each word's timing for a word style) whether or not it places them, and `place: false` changes nothing at all. `replace` is refused with `subtitles` or with `place: false`; when it is given, a placed run lists the removed tracks' ids under `replaced`. The tool never remembers the sheet's engine, style or looks, and never downloads a language model. A language whose model is not installed is refused by name.

## Subtitles

The **Subtitles** style makes classic two-line cues, built by these rules:

- at most two lines of at most 42 characters each
- at most 6 seconds per cue
- at least one frame between cues
- never two speakers in one cue

A word too long for a line is left whole rather than hyphenated, and wraps inside the caption box.

Each cue uses the **Caption** text preset: Source Sans 3 Regular at 3.5% of the canvas height, centred, on a 60% black backdrop, wrapping at 80% of the canvas width, with its box centred 38% of the frame height below the middle.

## Caption styles

The five word caption styles make the large, one-row captions used in shorts and reels. Instead of a cue, each clip holds a **page** of words with each word's timing, and the word being spoken is drawn the way the style says. All five are white with the spoken word marked. They are sized to the shorter side of the canvas, so a vertical and a horizontal canvas get the same text height.

| Style | Typeface | Case | How the spoken word shows | Position |
|---|---|---|---|---|
| **Subtitles** | Source Sans 3 Regular | As written | — (two-line cues, above) | 38% of the frame height below centre |
| **Highlight** | Montserrat Black, black outline | UPPERCASE | Turns yellow and pops to 112% | A quarter of the frame height below centre |
| **Pill** | Montserrat ExtraBold | UPPERCASE | Sits on a violet pill | A quarter of the frame height below centre |
| **Karaoke** | Montserrat ExtraBold | As written | Words turn yellow as they are said and stay yellow; words still to come are dimmed white. Up to two lines | 28% of the frame height below centre |
| **Build** | Anton, black outline | UPPERCASE | Words appear one by one; the newest is yellow and pops to 115% | A quarter of the frame height below centre |
| **One Word** | Bebas Neue, black outline | UPPERCASE | One large word at a time, popping to 120% | 18% of the frame height below centre |

The text is 7.5% of the shorter canvas side, and 12% for One Word. The four display faces ship inside the app under the SIL Open Font License.

### How pages are filled

A page is filled to the width it actually measures in its style on your canvas, not to a word count:

- A page fills up to 86% of the canvas width, on one line (Karaoke: up to two).
- It ends early at a pause of 0.25 s or more, after a word ending in `.` `?` `!` or `…`, after 3 seconds on screen, or at a change of speaker. One Word pages hold one word each.
- A comma, semicolon or colon just before the width runs out moves the break back to it, if the page is already at least half full.
- A single word too wide for the frame shrinks, down to 80% of the style's size, before it wraps.
- A page stays up 0.5 s after its last word, or runs up to the next page when the gap is under 0.25 s, so the row does not blink between pages.
- Pages never run past the end of the clip they came from.

### The preview

The preview under the Style row shows a sample page drawn by the same renderer the canvas uses, at this canvas's proportions. It uses the first words of the first clip's cached transcript when there is one, and "This is how it looks" otherwise. A word style shows two frames, with the first word active and then the second. A ticked **Fill words as spoken** shows the fill half done, and a ticked **Slide the pill** shows the pill half-way through its slide. **Dim in pauses** is not previewed.

## Looks for word captions

Three checkboxes under the Style popup each add a look to a word style's pages. Each is off until you tick it, and the sheet remembers each one between runs. A box that does not apply to the chosen style is greyed out and does nothing, but keeps its tick for when you switch back.

| Look | What it does | Works with |
|---|---|---|
| **Slide the pill** | The pill slides from the previous word to the one being said, over 0.2 s (or less when the next word comes sooner), instead of jumping. | Pill |
| **Fill words as spoken** | The word being said fills from left to right as it is spoken, taking at most 0.6 s. The part already said is in the highlight colour; the rest is in the upcoming colour (Karaoke's dimmed white), or not yet drawn in Build. | Highlight, Karaoke, Build |
| **Dim in pauses** | The page fades to half opacity during a pause of 0.25 s or more, then comes back before the next word. It also dims before the first word when that word starts late, and after the last word until the caption ends. Each fade takes 0.1 s. | All five word styles |

With **On this Mac** chosen and a word style selected, a note under the boxes reads "On-device words rarely carry a pause; this shows mostly with AssemblyAI." The on-device recogniser stretches each word's time across the silence after it, so few pauses are long enough to dim.

*Agents:* `transcribe`'s `slide`, `fill` and `dim`. Each is false unless given, never what the sheet last chose. `true` is refused by name with a style it would not show on, or with `place: false`; `false` is always accepted. A placed run given any of the three lists the looks that were on under `looks`.

## Restyle a caption track

A style is fixed when the captions are generated. To change it, generate again with **Replace** ticked:

1. Open **File ▸ Generate Captions…** over the same clips.
2. Choose the new word style and looks.
3. Tick **Replace: existing captions**. The line under it names each track it will remove, with its caption count, for example "Replaces “Captions” (12 captions)."
4. Press **Generate**.

The old tracks are removed and the new one takes their place at the front, all in one undo step. With AssemblyAI the cached transcript is reused, so nothing is uploaded and nothing is billed.

**Replace** is live only for a word style, and only when there is a track it may replace. That means a track named **Captions** or **Captions N** that holds only text clips, each of which overlaps a clip being transcribed. Tracks outside the run's scope are left alone.

## Editing captions

Captions are text clips, so the inspector's Clip tab edits them under **Text**: Content, Font, Style, Outline, Backdrop, Box, Reveal and Presets. Select several captions to change them together.

On a word caption page:

- **Case.** The style's capitals come from **Text ▸ Style ▸ UPPERCASE**. Untick it to show a page as written. Case is applied when the page is drawn, so the Content box shows the words as written, and changing case never drops the word timing.
- **Word style colours.** There is no inspector section for a page's word style (highlight colour, pop scale, pill colour). To change them, generate again with a different style, or have an agent use `set_text`'s `word_style`.
- **Editing the words.** Changing the text while keeping the same number of words keeps every word's timing. Changing the number of words drops the timing, and the page then shows plainly. The Content section notes "Not timed — regenerate to time it again". The same rule holds whether you edit in the Content box or in place on the canvas (double-click the page).
- **Reveal.** The text reveals (typewriter, word fade, line rise) do not apply to a timed page. The Reveal section says "Word style wins; the reveal does not apply."
- **Trimming and splitting.** These keep each word on the speech it times. Retiming a page by dragging it moves its words with it.

*Agents:* `set_text` edits a caption like any text clip, including a page's `words` and `word_style`. When `words` is not empty, it must have exactly one timing for each word of the content. Otherwise the edit is refused: "this text is timed word by word: N timings for M words".

## Export captions

Choose **File ▸ Export Captions…**. The item is greyed out unless some track holds only text clips with caption text on them. The save panel suggests *project name*`.srt` and adds two popups:

| Control | What it does | Default |
|---|---|---|
| **Track** | Which track to write, listed as "*name* — N cues (track *id*)", front-most first. Greyed when there is only one candidate. | The front-most candidate |
| **Format** | **SubRip (.srt)** or **WebVTT (.vtt)**. Changing it changes the file name's extension. | SubRip (.srt) |

Each text clip on the track becomes one cue, at the time and with the words it has now, so a caption you dragged exports where you dragged it. Empty captions are left out. Line endings become LF, and blank lines inside a caption are removed. The two formats differ only in WebVTT's `WEBVTT` header, its missing index lines, the `.` where SubRip writes `,` in timestamps, and WebVTT escaping `&`, `<` and `>`. Exporting changes nothing in the project.

Nothing marks a track as a caption track, so any track made only of text clips can be exported, a titles track included. A word caption track is written one cue per page, with the page's words as written: the style's UPPERCASE, its word timings and its styling are not part of a `.srt` or `.vtt`.

**Round trips are exact to the frame.** A track exported and imported again puts every cue back on the frame it came from, at every ordinary frame rate. The file itself may not match byte for byte, because import snaps times to the frame grid: at 30 fps, `00:00:04,120` comes back as `00:00:04,133`.

*Agents:* `export_captions` (`path`, plus optional `track` and `format`). The track is never guessed: with no candidate, or more than one and no `track` given, the call is refused and the candidates are listed. A `.srt` or `.vtt` extension in `path` is replaced by the format's own, and any other extension is kept (`chart.png` becomes `chart.png.srt`).

## Your AssemblyAI key

The key lives in **Frame Job ▸ Settings…** (⌘,), in the **Transcription** section:

| Control | What it does |
|---|---|
| **AssemblyAI API key:** | A secure field. "Paste your key" when none is saved. A saved key shows as a fixed row of dots and is never displayed again. Press Return or **Save** to save. |
| **Region:** | **United States** or **European Union**: the AssemblyAI data centre your audio goes to. Default: United States. The two regions do not share transcripts, so a pending delete is retried only in the region it was made in. |
| **Save** | Saves the key typed in the field ("Key saved."). |
| **Remove** | Deletes the saved key ("Key removed."). Live only when a key is saved. |
| **Verify** | Makes the cheapest signed-in call to AssemblyAI with the key in the field, or the saved key, and answers "Key accepted" or AssemblyAI's reason. It reads "Checking…" while it runs, "No API key is set." with no key, and "Settings changed since this check began. Verify again." if the key or region changes mid-check. It does not transcribe or bill anything. |
| **Account Page** | Opens your AssemblyAI dashboard in the browser, where you get a key and see your spending. |

The key is saved in a file only you can read (`~/Library/Application Support/Frame Job/assemblyai-key`, mode `0600`), not in the Keychain, and it is never passed on the command line. Saving, removing or changing the region updates an open Generate Captions sheet straight away. The ⓘ beside the heading explains what is uploaded, what is deleted, and the published rate.

No MCP tool can read or change the key or the region. Only a person sets them, here.

## Limits

- **Import reads SubRip only.** WebVTT can be exported but not imported.
- Captions are burned-in text clips, not a switchable subtitle stream in the exported movie.
- A clip played in reverse, a clip with its audio switched off, and a clip whose media is missing or silent cannot be transcribed.
- **On this Mac** needs the language's speech model installed from the sheet's Download row. Speakers, Vocabulary and Transcribe again are AssemblyAI only.
- **AssemblyAI** needs a key (unless every file is already cached), uploads and bills each whole media file, and refuses a file over 10 hours. Vocabulary is capped at 1,000 terms.
- Two media entries over the same file are uploaded and billed separately.
- Word styles mark words by their timing only. There is no keyword emphasis and no emoji.
- A page's word style colours and scale cannot be edited in the inspector. Generate again, or have an agent use `set_text`'s `word_style`.
- Speaker colours apply only to the Subtitles style.
- Changing the number of words on a word caption page drops its word timing. To time it again, generate again.
- A style cannot be switched on a placed track. Restyle by generating again with Replace.

## For agents

| Tool | Mirrors |
|---|---|
| `import_captions` | File ▸ Import Captions… |
| `transcribe` | File ▸ Generate Captions… |
| `export_captions` | File ▸ Export Captions… |
| `get_transcript` | Reads one clip's words with their timeline times, from the cached transcript or this Mac's recogniser. It never uses the network and edits nothing. Used for cutting by transcript ([Remove Silences and Remove Filler Words](cleanup-tools.md)). |

In the built-in [Assistant](assistant.md), `transcribe` with `engine: "assemblyai"` is withheld, because audio leaves the Mac only when a person chooses that in the sheet. `export_captions` asks before it writes a file. The full reference is [MCP](mcp.md).

Filler-word removal, which needs an AssemblyAI transcript made with filler words, is covered in [Remove Silences and Remove Filler Words](cleanup-tools.md). The Settings window as a whole is covered in [Settings](settings.md).
