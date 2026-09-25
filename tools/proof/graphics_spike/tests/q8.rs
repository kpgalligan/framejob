//! q8's "test binary": the same `math_hash` as `graphics_spike q8`, printed.

#[test]
fn prints_math_hash() {
    let answer = graphics_spike::q8(&graphics_spike::Library::new(&[])).expect("q8");
    println!("{answer}");
}
