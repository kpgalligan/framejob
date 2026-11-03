# Podcasts and several cameras

A show filmed with more than one camera — a podcast with a camera on each
guest, an interview with a wide and a close shot — is cut in Frame Job as
ordinary clips on ordinary tracks. There is no special multicam clip: each
camera is a track, and the edit you watch is a **program track** in front of
them, made of pieces copied from whichever camera you want at each moment.

## Setting it up

1. Put each camera's recording on a track of its own, lined up in time.
   **Clip ▸ Synchronize Audio** lines the selected recordings up by their
   sound ([Audio](audio.md)). Name each track after its camera (double-click
   the track's header): the names are what Switch Angle lists.
2. Add a track in front of them for the program, and put the first shots on
   it. An agent does this with `copy_pieces` (below); by hand, copy a camera's
   clip onto the program track and cut it with **Clip ▸ Split** (⌘T).

The camera tracks stay underneath. They can stay shown — the program track is
in front and covers them — or be hidden with their track switch; a hidden
track's clips still count as an angle.

## Switch Angle

**Clip ▸ Switch Angle ▸** re-picks one shot of the program from another
camera. Select the one shot, open the submenu, and choose a camera.

- The submenu lists, front first, every other track whose video clips cover
  the shot's whole span — only clips of a video file with a picture count, and
  a clip whose picture is switched off still counts. Up to nine tracks are
  listed. Two tracks with the same name are told apart by their position from
  the back, as "Camera (2)" and "Camera (3)". With no single shot selected, or
  no track covering it, the submenu holds a greyed **No Covering Angle**.
- An item is greyed when the shot's track is locked, or the shot is linked to
  a detached sound (**Clip ▸ Attach Audio** first).
- Choosing a camera replaces the shot with that camera's picture over exactly
  the same span, in sync: the new clip shows the camera's own frame at every
  moment. Where the shot crosses the end of one of the camera's clips and the
  start of the next (a camera that stopped and started again), it becomes two
  pieces, one from each file; where two of the camera's clips overlap, the
  later one takes over at its own start.
- The shot keeps its span and its video and audio switches, and the dissolves
  at both of its edges are kept with their kind, curve and audio shape. Nothing
  else carries over from the old shot: a punch-in, a grade or an action on it
  is not copied to the new camera's piece.
- The whole switch is one undo step, **Switch Angle**, and the new pieces are
  selected afterwards.
- If a dissolve can no longer fit — the camera's first or last piece is too
  short to overlap by the dissolve's length — the dissolve is dropped and the
  undo step is named **Switch Angle (transition removed)**.
- A switch that cannot be done changes nothing, beeps and says why at the foot
  of the inspector: the camera does not cover the shot (naming the first moment
  it does not), or the clip next to the shot plays a speed ramp that cannot
  give up the dissolve's frames ("clip X's edge is held at tick …").

Switch Angle works inside an open nest too, on the nest's own tracks. It has
no keyboard shortcut.

## For agents: copy_pieces and switch_angle

Two MCP tools do the same work ([Driving Frame Job from an AI agent](mcp.md)):

- `switch_angle {clip, angle}` is **Clip ▸ Switch Angle ▸**: `clip` the shot,
  `angle` the camera's track id. It answers the step's name, the new pieces'
  ids in time order and how many dissolves were dropped.
- `copy_pieces {clip, track, ranges, video?, audio?}` is the operation Switch
  Angle is built from: it copies the parts of one clip between the given times
  onto another track at the same times. Each piece is exactly what splitting
  the clip at both ends would leave in the middle — the same frames, speed,
  speed ramp, actions and timed words — with no dissolve and no link. The
  destination track must be free over every range. An agent cuts a whole
  program from the cameras with one `copy_pieces` per camera.
