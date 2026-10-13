# 2. The a screencast editor model, and why it stays simple

Six ideas do most of the work. Frame Job copies all six.

1. **One kind of track.** Every track holds any clip — video, audio,
   still, text, shape. There are no video-vs-audio track types; an
   audio-only clip simply draws a waveform. Higher track = in front.
2. **A fixed canvas with direct manipulation.** The document has a size
   (1920×1080 by default). Clips are placed on it by dragging on the
   preview; scale, position, rotation and crop are clip properties with
   numbers in the inspector and handles on the canvas.
3. **Actions, not keyframes.** An Action is a span on a clip with an
   easing curve. You edit the property values at the *end* of the span;
   the values at the start are whatever was already in effect. There is
   no keyframe graph.
4. **Overlap is a transition.** Sliding one clip over its neighbour on
   the same track makes a transition of that length. No transition
   track, no browser to drag from.
5. **One inspector, tabbed by what the selection is.** Video / Audio /
   Text / Shape for the selected clip; Media and Document always.
6. **A small keyboard vocabulary.** ⌘T split, W/E trim to playhead,
   ⌘⌫ ripple delete, ⇧⌘F freeze frame, M marker, Space/JKL transport.

Dropped from a screencast editor: everything that only makes sense for a recording
it made itself (mouse/keyboard/touch callouts, pointer effects), templates,
publishing to YouTube/Vimeo, the stock-media library.
