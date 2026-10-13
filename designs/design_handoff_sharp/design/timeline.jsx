function Timeline({ clips, selected, onSelect, size, time, onScrub, zoom }) {
  const { Ruler, TrackHeader, Clip, Transition, Playhead } = window.ReelcutDesignSystem_2b6440;
  const k = 0.6 + zoom * 0.95; const px = (s) => Math.round(s * RC.PPS * k);
  const h = RC.HEIGHTS[size];
  const tracks = [
    { name: "T1", kind: "text", lane: "var(--surface-lane)", toggles: ["visibility","lock_open"] },
    { name: "V1", kind: "video", lane: "var(--surface-lane-alt)", toggles: ["visibility","volume_up","lock_open"] },
    { name: "A1", kind: "audio", lane: "var(--surface-lane)", toggles: ["volume_up","lock_open"] },
  ];
  const ticks = Array.from({ length: 14 }, (_, i) => ({ x: px(i * 4), label: "00:" + String(i * 4).padStart(2, "0") + ":00" }));
  const scrub = (e) => { const r = e.currentTarget.getBoundingClientRect(); onScrub(Math.max(0, Math.min(RC.DURATION, (e.clientX - r.left) / (RC.PPS * k)))); };
  const list = Object.entries(clips);
  return <div style={{ flex: 1, background: "var(--surface-timeline)", position: "relative", overflow: "hidden", display: "flex", flexDirection: "column" }}>
    <div style={{ position: "relative" }}><Ruler ticks={ticks} /><div onMouseDown={scrub} style={{ position: "absolute", left: 132, right: 0, top: 0, height: 22, cursor: "ew-resize" }}></div></div>
    {tracks.map((tr) => {
      const on = list.filter(([, c]) => c.track === tr.name).sort((a, b) => a[1].start - b[1].start);
      const trans = [];
      for (let i = 1; i < on.length; i++) { const a = on[i - 1][1], b = on[i][1]; if (b.start < a.end) trans.push({ x: px(b.start), w: px(a.end) - px(b.start) }); }
      return <div key={tr.name} style={{ display: "flex", height: h[tr.name], borderBottom: "1px solid var(--border-lane)", transition: "height var(--duration-state) var(--ease-standard)" }}>
        <TrackHeader name={tr.name} kind={tr.kind} toggles={tr.toggles} />
        <div style={{ flex: 1, position: "relative", background: tr.lane }} onClick={(e) => e.target === e.currentTarget && onSelect(null)}>
          {on.map(([id, c]) => <Clip key={id} kind={c.kind} name={c.name} caption={c.caption} thumb={c.kind === "video" ? RC.FRAME : null} x={px(c.start)} width={px(c.end) - px(c.start)} selected={selected === id} onClick={() => onSelect(id)} />)}
          {trans.map((t, i) => <Transition key={i} x={t.x} width={t.w} />)}
        </div>
      </div>;
    })}
    <Playhead x={132 + px(time)} />
  </div>;
}
window.Timeline = Timeline;
