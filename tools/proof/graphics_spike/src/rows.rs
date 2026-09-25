//! The row bodies q2, q3 and q8 of road map 10 §3, each answering one JSON
//! value, plus `render_frame` and the helpers every row shares. q4 is
//! `rows_text.rs`; q5 and q6 are `rows_stress.rs`.

use std::io::Write;
use std::time::Instant;

use serde_json::{json, Value};
use sha2::{Digest, Sha256};

use crate::diagnostic::Diagnostic;
use crate::raster::{rasterize, Library};
use crate::runtime::{default_props, hex_digest, Ctx, Engine, SPIKE_LIMITS};

pub struct Timed {
    pub js_ms: f64,
    pub parse_ms: f64,
    pub raster_ms: f64,
    pub svg_bytes: usize,
    pub sha256: String,
}

impl Timed {
    pub fn to_json(&self) -> Value {
        json!({"js_ms": self.js_ms, "parse_ms": self.parse_ms, "raster_ms": self.raster_ms,
               "svg_bytes": self.svg_bytes, "sha256": self.sha256})
    }
}

pub fn render_frame(
    engine: &mut Engine,
    lib: &Library,
    frame: i64,
    props: &Value,
    ctx: &Ctx,
    w: u32,
    h: u32,
) -> Result<Timed, Diagnostic> {
    let started = Instant::now();
    let svg = engine.svg(frame, props, ctx)?;
    let js_ms = ms(started);
    let raster = rasterize(lib, &svg, w, h)?;
    Ok(Timed {
        js_ms,
        parse_ms: raster.parse_ms,
        raster_ms: raster.raster_ms,
        svg_bytes: svg.len(),
        sha256: hex_digest(&Sha256::digest(&raster.bgra)),
    })
}

pub(crate) fn ms(since: Instant) -> f64 {
    since.elapsed().as_secs_f64() * 1000.0
}

pub(crate) fn sha(bytes: &[u8]) -> String {
    hex_digest(&Sha256::digest(bytes))
}

/// p50 / p95 / max by nearest rank over a copy.
pub fn summary(values: &[f64]) -> Value {
    let mut v = values.to_vec();
    v.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let at = |q: f64| {
        let rank = ((q * v.len() as f64).ceil() as usize).clamp(1, v.len().max(1));
        v.get(rank - 1).copied().unwrap_or(f64::NAN)
    };
    json!({"p50": at(0.50), "p95": at(0.95), "max": v.last().copied().unwrap_or(f64::NAN)})
}

pub(crate) fn loaded(
    lib: &Library,
    name: &str,
    source: &str,
) -> Result<(Engine, Value), Diagnostic> {
    let mut engine = Engine::new(lib, &SPIKE_LIMITS)?;
    let info = engine.load(name, source)?;
    Ok((engine, default_props(&info)))
}

// ---- q2 -------------------------------------------------------------------

/// §5c's module, verbatim.
pub const SECTION_5C: &str = r##"export const meta = {
  name: "Lower third",        // shown in the inspector; the file name is the id
  width: 1920, height: 1080,  // optional; default the canvas at add time (G-7)
  durationInFrames: 150,      // optional; default length of a new clip
};

export const schema = {
  title:    { type: "string",  default: "Jane Doe", label: "Title" },
  subtitle: { type: "string",  default: "Director" },
  accent:   { type: "color",   default: "#ff5a36" },
  size:     { type: "number",  default: 64, min: 12, max: 200, step: 1 },
  boxed:    { type: "boolean", default: true },
  align:    { type: "enum",    default: "left", options: ["left", "center", "right"] },
  logo:     { type: "asset",   default: null },          // a file in graphics/assets/
};

export function render(frame, props, ctx) {
  // ctx = { fps, time, durationInFrames, progress, width, height, canvas: {width, height} }
  const x = interpolate(frame, [0, 20], [-600, 80], { easing: Easing.outCubic, clamp: true });
  const s = spring({ frame: frame - 10, fps: ctx.fps, damping: 14 });
  const out = interpolate(frame, [ctx.durationInFrames - 15, ctx.durationInFrames], [1, 0], { clamp: true });
  return svg(ctx, `
    <g opacity="${out}">
      <rect x="${x}" y="${ctx.height - 260}" width="12" height="140" fill="${props.accent}"/>
      <text x="${x + 40}" y="${ctx.height - 180}" font-family="Montserrat" font-weight="800"
            font-size="${props.size}" opacity="${s}">${escapeXml(props.title)}</text>
    </g>`);
}
"##;

