function Inspector({ tab, setTab, selected, onSelectMedia }) {
  const { PanelTabs, SelectionBlock, InspectorSection, MediaRow, Button, PropertyGrid } = window.ReelcutDesignSystem_2b6440;
  const [open, setOpen] = React.useState({ transform: true, video: true });
  const sel = RC.CLIPS[selected];
  const sections = sel ? RC.SECTIONS.filter((s) => s.kinds.includes(sel.kind)) : [];
  const [pick, setPick] = React.useState(0);
  return <div style={{ width: "var(--panel-width)", flex: "none", background: "var(--surface-panel)", borderLeft: "1px solid var(--border)", display: "flex", flexDirection: "column" }}>
    <PanelTabs tabs={["Clip","Media","Document"]} value={tab} onChange={setTab} />
    {tab === "Clip" && <div style={{ display: "flex", flexDirection: "column", flex: 1, overflow: "auto" }}>
      <SelectionBlock variant="header" kind={sel && sel.kind} name={sel && sel.name} meta={sel && sel.meta} />
      {sections.map((s) => <InspectorSection key={s.id} label={s.label} summary={s.summary} open={!!open[s.id]}
        onToggle={() => setOpen({ ...open, [s.id]: !open[s.id] })}
        rows={s.rows.map(([label, value, affix]) => ({ label, value, affix }))} />)}
      {!sel && <div style={{ padding: 16, font: "var(--type-label)", color: "var(--text-faint)" }}>Select a clip in the timeline.</div>}
    </div>}
    {tab === "Media" && <div style={{ display: "flex", flexDirection: "column", flex: 1 }}>
      <div style={{ height: 38, boxSizing: "border-box", borderBottom: "1px solid var(--border)", display: "flex", alignItems: "center", gap: 8, padding: "0 10px" }}>
        <Button icon="add" emphasis="strong">Add Media</Button>
        <span style={{ font: "var(--type-mono-sm)", color: "var(--text-faint)" }}>⇧⌘I</span>
        <div style={{ flex: 1 }}></div>
        <span style={{ font: "var(--type-mono-sm)", color: "var(--text-faint)" }}>{RC.MEDIA.length} items</span>
      </div>
      <div style={{ flex: 1, padding: 8, display: "flex", flexDirection: "column", gap: 3 }}>
        {RC.MEDIA.map((m, i) => <MediaRow key={m.name} name={m.name} meta={m.meta} kind={m.kind} thumb={m.thumb ? RC.FRAME : null} selected={pick === i} onClick={() => setPick(i)} />)}
      </div>
      <div style={{ height: 40, boxSizing: "border-box", borderTop: "1px solid var(--border)", display: "flex", alignItems: "center", padding: "0 10px", gap: 10 }}>
        <Button>Consolidate…</Button>
        <span style={{ font: "var(--type-hint)", color: "var(--text-faint)" }}>Copies sources into the package</span>
      </div>
    </div>}
    {tab === "Document" && <div style={{ padding: "12px 10px" }}>
      <PropertyGrid labelWidth={86} gap={8} rows={RC.DOC.map(([label, value, affix]) => ({ label, value, affix }))} />
    </div>}
  </div>;
}
window.Inspector = Inspector;
