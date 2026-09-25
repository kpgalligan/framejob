//! The spike's CLI: every subcommand prints ONE JSON object on stdout.

use std::path::{Path, PathBuf};

use graphics_spike::{
    default_props, mutant, q2, q3, q4, q5, q6, q8, render_frame, Ctx, Diagnostic, Engine, Library,
    SPIKE_LIMITS,
};
use serde_json::{json, Value};

fn flag(args: &[String], name: &str) -> Option<String> {
    args.iter()
        .position(|a| a == name)
        .and_then(|i| args.get(i + 1))
        .cloned()
}

fn files(dir: &str, extension: &str) -> Vec<PathBuf> {
    let mut found: Vec<PathBuf> = std::fs::read_dir(dir)
        .map(|entries| {
            entries
                .filter_map(|e| e.ok().map(|e| e.path()))
                .filter(|p| p.extension().and_then(|x| x.to_str()) == Some(extension))
                .collect()
        })
        .unwrap_or_default();
    found.sort();
    found
}

fn library(args: &[String]) -> Library {
    let fonts: Vec<Vec<u8>> = flag(args, "--fonts")
        .map(|dir| files(&dir, "ttf"))
        .unwrap_or_default()
        .iter()
        .filter_map(|p| std::fs::read(p).ok())
        .collect();
    Library::new(&fonts)
}

fn stem(path: &Path) -> String {
    path.file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_string()
}

fn graphics(args: &[String]) -> Vec<(String, String)> {
    flag(args, "--graphics")
        .map(|dir| files(&dir, "js"))
        .unwrap_or_default()
        .iter()
        .filter_map(|p| std::fs::read_to_string(p).ok().map(|s| (stem(p), s)))
        .collect()
}

fn source(args: &[String], name: &str) -> Result<String, Diagnostic> {
    graphics(args)
        .into_iter()
        .find(|g| g.0 == name)
        .map(|g| g.1)
        .ok_or_else(|| Diagnostic::error(format!("no graphic {name} in --graphics")))
}

fn number(args: &[String], name: &str, default: i64) -> i64 {
    flag(args, name)
        .and_then(|v| v.parse().ok())
        .unwrap_or(default)
}

fn render(args: &[String]) -> Result<Value, Diagnostic> {
    let lib = library(args);
    let name = flag(args, "--name").unwrap_or_default();
    let (frame, w, h) = (
        number(args, "--frame", 0),
        number(args, "--width", 1920) as u32,
        number(args, "--height", 1080) as u32,
    );
    let mut engine = Engine::new(&lib, &SPIKE_LIMITS)?;
    let info = engine.load(&name, &source(args, &name)?)?;
    let props = default_props(&info);
    let ctx = Ctx::at(frame, 30.0, 300, w, h);
    let timed = render_frame(&mut engine, &lib, frame, &props, &ctx, w, h)?;
    if let Some(png) = flag(args, "--png") {
        let svg = engine.svg(frame, &props, &ctx)?;
        let raster = graphics_spike::rasterize(&lib, &svg, w, h)?;
        let mut rgba = raster.bgra;
        for pixel in rgba.chunks_exact_mut(4) {
            pixel.swap(0, 2);
        }
        let size = resvg::tiny_skia::IntSize::from_wh(w, h).unwrap();
        let pixmap = resvg::tiny_skia::Pixmap::from_vec(rgba, size).unwrap();
        pixmap
            .save_png(&png)
            .map_err(|e| Diagnostic::error(e.to_string()))?;
    }
    let mut out = timed.to_json();
    out["families"] = json!(lib.families());
    Ok(out)
}

fn run(args: &[String]) -> Result<Value, Diagnostic> {
    match args.first().map(String::as_str) {
        Some("q2") => q2(&library(args)),
        Some("q3") => {
            let path = flag(args, "--csv").unwrap_or_else(|| "q3.csv".into());
            let mut csv =
                std::fs::File::create(&path).map_err(|e| Diagnostic::error(e.to_string()))?;
            q3(
                &library(args),
                &graphics(args),
                number(args, "--frames", 300),
                &mut csv,
            )
        }
        Some("q4") => q4(&library(args)),
        Some("q5") => {
            let mut set = graphics(args);
            let is_mutant = args.iter().any(|a| a == "--mutant");
            if is_mutant {
                for g in set.iter_mut().filter(|g| g.0 == "counter") {
                    g.1 = mutant(&g.1);
                }
            }
            let mut out = q5(&library(args), &set)?;
            out["mutant"] = json!(is_mutant);
            Ok(out)
        }
        Some("q6") => {
            let case = flag(args, "--case").unwrap_or_default();
            q6(&library(args), &case, &source(args, "lower-third")?)
        }
        Some("q8") => q8(&Library::new(&[])),
        Some("render") => render(args),
        _ => Err(Diagnostic::error(
            "usage: graphics_spike q2|q3|q4|q5|q6|q8|render …",
        )),
    }
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args) {
        Ok(value) => println!("{value}"),
        Err(d) => {
            println!("{}", json!({"error": d.to_json()}));
            std::process::exit(1);
        }
    }
}
