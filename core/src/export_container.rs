//! The containers Frame Job writes (spec §7.8), and the four questions
//! each one answers about ITSELF: its extension, its UTI, whether a
//! leading index is worth rewriting, whether it can hold sound at all.
//!
//! Moved whole out of `export_table.rs` under the size rule (core/CLAUDE.md:
//! a module at ~600 lines gives something up BEFORE it takes anything on),
//! as codec-export C1's toll T1, a pure move. `export_table.rs` re-exports
//! [`Container`], so every `crate::export_table::Container` path holds.

/// The containers Frame Job writes. Kept as an enum rather than a string so
/// the container, its UTI, its network-optimization default and whether it
/// can hold sound at all are decided in exactly one exhaustive place.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Container {
    Mov,
    Mp4,
    M4a,
    Wav,
    Aiff,
    Gif,
    Apng,
}

impl Container {
    pub(crate) fn as_str(self) -> &'static str {
        match self {
            Container::Mov => "mov",
            Container::Mp4 => "mp4",
            Container::M4a => "m4a",
            Container::Wav => "wav",
            Container::Aiff => "aiff",
            Container::Gif => "gif",
            Container::Apng => "apng",
        }
    }

    /// The output file's UTI. On the AVFoundation path Swift passes this
    /// straight to `outputFileType`, whose raw values ARE UTIs; on the
    /// ImageIO path it is the destination type
    /// `CGImageDestinationCreateWithURL` takes. Either way it is what the
    /// save panel's content type and file extension are derived from, which
    /// is why the two image formats name a real UTI here rather than
    /// nothing — an export that could not tell the panel it writes a `.gif`
    /// would be worse off than one whose type string a session would
    /// reject, and a session is never built for them.
    ///
    /// An APNG is written to an ordinary PNG destination — the animation
    /// lives in `acTL`/`fcTL` chunks inside a file that is still a PNG — so
    /// its type identifier is PNG's, not one of its own.
    ///
    /// The two LPCM rows' identifiers are exactly `AVFileType.wav` and
    /// `AVFileType.aiff`'s raw values, which is what lets
    /// `Exporter.fileType(for:)` resolve them from this string alone
    /// rather than growing a container list of its own.
    pub(crate) fn file_type(self) -> &'static str {
        match self {
            Container::Mov => "com.apple.quicktime-movie",
            Container::Mp4 => "public.mpeg-4",
            Container::M4a => "com.apple.m4a-audio",
            Container::Wav => "com.microsoft.waveform-audio",
            Container::Aiff => "public.aiff-audio",
            Container::Gif => "com.compuserve.gif",
            Container::Apng => "public.png",
        }
    }

    /// Whether `shouldOptimizeForNetworkUse` defaults on. MP4 and M4A are
    /// the delivery containers people upload, and a leading `moov` atom
    /// lets a player start before the file is fully fetched. A ProRes MOV
    /// is an editing master handed to another application, where the
    /// rewrite pass buys nothing. An HEVC-with-alpha MOV is a delivery file
    /// too, and its default stays off all the same: that was the owner's
    /// choice for the row (spec §11 G-33), and the override turns it on. GIF
    /// and APNG have no `moov` atom and nothing to move: a viewer already
    /// starts on the first frame, and
    /// neither do WAV and AIFF — a RIFF or an IFF file is a header
    /// followed by samples, with no index to relocate, so the flag would
    /// be a request the writer has nothing to do about.
    pub(crate) fn optimizes_for_network(self) -> bool {
        matches!(self, Container::Mp4 | Container::M4a)
    }

    /// Whether the container can hold sound. Every movie container can,
    /// and M4A, WAV and AIFF are nothing else; GIF and APNG are picture
    /// formats with no audio track in the file format at all, so
    /// `audio: false` for those is a fact about the container rather than
    /// a decision about the project.
    pub(crate) fn carries_audio(self) -> bool {
        !matches!(self, Container::Gif | Container::Apng)
    }
}
