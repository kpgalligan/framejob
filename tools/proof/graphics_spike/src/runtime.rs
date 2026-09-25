//! One QuickJS runtime and context per `Engine`, the sandbox of road map 10
//! G-5, the standard library evaluated in, the ES-module load and `svg()`.
//!
//! An `Engine` is `!Send`: it lives on the thread that made it, which is
//! also the thread whose stack QuickJS measured at `Runtime::new`.

use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use rquickjs::loader::{ImportAttributes, Loader, Resolver};
use rquickjs::module::Declared;
use rquickjs::{Context, Function, Module, Persistent, Runtime, Value};
use sha2::{Digest, Sha256};

use crate::diagnostic::{budgeted, diagnose, returned_svg, Diagnostic};
use crate::raster::{measure_text, Library};

/// §5b's limits. `budget_ms` is the interrupt deadline of one call.
pub struct Limits {
    pub heap_bytes: usize,
    pub stack_bytes: usize,
    pub budget_ms: u64,
}

pub const SPIKE_LIMITS: Limits = Limits {
    heap_bytes: 64 << 20,
    stack_bytes: 1 << 20,
    budget_ms: 250,
};

/// §5c's `ctx`.
#[derive(Debug, Clone)]
pub struct Ctx {
    pub fps: f64,
    pub time: f64,
    pub duration_in_frames: i64,
    pub progress: f64,
    pub width: u32,
    pub height: u32,
    pub canvas: (u32, u32),
}

impl Ctx {
    /// The ctx of `frame` on a `duration`-frame graphic at `fps`, the
    /// graphic the size of the canvas — what every row of the spike uses.
    pub fn at(frame: i64, fps: f64, duration: i64, width: u32, height: u32) -> Ctx {
        let progress = (frame as f64 / ((duration - 1).max(1)) as f64).clamp(0.0, 1.0);
        Ctx {
            fps,
            time: frame as f64 / fps,
            duration_in_frames: duration,
            progress,
            width,
            height,
            canvas: (width, height),
        }
    }

    pub fn to_json(&self) -> serde_json::Value {
        serde_json::json!({
            "fps": self.fps, "time": self.time, "durationInFrames": self.duration_in_frames,
            "progress": self.progress, "width": self.width, "height": self.height,
            "canvas": {"width": self.canvas.0, "height": self.canvas.1},
        })
    }
}

pub struct ModuleInfo {
    pub meta: serde_json::Value,
    pub schema: serde_json::Value,
}

/// The schema's defaults, key by key (G-4's overlay with nothing stored).
pub fn default_props(info: &ModuleInfo) -> serde_json::Value {
    let mut props = serde_json::Map::new();
    if let Some(schema) = info.schema.as_object() {
        for (key, entry) in schema {
            let value = entry
                .get("default")
                .cloned()
                .unwrap_or(serde_json::Value::Null);
            props.insert(key.clone(), value);
        }
    }
    serde_json::Value::Object(props)
}

const IMPORT_REFUSAL: &str =
    "imports are not available in a graphic; the standard library is global";

struct NoImports;

impl Resolver for NoImports {
    fn resolve<'js>(
        &mut self,
        _ctx: &rquickjs::Ctx<'js>,
        base: &str,
        name: &str,
        _attributes: Option<ImportAttributes<'js>>,
    ) -> rquickjs::Result<String> {
        Err(rquickjs::Error::new_resolving_message(
            base,
            name,
            IMPORT_REFUSAL,
        ))
    }
}

impl Loader for NoImports {
    fn load<'js>(
        &mut self,
        _ctx: &rquickjs::Ctx<'js>,
        name: &str,
        _attributes: Option<ImportAttributes<'js>>,
    ) -> rquickjs::Result<Module<'js, Declared>> {
        Err(rquickjs::Error::new_loading_message(name, IMPORT_REFUSAL))
    }
}

