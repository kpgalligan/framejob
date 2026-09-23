window.RC = (() => {
  const PPS = 1308 / 40; const px = (s) => Math.round(s * PPS);
  const CLIPS = {
    v1: { name: "IMG_9619.MOV", kind: "video", start: 0, end: 21, track: "V1", meta: "00:00:21:00 · 1080×1920 · 25.106 fps" },
    v2: { name: "IMG_9622.MOV", kind: "video", start: 20.5, end: 37.2, track: "V1", meta: "00:00:16:18 · 1080×1920 · 25.106 fps" },
    t1: { name: "Title card", kind: "text", start: 0.5, end: 5, track: "T1", caption: "Nightfall", meta: "00:00:04:12 · Darker Grotesque Black 96pt" },
    t2: { name: "Lower third", kind: "text", start: 12, end: 18, track: "T1", caption: "Kevin · producer", meta: "00:00:06:00 · Source Sans 3 SemiBold 42pt" },
    a1: { name: "room-tone.wav", kind: "audio", start: 0, end: 37.2, track: "A1", meta: "00:00:37:05 · 48 kHz stereo" },
  };
  const SECTIONS = [
    { id: "transform", label: "Transform", summary: "100%", kinds: ["video","text"], rows: [["Position","0, 0","open_with"],["Scale","100%"],["Rotation","0.0°"],["Anchor","Center","unfold_more"]] },
    { id: "video", label: "Video", summary: "normal", kinds: ["video","text"], rows: [["Opacity","100%"],["Blend","Normal","unfold_more"],["Corner radius","0 px"],["Speed","1.00×"]] },
    { id: "audio", label: "Audio", summary: "0.0 dB", kinds: ["video","audio"], rows: [["Volume","0.0 dB"],["Pan","Center"],["Fade in","0.0 s"],["Fade out","0.5 s"],["Duck","Off","unfold_more"]] },
    { id: "effects", label: "Effects", summary: "none", kinds: ["video","text"], rows: [["Filter","None","unfold_more"],["Chroma key","Off","unfold_more"],["Shadow","Off","unfold_more"],["Reflection","Off","unfold_more"]] },
    { id: "timing", label: "Timing", summary: "21:00", kinds: ["video","audio","text"], rows: [["In","00:00:00:00"],["Out","00:00:21:00"],["Duration","00:00:21:00"],["Reverse","Off","unfold_more"]] },
  ];
  const HEIGHTS = { S: { T1: 30, V1: 54, A1: 40 }, M: { T1: 44, V1: 84, A1: 60 }, L: { T1: 58, V1: 116, A1: 82 } };
  const MEDIA = [
    { name: "IMG_9619.MOV", meta: "01:48:24 · 1080×1920", kind: "video", thumb: true },
    { name: "IMG_9622.MOV", meta: "00:41:02 · 1080×1920", kind: "video", thumb: true },
    { name: "room-tone.wav", meta: "00:37:05 · 48 kHz", kind: "audio" },
  ];
  const DOC = [["Resolution","1080 × 1920"],["Frame rate","25.106 fps"],["Duration","00:00:37:05"],["Colour","Rec. 709"],["Tracks","3"],["Background","Black","unfold_more"]];
  const FPS = 25;
  const tc = (s) => { const f = Math.floor((s % 1) * FPS); const t = Math.floor(s); return ["00", String(Math.floor(t / 60)).padStart(2,"0"), String(t % 60).padStart(2,"0"), String(f).padStart(2,"0")].join(":"); };
  return { PPS, px, CLIPS, SECTIONS, HEIGHTS, MEDIA, DOC, tc, DURATION: 37.2, FRAME: "assets/reel-frame.png" };
})();
