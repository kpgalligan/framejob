"""q1 and q9 of road map 10 §3: the spike crate as a path dependency of
`framejob-core`, measured against the tree at c874069, then REVERTED.

Every build and test runs under `bounded.run` (600 s). The four core files
are patched only between `patch()` and `revert()`, and `revert()` always
runs (the runner calls it in a `finally`); its git check is part of the
answer."""

import os
import re
import shutil
import sys

import bounded
from rows_local import FONTS, GRAPHICS, REPO, SPIKE, WORK, binary

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import proof_app  # noqa: E402

BASE = "c874069"
CORE = os.path.join(REPO, "core")
OUTCOME = os.path.join(CORE, "src", "outcome.rs")
LIB_A = os.path.join(CORE, "target", "release", "libframejob_core.a")
APP = os.path.join(REPO, "build", "Build", "Products", "Release", "Frame Job.app")
APP_BINARY = str(proof_app.executable(APP))
SPIKE_TOML = os.path.join(SPIKE, "Cargo.toml")
BOUND = 600

FFI_GRAPHIC = '''//! THROWAWAY — road map 10 G0's q1 and q9 (tools/proof/graphics_spike).
//! Written by `rows_build.patch()` and deleted by `rows_build.revert()`;
//! declared only in the spike's `q9_probe.h`, never in the header.

use std::ffi::{c_char, CStr, CString};

use graphics_spike::{default_props, render_frame, Ctx, Engine, Library, SPIKE_LIMITS};

unsafe fn fail(err_out: *mut *mut c_char, message: String) -> *mut c_char {
    if !err_out.is_null() {
        *err_out = CString::new(message).unwrap_or_default().into_raw();
    }
    std::ptr::null_mut()
}

/// # Safety
/// `source` is NUL-terminated; `font_bytes` holds `font_len` bytes or is
/// NULL; `err_out` is NULL or writable.
#[no_mangle]
pub unsafe extern "C" fn rc_graphic_spike_render(
    source: *const c_char,
    frame: i64,
    width: u32,
    height: u32,
    font_bytes: *const u8,
    font_len: usize,
    err_out: *mut *mut c_char,
) -> *mut c_char {
    if source.is_null() {
        return fail(err_out, "source is NULL".into());
    }
    let Ok(source) = CStr::from_ptr(source).to_str() else {
        return fail(err_out, "source is not UTF-8".into());
    };
    let fonts = if font_bytes.is_null() {
        vec![]
    } else {
        vec![std::slice::from_raw_parts(font_bytes, font_len).to_vec()]
    };
    let answer = std::panic::catch_unwind(|| {
        let library = Library::new(&fonts);
        let mut engine = Engine::new(&library, &SPIKE_LIMITS)?;
        let info = engine.load("graphic", source)?;
        let ctx = Ctx::at(frame, 30.0, 300, width, height);
        render_frame(&mut engine, &library, frame, &default_props(&info), &ctx, width, height)
    });
    match answer {
        Ok(Ok(timed)) => CString::new(timed.to_json().to_string()).unwrap_or_default().into_raw(),
        Ok(Err(d)) => fail(err_out, d.message),
        Err(_) => fail(err_out, "internal error: the spike engine panicked".into()),
    }
}
'''


def run(argv, cwd=REPO):
    return bounded.run(argv, BOUND, cwd=cwd)


def git_check():
    diff = run(["git", "diff", BASE, "--stat", "--", "core", "app"])
    status = run(["git", "status", "--short", "--", "core", "app"])
    return {"diff_stat": diff["stdout"], "status_short": status["stdout"],
            "clean": diff["stdout"].strip() == "" and status["stdout"].strip() == ""}


def tests_passed(output):
    passed = sum(int(n) for n in re.findall(r"test result: ok\. (\d+) passed", output))
    failed = len(re.findall(r"test result: FAILED", output))
    return passed, failed


def timed(label, argv, cwd, say, out):
    result = run(argv, cwd)
    entry = {"seconds": result["seconds"], "rc": result["rc"], "expired": result["expired"]}
    if argv[:2] == ["make", "test"]:
        entry["passed"], entry["failed_binaries"] = tests_passed(result["stdout"] + result["stderr"])
    if result["rc"] != 0:
        entry["tail"] = (result["stdout"] + result["stderr"])[-3000:]
    out[label] = entry
    say(f"    {label}: rc {result['rc']} in {result['seconds']} s"
        + (f", {entry.get('passed')} tests passed" if "passed" in entry else ""))
    return result["rc"] == 0


