# Settings

Frame Job keeps the things that belong to you, not to a project, in one
window: how an MCP client reaches the app, your Anthropic key and the
assistant's model, your AssemblyAI key and region for cloud transcription,
and whether graphics render in the background while you are idle. This page
covers every control in that window, the View-menu choices Frame Job
remembers between launches, and where the app keeps its files on disk.

## Opening Settings

Choose **Frame Job ▸ Settings…** (⌘,). It works with or without a project
open, so you can set keys from the Welcome window before you make anything.
The Assistant tab also opens it for you: when no Anthropic key is set, it
shows "Add your Anthropic API key in Settings to use the assistant." and an
**Open Settings…** button. The Generate Captions sheet only tells you where
to go: with AssemblyAI chosen and no key set, the note under its button reads
"No AssemblyAI API key is set — Frame Job ▸ Settings…".

Settings is one window, not a set of tabs. It holds four sections, top to
bottom: **MCP**, **Assistant**, **Transcription** and **Playback**. On a
short screen the window stops at the screen's height and scrolls. Closing it
loses nothing: every control saves as you use it, or when you press its
**Save** button, as described below. While it is open it is listed in the
**Window** menu, so you can bring it back from behind other windows.

The Assistant, Transcription and Playback headings each carry an ⓘ button.
Rest the pointer on it for a moment to see that section's explanation; click
it to keep the explanation open, and click it again (or anywhere else, or
press Escape) to close it.

*Agents:* no MCP tool reads or writes anything in Settings. Keys, the model,
the region and Background render are set only by a person in this window.
An agent's cloud tools (`transcribe` with the AssemblyAI engine,
`transcribe_for_fillers`) do use the key and region saved here, so a person
must set the key first; without one they refuse with "No AssemblyAI API key
is set. Set one in Frame Job ▸ Settings ▸ Transcription…".

## MCP

This section tells an MCP client, such as Claude Code, how to reach
Frame Job. Its text is shown in full rather than behind an ⓘ:

> An MCP client such as Claude Code uses Frame Job's tools through
> framejob-mcp, a helper inside this app. It reaches Frame Job over a local
> socket that only programs you run can open.
>
> If Frame Job isn't running, the first tool call opens it in the
> background. To add Frame Job to Claude Code, copy the command and run it in
> Terminal.

Under the text is the full path of the `framejob-mcp` helper inside the copy
of Frame Job you are running. You can select and copy it.

**Copy MCP Command** puts the line that registers the helper with Claude Code
on the clipboard, with that path filled in and quoted for the shell:

```sh
claude mcp add --scope user framejob -- '/Applications/Frame Job.app/Contents/Helpers/framejob-mcp'
```

After a copy the section says "Copied. Paste it into Terminal and press
Return." The path is always the one for the app you opened Settings from, so
if you move Frame Job, copy the command again.

If the helper is missing from this copy of the app, the button is disabled
and the section says "framejob-mcp is missing from this copy of Frame Job."

Other clients, the socket and the tool list are covered in [MCP](mcp.md).

## Assistant

This section holds what the Assistant tab needs: your Anthropic API key, the
model, and two settings for long conversations. The assistant itself is
described in [Assistant](assistant.md).

| Control | What it does | Default |
|---|---|---|
| **Anthropic API key:** | A secure field. Paste a key and press **Save** or Return. | None |
| **Save** | Stores the key typed in the field, then empties the field. With the field empty it only beeps. | — |
| **Remove** | Deletes the stored key. Disabled when no key is stored. | — |
| **Model:** | The Anthropic model the assistant uses. Saved when you press Return or leave the field. Leave it blank for the default. | `claude-opus-5-5` |
| **Compact when context reaches … tokens** | When a turn ends with the conversation past this size, the conversation is replaced by a summary. Untick it to never compact. The number can be 20,000 to 900,000. | On, 300,000 |
| **Clear old tool results past 150,000 tokens** | Lets Anthropic drop old tool results from what the model sees, even partway through a turn (never tool search results). | Off |

