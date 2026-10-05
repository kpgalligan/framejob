//! One QuickJS runtime and context per (thread, module) — the `Engine` —
//! the thread's map of them, and `svg`, the one call that runs a module's
//! `render` (road map 10 §5b).
//!
//! A runtime never leaves the thread that made it: the map is a
//! `thread_local!`, keyed by the module's id, and an entry whose `Module`
//! has been dropped everywhere is swept before the next call on that
//! thread. The map holds at most `ENGINES_PER_THREAD` engines: each is
//! stamped with a use counter when it is adopted, and the least recently
//! used past the cap are evicted after the call, to be loaded again on
//! their next frame (spec §11 G-21 (a)). What `__warn` collects while a
//! module's top level evaluates is drained by `load` (G-21 (b)). The
//! deadline is the ONE clock in the crate's `src/`: it stops a call that
//! runs too long and feeds no pixel.

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
/// The most SVG `render` may answer, in bytes (spec §11 G-20 (c)).
pub const SVG_BYTES: usize = 8 << 20;
/// The most engines one thread holds (spec §11 G-21 (a)).
pub const ENGINES_PER_THREAD: usize = 16;

const STDLIB: &str = include_str!("stdlib.js");
const NOISE: &str = include_str!("noise.js");
const PATH: &str = include_str!("path.js");

/// A loaded module's `meta` and `schema`, as JSON, and what `__warn`
/// collected while its top level evaluated, in order.
pub(crate) struct Exports {
    pub(crate) meta: serde_json::Value,
    pub(crate) schema: serde_json::Value,
    pub(crate) warnings: Vec<String>,
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

/// The module, the use stamp of the entry's last adoption, its engine.
type Entry = (Weak<Inner>, u64, Engine);

/// This thread's engines by module id, and the use counter that stamps
/// them — a count of adoptions, not a clock.
#[derive(Default)]
struct Engines {
    map: HashMap<u64, Entry>,
    uses: u64,
}

thread_local! {
    static ENGINES: RefCell<Engines> = RefCell::new(Engines::default());
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
                ("path.js", PATH),
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
    /// not exported) and the warnings its top level raised.
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
            Ok((Persistent::save(&ctx, render), (meta, schema)))
        });
        let expired = self.disarm();
        match answer {
            Ok((render, (meta, schema))) => {
                self.render = Some(render);
                let warnings = self.warnings.borrow_mut().drain(..).collect();
                Ok(Exports {
                    meta,
                    schema,
                    warnings,
                })
            }
            Err(d) => Err(budgeted(d, expired, budget_ms)),
        }
    }

    /// Whether the standard library's `__parseColour` takes each of `texts`
    /// (G-12), under ONE deadline of `budget_ms`: a throw, or a call the
    /// deadline had already passed, is false (spec §11 G-25). Stores nothing.
    pub(crate) fn parse_colours(&self, texts: &[String], budget_ms: u64) -> Vec<bool> {
        self.arm(budget_ms);
        let answer = self.context.with(|ctx| {
            let parse: Option<Function> = ctx.globals().get("__parseColour").ok();
            texts
                .iter()
                .map(|text| {
                    let deadline = *crate::library::lock(&self.deadline);
                    let late = deadline.is_some_and(|at| Instant::now() > at);
                    let Some(parse) = parse.as_ref().filter(|_| !late) else {
                        return false;
                    };
                    let taken = parse.call::<_, Value>((text.as_str(),)).is_ok();
                    if !taken {
                        let _ = ctx.catch();
                    }
                    taken
                })
                .collect()
        });
        self.disarm();
        answer
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
        .filter(|(_, (weak, _, _))| weak.strong_count() == 0)
        .map(|(id, _)| *id)
        .collect();
    dead.into_iter().filter_map(|id| map.remove(&id)).collect()
}

/// Removes the least recently used entries while the map holds more than
/// `ENGINES_PER_THREAD`, and answers them so the caller drops them outside
/// the map's borrow. The entry adopted last holds the highest stamp, so it
/// is never one of them.
fn evict(map: &mut HashMap<u64, Entry>) -> Vec<Entry> {
    let mut evicted = Vec::new();
    while map.len() > ENGINES_PER_THREAD {
        let oldest = map
            .iter()
            .min_by_key(|(_, (_, stamp, _))| *stamp)
            .map(|(id, _)| *id);
        match oldest.and_then(|id| map.remove(&id)) {
            Some(entry) => evicted.push(entry),
            None => break,
        }
    }
    evicted
}

/// Keeps `engine` as this thread's engine for the module `inner`, stamped
/// as the most recently used, and evicts past `ENGINES_PER_THREAD`.
pub(crate) fn adopt(inner: &Arc<Inner>, engine: Engine) {
    let (dead, evicted) = ENGINES.with(|engines| {
        let mut engines = engines.borrow_mut();
        let dead = sweep(&mut engines.map);
        engines.uses += 1;
        let stamp = engines.uses;
        engines
            .map
            .insert(inner.id, (Arc::downgrade(inner), stamp, engine));
        let evicted = evict(&mut engines.map);
        (dead, evicted)
    });
    drop(dead);
    drop(evicted);
}

/// Runs `f` on this thread's engine for `module`, building it by `load`
/// when this thread has none. The map is not borrowed while `f` runs.
fn with_engine<T>(
    module: &Module,
    budget_ms: u64,
    f: impl FnOnce(&mut Engine) -> Result<T, Diagnostic>,
) -> Result<T, Diagnostic> {
    let inner = module.inner();
    let (dead, found) = ENGINES.with(|engines| {
        let mut engines = engines.borrow_mut();
        let dead = sweep(&mut engines.map);
        let found = engines.map.remove(&inner.id);
        (dead, found)
    });
    drop(dead);
    let mut engine = match found {
        Some((_, _, engine)) => engine,
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

/// The engines held on THIS thread, at most `ENGINES_PER_THREAD` after
/// any `svg`/`compile`, including dropped modules' not yet swept by the
/// next one.
pub fn engine_count() -> usize {
    ENGINES.with(|engines| engines.borrow().map.len())
}
