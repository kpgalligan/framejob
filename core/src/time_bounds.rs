//! One admission rule for structural times stored in a project.
//!
//! Use i128 for endpoints: even an invalid pair of i64 fields must be
//! reported by its mathematical sum, never by a wrapping or clamped value.

use crate::model::{Clip, Project, Source};
use crate::time::Ticks;

pub(crate) const MAX_STORED_TICKS: Ticks = 9_000_000_000_000_000;

fn check(path: &str, value: i128) -> Result<(), String> {
    let max = i128::from(MAX_STORED_TICKS);
    if !(-max..=max).contains(&value) {
        return Err(format!(
            "{path} must be between -{MAX_STORED_TICKS} and {MAX_STORED_TICKS} ticks, not {value}"
        ));
    }
    Ok(())
}

fn check_clips(clips: &[Clip], nest: Option<u32>) -> Result<(), String> {
    for clip in clips {
        let where_in = nest.map_or(String::new(), |id| format!(" in nest {id}"));
        let path = format!("clip {}{where_in}", clip.id);
        check(&format!("{path}.start"), i128::from(clip.start))?;
        check(&format!("{path}.duration"), i128::from(clip.duration))?;
        check(
            &format!("{path}.end"),
            i128::from(clip.start) + i128::from(clip.duration),
        )?;
        match clip.source {
            Source::Media { r#in, .. } => {
                check(&format!("{path}.source.in"), i128::from(r#in))?;
            }
            Source::Still { at, .. } => {
                check(&format!("{path}.source.at"), i128::from(at))?;
            }
            _ => {}
        }
        for action in &clip.actions {
            let path = format!("{path}.action {}", action.id);
            check(&format!("{path}.start"), i128::from(action.start))?;
            check(&format!("{path}.duration"), i128::from(action.duration))?;
            check(
                &format!("{path}.end"),
                i128::from(action.start) + i128::from(action.duration),
            )?;
        }
    }
    Ok(())
}

pub(crate) fn check_stored_times(project: &Project) -> Result<(), String> {
    for media in &project.media {
        check(
            &format!("media {}.duration", media.id),
            i128::from(media.duration),
        )?;
    }
    for marker in &project.markers {
        check(
            &format!("marker {}.time", marker.id),
            i128::from(marker.time),
        )?;
    }
    check_clips(&project.clips, None)?;
    for nest in &project.nests {
        check_clips(&nest.clips, Some(nest.id))?;
    }
    Ok(())
}
