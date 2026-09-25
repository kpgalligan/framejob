//! G-5's sandbox (road map 10 §5b): the script evaluated after the standard
//! library that freezes the clock and removes randomness and every second
//! source of code, and the module loader that resolves no specifier.

use rquickjs::loader::{ImportAttributes, Loader, Resolver};
use rquickjs::module::Declared;
use rquickjs::Module;

/// The sentence an `import` of any specifier is refused with; QuickJS
/// prefixes it with `Error resolving module '<x>' from '<name>': `.
pub(crate) const IMPORT_REFUSAL: &str =
    "imports are not available in a graphic; the standard library is global";

/// Evaluated as a script, last: `Date` frozen at 2000-01-01T00:00:00Z (its
/// prototype's `constructor` too), `Math.random` throwing, `eval`,
/// `Function` and the three other function-kind constructors gone,
/// `WebAssembly` and `performance` (`JS_NewContext` installs a clock there)
/// deleted.
pub(crate) const SANDBOX: &str = r#"
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
  delete globalThis.performance;
})();
"#;

/// The resolver and loader of every engine: both refuse.
pub(crate) struct NoImports;

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
