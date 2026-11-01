//! CU-S4's reader prototype (road map "creator-jobs" CU0b).
//!
//!     cursor-spike-reader generate --out DIR
//!     cursor-spike-reader measure --body json|binary --file F --runs 5
//!     cursor-spike-reader selftest --dir DIR
//!
//! `generate` writes the worst case as `worst.json` and `worst.bin`. `measure` reads the file
//! into memory, then per run: parse and validate (timed, `parse_ms`), 1,000 states at seeded
//! times unprepared, `prepare` at smoothing 1 (timed, `prepare_ms`), 1,000 states prepared;
//! each state a JSON request string to a JSON answer string. It prints one JSON line. The
//! selftest (R4a) answers whether the JSON body's states equal the binary body's at 100 seeded
//! times, unprepared and prepared.

mod body;
mod track;

use body::{parse_binary, parse_json, to_binary, to_json, worst_case, Lcg, HOUR_US};
use std::time::Instant;
use track::Reader;

const STATES_PER_RUN: usize = 1000;

fn arg(args: &[String], name: &str) -> Option<String> {
    args.iter()
        .position(|a| a == name)
        .and_then(|i| args.get(i + 1).cloned())
}

fn fail(message: &str) -> ! {
    println!(
        "{}",
        serde_json::json!({"outcome": "failed", "reason": message})
    );
    std::process::exit(1)
}

fn median(values: &mut [f64]) -> f64 {
    values.sort_by(|a, b| a.partial_cmp(b).expect("finite"));
    let n = values.len();
    if n == 0 {
        return f64::NAN;
    }
    if n % 2 == 1 {
        values[n / 2]
    } else {
        (values[n / 2 - 1] + values[n / 2]) / 2.0
    }
}

fn round3(v: f64) -> f64 {
    (v * 1000.0).round() / 1000.0
}

fn parse(body: &str, bytes: &[u8]) -> Result<body::Track, String> {
    match body {
        "json" => parse_json(bytes),
        "binary" => parse_binary(bytes),
        other => Err(format!("no body {other}")),
    }
}

fn states(reader: &mut Reader, rng: &mut Lcg, n: usize, timings: &mut Vec<f64>) {
    for _ in 0..n {
        let request = format!("{{\"state\":{{\"at\":{}}}}}", rng.below(HOUR_US as u64));
        let started = Instant::now();
        let answer = reader.query(&request);
        timings.push(started.elapsed().as_secs_f64() * 1e6);
        std::hint::black_box(answer);
    }
}

fn measure(args: &[String]) {
    let body = arg(args, "--body").unwrap_or_else(|| fail("--body is required"));
    let file = arg(args, "--file").unwrap_or_else(|| fail("--file is required"));
    let runs: usize = arg(args, "--runs")
        .and_then(|r| r.parse().ok())
        .unwrap_or(5);
    let bytes = std::fs::read(&file).unwrap_or_else(|e| fail(&format!("{file}: {e}")));
    let (mut parse_ms, mut prepare_ms) = (Vec::new(), Vec::new());
    let (mut raw_us, mut prepared_us) = (Vec::new(), Vec::new());
    let mut rng = Lcg::new(1);
    for _ in 0..runs {
        let started = Instant::now();
        let track = parse(&body, &bytes).unwrap_or_else(|e| fail(&e));
        parse_ms.push(round3(started.elapsed().as_secs_f64() * 1000.0));
        let mut reader = Reader::new(track);
        states(&mut reader, &mut rng, STATES_PER_RUN, &mut raw_us);
        let started = Instant::now();
        let answer = reader.query("{\"prepare\":{\"smoothing\":1}}");
        prepare_ms.push(round3(started.elapsed().as_secs_f64() * 1000.0));
        if !answer.contains("\"prepared\"") {
            fail(&format!("prepare answered {answer}"));
        }
        states(&mut reader, &mut rng, STATES_PER_RUN, &mut prepared_us);
    }
    println!(
        "{}",
        serde_json::json!({
            "outcome": "ok", "body": body, "bytes": bytes.len(), "runs": runs,
            "parse_ms": parse_ms, "prepare_ms": prepare_ms,
            "state_us_raw_median": round3(median(&mut raw_us)),
            "state_us_prepared_median": round3(median(&mut prepared_us)),
            "states_per_run": STATES_PER_RUN,
        })
    );
}

fn generate(args: &[String]) {
    let out = arg(args, "--out").unwrap_or_else(|| fail("--out is required"));
    std::fs::create_dir_all(&out).unwrap_or_else(|e| fail(&format!("{out}: {e}")));
    let track = worst_case();
    let json = to_json(&track);
    let binary = to_binary(&track);
    let (jp, bp) = (format!("{out}/worst.json"), format!("{out}/worst.bin"));
    std::fs::write(&jp, &json).unwrap_or_else(|e| fail(&format!("{jp}: {e}")));
    std::fs::write(&bp, &binary).unwrap_or_else(|e| fail(&format!("{bp}: {e}")));
    println!(
        "{}",
        serde_json::json!({
            "outcome": "ok", "json": jp, "json_bytes": json.len(), "binary": bp,
            "binary_bytes": binary.len(), "moves": track.moves.t.len(),
            "click_records": track.clicks.t.len(), "keys": track.keys.t.len(),
            "images": track.images.len(), "image_changes": track.image_changes.t.len(),
        })
    );
}

/// R4a: the JSON body's states equal the binary body's at 100 seeded times.
fn selftest(args: &[String]) {
    let dir = arg(args, "--dir").unwrap_or_else(|| fail("--dir is required"));
    let read = |name: &str| {
        std::fs::read(format!("{dir}/{name}")).unwrap_or_else(|e| fail(&format!("{name}: {e}")))
    };
    let from_json = parse_json(&read("worst.json")).unwrap_or_else(|e| fail(&e));
    let from_binary = parse_binary(&read("worst.bin")).unwrap_or_else(|e| fail(&e));
    let tracks_equal = from_json == from_binary;
    let (mut a, mut b) = (Reader::new(from_json), Reader::new(from_binary));
    let mut rng = Lcg::new(1);
    let times: Vec<u64> = (0..100).map(|_| rng.below(HOUR_US as u64)).collect();
    let mut mismatches = 0;
    for phase in 0..2 {
        if phase == 1 {
            a.query("{\"prepare\":{\"smoothing\":1}}");
            b.query("{\"prepare\":{\"smoothing\":1}}");
        }
        for t in &times {
            let request = format!("{{\"state\":{{\"at\":{t}}}}}");
            if a.query(&request) != b.query(&request) {
                mismatches += 1;
            }
        }
    }
    println!(
        "{}",
        serde_json::json!({
            "outcome": "ok", "r4a": tracks_equal && mismatches == 0, "tracks_equal": tracks_equal,
            "compared": times.len() * 2, "mismatches": mismatches,
        })
    );
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    match args.get(1).map(String::as_str) {
        Some("generate") => generate(&args),
        Some("measure") => measure(&args),
        Some("selftest") => selftest(&args),
        _ => fail("usage: cursor-spike-reader generate|measure|selftest …"),
    }
}
