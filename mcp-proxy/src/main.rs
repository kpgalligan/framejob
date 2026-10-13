#![forbid(unsafe_code)]
//! `framejob-mcp`: the stdio MCP server inside Frame Job's bundle (spec §11
//! MC-3). Everything is in the library; see `lib.rs`.

fn main() {
    framejob_mcp::run()
}