const FEATURES: &[(&str, &str)] = &[
    ("nullish_coalescing", "(null ?? 7) === 7"),
    (
        "optional_chaining",
        "({a: {b: 2}}).a?.b === 2 && ({}).x?.y === undefined",
    ),
    ("exponent_operator", "2 ** 10 === 1024"),
    ("template_literals", "`a${1 + 1}b` === 'a2b'"),
    ("array_at", "[1, 2, 3].at(-1) === 3"),
    ("object_hasown", "Object.hasOwn({k: 1}, 'k')"),
    (
        "string_replaceall",
        "'a.b.c'.replaceAll('.', '-') === 'a-b-c'",
    ),
    (
        "array_findlast",
        "[1, 2, 3, 4].findLast((x) => x % 2 === 1) === 3",
    ),
    ("structured_clone", "typeof structuredClone === 'function'"),
];

pub fn q2(lib: &Library) -> Result<Value, Diagnostic> {
    let mut engine = Engine::new(lib, &SPIKE_LIMITS)?;
    let agent = engine.eval_json(
        "typeof navigator === 'undefined' ? null : (navigator.userAgent === undefined ? null : navigator.userAgent)",
    )?;
    let mut features = serde_json::Map::new();
    for (name, script) in FEATURES {
        let ok = matches!(engine.eval_json(script), Ok(Value::Bool(true)));
        features.insert(name.to_string(), Value::Bool(ok));
    }
    let shape = match engine.load("section-5c", SECTION_5C) {
        Ok(info) => {
            let props = default_props(&info);
            let ctx = Ctx::at(30, 30.0, 150, 1920, 1080);
            match engine.svg(30, &props, &ctx) {
                Ok(svg) => json!({"ok": true, "meta": info.meta, "schema": info.schema,
                                  "svg_prefix": svg.chars().take(120).collect::<String>()}),
                Err(d) => {
                    json!({"ok": false, "meta": info.meta, "schema": info.schema, "error": d.to_json()})
                }
            }
        }
        Err(d) => json!({"ok": false, "error": d.to_json()}),
    };
    Ok(json!({"userAgent": agent, "features": features, "module_shape": shape}))
}

// ---- q3 -------------------------------------------------------------------

pub fn q3(
    lib: &Library,
    graphics: &[(String, String)],
    frames: i64,
    csv: &mut dyn Write,
) -> Result<Value, Diagnostic> {
    let _ = writeln!(
        csv,
        "graphic,width,height,frame,js_ms,parse_ms,raster_ms,total_ms,svg_bytes,sha256"
    );
    let mut rows = Vec::new();
    for (width, height) in [(1920u32, 1080u32), (3840, 2160)] {
        for (name, source) in graphics {
            let started = Instant::now();
            let (mut engine, props) = loaded(lib, name, source)?;
            let load_ms = ms(started);
            let (mut js, mut parse, mut raster, mut total, mut bytes) =
                (vec![], vec![], vec![], vec![], vec![]);
            let (mut identical, mut previous) = (0, String::new());
            for frame in 0..frames {
                let ctx = Ctx::at(frame, 30.0, frames, width, height);
                let t0 = Instant::now();
                let svg = engine.svg(frame, &props, &ctx)?;
                let js_ms = ms(t0);
                let r = rasterize(lib, &svg, width, height)?;
                let sum = js_ms + r.parse_ms + r.raster_ms;
                let _ = writeln!(
                    csv,
                    "{name},{width},{height},{frame},{js_ms:.4},{:.4},{:.4},{sum:.4},{},{}",
                    r.parse_ms,
                    r.raster_ms,
                    svg.len(),
                    sha(&r.bgra)
                );
                identical += usize::from(svg == previous);
                previous = svg;
                js.push(js_ms);
                parse.push(r.parse_ms);
                raster.push(r.raster_ms);
                total.push(sum);
                bytes.push(previous.len() as f64);
            }
            rows.push(json!({
                "graphic": name, "width": width, "height": height, "frames": frames,
                "load_ms": load_ms, "first_frame_ms": total[0],
                "js": summary(&js), "parse": summary(&parse), "raster": summary(&raster),
                "total": summary(&total), "svg_bytes_p50": summary(&bytes)["p50"],
                "identical_consecutive_svg": identical,
            }));
        }
    }
    Ok(json!({"rows": rows}))
}

pub(crate) struct Splitmix(pub(crate) u32);

impl Splitmix {
    pub(crate) fn next(&mut self) -> u32 {
        self.0 = self.0.wrapping_add(0x9e37_79b9);
        let mut t = self.0 ^ (self.0 >> 16);
        t = t.wrapping_mul(0x21f0_aaad);
        t ^= t >> 15;
        t = t.wrapping_mul(0x735a_2d97);
        t ^ (t >> 15)
    }
    pub(crate) fn below(&mut self, n: usize) -> usize {
        (self.next() as usize) % n
    }
}

pub fn q8(lib: &Library) -> Result<Value, Diagnostic> {
    let mut engine = Engine::new(lib, &SPIKE_LIMITS)?;
    let profile = if cfg!(debug_assertions) {
        "debug"
    } else {
        "release"
    };
    Ok(json!({"sha256": engine.math_hash()?, "profile": profile}))
}
