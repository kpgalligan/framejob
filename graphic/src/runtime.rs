//! One QuickJS runtime and context per (thread, module) — the `Engine` —
//! the thread's map of them, and `svg`, the one call that runs a module's
//! `render` (road map 10 §5b).
//!
//! A runtime never leaves the thread that made it: the map is a
//! `thread_local!`, keyed by the module's id, and an entry whose `Module`
//! has been dropped everywhere is swept before the next call on that
//! thread. The deadline is the ONE clock in the crate's `src/`: it stops a
//! call that runs too long and feeds no pixel.

use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;
use std::sync::{Arc, Mutex, Weak};
use std::time::{Duration, Instant};

use rquickjs::{Context, Function, Module as JsModule, Persistent, Runtime, Value};

use crate::diagnostic::Diagnostic;
use crate::exception::{budgeted, diagnose, returned_svg};
use crate::host;
use crate::library::Library;
use crate::module::{Inner, Module};
use crate::props::overlay;
use crate::sandbox::{NoImports, SANDBOX};

/// §5b's heap limit per runtime.
pub const HEAP_BYTES: usize = 64 << 20;
/// §5b's stack limit per runtime.
pub const STACK_BYTES: usize = 1 << 20;

const STDLIB: &str = include_str!("stdlib.js");
const NOISE: &str = include_str!("noise.js");

/// A loaded module's `meta` and `schema`, as JSON.
pub(crate) struct Exports {
    pub(crate) meta: serde_json::Value,
    pub(crate) schema: serde_json::Value,
}

/// Fields drop in DECLARATION order: the saved `render` before its
/// context, the context before its runtime — the reverse aborts in
/// QuickJS's `JS_FreeRuntime` (§5b).
pub(crate) struct Engine {
    render: Option<Persistent<Function<'static>>>,
    warnings: Rc<RefCell<Vec<String>>>,
    deadline: Arc<Mutex<Option<Instant>>>,
    context: Context,
    #[allow(dead_code)] // held, never read: it must outlive `context`
    runtime: Runtime,
}

type Entry = (Weak<Inner>, Engine);

thread_local! {
    static ENGINES: RefCell<HashMap<u64, Entry>> = RefCell::new(HashMap::new());
}

fn engine_error(e: rquickjs::Error) -> Diagnostic {
    Diagnostic::error(format!("the engine could not start: {e}"))
}

impl Engine {
    /// A runtime with §5b's limits, the host functions, the standard
    /// library and the sandbox — in that order, with no deadline.
    pub(crate) fn new(library: &Arc<Library>) -> Result<Engine, Diagnostic> {
        let runtime = Runtime::new().map_err(engine_error)?;
        runtime.set_memory_limit(HEAP_BYTES);
        runtime.set_max_stack_size(STACK_BYTES);
        let deadline: Arc<Mutex<Option<Instant>>> = Arc::new(Mutex::new(None));
        let watched = deadline.clone();
        runtime.set_interrupt_handler(Some(Box::new(
            move || matches!(*crate::library::lock(&watched), Some(at) if Instant::now() > at),
        )));
        runtime.set_loader(NoImports, NoImports);
        let context = Context::full(&runtime).map_err(engine_error)?;
        let warnings = Rc::new(RefCell::new(Vec::new()));
        context.with(|ctx| -> Result<(), Diagnostic> {
            host::install(&ctx, library, warnings.clone())?;
            for (name, script) in [
                ("stdlib.js", STDLIB),
                ("noise.js", NOISE),
                ("sandbox", SANDBOX),
            ] {
                ctx.eval::<(), _>(script)
                    .map_err(|e| diagnose(&ctx, e, name, None))?;
            }
            Ok(())
        })?;
        Ok(Engine {
            render: None,
            warnings,
            deadline,
            context,
            runtime,
        })
    }

    /// Sets the deadline `budget_ms` from now and clears the warning sink.
    fn arm(&self, budget_ms: u64) {
        self.warnings.borrow_mut().clear();
        *crate::library::lock(&self.deadline) =
            Some(Instant::now() + Duration::from_millis(budget_ms));
    }

    /// Clears the deadline; answers whether it had passed.
    fn disarm(&self) -> bool {
        let mut slot = crate::library::lock(&self.deadline);
        let expired = matches!(*slot, Some(at) if Instant::now() > at);
        *slot = None;
        expired
    }

    /// Declares and evaluates `source` as the ES module `name`, unwrapped,
    /// keeps its `render`, and answers its `meta` and `schema` (`{}` when
    /// not exported).
    pub(crate) fn load(
        &mut self,
        name: &str,
        source: &str,
        budget_ms: u64,
    ) -> Result<Exports, Diagnostic> {
        self.render = None;
        self.arm(budget_ms);
        let answer = self.context.with(|ctx| {
            let module = JsModule::declare(ctx.clone(), name, source)
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
            Ok((Persistent::save(&ctx, render), Exports { meta, schema }))
        });
        let expired = self.disarm();
        match answer {
            Ok((render, exports)) => {
                self.render = Some(render);
                Ok(exports)
            }
            Err(d) => Err(budgeted(d, expired, budget_ms)),
        }
    }

