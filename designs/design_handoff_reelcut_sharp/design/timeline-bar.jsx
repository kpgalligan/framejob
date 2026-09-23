function TimelineBar({ selected, onBlade, onDelete, onDuplicate, snap, setSnap, zoom, setZoom, size, setSize }) {
  const { ChromeBar, SelectionBlock, Divider, GhostButton, Checkbox, Slider, SegmentedControl } = window.ReelcutDesignSystem_2b6440;
  const sel = RC.CLIPS[selected];
  const acts = [["content_cut","Blade",onBlade],["first_page","Trim start"],["last_page","Trim end"],["backspace","Ripple delete",onDelete],["bookmark_add","Add marker"],["content_copy","Duplicate",onDuplicate],["title","Add text"]];
  return <ChromeBar variant="bar" borderTop>
    <SelectionBlock kind={sel && sel.kind} name={sel && sel.name} meta={sel && ("Track " + sel.track + " · " + sel.kind)} />
    <Divider length={18} />
    <div style={{ display: "flex", gap: 2 }}>{acts.map(([i, n, f]) => <GhostButton key={n} icon={i} size="bar" title={n} onClick={f} disabled={!sel && i !== "title" && i !== "bookmark_add"} />)}</div>
    <Divider length={18} />
    <Checkbox checked={snap} onChange={setSnap} label="Snap" />
    <div style={{ flex: 1 }}></div>
    <Slider value={zoom} onChange={setZoom} iconMin="zoom_out" iconMax="zoom_in" />
    <Divider length={18} />
    <SegmentedControl options={["S","M","L"]} value={size} onChange={setSize} />
  </ChromeBar>;
}
window.TimelineBar = TimelineBar;