/// G-5, after the standard library: the clock frozen, randomness and the
/// second sources of code removed.
const SANDBOX: &str = r#"
(() => {
  const RealDate = Date;
  const EPOCH = 946684800000;
  function FrozenDate(...args) {
    if (!new.target) return new RealDate(EPOCH).toString();
    return args.length ? new RealDate(...args) : new RealDate(EPOCH);
  }
  FrozenDate.now = () => EPOCH;
  FrozenDate.UTC = RealDate.UTC;
  FrozenDate.parse = RealDate.parse;
  FrozenDate.prototype = RealDate.prototype;
  Object.defineProperty(RealDate.prototype, "constructor", { value: FrozenDate });
  globalThis.Date = FrozenDate;
  Math.random = function () { throw new Error("Math.random is not available; use random(seed)"); };
  const refuse = function () { throw new Error("Function is not available in a graphic; the module is the one source of code"); };
  Object.defineProperty(Function.prototype, "constructor", { value: refuse });
  for (const f of [async function () {}, function* () {}, async function* () {}]) {
    Object.defineProperty(Object.getPrototypeOf(f), "constructor", { value: refuse });
  }
  delete globalThis.eval;
  globalThis.Function = refuse;
  delete globalThis.WebAssembly;
})();
"#;

const STDLIB: &str = include_str!("stdlib.js");

/// Fields drop in order: the saved `render` before its context, the
/// context before its runtime (QuickJS asserts an empty GC list).
pub struct Engine {
    render: Option<Persistent<Function<'static>>>,
    name: String,
    deadline: Arc<Mutex<Option<Instant>>>,
    budget: Duration,
    context: Context,
    _runtime: Runtime,
}

impl Engine {
    pub fn new(library: &Library, limits: &Limits) -> Result<Engine, Diagnostic> {
        let runtime = Runtime::new().map_err(|e| Diagnostic::error(e.to_string()))?;
        runtime.set_memory_limit(limits.heap_bytes);
        runtime.set_max_stack_size(limits.stack_bytes);
        let deadline: Arc<Mutex<Option<Instant>>> = Arc::new(Mutex::new(None));
        let watched = deadline.clone();
        runtime.set_interrupt_handler(Some(Box::new(
            move || matches!(*watched.lock().unwrap(), Some(at) if Instant::now() > at),
        )));
        runtime.set_loader(NoImports, NoImports);
        let context = Context::full(&runtime).map_err(|e| Diagnostic::error(e.to_string()))?;
        let fonts = library.clone();
        context.with(|ctx| -> Result<(), Diagnostic> {
            let measure = Function::new(
                ctx.clone(),
                move |text: String, family: String, size: f64, weight: f64, style: String| {
                    match measure_text(&fonts, &text, &family, size, weight as u16, &style) {
                        Ok(m) => serde_json::json!({
                            "width": m.width, "x": m.x, "ascent": m.ascent, "descent": m.descent,
                            "lineHeight": m.line_height, "inkWidth": m.ink_width, "inkX": m.ink_x,
                        })
                        .to_string(),
                        Err(d) => serde_json::json!({ "error": d.message }).to_string(),
                    }
                },
            )
            .map_err(|e| Diagnostic::error(e.to_string()))?;
            ctx.globals()
                .set("__measureText", measure)
                .map_err(|e| Diagnostic::error(e.to_string()))?;
            ctx.eval::<(), _>(STDLIB)
                .map_err(|e| diagnose(&ctx, e, "stdlib.js", None))?;
            ctx.eval::<(), _>(SANDBOX)
                .map_err(|e| diagnose(&ctx, e, "sandbox", None))
        })?;
        Ok(Engine {
            render: None,
            name: String::new(),
            deadline,
            budget: Duration::from_millis(limits.budget_ms),
            context,
            _runtime: runtime,
        })
    }

    fn arm(&self) {
        *self.deadline.lock().unwrap() = Some(Instant::now() + self.budget);
    }

    fn disarm(&self) -> bool {
        let mut slot = self.deadline.lock().unwrap();
        let expired = matches!(*slot, Some(at) if Instant::now() > at);
        *slot = None;
        expired
    }

    /// Evaluates `source` as an ES module named `name`, once, and keeps its
    /// `render`; answers its `meta` and `schema`.
    pub fn load(&mut self, name: &str, source: &str) -> Result<ModuleInfo, Diagnostic> {
        self.render = None;
        self.name = name.to_string();
        self.arm();
        let answer = self.context.with(|ctx| {
            let module = Module::declare(ctx.clone(), name, source)
                .map_err(|e| diagnose(&ctx, e, name, None))?;
            let (module, promise) = module.eval().map_err(|e| diagnose(&ctx, e, name, None))?;
            promise
                .finish::<()>()
                .map_err(|e| diagnose(&ctx, e, name, None))?;
            let render: Function = module
                .get("render")
                .map_err(|_| Diagnostic::error("the module exports no `render` function"))?;
            let meta = export_json(&ctx, &module, "meta");
            let schema = export_json(&ctx, &module, "schema");
            Ok((Persistent::save(&ctx, render), ModuleInfo { meta, schema }))
        });
        let expired = self.disarm();
        match answer {
            Ok((render, info)) => {
                self.render = Some(render);
                Ok(info)
            }
            Err(d) => Err(budgeted(d, expired, self.budget)),
        }
    }

