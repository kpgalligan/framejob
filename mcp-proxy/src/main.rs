#![forbid(unsafe_code)]
//! `reelcut-mcp`: the stdio MCP server inside Reelcut's bundle (spec §11
//! MC-3). Everything is in the library; see `lib.rs`.

fn main() {
    reelcut_mcp::run()
}