    /// One call of `render(frame, props, ctx)`; answers the SVG text and
    /// the warnings `__warn` collected during it.
    fn call(
        &mut self,
        name: &str,
        frame: i64,
        props: &serde_json::Value,
        ctx: &serde_json::Value,
        budget_ms: u64,
    ) -> Result<(String, Vec<String>), Diagnostic> {
        let render = self
            .render
            .clone()
            .ok_or_else(|| Diagnostic::error("the module exports no `render` function"))?;
        self.arm(budget_ms);
        let answer = self.context.with(|js| -> Result<String, Diagnostic> {
            let at = Some(frame);
            let render = render
                .restore(&js)
                .map_err(|e| diagnose(&js, e, name, at))?;
            let props = js
                .json_parse(props.to_string())
                .map_err(|e| diagnose(&js, e, name, at))?;
            let context = js
                .json_parse(ctx.to_string())
                .map_err(|e| diagnose(&js, e, name, at))?;
            let value: Value = render
                .call((frame as f64, props, context))
                .map_err(|e| diagnose(&js, e, name, at))?;
            returned_svg(value, frame)
        });
        let expired = self.disarm();
        let svg = answer.map_err(|d| budgeted(d, expired, budget_ms))?;
        let warnings = self.warnings.borrow_mut().drain(..).collect();
        Ok((svg, warnings))
    }
}

fn export_json<'js>(
    ctx: &rquickjs::Ctx<'js>,
    module: &JsModule<'js, rquickjs::module::Evaluated>,
    name: &str,
) -> serde_json::Value {
    let value = match module.get::<_, Value>(name) {
        Ok(value) if value.is_undefined() => return serde_json::json!({}),
        Ok(value) => value,
        Err(_) => return serde_json::json!({}),
    };
    let text = ctx
        .json_stringify(value)
        .ok()
        .flatten()
        .and_then(|s| s.to_string().ok());
    text.and_then(|t| serde_json::from_str(&t).ok())
        .unwrap_or(serde_json::Value::Null)
}

/// Removes this thread's entries whose module has been dropped everywhere,
/// and answers them so the caller drops them outside the map's borrow.
fn sweep(map: &mut HashMap<u64, Entry>) -> Vec<Entry> {
    let dead: Vec<u64> = map
        .iter()
        .filter(|(_, (weak, _))| weak.strong_count() == 0)
        .map(|(id, _)| *id)
        .collect();
    dead.into_iter().filter_map(|id| map.remove(&id)).collect()
}

/// Keeps `engine` as this thread's engine for the module `inner`.
pub(crate) fn adopt(inner: &Arc<Inner>, engine: Engine) {
    let dead = ENGINES.with(|map| {
        let mut map = map.borrow_mut();
        let dead = sweep(&mut map);
        map.insert(inner.id, (Arc::downgrade(inner), engine));
        dead
    });
    drop(dead);
}

/// Runs `f` on this thread's engine for `module`, building it by `load`
/// when this thread has none. The map is not borrowed while `f` runs.
fn with_engine<T>(
    module: &Module,
    budget_ms: u64,
    f: impl FnOnce(&mut Engine) -> Result<T, Diagnostic>,
) -> Result<T, Diagnostic> {
    let inner = module.inner();
    let (dead, found) = ENGINES.with(|map| {
        let mut map = map.borrow_mut();
        let dead = sweep(&mut map);
        (dead, map.remove(&inner.id))
    });
    drop(dead);
    let mut engine = match found {
        Some((_, engine)) => engine,
        None => {
            let mut engine = Engine::new(module.library())?;
            engine.load(module.name(), module.source(), budget_ms)?;
            engine
        }
    };
    let answer = f(&mut engine);
    adopt(inner, engine);
    answer
}

/// Runs `module`'s `render` at `frame` with `props` laid over its schema
/// (G-4) and `ctx`, under a deadline of `budget_ms`. `Ok` is the SVG text
/// and the warnings of THIS call, each stamped with `frame`.
pub fn svg(
    module: &Module,
    frame: i64,
    props: &serde_json::Value,
    ctx: &serde_json::Value,
    budget_ms: u64,
) -> Result<(String, Vec<Diagnostic>), Diagnostic> {
    if !ctx.is_object() {
        let mut d = Diagnostic::error("ctx must be a JSON object");
        d.frame = Some(frame);
        return Err(d);
    }
    let (merged, mut warnings) = overlay(module.schema(), props);
    let (text, sink) = with_engine(module, budget_ms, |engine| {
        engine.call(module.name(), frame, &merged, ctx, budget_ms)
    })
    .map_err(|mut d| {
        // A load on a thread with no engine yet fails here too; its
        // sentence already says "while loading", and it still gets a frame.
        d.frame.get_or_insert(frame);
        d
    })?;
    warnings.extend(sink.into_iter().map(Diagnostic::warning));
    for w in &mut warnings {
        w.frame = Some(frame);
    }
    Ok((text, warnings))
}

/// The engines held on THIS thread, including dropped modules' not yet
/// swept by the next `svg`/`compile`.
pub fn engine_count() -> usize {
    ENGINES.with(|map| map.borrow().len())
}