    /// One call of `render(frame, props, ctx)`; the string must start `<svg`.
    pub fn svg(
        &mut self,
        frame: i64,
        props: &serde_json::Value,
        ctx: &Ctx,
    ) -> Result<String, Diagnostic> {
        let render = self
            .render
            .clone()
            .ok_or_else(|| Diagnostic::error("no module is loaded"))?;
        let name = self.name.clone();
        self.arm();
        let answer = self.context.with(|js| -> Result<String, Diagnostic> {
            let at = Some(frame);
            let render = render
                .restore(&js)
                .map_err(|e| diagnose(&js, e, &name, at))?;
            let props = js
                .json_parse(props.to_string())
                .map_err(|e| diagnose(&js, e, &name, at))?;
            let context = js
                .json_parse(ctx.to_json().to_string())
                .map_err(|e| diagnose(&js, e, &name, at))?;
            let value: Value = render
                .call((frame as f64, props, context))
                .map_err(|e| diagnose(&js, e, &name, at))?;
            returned_svg(value, frame)
        });
        let expired = self.disarm();
        answer.map_err(|d| budgeted(d, expired, self.budget))
    }

    /// Evaluates a script in the sandboxed context and answers its result
    /// JSON-stringified (q2's feature probes; q6 does not use it).
    pub fn eval_json(&mut self, script: &str) -> Result<serde_json::Value, Diagnostic> {
        self.arm();
        let answer = self.context.with(|ctx| {
            let value: Value = ctx
                .eval(script)
                .map_err(|e| diagnose(&ctx, e, "script", None))?;
            Ok(value_json(&ctx, value))
        });
        let expired = self.disarm();
        answer.map_err(|d| budgeted(d, expired, self.budget))
    }

    /// q8: SHA-256 over the big-endian f64 bit patterns of 10 000 results
    /// of `Math.sin/cos/tan/pow/exp/log`.
    pub fn math_hash(&mut self) -> Result<String, Diagnostic> {
        let script = r#"
          (() => {
            const view = new DataView(new ArrayBuffer(8));
            const hex = (v) => { view.setFloat64(0, v);
              return view.getUint32(0).toString(16).padStart(8, "0") +
                     view.getUint32(4).toString(16).padStart(8, "0"); };
            let out = "";
            for (let i = 0; i < 2000; i++) {
              const x = i * 0.3719 - 371.9;
              out += hex(Math.sin(x)) + hex(Math.cos(x)) + hex(Math.tan(x)) +
                     hex(Math.pow(1.0003 + i * 1e-4, x / 7)) +
                     hex(Math.exp(x / 50) + Math.log(i + 0.5));
            }
            return out;
          })()"#;
        let hex = self
            .eval_json(script)?
            .as_str()
            .map(str::to_string)
            .ok_or_else(|| Diagnostic::error("math script returned no string"))?;
        let mut bytes = Vec::with_capacity(hex.len() / 2);
        for pair in hex.as_bytes().chunks(2) {
            let text = std::str::from_utf8(pair).unwrap_or("00");
            bytes.push(u8::from_str_radix(text, 16).unwrap_or(0));
        }
        Ok(hex_digest(&Sha256::digest(&bytes)))
    }
}

pub(crate) fn hex_digest(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn export_json<'js>(
    ctx: &rquickjs::Ctx<'js>,
    module: &Module<'js, rquickjs::module::Evaluated>,
    name: &str,
) -> serde_json::Value {
    match module.get::<_, Value>(name) {
        Ok(value) => value_json(ctx, value),
        Err(_) => serde_json::Value::Null,
    }
}

fn value_json<'js>(ctx: &rquickjs::Ctx<'js>, value: Value<'js>) -> serde_json::Value {
    let text = ctx
        .json_stringify(value)
        .ok()
        .flatten()
        .and_then(|s| s.to_string().ok());
    text.and_then(|t| serde_json::from_str(&t).ok())
        .unwrap_or(serde_json::Value::Null)
}