def staticlib():
    if not os.path.exists(LIB_A):
        return None
    members = run(["ar", "t", LIB_A])["stdout"].splitlines()
    return {"bytes": os.path.getsize(LIB_A), "members": len(members)}


def app_sizes():
    if not os.path.exists(APP_BINARY):
        return None
    du = run(["du", "-sk", APP])["stdout"].split()
    return {"app_kib": int(du[0]) if du else None, "binary_bytes": os.path.getsize(APP_BINARY)}


def measure(label, say):
    """Cold build, `make test`, the remaining-§6 warm edit, `make test`
    again, the staticlib, `make app`, the app — one side of q1."""
    say(f"  q1 {label}:")
    out = {}
    shutil.rmtree(os.path.join(CORE, "target"), ignore_errors=True)
    timed("cold_build", ["cargo", "build", "--release"], CORE, say, out)
    timed("make_test_first", ["make", "test"], REPO, say, out)
    with open(OUTCOME, "rb") as handle:
        original = handle.read()
    try:
        with open(OUTCOME, "wb") as handle:
            handle.write(b"// graphics spike q1: a warm-edit comment, removed again\n" + original)
        timed("warm_build", ["cargo", "build", "--release"], CORE, say, out)
        timed("make_test_after_edit", ["make", "test"], REPO, say, out)
    finally:
        with open(OUTCOME, "wb") as handle:
            handle.write(original)
    out["staticlib"] = staticlib()
    timed("make_app", ["make", "app"], REPO, say, out)
    out["app"] = app_sizes()
    say(f"    staticlib {out['staticlib']}, app {out['app']}")
    return out


def patch(say):
    with open(os.path.join(CORE, "Cargo.toml")) as handle:
        toml = handle.read()
    toml = toml.replace('tiny_http = "0.12"\n',
                        'tiny_http = "0.12"\ngraphics_spike = { path = "../tools/proof/graphics_spike" }\n')
    with open(os.path.join(CORE, "Cargo.toml"), "w") as handle:
        handle.write(toml)
    lib = os.path.join(CORE, "src", "lib.rs")
    with open(lib) as handle:
        body = handle.read()
    with open(lib, "w") as handle:
        handle.write(body.replace("pub mod ffi_edit;\n", "pub mod ffi_edit;\npub mod ffi_graphic;\n"))
    with open(os.path.join(CORE, "src", "ffi_graphic.rs"), "w") as handle:
        handle.write(FFI_GRAPHIC)
    say("  patched core/Cargo.toml, core/src/lib.rs, core/src/ffi_graphic.rs (Cargo.lock follows)")


def raster_images(say):
    """q1c: `raster-images` ON in the spike's Cargo.toml, one warm core
    build and the staticlib, then the exact bytes back."""
    with open(SPIKE_TOML) as handle:
        original = handle.read()
    out = {}
    try:
        with open(SPIKE_TOML, "w") as handle:
            handle.write(original.replace('features = ["text"]', 'features = ["text", "raster-images"]'))
        timed("warm_build_raster_images", ["cargo", "build", "--release"], CORE, say, out)
        out["staticlib"] = staticlib()
    finally:
        with open(SPIKE_TOML, "w") as handle:
            handle.write(original)
    timed("rebuild_without", ["cargo", "build", "--release"], CORE, say, out)
    out["staticlib_after_flip_back"] = staticlib()
    say(f"    q1c: staticlib with raster-images {out['staticlib']}")
    return out


def revert(say):
    checkout = run(["git", "checkout", BASE, "--", "core/Cargo.toml", "core/Cargo.lock", "core/src/lib.rs"])
    ffi = os.path.join(CORE, "src", "ffi_graphic.rs")
    if os.path.exists(ffi):
        os.remove(ffi)
    out = {"checkout_rc": checkout["rc"]}
    timed("core_build", ["cargo", "build", "--release"], CORE, say, out)
    timed("make_app", ["make", "app"], REPO, say, out)
    out["git_check"] = git_check()
    say(f"  revert: git check clean = {out['git_check']['clean']}")
    return out


def q1(say):
    before = git_check()
    if not before["clean"]:
        return {"state": "failed", "reason": f"core/ or app/ differs from {BASE} before q1",
                "measured": {"git_check": before}}
    baseline = measure("BASELINE at c874069", say)
    patch(say)
    patched = measure("PATCHED (graphics_spike as a path dependency)", say)
    q1c = raster_images(say)
    measured = {"baseline": baseline, "patched": patched, "q1c_raster_images": q1c}
    ok = all(v.get("rc") == 0 for side in (baseline, patched) for v in side.values()
             if isinstance(v, dict) and "rc" in v)
    return {"state": "run" if ok else "failed",
            "reason": None if ok else "a build or test step failed; see measured",
            "measured": measured}


