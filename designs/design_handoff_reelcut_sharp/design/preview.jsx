function Preview({ safe, fit }) {
  const scale = { Fit: 1, "25%": 0.55, "50%": 0.8, "100%": 1.12 }[fit] || 1;
  return <div style={{ flex: 1, background: "var(--surface-well)", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 10, position: "relative", overflow: "hidden", minWidth: 0 }}>
    <div style={{ height: 410 * scale, width: 231 * scale, position: "relative", boxShadow: "var(--shadow-preview)", flex: "none" }}>
      <img src={RC.FRAME} alt="preview" style={{ width: "100%", height: "100%", objectFit: "cover", display: "block" }} />
      {safe && <div style={{ position: "absolute", inset: 0, pointerEvents: "none" }}>
        <div style={{ position: "absolute", inset: "5%", border: "1px solid var(--safe-outer)" }}></div>
        <div style={{ position: "absolute", inset: "10%", border: "1px solid var(--safe-inner)" }}></div>
      </div>}
    </div>
    <div style={{ font: "400 10px/1 var(--font-mono)", color: "var(--text-faint)", letterSpacing: "0.06em" }}>1080 × 1920 · 25.106 FPS</div>
  </div>;
}
window.Preview = Preview;