### The key

Your key is never shown again once saved. When a key is stored, the field
shows a fixed row of dots as its placeholder. The row is always the same
length, so it says nothing about your key, and the key itself is never put in
the field. When no key is stored, the field reads "Paste your key". The line
under the controls says "Key saved." or "Key removed." after a press. It says
"No API key is set." (in ordinary grey, not as an error) whenever there is no
key in the field, the store or the environment.

If the key file cannot be written (for example, because its folder is not
writable), the field is still emptied and the line reads "The API key could
not be saved: <reason>", styled as a problem. A Remove that fails shows the
same sentence with its own reason, and the stored key stays.

There is no Verify button here. The app does not call Anthropic itself; the
key is first used when you send a message from the Assistant tab.

### What a change does

- **Saving or removing the key, or changing the model**, ends the
  conversation in every open window's Assistant tab. A conversation keeps the
  key and model it started with, so the next message starts a new one.
  Pressing Return in the Model field without changing what it resolves to
  ends nothing.
- **Changing the compaction or clearing settings** takes effect in every open
  conversation at once and keeps each one going. There is no Save button for
  these. A threshold outside 20,000–900,000 beeps and the field goes back to
  the stored number.

Compaction happens at the end of a turn, and renders from earlier in the
conversation do not survive it. Each clearing costs a fresh prompt-cache
write.

### What the ⓘ says

The Assistant ⓘ sums up what the assistant sends and where:

- it sends your messages, the project's details and the frames it renders to
  Anthropic, using your own API key, and what it costs is billed to that key;
- it asks before writing a file;
- the key is kept in a file only you can read and is never shown again once
  saved;
- a blank Model means `claude-opus-5-5`, and changing the key or the model
  starts a new conversation;
- the compaction and clearing settings, as in the table above.

### This month's spend

