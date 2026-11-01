//! The reader's two queries over a parsed track, each a JSON request string to a JSON answer
//! string as `rc_cursor_query` would run them: `{"prepare":{"smoothing":s}}` and
//! `{"state":{"at":µs}}`.
//!
//! Smoothing's prototype: pins at every down click; between pins, iterative Ramer–Douglas–
//! Peucker with a tolerance of 12 pt × smoothing; centripetal Catmull–Rom in time over the
//! kept points. Smoothing 0 is the raw samples, linearly interpolated, and a state at a
//! smoothing that was not prepared answers raw.

use crate::body::Track;
use serde::{Deserialize, Serialize};

/// A ripple lasts this long after its down click.
const RIPPLE_US: i64 = 400_000;
/// 12 pt in points × 100.
const TOLERANCE_PER_UNIT: f64 = 1200.0;

#[derive(Deserialize)]
#[serde(rename_all = "lowercase")]
enum Request {
    Prepare { smoothing: f64 },
    State { at: i64 },
}

#[derive(Serialize)]
struct Ripple {
    x: f64,
    y: f64,
    age_us: i64,
}

#[derive(Serialize)]
struct State {
    visible: bool,
    x: f64,
    y: f64,
    image: i64,
    opacity: f64,
    ripples: Vec<Ripple>,
}

/// A kept point: (µs, x, y), x and y in points × 100.
type Kept = (f64, f64, f64);

pub struct Reader {
    pub track: Track,
    prepared: Option<(f64, Vec<Kept>)>,
}

impl Reader {
    pub fn new(track: Track) -> Self {
        Reader {
            track,
            prepared: None,
        }
    }

    /// One request string → one answer string.
    pub fn query(&mut self, request: &str) -> String {
        match serde_json::from_str::<Request>(request) {
            Ok(Request::Prepare { smoothing }) => {
                let kept = self.prepare(smoothing);
                format!("{{\"prepared\":{{\"smoothing\":{smoothing},\"kept\":{kept}}}}}")
            }
            Ok(Request::State { at }) => serde_json::to_string(&self.state(at)).expect("state"),
            Err(error) => format!(
                "{{\"error\":{}}}",
                serde_json::Value::from(error.to_string())
            ),
        }
    }

    fn prepare(&mut self, smoothing: f64) -> usize {
        if smoothing <= 0.0 {
            self.prepared = None;
            return self.track.moves.t.len();
        }
        let m = &self.track.moves;
        let c = &self.track.clicks;
        let pins: Vec<i64> =
            c.t.iter()
                .zip(&c.down)
                .filter(|(_, &d)| d == 1)
                .map(|(&t, _)| t)
                .collect();
        let tolerance = TOLERANCE_PER_UNIT * smoothing;
        let mut keep = vec![false; m.t.len()];
        let mut start = 0usize;
        let mut pin = 0usize;
        while start < m.t.len() {
            while pin < pins.len() && pins[pin] <= m.t[start] {
                pin += 1;
            }
            // The segment runs to the last sample before the next pin (or the end).
            let end = if pin < pins.len() {
                m.t.partition_point(|&t| t < pins[pin]).max(start + 1)
            } else {
                m.t.len()
            };
            rdp(&m.x, &m.y, start, end - 1, tolerance, &mut keep);
            start = end;
        }
        let kept: Vec<(f64, f64, f64)> = (0..m.t.len())
            .filter(|&i| keep[i])
            .map(|i| (m.t[i] as f64, m.x[i] as f64, m.y[i] as f64))
            .collect();
        let count = kept.len();
        self.prepared = Some((smoothing, kept));
        count
    }

    fn state(&self, at: i64) -> State {
        let m = &self.track.moves;
        let visible = !m.t.is_empty() && at >= m.t[0] && at <= *m.t.last().unwrap();
        let (x, y) = match &self.prepared {
            Some((_, kept)) if kept.len() >= 2 => catmull_rom(kept, at as f64),
            _ => linear(&m.t, &m.x, &m.y, at),
        };
        let ic = &self.track.image_changes;
        let k = ic.t.partition_point(|&t| t <= at);
        let image = if k == 0 { -1 } else { ic.id[k - 1] };
        let c = &self.track.clicks;
        let from = c.t.partition_point(|&t| t < at - RIPPLE_US);
        let to = c.t.partition_point(|&t| t <= at);
        let ripples = (from..to)
            .filter(|&i| c.down[i] == 1)
            .map(|i| Ripple {
                x: c.x[i] as f64 / 100.0,
                y: c.y[i] as f64 / 100.0,
                age_us: at - c.t[i],
            })
            .collect();
        State {
            visible,
            x: (x / 100.0 * 1000.0).round() / 1000.0,
            y: (y / 100.0 * 1000.0).round() / 1000.0,
            image,
            opacity: if visible { 1.0 } else { 0.0 },
            ripples,
        }
    }
}

