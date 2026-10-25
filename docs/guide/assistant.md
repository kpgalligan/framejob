# The Assistant

The Assistant is a conversation with Claude, built into the inspector of every editor window. You ask in plain words ("trim the pauses out of the interview", "put a title over the first five seconds", "what is under the playhead?"), and it reads and edits the window's project with the same tools an agent uses over MCP. You watch each change land, and each one is its own undo step. It runs on your own Anthropic API key, so Anthropic bills its usage to your account. Frame Job shows its own estimate of what each turn and each month costs.

## Setting it up

Open **Frame Job ▸ Settings…** (⌘,). The **Assistant** section is second, under MCP and above Transcription. The ⓘ beside its heading explains what is sent, what it costs and what the chat settings do.

| Control | What it does | Default |
|---|---|---|
| **Anthropic API key:** | A secure field, with the placeholder "Paste your key". Paste the key and click **Save** (or press Return in the field). The field empties, and from then on a saved key shows only as a fixed-length mask. It is never shown again. **Remove** deletes the saved key and is enabled only while one is saved. | none |
| **Model:** | The Claude model the assistant uses. Leave it blank to use the default. A change takes effect when you press Return or leave the field, and only a change to a different model ends conversations: retyping the current model, or blanking the field while the default is in use, changes nothing. | `claude-opus-5-5` |
| **Compact when context reaches … tokens** | When on, a long conversation is replaced by a summary at the end of the first turn that passes the threshold (see [Long conversations](#long-conversations-the-context-meter-and-compaction)). The field accepts 20,000 to 900,000 and is enabled only while the box is checked. | on, 300,000 |
| **Clear old tool results past 150,000 tokens** | Lets Anthropic drop old tool results from what the model sees. | off |

Under the controls, a status line reports the key's state: "No API key is set." (when neither a saved key nor the environment provides one), "Key saved." or "Key removed.". If the key file cannot be written or removed, the status line shows the file error instead, and nothing changes. Clicking **Save** with an empty field beeps. A threshold outside the range also beeps, and the field goes back to the stored value.

**What ends a conversation.** A conversation keeps the key and model it started with. Saving or removing the key, or changing the model to a different one, ends the conversation in every open window. The transcript stays and gets a note: "The API key changed; the next message starts a new conversation." or "The model is now … ; the next message starts a new conversation.". The two chat settings apply without Save and without ending anything. A new compaction threshold applies at the end of the current turn, and a change to clearing applies from the next message.

### Where the key is kept

A saved key is stored in a file named `anthropic-key` in `~/Library/Application Support/Frame Job/`, which only your user account can read. It goes to the assistant's helper process when a conversation starts and nowhere else. No tool reads or writes the key, the model or the chat settings, so an agent connected over MCP cannot see or change them.

If no key is saved, Frame Job uses the `ANTHROPIC_API_KEY` environment variable instead. In practice that only applies when Frame Job is launched from a shell that sets the variable. A saved key always takes precedence.

## Opening the Assistant

The Assistant is the fourth tab of the inspector, after Clip, Media and Document. **View ▸ Assistant** (⌃⌘A) shows the inspector if it was hidden, switches to the Assistant tab and puts the cursor in the message field.

From top to bottom, the tab has:

1. **Context**: the context meter, with **Clear** (↺, "Clear the conversation") at its right end.
2. **Spend**: what this conversation has cost so far.
3. **The transcript.**
4. **The ask-first row**, shown only while the assistant is waiting for your permission.
5. **The message field and Send.**

Without a key, the message field is replaced by "Add your Anthropic API key in Settings to use the assistant." and an **Open Settings…** button.

The tab doesn't switch away on its own while you work in it. The assistant's own edits change the selection without moving you to the Clip tab. Clicking a clip in the timeline or on the canvas still shows the Clip tab, as it always does.

## Sending a message

Type in the field ("Ask about or edit this project…") and press Return or click **Send**. The field starts one line high and grows to five lines as you type. Past five lines it scrolls.

| Key | In the message field |
|---|---|
| Return or keypad Enter | Sends the message. While the assistant is working or waiting for an answer, it beeps instead. |
| ⇧Return, ⌘Return, ⌥Return, ⌃Return | Starts a new line |
| Tab, ⇧Tab | Moves focus to the next or previous control |
| ⌘Z, ⇧⌘Z | Undoes or redoes your typing. Typing never lands on the project's undo stack. |

The field empties once the message is sent. If the conversation cannot start (for example, the key was removed), the reason appears in red in the transcript and your text stays in the field.

While a turn runs, **Send** reads **Stop**. See [Stopping a turn](#stopping-a-turn).

### What each message carries

Each message you send starts with a short block describing your window at the moment you pressed Send:

- the project's name, and its path (or "never saved")
- the nest open in the window, if any (otherwise the timeline)
- the playhead, in ticks and in seconds
- the selected clip ids

So "split this clip at the playhead" or "make the selected titles bigger" mean what you'd expect. The block isn't updated during the assistant's turn. After its own edits, the assistant reads the project again.

## The transcript

The transcript is one block of text. You can select across entries and copy it as plain text. It scrolls to the newest line as the reply arrives.

| What you see | Style |
|---|---|
| Your message | Semibold |
| The assistant's reply, streamed as it is written | Regular |
| Its working notes between tool calls | Small, faint |
| One line per tool call: the tool's name and its arguments, e.g. `split (at: 96000, clips: [12])` (first 70 characters) | Small monospace |
| `failed: …` for a tool call that was refused, with the reason | Small monospace |
| `Allowed: …` / `Declined: …` for each permission question, or `Declined (stop): …`, `Declined (close): …` or `Declined (helper): …` when it was declined by Stop, by closing the window or by the helper stopping | Small monospace |
| Compaction and clearing notes, and notes about key, model or spend-ledger problems | Small monospace |
| `Cost: …` at the end of each turn | Small monospace |
| Errors | Red |

Errors you may see:

- "API error *status*: *message*": Anthropic refused or failed the request (a bad key, a rate limit, an outage). Rate limits, outages and connection failures are retried up to three times before this appears. A bad key fails at once.
- "The reply was cut off at the output limit."
- "The model declined this request."
- "The assistant helper stopped. Clear the conversation to start a new one."

If the helper stops, a waiting question is declined. Your next message starts a new conversation under the old transcript, and the Spend row carries on from where it was. Click **Clear** to start clean.

If a response's cost cannot be written to the spend ledger, the transcript notes it once per conversation: "The spend ledger *path* could not be written: *reason*." That response is then missing from the month's total in Settings.

The assistant works for up to 30 rounds of tool calls in one turn, then stops.

**Clear** (↺) ends the conversation, empties the transcript and resets the Spend row and the meter. The meter keeps the model's window size, so it reads "0 of *L* tokens · 0%" until the next response. Your next message starts a fresh conversation. Closing the window also ends its conversation. Conversations aren't saved with the project, and each window has its own.

## What the assistant can do

The assistant has the same tools an agent has over MCP (see [MCP](mcp.md)), with a few exceptions listed below. It can:

- open, create and save projects, move the playhead, set the in and out range, change the selection, and enter or leave a nest
- add, remove, reorder and set tracks; add and edit markers; change the canvas
- import, relink and remove media, copy it into the project (it asks first), and set a media's camera log
- place media, text, shapes, backgrounds, adjustment clips and graphics; insert, overwrite, paste and duplicate
- move, trim, split, slip, roll, rate-stretch, ripple-delete, lift, insert time and close gaps; detach audio
- nest clips, or take a nest apart
- set speed, reverse, freeze frames and add speed ramps (see [Speed](speed.md))
- change how a clip looks and sounds, including transitions, actions and zooms; rename a clip, hide or mute it, and paste attributes
- import captions, transcribe on this Mac, read a clip's timed words, and export captions
- find silences and filler words, normalize loudness and synchronize audio
- write, place and change graphics modules; import fonts and assets; rename, delete or restore a module
- export, check an export's progress, or cancel it
- render a frame of the timeline to look at the result, before and after a visual edit

Every edit is one undo step on the project, the same as your own. A turn isn't grouped: each edit is its own step, so a turn that made ten edits takes ten Undos, and **Edit ▸ Undo** names each step after its edit, as it does for an agent's call over MCP. **Edit ▸ Undo** (⌘Z) outside the message field takes back the assistant's last change. You can also ask the assistant to undo.

**How it behaves.** Its replies are short, a sentence or two, and don't repeat what the tool lines already show. It writes or restyles captions only when you ask. It renders a frame to look before and after a visual edit. The model runs at medium effort with thinking on, and the faint working notes between tool calls are its thinking updates.

The assistant works only on its own window's project. A tool call that names another project is refused.

**Cutting words.** Ask it to take out filler words and it finds them and cuts them in one step, but only in media that already have a cloud transcript made with filler words (by **Clip ▸ Remove Filler Words…**). The assistant can't upload audio to make one, so in other media it cuts nothing (the search reports which media have no such transcript). Ask it to remove a false start and it reads the clip's words and their times (from the media's cached transcript, or from this Mac's own speech recogniser, never the network), says which words it will cut, then cuts them as one undo step. It removes a false start only when you ask, because deciding what was a false start is a judgement call. See [Clean-up tools](cleanup-tools.md).

### Tools it will not call

`record_screen`, `close_project` and `transcribe_for_fillers` are removed from what the assistant can see. `transcribe` stays available for transcribing on this Mac, and only a call with the cloud engine (AssemblyAI) is refused. All four are refused if the assistant calls them anyway, and the call shows in the transcript as a `failed:` line: "*tool* is not available to the assistant: *reason*" (for the cloud case, `transcribe with engine "assemblyai" is not available to the assistant: …`). The reason names the menu item to use instead.

| Tool | Why | Do it yourself with |
|---|---|---|
| `record_screen` | Recording needs a person at the Record button. | **File ▸ New Recording…** (⌥⌘N) |
| `close_project` | Closing the project would close the window the conversation lives in. | **File ▸ Close** (⌘W) |
| `transcribe` with the cloud engine (AssemblyAI) | Audio leaves the machine only when you choose it, with the price in front of you. | **File ▸ Generate Captions…** |
| `transcribe_for_fillers` | The same: it uploads audio to the cloud. | **Clip ▸ Remove Filler Words…** |

### Tools it asks about first

Four tools ask first: `export`, `export_captions`, `save_project` and `consolidate_media`. Before each one runs, the tab shows the ask-first row, "The assistant asks first:", with a sentence that says what will happen, and **Allow** and **Deny** buttons:

| Tool | The question reads |
|---|---|
| `export` | "export writes *path*", or "export REPLACES *path*" when a file is already there |
| `export_captions` | "export_captions writes *path*" (or REPLACES) |
| `save_project` | "save_project writes *path*" (or REPLACES); "save_project writes a file" when no path is known |
| `consolidate_media` | "consolidate_media copies every referenced file into *package*/media", or "… into the project's package" when the project has never been saved |

A `~` in the path is expanded before the question is asked, so the sentence shows the full path.

Other tools the assistant can call write files without asking: `render_frame` writes a PNG (to a temporary file, or to a path the model names), and `write_graphic`, `import_graphic_font` and `import_graphic_asset` write graphics modules, fonts and assets into the project's package.

While a question waits, the **Assistant** tab title shows a small dot, whichever inspector tab you are on. Answer with a click: Return never answers a question. Nothing runs until you click **Allow**. **Deny** tells the assistant you declined, and it won't retry that call in the same turn unless you ask. Stopping the turn, closing the window or the helper stopping each count as a decline. Other windows' assistants and agents over MCP keep working while one window waits for an answer.

### While you are dragging

If one of the assistant's tool calls arrives while you are in the middle of a drag (on the timeline, the canvas or an inspector slider), it waits until you release the mouse. Then it runs as its own undo step, after yours, so your drag never undoes the assistant's change or mixes with it. The same applies to agents over MCP.

The assistant's tool calls and MCP agents' calls take turns, one at a time, and each window's calls run in order. While a window waits for your **Allow** or **Deny**, MCP agents and other windows keep working.

### Stopping a turn

Click **Stop** (the Send button while a turn runs). Stop:

- ends the request to Anthropic
- declines a question that is waiting
- answers every tool call that has not started yet with "Cancelled by the user."
- cancels an on-device transcription or transcript read that is running. Any other tool call that has already started is allowed to finish.

An export is handed to the Export Queue as soon as it starts, so Stop doesn't reach it. Cancel it in the Export Queue, or ask the assistant to cancel it. See [Export](export.md).

## Long conversations: the context meter and compaction

The **Context** meter shows how much of the model's context window the conversation is using, as of the last response:

- "Nothing reported yet" before the first response
- "*N* of *L* tokens · *P*%" once the model's window is known (shortened to "*N* / *L* · *P*%" or "*P*%" when the inspector is narrow; the tooltip always has the full figure)
- "*N* tokens (window size unknown)" if Anthropic did not report the window size

The bar under the figure fills in the accent colour and turns red past 80%.

**Compaction.** With **Compact when context reaches** on, the conversation is summarised at the end of the first turn that passes the threshold, never in the middle of a turn. The summary keeps what you asked for and your stated preferences, the project and the clips, tracks, markers and media involved, the edits made and undone, and what is still open. The transcript notes "Compacting the conversation (*N* tokens)…" and then "Compacted: *N* → about *M* tokens. Earlier renders are gone; the assistant re-renders when it needs to look.". If no summary comes back, the note says compaction didn't finish and that it will try again after the next turn. The summary request is priced like any other response.

With compaction off, a conversation grows until it fills the model's window, and requests then fail until you click **Clear**.

**Clearing old tool results.** With **Clear old tool results past 150,000 tokens** on, Anthropic may drop older tool results from what the model sees once the conversation passes 150,000 tokens. It keeps the five most recent, clears at least 50,000 tokens at a time, and can happen mid-turn. Each clearing adds a note, "Cleared *N* old tool results (*M* tokens) from the model's view.", and costs a fresh prompt-cache write. The model may have to fetch something again after a clearing.

## What it costs

Every response is priced by Frame Job from LiteLLM's published Anthropic prices. All the figures below are **Frame Job's own estimate**. The Anthropic Console shows what your account was actually billed.

### Per turn

Each turn ends with a line in the transcript:

`Cost: $0.0182 · Frame Job's estimate at LiteLLM prices (cached 2026-10-25)`

The part in brackets names the price table and its date: "bundled table of …" (the copy built into the app), "cached …" or "fetched …" (a copy Frame Job refreshes at most once a day). If a refresh failed, the line adds "not refreshed:" and the reason.

- A response that could not be priced shows as "unknown (*reason*)", never $0, followed by "at least" the part that could be priced.
- A response cut short by Stop or an error is priced from what had arrived, as "at least $… (a response was cut short)".
- Amounts are shown to four decimal places. A tiny positive amount reads "under $0.0001".

### Per conversation

The tab's **Spend** row adds up the conversation's turns since the last **Clear**, or since a key or model change ended the conversation:

- "Nothing yet" before the first response
- "$0.0532 · Frame Job's estimate"
- "at least $… · Frame Job's estimate" when a response was cut short or could not be priced (shortened to "≥$…" when narrow)
- "under $0.0001 · Frame Job's estimate" for a tiny positive amount (shortened to "<$0.0001" when narrow)
- "unknown · Frame Job's estimate" when nothing could be priced

Hovering the figure shows "What this conversation's responses cost at LiteLLM prices, as Frame Job estimates it. The Anthropic Console shows what your account was billed."

### Per month

Under the buttons in **Settings ▸ Assistant**, a line totals the current calendar month in UTC, for example "October 2026 (UTC): $1.24 over 87 responses.". Variants report "Nothing recorded in …", responses that could not be priced, and ledger lines that could not be read. Totals are rounded to the cent, and a tiny positive amount reads "under $0.01". While the ledger is being read the line says "Reading the spend ledger…", and if it cannot be read, "The spend ledger could not be read: *reason*.". The line refreshes when Settings opens and after each response while Settings is visible. Under it, a faint note says: "Frame Job's own estimate at LiteLLM prices, from its spend ledger. The Anthropic Console shows what your account was billed."

The figures come from a spend ledger, `spend.jsonl` in `~/Library/Application Support/Frame Job/`, with one line per response: the time, the model, the token counts and the dollars. It never records your key or the conversation's content.

## Privacy: what leaves your Mac

When you use the assistant, these go to Anthropic, under your key:

- your messages, and the context block in front of each one (the project's name and path, the open nest, the playhead, the selection)
- what the tools answer: the project's details as JSON (including media file paths), clip transcripts it reads, refusals and other results
- the frames it renders to look at the picture

Frame Job doesn't send any of this anywhere else. Audio never goes to the cloud transcriber from the assistant (see [Tools it will not call](#tools-it-will-not-call)). The assistant asks before it exports a movie or captions, saves the project, or consolidates media; other tools can still write files without asking (a rendered frame's PNG, and graphics modules, fonts and assets in the project's package). Once a day at most, the helper downloads LiteLLM's public price table from GitHub. That request carries no key and no project data.

Everything else stays on your Mac: the key file, the spend ledger and the cached price table, `anthropic-prices.json`, all in `~/Library/Application Support/Frame Job/`. The conversation itself is kept in memory only, and goes when you clear it or close the window.

## Limits

- The assistant works only on the project in its own window, and each window has its own conversation.
- It needs your own Anthropic API key. There is no Frame Job account or relay.
- It can't record the screen, close its window's project, or send audio to the cloud transcriber.
- A tool call that arrives during a drag waits until you release the mouse.
- Stop doesn't cancel an export that has already been queued.
- With compaction off, a long conversation eventually fails until you **Clear** it.
- Changing the key or the model ends every window's conversation.

*Agents:* none. The Assistant is the person's own conversation, and its settings are deliberately out of reach of any tool. An agent drives the same tools directly over [MCP](mcp.md), and is never asked first or refused by the assistant's rules above.