Under the buttons is what the assistant has cost in the current calendar
month, in UTC, for example "October 2026 (UTC): $1.24 over 37 responses." It
is read from the spend ledger (see [Where Frame Job keeps its
files](#where-frame-job-keeps-its-files)) each time Settings opens, and
again after every response while the window is open. Other forms it can take:

- "Nothing recorded in October 2026 (UTC)." for a month with no responses;
- "…; none could be priced." or "…; 3 could not be priced, the rest came to
  $0.80." when some responses had no price (they are counted, never added as
  $0);
- a positive amount that would round to $0.00 (less than half a cent)
  reads "under $0.01";
- " 2 ledger lines could not be read." is added to the sentence when some
  lines of the ledger are damaged;
- "Reading the spend ledger…" while it is being read, and "The spend ledger
  could not be read: …" if it cannot be;
- "This launch keeps no spend ledger." when Frame Job has no folder to keep
  one in.

The note beneath says what the figure is: "Frame Job's own estimate at
LiteLLM prices, from its spend ledger. The Anthropic Console shows what your
account was billed." The Assistant tab's own Spend row, for the current
conversation, is described in [Assistant](assistant.md).

## Transcription

This section holds your AssemblyAI key and region. They are used when you
choose AssemblyAI in **File ▸ Generate Captions…** (see
[Captions](captions.md)) and by **Clip ▸ Remove Filler Words…**, which
finds fillers only through AssemblyAI (see [Remove Silences and Remove Filler Words](cleanup-tools.md)).
On-device captions need no key.

| Control | What it does | Default |
|---|---|---|
| **AssemblyAI API key:** | A secure field. Paste a key and press **Save** or Return. | None |
| **Region:** | Which AssemblyAI data region to use: **United States** or **European Union**. Saved as soon as you pick it. | United States |
| **Save** | Stores the key typed in the field, then empties the field. With the field empty it only beeps. | — |
| **Remove** | Deletes the stored key. Disabled when no key is stored. | — |
| **Verify** | Makes AssemblyAI's cheapest signed-in request with the key and region, to check the key works. | — |
| **Account Page** | Opens AssemblyAI's dashboard (assemblyai.com/dashboard) in your browser, where you get a key and see what you have spent. | — |

The key field behaves exactly like the Assistant's: a fixed row of dots when
a key is stored, "Paste your key" when one is not, and "Key saved.",
"Key removed." or "No API key is set." on the line beneath, and "The API key
could not be saved: <reason>" if the key file cannot be written or removed.

A transcript made in one region cannot be seen from the other, so the region
is a choice you make, not a fallback. Pick the region your AssemblyAI account
uses.

### Verify

**Verify** checks whichever key a real run would use: the one typed in the
field if you have typed one and not saved it yet, otherwise the stored key,
otherwise the key in the environment (see below). It is disabled when there
is no key at all, and while a check of the same key and region is running.

| Line under the controls | Meaning |
|---|---|
| Checking… | The request is in flight. |
| Key accepted | AssemblyAI accepted the key in this region. |
| Settings changed since this check began. Verify again. | You changed the key or the region during the check, so its answer no longer applies. |
| An AssemblyAI message, such as "AssemblyAI refused the API key — check it in Frame Job ▸ Settings" | The check failed; the text says why. |

Saving, removing or changing the region also tells an open Generate Captions
sheet straight away, so it can enable its button without being reopened.

### What the ⓘ says

The Transcription ⓘ explains what leaves your Mac: with AssemblyAI chosen,
the audio of the files you are captioning is uploaded, transcribed, read back
and then deleted from AssemblyAI. Frame Job asks for the delete as soon as it
has the words, and retries it at the start of the next run if it did not go
through. Nothing is uploaded until you press Generate, and captions made on
your Mac never leave it. It also gives AssemblyAI's published rate as Frame
Job last read it: $0.21 an hour of audio, $0.02 more with Speakers on (read on
2026-09-17).

A retried delete is sent with the key and region set at that later run, so
it can only succeed with a key for the account and region that made the
upload; keep that in mind before changing either. With no key set, the
cleanup is deferred and the run reports it. If a transcript could not be
saved in the project, Frame Job cannot retry its delete at all, and says so:
delete it yourself in AssemblyAI's dashboard (the **Account Page** button).

## Playback

This section has one row: whether Frame Job draws graphics ahead of time
while you are idle, and how long it waits first.

| Control | What it does | Default |
|---|---|---|
| **Background render** | While you leave Frame Job alone, it draws the graphics after the playhead in the window you used last, so they play smoothly from the start. | On |
| **Start after … seconds** | How long you must be idle before it starts. Type a whole number from 1 to 60, or use the stepper. Disabled while Background render is off. | 5 |

Both save the moment you change them. A number outside 1–60 beeps and the
field goes back to the stored value.

Anything you do in Frame Job (a key, a click, a scroll, an edit, play or a
seek) stops the pass at once, and the wait starts again from zero. An agent's
calls over MCP count too when they edit a project or move a playhead; a call
that only reads, such as `get_project`, does not. Moving the
pointer alone does not count, and neither does what you do in other apps. It
never runs while a window is playing. While it runs it keeps the processor
busy. The frames it draws are held in memory, at most a quarter of your Mac's
memory and less when memory is short, until the window closes or newer frames
replace them. See [Graphics](graphics.md).

## Updates

The copy of Frame Job you download from the project's GitHub Releases page
updates itself, with [Sparkle](https://sparkle-project.org). A copy you build
from source (`make app`, `make app-debug`) has no updater: no menu item, and
it never checks.

- **Frame Job ▸ Check for Updates…**, directly under About Frame Job, checks
  now. When a newer Frame Job has been published, a window shows its version
  and a link to its release page, and offers to install it; **Install
  Update** replaces the app and relaunches it. When there is nothing newer,
  it says you are up to date. The item is greyed out while a check is
  already running.
- **Automatic checks.** The second time you open Frame Job, it asks whether
  to check for updates automatically. If you agree, it checks about once a
  day while it is open, and tells you when an update is ready; it never
  installs one without asking you.

Every update is signed, and Frame Job refuses one whose signature does not
match the key built into the app, so only a release published from the
project itself can be installed. Updates are always the whole app; release
notes are on the release's page on GitHub.

There is no Settings control for automatic checks. Your answer is kept in
macOS's preferences for Frame Job (below); to turn checks off later, run
`defaults write com.kgalligan.FrameJob SUEnableAutomaticChecks -bool NO` in
Terminal while Frame Job is closed, and **Check for Updates…** still works.

*Agents:* no MCP tool checks for or installs updates.

## View settings Frame Job remembers

These are View-menu choices, not Settings controls, but Frame Job remembers
them between launches: the last choice you made, in any window, is what the
next window opens with.

| Setting | Where | Choices | Default |
|---|---|---|---|
| Snapping | **View ▸ Snapping**, the bare key N, or the timeline bar's **Snap** toggle | On / off (a checkmark) | On |
| Safe area guides | **View ▸ Safe Areas**, or the **Safe** checkbox in the preview toolbar | On / off | Off |
| Inspector | **View ▸ Hide Inspector** (⌥⌘I); reads **Show Inspector** while hidden | Shown / hidden | Shown |
| Timeline track height | **View ▸ Timeline Track Height ▸**, or the timeline bar's S / M / L buttons (Small tracks, Medium tracks, Large tracks) | Small · Medium · Large | Medium |
| Preview quality | **View ▸ Preview Quality ▸** | Full · Half · Quarter | Full |
| Pane sizes | Drag the dividers | Inspector width 280–440 pt; timeline height from 140 pt to 60% of the window | Inspector 304 pt, timeline 300 pt |

Only dragging a divider saves a pane size. Resizing the window, or hiding and
showing the inspector, changes nothing remembered, and the inspector's width
is not saved while it is hidden.

Preview Quality changes only how sharply the preview is drawn while you
work. Export and saved frames always render at full size. Holding ⌘ while
you drag turns snapping off for that drag only, and changes nothing that is
remembered. See [Timeline](timeline.md) and [Canvas and
layers](canvas-and-layers.md).

Other View items, such as **Preview Window**, **Show Ungraded**, **Show
Selection**, **Show SDR Version** and **Scopes**, are not remembered; they
start off in each new window. The preview window's position and size are
remembered, though: there is one saved frame for every project, so a preview
opens where the last one was left, on a second display for example. With two
projects' previews open at once, the second opens on top of the first, and
only one of them saves where it is moved. A full list is in [Menus and
shortcuts](menus-and-shortcuts.md).

## Other choices Frame Job remembers

Some sheets and panels reopen on what you chose last time. These are your
choices, not the project's, and no agent tool reads them.

| What | Remembered | Page |
|---|---|---|
| **File ▸ Generate Captions…** | The engine (On this Mac or AssemblyAI), the Style, and the Slide the pill, Fill words as spoken and Dim in pauses boxes | [Captions](captions.md) |
| **File ▸ Export…** | The last settings you exported with; named presets are kept in a file (below) | [Export](export.md) |
| Document tab | **Resize clips proportionally**, used with the next canvas-size change | [Projects and media](projects-and-media.md#canvas) |
| Recorder panel | Display, microphone, System Audio, show clicks, frame rate, size and **Include Frame Job windows** | [Screen recording](screen-recording.md) |
| Inspector sections | Whether each section is collapsed or expanded, per section, in every window. A section you have never clicked opens in its default state (Transform, a text or shape's main section and a graphic's Properties open, the rest closed). | [Canvas and layers](canvas-and-layers.md) |
| Screen Recording permission | That Frame Job has already asked macOS once. macOS will not show its prompt twice, so later presses of Record without the permission open System Settings' Screen Recording pane instead. | [Screen recording](screen-recording.md) |
| Importing a file macOS cannot open | Ticking **Do this automatically from now on** in the Convert / Repackage alert remembers your answer: ticked with **Convert** or **Repackage**, such files are converted from then on without asking; ticked with **Cancel**, they are never converted and the import simply fails | [Projects and media](projects-and-media.md) |
| Automatic update checks (the downloaded copy only) | Your answer to the question asked on the second launch, whether to check for updates automatically, and when it last checked | [Updates](#updates) |

All of these, and the View settings above, live in macOS's preferences for
Frame Job (the `com.kgalligan.FrameJob` domain). Keys are never stored
there.

## Where Frame Job keeps its files

Frame Job's own folder is `~/Library/Application Support/Frame Job/`. It is
created only when something first needs it, at a mode only you can open; if
you have already set the folder's permissions yourself, Frame Job leaves them
alone.

| Path | What it is |
|---|---|
| `…/Frame Job/assemblyai-key` | Your AssemblyAI key. |
| `…/Frame Job/anthropic-key` | Your Anthropic key. |
| `…/Frame Job/spend.jsonl` | The spend ledger: one line per assistant response, with its time, model, token counts and estimated dollars. It never holds your key or the conversation. |
| `…/Frame Job/anthropic-prices.json` | The assistant's cached copy of the price table it uses for that estimate. |
| `…/Frame Job/ExportPresets.json` | Your named export presets. |
| `…/Frame Job/Rewrapped/` | Movies Frame Job converted or repackaged from files macOS could not open. A project refers to these files; moving them leaves the media missing until you relink. |
| `…/Frame Job/Agent/agent.sock` | The local socket MCP clients connect to, created at every launch. |
| `~/Movies/Frame Job Recordings/` | Screen recordings and voice-overs, named by date and time (for example `Screen Recording 2026-09-10 at 14.03.22`; a voice-over is `Voice-over 2026-10-02 at 09.15.04.m4a`). |

Projects themselves are `.framejob` packages wherever you save them, and hold
their own caches (see [Projects and media](projects-and-media.md)).

### How keys are stored

Each key is a plain file, readable and writable only by your user account
(mode `0600`). It is written to a temporary name and renamed into place, so
it never exists with looser permissions and is never half-written. Keys are
never put in macOS preferences, never logged, never passed as a launch
argument and never shown in the window again. Frame Job does not use the
Keychain. Anything running as your user account can read these files, so
treat your Mac account as the protection.

### Keys from the environment

If no key is stored, Frame Job falls back to an environment variable, which
is useful when you launch it from a terminal:

| Key | Variable |
|---|---|
| Anthropic (Assistant) | `ANTHROPIC_API_KEY` |
| AssemblyAI (Transcription) | `RC_ASSEMBLYAI_KEY` |

A stored key always wins over the variable. An empty variable counts as no
key. **Verify** checks the variable's key when nothing is typed or stored.

## Limits

- Settings has no MCP mirror. An agent cannot set or read a key, the model,
  the region or Background render.
- There is no button to forget the remembered convert-on-import answer. To
  be asked again, run `defaults delete com.kgalligan.FrameJob RCFFmpegImport`
  in Terminal while Frame Job is closed.
- Converting on import needs `ffmpeg` and `ffprobe`. Frame Job looks for them
  on `PATH` and in `/opt/homebrew/bin`, `/usr/local/bin`, `/opt/local/bin`,
  `/usr/bin` and `/bin`. For an install elsewhere, run
  `defaults write com.kgalligan.FrameJob RCFFmpegPath /path/to/ffmpeg`;
  `ffprobe` is taken from beside it, or else found by the same search.
- An unknown or missing region reads as United States.
- The MCP command copied is for Claude Code. Other MCP clients use the same
  helper path in their own configuration; see [MCP](mcp.md).