fn linear(t: &[i64], x: &[i64], y: &[i64], at: i64) -> (f64, f64) {
    if t.is_empty() {
        return (0.0, 0.0);
    }
    let k = t.partition_point(|&v| v <= at);
    if k == 0 {
        return (x[0] as f64, y[0] as f64);
    }
    if k >= t.len() {
        return (x[t.len() - 1] as f64, y[t.len() - 1] as f64);
    }
    let (t0, t1) = (t[k - 1] as f64, t[k] as f64);
    let u = if t1 > t0 {
        (at as f64 - t0) / (t1 - t0)
    } else {
        0.0
    };
    (
        x[k - 1] as f64 + (x[k] - x[k - 1]) as f64 * u,
        y[k - 1] as f64 + (y[k] - y[k - 1]) as f64 * u,
    )
}

/// Iterative Ramer–Douglas–Peucker over samples first..=last; marks the kept ones.
fn rdp(x: &[i64], y: &[i64], first: usize, last: usize, tolerance: f64, keep: &mut [bool]) {
    keep[first] = true;
    keep[last] = true;
    let mut stack = vec![(first, last)];
    while let Some((a, b)) = stack.pop() {
        if b <= a + 1 {
            continue;
        }
        let (ax, ay, bx, by) = (x[a] as f64, y[a] as f64, x[b] as f64, y[b] as f64);
        let (dx, dy) = (bx - ax, by - ay);
        let length = (dx * dx + dy * dy).sqrt();
        let (mut worst, mut at) = (0.0f64, a);
        for i in a + 1..b {
            let (px, py) = (x[i] as f64 - ax, y[i] as f64 - ay);
            let d = if length > 0.0 {
                (px * dy - py * dx).abs() / length
            } else {
                (px * px + py * py).sqrt()
            };
            if d > worst {
                worst = d;
                at = i;
            }
        }
        if worst > tolerance {
            keep[at] = true;
            stack.push((a, at));
            stack.push((at, b));
        }
    }
}

/// Centripetal Catmull–Rom (α = ½) in time: the segment holding `at` among the kept points,
/// its time fraction mapped onto the centripetal knots (Barry–Goldman's pyramid).
fn catmull_rom(kept: &[(f64, f64, f64)], at: f64) -> (f64, f64) {
    let n = kept.len();
    let k = kept.partition_point(|p| p.0 <= at);
    if k == 0 {
        return (kept[0].1, kept[0].2);
    }
    if k >= n {
        return (kept[n - 1].1, kept[n - 1].2);
    }
    let i1 = k - 1;
    let p = [
        kept[i1.saturating_sub(1)],
        kept[i1],
        kept[k],
        kept[(k + 1).min(n - 1)],
    ];
    let mut knots = [0.0f64; 4];
    for j in 1..4 {
        let (dx, dy) = (p[j].1 - p[j - 1].1, p[j].2 - p[j - 1].2);
        knots[j] = knots[j - 1] + (dx * dx + dy * dy).sqrt().sqrt().max(1e-6);
    }
    let span = p[2].0 - p[1].0;
    let u = if span > 0.0 {
        (at - p[1].0) / span
    } else {
        0.0
    };
    let s = knots[1] + u * (knots[2] - knots[1]);
    let lerp = |a: (f64, f64), b: (f64, f64), ta: f64, tb: f64| {
        let w = (s - ta) / (tb - ta);
        (a.0 + (b.0 - a.0) * w, a.1 + (b.1 - a.1) * w)
    };
    let q: Vec<(f64, f64)> = p.iter().map(|v| (v.1, v.2)).collect();
    let a1 = lerp(q[0], q[1], knots[0], knots[1]);
    let a2 = lerp(q[1], q[2], knots[1], knots[2]);
    let a3 = lerp(q[2], q[3], knots[2], knots[3]);
    let b1 = lerp(a1, a2, knots[0], knots[2]);
    let b2 = lerp(a2, a3, knots[1], knots[3]);
    lerp(b1, b2, knots[1], knots[2])
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::body::worst_case;

    #[test]
    fn smoothing_zero_and_unprepared_answer_raw() {
        let mut reader = Reader::new(worst_case());
        let raw = reader.query("{\"state\":{\"at\":1234567}}");
        reader.query("{\"prepare\":{\"smoothing\":0}}");
        assert_eq!(reader.query("{\"state\":{\"at\":1234567}}"), raw);
    }

    #[test]
    fn prepared_passes_through_kept_points() {
        let mut reader = Reader::new(worst_case());
        reader.query("{\"prepare\":{\"smoothing\":1}}");
        let (t, x) = {
            let kept = &reader.prepared.as_ref().unwrap().1;
            (kept[10].0 as i64, kept[10].1)
        };
        let state: serde_json::Value =
            serde_json::from_str(&reader.query(&format!("{{\"state\":{{\"at\":{t}}}}}"))).unwrap();
        assert!((state["x"].as_f64().unwrap() - x / 100.0).abs() < 0.01);
    }
}
