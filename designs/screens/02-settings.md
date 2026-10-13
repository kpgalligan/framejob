```json screen
{
  "title": "Settings",
  "project": null,
  "steps": [{"call": "perform_menu_item", "args": {"path": ["Frame Job", "Settings…"]}}],
  "captures": [{"name": "window", "window": "settings"}],
  "expect": [{"capture": "window", "visible_text": "Copy MCP Command"},
             {"capture": "window",
              "visible_text": "An MCP client such as Claude Code uses Frame Job's tools through framejob-mcp, a helper inside this app. It reaches Frame Job over a local socket that only programs you run can open."},
             {"capture": "window", "visible_text": "Anthropic API key:"},
             {"capture": "window", "visible_text": "AssemblyAI API key:"},
             {"capture": "window", "visible_text": "No API key is set."},
             {"capture": "window", "visible_text": "Compact when context reaches"},
             {"capture": "window",
              "visible_text": "Frame Job's own estimate at LiteLLM prices, from its spend ledger. The Anthropic Console shows what your account was billed."},
             {"capture": "window", "no_visible_text": "API key:"}]
}
```

Settings (Frame Job ▸ Settings…) has three sections, one under the other: MCP,
Assistant and Transcription. The first is where a person finds how to connect
an MCP client such as Claude Code to Frame Job (spec §11 MC-7); the second is
where they give Frame Job an Anthropic API key, choose the model for the
Assistant tab, and set how a long conversation is kept in bounds; the third is
where they give it an AssemblyAI API key, so that the Generate Captions sheet
can transcribe in the cloud instead of on this Mac.

The "MCP" section opens with its bold heading alone, with no ⓘ. Under it, two
short paragraphs in 13 pt black (white in dark), visible rather than in a
popover: "An MCP client such as Claude Code uses Frame Job's tools through
framejob-mcp, a helper inside this app. It reaches Frame Job over a local socket
that only programs you run can open." and "If Frame Job isn't running, the first
tool call opens it in the background. To add Frame Job to Claude Code, copy the
command and run it in Terminal." Then the helper's path inside this copy of
the app, ending `Contents/Helpers/framejob-mcp`, in 12 pt monospace black,
selectable, wrapping by character when it is long. Then a "Copy MCP Command"
button (a white square button with a thin outline), and under it an empty
status line: after a press it reads "Copied. Paste it into Terminal and press
Return.", and in a copy of Frame Job without the helper the button is dimmed and
the line reads "framejob-mcp is missing from this copy of Frame Job." Nothing in
the section is selected when the window opens; the Anthropic key field has the
focus.

The Assistant and Transcription sections each open with their bold heading
and, just after it, a small mid-grey ⓘ icon about the height of the heading's capitals, darkening while the pointer
is on it. Resting on an ⓘ for about a third of a second opens a standard macOS
popover under it — the rounded bubble with an arrow (spec §11 SH-5) — holding
that section's explanation in 13 pt black (white in dark), in short
paragraphs; leaving the icon closes it, and clicking the icon opens it and
keeps it open until it is clicked again or a click lands elsewhere. The
popover is not in the capture: it opens only under the pointer or a click,
and nothing in the catalog hovers or clicks.

Under the "Assistant" heading: an "Anthropic API key:" field, empty, whose
placeholder reads "Paste your key"; a "Model:" field, empty, whose grey
placeholder reads "claude-opus-5-5" (the default when it is left blank); then
the chat settings, two rows of their own. The first is a ticked checkbox
"Compact when context reaches", a short right-aligned field reading "300,000",
and the word "tokens" in grey; the field can be typed in only while the box is
ticked. The second is an unticked checkbox "Clear old tool results past
150,000 tokens". Neither has a Save: a change applies at once and keeps the
conversation going. Then the status line "No API key is set." and, along its
bottom, "Save" (blue) and "Remove" (dimmed). It has no Verify and no account
link. Its ⓘ says the assistant sends the messages, the project's details and
the frames it renders to Anthropic with the person's own key, which is billed;
that it asks before writing a file; that the key is kept in a file only the
person can read and never shown again; that a blank model means
claude-opus-5-5 and that changing the key or the model starts a new
conversation; and that at the end of a turn past the compaction threshold
(20,000 to 900,000 tokens; 300,000 by default) the conversation is replaced by
a summary, that clearing drops old tool results, and that changing either
setting keeps the conversation.

Under those two buttons, after a small gap, is what the assistant has cost this
month: one line in the same black as the status lines, here "Nothing recorded in
September 2026 (UTC)." (the capture's launch keeps an empty spend folder, and the
month is the UTC calendar month the capture was taken in). With responses recorded
it reads, for example, "September 2026 (UTC): $0.42 over 12 responses.", and says
how many could not be priced or could not be read rather than counting them as
nothing. Under it, in small grey: "Frame Job's own estimate at LiteLLM prices, from
its spend ledger. The Anthropic Console shows what your account was billed."

Under the "Transcription" heading, after a wider gap (the same gap separates
MCP from Assistant): an "AssemblyAI API key:"
field, empty, whose placeholder reads "Paste your key"; a "Region:" pop-up set
to "United States"; and the status line "No API key is set." Along its bottom:
"Save" (blue), "Remove" and "Verify" (both dimmed, since there is no key), and
"Account Page" on the right. Its ⓘ says what happens when AssemblyAI is
chosen: the audio of the files being captioned is uploaded, transcribed, read
back and then deleted from AssemblyAI; nothing is uploaded until Generate is
pressed; captions made on this Mac never leave it; the published price and the
date it was read; and that the key is kept in a file only the person can read
and is never shown again once saved.

No long grey paragraph is left in the window; the MCP section's blurb is its
only paragraph, and it is black.

In the light capture the ground is white and the headings, the MCP blurb and
path, labels, status lines and the month's line black; the ⓘ icons, the spend note and the word
"tokens" are mid-grey, the key, model and threshold fields white boxes with grey
borders, the Region pop-up a light-grey pill, "Account Page" a white square
button with a thin black outline and no shadow, the two Saves flat blue blocks,
and the dimmed Remove and Verify grey-outlined with grey titles.
