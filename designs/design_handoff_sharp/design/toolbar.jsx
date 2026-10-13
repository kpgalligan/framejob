function Toolbar({ time, playing, onPlay, onJump, safe, setSafe, fit, setFit, onExport }) {
  const { ChromeBar, GhostButton, Divider, TimecodeField, PopupButton, Checkbox, AccentButton } = window.ReelcutDesignSystem_2b6440;
  const t = [["skip_previous","Go to start",() => onJump(0)],["fast_rewind","Back one second",() => onJump(time - 1)],[playing ? "pause" : "play_arrow", playing ? "Pause" : "Play", onPlay],["fast_forward","Forward one second",() => onJump(time + 1)],["skip_next","Go to end",() => onJump(RC.DURATION)],["repeat","Loop"]];
  return <ChromeBar variant="toolbar">
    <div style={{ display: "flex", gap: 2 }}>{t.map(([i, n, f]) => <GhostButton key={n} icon={i} title={n} onClick={f} />)}</div>
    <Divider />
    <TimecodeField value={RC.tc(time)} total="00:00:37:05" />
    <div style={{ flex: 1 }}></div>
    <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
      <PopupButton value={fit} options={["Fit","25%","50%","100%"]} onChange={setFit} />
      <Checkbox checked={safe} onChange={setSafe} label="Safe" />
    </div>
    <Divider />
    <AccentButton icon="ios_share" onClick={onExport}>Export</AccentButton>
  </ChromeBar>;
}
window.Toolbar = Toolbar;