def q9(say):
    """While patched: the symbol in the archive, two Swift links, the call,
    and the reference render from the same one-font set."""
    out = {}
    timed("core_build", ["cargo", "build", "--release"], CORE, say, out)
    nm = run(["nm", "-g", LIB_A])["stdout"]
    out["archive_rc_graphic_spike_render"] = nm.count("rc_graphic_spike_render")
    out["archive_JS_NewRuntime"] = nm.count("JS_NewRuntime")
    bin_dir = os.path.join(WORK, "q9")
    os.makedirs(bin_dir, exist_ok=True)
    probes = {}
    for label, extra in (("engine", []), ("control", ["-D", "CONTROL"])):
        target = os.path.join(bin_dir, f"q9_probe_{label}")
        argv = (["xcrun", "swiftc", "-O", "-target", "arm64-apple-macos26.0",
                 "-import-objc-header", os.path.join(SPIKE, "q9_probe.h"),
                 "-L", os.path.join(CORE, "target", "release"), "-lframejob_core"] + extra
                + [os.path.join(SPIKE, "q9_probe.swift"), "-o", target])
        result = run(argv)
        probes[label] = {"rc": result["rc"], "seconds": result["seconds"],
                         "bytes": os.path.getsize(target) if os.path.exists(target) else None}
        if result["rc"] != 0:
            probes[label]["stderr"] = result["stderr"][-3000:]
    for label in probes:
        target = os.path.join(bin_dir, f"q9_probe_{label}")
        symbols = run(["nm", target])["stdout"] if os.path.exists(target) else ""
        probes[label]["JS_NewRuntime"] = symbols.count("JS_NewRuntime")
        probes[label]["rc_graphic_spike_render"] = symbols.count("rc_graphic_spike_render")
    out["probes"] = probes
    if probes["engine"]["bytes"] and probes["control"]["bytes"]:
        out["engine_linked_bytes"] = probes["engine"]["bytes"] - probes["control"]["bytes"]
    font = os.path.join(FONTS, "Montserrat-ExtraBold.ttf")
    fonts_dir = os.path.join(WORK, "q9_fonts")
    shutil.rmtree(fonts_dir, ignore_errors=True)
    os.makedirs(fonts_dir)
    shutil.copy(font, fonts_dir)
    module = os.path.join(GRAPHICS, "lower-third.js")
    import json
    call = run([os.path.join(bin_dir, "q9_probe_engine"), module, "30", "1920", "1080", font])
    control = run([os.path.join(bin_dir, "q9_probe_control")])
    reference = run([binary(), "render", "--graphics", GRAPHICS, "--fonts", fonts_dir,
                     "--name", "lower-third", "--frame", "30", "--width", "1920", "--height", "1080"])

    def parsed(result):
        try:
            return json.loads(result["stdout"].strip().splitlines()[-1])
        except (IndexError, json.JSONDecodeError):
            return {"rc": result["rc"], "stderr": result["stderr"][-1500:]}
    out["call"] = parsed(call)
    out["control_call"] = parsed(control)
    out["reference"] = parsed(reference)
    swift_sha = (out["call"].get("timed") or {}).get("sha256") if isinstance(out["call"].get("timed"), dict) else None
    out["sha256_equal"] = swift_sha is not None and swift_sha == out["reference"].get("sha256")
    app_nm = run(["nm", APP_BINARY])["stdout"] if os.path.exists(APP_BINARY) else ""
    out["app_rc_graphic_spike_render"] = app_nm.count("rc_graphic_spike_render")
    out["app_JS_NewRuntime"] = app_nm.count("JS_NewRuntime")
    say(f"  q9: archive symbol ×{out['archive_rc_graphic_spike_render']}, Swift call sha equal "
        f"{out['sha256_equal']}, engine linked bytes {out.get('engine_linked_bytes')}, app keeps "
        f"×{out['app_rc_graphic_spike_render']}")
    ok = probes["engine"]["rc"] == 0 and probes["control"]["rc"] == 0 and swift_sha is not None
    return {"state": "run" if ok else "failed",
            "reason": None if ok else "a probe did not build or did not answer", "measured": out}
