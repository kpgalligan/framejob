//! G-5 (road map 10 §5l, G0's q5 kept as a test): a frame is a function of
//! its inputs — the same SVG and the same pixels on any thread, in any
//! order, after any other frames. A module that keeps state across calls
//! (the MUTANT) is caught by the same comparison.

mod common;

use std::collections::HashMap;

use graphic::{rasterize, Module};

use common::{shared, BUDGET_MS, FIXTURES};

type Key = (usize, i64);

/// G0's shuffle: splitmix32.
struct Splitmix(u32);

impl Splitmix {
    fn next(&mut self) -> u32 {
        self.0 = self.0.wrapping_add(0x9e37_79b9);
        let mut t = self.0 ^ (self.0 >> 16);
        t = t.wrapping_mul(0x21f0_aaad);
        t ^= t >> 15;
        t = t.wrapping_mul(0x735a_2d97);
        t ^ (t >> 15)
    }

    fn below(&mut self, n: usize) -> usize {
        (self.next() as usize) % n
    }
}

fn frames() -> Vec<i64> {
    (0..20).map(|i| i * 7).collect()
}

/// The SVG text and the SHA-256 of its BGRA at 1920×1080.
fn one(module: &Module, frame: i64) -> (String, String) {
    let (svg, _) = common::frame(module, frame)
        .unwrap_or_else(|d| panic!("{} {frame}: {}", module.name(), d.message));
    let mut out = vec![0u8; 1920 * 1080 * 4];
    rasterize(&shared(), &svg, 1920, 1080, &mut out, 1920 * 4)
        .unwrap_or_else(|d| panic!("{} {frame}: {}", module.name(), d.message));
    (svg, common::sha256(&out))
}

/// Draws every (module, frame) once on this thread, then 3 shuffled times
/// on each of 8 threads; answers how many answers differ from this
/// thread's, and how many were compared.
fn mismatches(modules: &[Module]) -> (usize, usize) {
    let keys: Vec<Key> = (0..modules.len())
        .flat_map(|m| frames().into_iter().map(move |f| (m, f)))
        .collect();
    let reference: HashMap<Key, (String, String)> = keys
        .iter()
        .map(|&(m, f)| ((m, f), one(&modules[m], f)))
        .collect();
    let threads: Vec<Vec<(Key, (String, String))>> = std::thread::scope(|scope| {
        let handles: Vec<_> = (0..8u32)
            .map(|t| {
                let keys = keys.clone();
                scope.spawn(move || {
                    let mut rng = Splitmix(0xd5_0000 + t);
                    let mut order: Vec<Key> = (0..3).flat_map(|_| keys.clone()).collect();
                    for i in (1..order.len()).rev() {
                        order.swap(i, rng.below(i + 1));
                    }
                    order
                        .into_iter()
                        .map(|(m, f)| ((m, f), one(&modules[m], f)))
                        .collect()
                })
            })
            .collect();
        handles.into_iter().map(|h| h.join().unwrap()).collect()
    });
    let mut compared = 0;
    let mut differ = 0;
    for thread in threads {
        for (key, answer) in thread {
            compared += 1;
            differ += usize::from(reference[&key] != answer);
        }
    }
    (differ, compared)
}

#[test]
fn every_frame_is_the_same_on_every_thread_in_every_order() {
    let modules: Vec<Module> = FIXTURES.iter().map(|n| common::module(n)).collect();
    let (differ, compared) = mismatches(&modules);
    println!("determinism: {compared} renders compared, {differ} differ");
    assert_eq!(compared, 6 * 20 * 8 * 3);
    assert_eq!(differ, 0);
}

#[test]
fn a_frame_is_the_same_after_300_others() {
    for name in FIXTURES {
        let module = common::module(name);
        let before: Vec<(String, String)> = [0, 30, 90].iter().map(|&f| one(&module, f)).collect();
        for f in 0..300 {
            common::frame(&module, f).unwrap();
        }
        let after: Vec<(String, String)> = [0, 30, 90].iter().map(|&f| one(&module, f)).collect();
        assert_eq!(after, before, "{name}");
    }
}

/// `counter.js` with a module-level call counter drawn into the frame: the
/// graphic G-5 says the standard library cannot stop.
fn mutant(counter: &str) -> String {
    counter.replace("export function render(", "function __render(")
        + "\nlet __calls = 0;\nexport function render(frame, props, ctx) {\n  __calls++;\n  \
           return __render(frame, props, ctx).replace(\"</svg>\", `<rect width=\"${__calls % 97 + 1}\" height=\"1\" fill=\"#fff\"/></svg>`);\n}\n"
}

#[test]
fn the_comparison_catches_a_module_that_keeps_state() {
    let source = mutant(&common::fixture("counter"));
    let module = Module::compile(shared(), "counter", &source, BUDGET_MS).unwrap();
    let (differ, compared) = mismatches(&[module]);
    println!("mutant: {compared} renders compared, {differ} differ");
    assert!(differ >= 1);
}
