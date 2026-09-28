```json screen
{
  "title": "Assistant tab",
  "project": "demo",
  "steps": [
    {"call": "set_selection", "args": {"clips": []}},
    {"call": "select_inspector_tab", "args": {"tab": "assistant"}}
  ],
  "captures": [
    {"name": "window", "window": "editor"},
    {"name": "inspector", "window": "editor", "view": "inspector"}
  ],
  "after": [{"call": "select_inspector_tab", "args": {"tab": "clip"}}],
  "expect": [{"capture": "inspector",
              "visible_text": "Add your Anthropic API key in Settings to use the assistant."}]
}
```

The inspector's fourth tab, Assistant (View ▸ Assistant, ⌃⌘A): a conversation
with the built-in assistant, which edits this window's project with the same
tools an agent uses. Here no Anthropic API key is set, so the tab points at
Settings instead of offering a message field.

The Assistant tab is selected at the top of the inspector, beside Clip, Media and
Document, and nothing is selected in the timeline ("No selection"). Under the
tabs is a slim strip: "CONTEXT" in small grey capitals on the left, "Nothing
reported yet" on the right in small grey monospace, a thin empty bar under both
(how full the conversation's context is), and a round-arrow Clear button at the
right end. A hairline separates it from the transcript, which fills the middle of
the tab and is empty. At the foot: "Add your Anthropic API key in Settings to use
the assistant." over two lines, and under it a small bordered "Open Settings…"
button. With a key set, the foot is instead a message field whose placeholder
reads "Ask about or edit this project…" with a blue "Send" button beside it, and
while the assistant asks before writing a file, a row above the field reads "The
assistant asks first:" with the tool and the path, and "Allow" and "Deny" buttons.

In the light capture the tab strip and the panel are white with black text, the
Assistant tab a white cell with a blue underline, the context strip's text and bar
light grey, and the pointer's sentence black. In the dark capture the panel is
near-black with white text and the context strip's text a dim grey.
