# Spec §11 — decisions: The rename to Frame Job (road map "rename")

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The road map that made these is closed: its condensed record is `designs/adr/rename.md`, and
the original, `archive/rename.md`, holds the inventory, the phases (R0 the plan, these
decisions and the logo assets; R1 the code; R2 the mark and the icon; R3 the documents; R4 the
close) and each phase's record. NM-1…NM-11 were recorded in R0, before
any rename code, from the owner's choices of 2026-10-12 ("'Reelcut' is a terrible name from a
trademark perspective. The new name will be 'Frame Job'."): rename everything that spells
Reelcut, `reelcut` or `REELCUT` and keep the generic `Reel*` names, `rc_` and `RC_*`; the
spelling "Frame Job" for people and `FrameJob` / `framejob` for machines; no migration code,
the old folders moved by hand; and now, in the worktree `~/devel/reelcut-rename`, phase by
phase, each gated and merged into main alone (`archive/rename.md`, "The owner's choices").
The new icon and mark are the owner's, in `designs/frame-job/`.

**Stands, and nothing here re-litigates it:** every earlier decision. Where one names an old
identifier, path or sentence, an amendment paragraph at its end, naming the NM decision, says
what it is now; nothing else in it changes. `RC_FORMAT_VERSION` is not bumped
(`core/src/format.rs`): the package format does not change. PUB-2's run counter stays with the
workflow FILE, whose name does not change.

- **NM-1 — The product is Frame Job. Every spelling of the old name in the product, the build,
  the tooling and the live documents changes; history does not.** History is `archive/`,
  `designs/adr/` (but for the new ADR at the close), the design handoffs and briefs
  (`designs/design_handoff_reelcut/`, `designs/design_handoff_reelcut_sharp/`,
  `designs/design_handoff_clip_inspector/`, `designs/clip_inspector_brief/`), `.dupscan/`, the
  recorded results in `tools/proof/README.md`, and the text of every existing decision in this
  folder. **The reading rule:** "Reelcut" in an existing decision's prose, or in any historical
  document, names the product, now Frame Job; a decision is amended only where it names an
  identifier, a path, a file or a sentence that a program writes or a person reads, since those
  change. Why: the owner asked for everything (choice 1), and a decision that names a path
  must name the real one; rewriting history would make every recorded run and citation lie
  about what it ran. Risk accepted: an old document read without this rule names a product
  that no longer exists, and an archived road map's path names (`archive/reelcut-*.md`) keep
  the old spelling.
- **NM-2 — One name, four spellings.** "Frame Job" with its space wherever a person reads it;
  `FrameJob` where a CamelCase identifier is needed; `framejob` where a lower-case one is; and
  `FRAMEJOB` in upper-case macros. One exception: a space breaks it.

  | Use | Spelling | Examples |
  |---|---|---|
  | Display: any sentence, title, menu, alert, label, Metal debug label, log prefix, a folder a person sees | `Frame Job` | "About Frame Job", "Frame Job ▸ Settings…", `Frame Job: ` (the parity prefix), `Frame Job agent socket listening at `, `~/Library/Application Support/Frame Job/`, `~/Movies/Frame Job Recordings/`, `…/Frame Job Proofs/spend.jsonl`, UTI description "Frame Job Project" |
  | Products | `Frame Job.app`, `Frame Job Debug.app`; executables `Frame Job`, `Frame Job Debug` (follow PRODUCT_NAME) | `pgrep -f "MacOS/Frame Job"` lists both |
  | CamelCase identifiers | `FrameJob` | module/target/scheme/`FrameJob.xcodeproj`, `PRODUCT_MODULE_NAME: FrameJob` (pinned: a per-config PRODUCT_NAME would otherwise derive `Frame_Job`/`Frame_Job_Debug`), `NSDocumentClass: FrameJob.ProjectDocument`, `com.kgalligan.FrameJob`, `com.kgalligan.FrameJob.debug`, `app/Bridging/FrameJob-Bridging-Header.h`, `app/FrameJob.entitlements`, defaults keys `FrameJob*` (and their `-FrameJob*` launch arguments), notification names `FrameJob*DidChange`, temp folders under `NSTemporaryDirectory()` named `FrameJob` |
  | lower-case identifiers | `framejob` | `.framejob`, `com.kgalligan.framejob-project`, `framejob-core`/`framejob_core`/`libframejob_core.a`/`core/include/framejob_core.h`, `framejob-mcp` (crate, lib `framejob_mcp`, bin), `framejob-agent` (helper, package, user-agent), MCP server name `framejob`, `framejob-launch.log`, `framejob.log` (a proof's log), `<framejob_context>`, `include_framejob_windows`, shader functions `framejob_*`, queue/pasteboard labels `com.kgalligan.framejob.*`, temp-file prefixes `framejob-*`, `[framejob]` |
  | UPPER | `FRAMEJOB_DEV_TOOLS`, `FRAMEJOB_CORE_H`, `FRAMEJOB_BRIDGING_HEADER_H` | |
  | Exception: a space breaks it | `FrameJob.dmg` (GitHub rewrites a space in a release asset name to a dot); DMG volume name and release title keep "Frame Job" | |

  **Kept everywhere:** the generic `Reel*` internal names (`ReelOp`, `ReelProject`, `ReelTime`,
  `ReelCore`, `ReelCoreError`, …), the `rc_` FFI prefix, `RC_*` variables and `-RC*` launch
  arguments, the publish workflow FILE's name (PUB-2), and `RC_FORMAT_VERSION` with no bump —
  the package format does not change, so a `.reelcut` renamed by hand to `.framejob` opens.
  Why: the owner's spelling (choice 2) with the designer's one deviation, which the owner
  allowed "where a space breaks something": a Swift module name cannot hold a space, so the
  module is pinned rather than derived, and a release asset's space would silently become a
  dot. Risk accepted: four spellings of one name to keep straight, and a wrong one among them
  is found by review, not by NM-8's check, which looks only for the old name.
- **NM-3 — The bundle and the document.** Release and Distribution are `Frame Job.app`,
  `com.kgalligan.FrameJob`, executable `Frame Job`; Debug is `Frame Job Debug.app`,
  `com.kgalligan.FrameJob.debug`, executable `Frame Job Debug`. The project, target and scheme
  are `FrameJob` (`FrameJob.xcodeproj`), the module is `FrameJob` through
  `PRODUCT_MODULE_NAME`, and every `NSDocumentClass` is `FrameJob.ProjectDocument`. The document
  is a `.framejob` package of UTI `com.kgalligan.framejob-project`, described "Frame Job
  Project", type name "Frame Job Project". The entitlements file is `app/FrameJob.entitlements`.
  The published DMG is `FrameJob.dmg`, its volume "Frame Job", its release "Frame Job
  <version>". **Debug sets `PRODUCT_NAME` to "Frame Job Debug"**, and `CFBundleName` and
  `CFBundleDisplayName` read `$(PRODUCT_NAME)`, so `RC_APP_NAME` is removed;
  `RC_PROJECT_HANDLER_RANK` stays (V-5's Alternate handler). Why: V-5's own app per
  configuration, with the name now carried by the product rather than a second setting, and
  the module name, which `NSDocumentClass` spells, held the same in every configuration. Risk
  accepted: a new bundle id is a new app to macOS — new defaults domains, new TCC rows, new
  Launch Services registrations; the old ones are left for the owner's hand steps
  (`designs/adr/rename.md`, "Owner's hand steps").
- **NM-4 — The folders and paths.** The support folder is `~/Library/Application Support/Frame
  Job/`, with `Rewrapped/`, `ExportPresets.json`, the spend folder's `spend.jsonl` and
  `anthropic-prices.json`, the key files `assemblyai-key` and `anthropic-key`, and the socket
  `Agent/agent.sock` — 75 bytes for the owner's home
  (`/Users/kevingalligan/Library/Application Support/Frame Job/Agent/agent.sock`), within
  `MAX_SOCKET_PATH_BYTES`' 103. Recordings land in `~/Movies/Frame Job Recordings/`; the
  proofs' ledger is `~/Library/Application Support/Frame Job Proofs/spend.jsonl`; the app's
  temporary folders are `<NSTemporaryDirectory()>/FrameJob/…`. Why: a person sees the first
  three in the Finder, so they take the display spelling; the temporary root is an identifier
  no person browses. Risk accepted: the socket path grows by 2 bytes, and a home folder more
  than 28 bytes longer than the owner's would pass 103 and leave the socket unbound, its
  `not bound:` line naming the length, as before.
- **NM-5 — What other programs and people read.** The MCP server's name is `framejob` (the
  `initialize` answer and the `claude mcp add --scope user framejob -- …` line Copy MCP Command
  writes); the two bundled helpers are `Contents/Helpers/framejob-mcp` and
  `Contents/Helpers/framejob-agent`; the helper's user-agent is `framejob-agent`; the proxy's
  launch log is `framejob-launch.log`; the assistant's live context is a `<framejob_context>`
  block; `record_screen`'s argument is `include_framejob_windows` and the panel's checkbox
  "Include Frame Job windows"; log lines open `Frame Job: ` or `[framejob]`; every quoted
  sentence that names the product names Frame Job ("update Frame Job to open it", "Frame Job's
  estimate", "copied into Frame Job's Rewrapped folder.", "framejob-mcp is missing from this
  copy of Frame Job."); the pasteboard types are `com.kgalligan.framejob.clips` and
  `com.kgalligan.framejob.media`. Why: these are what a client, a log reader or a person sees.
  Risk accepted: an MCP client configured for `reelcut` stops connecting until it is re-added
  (a hand step), and a tool argument is renamed with no alias — the argument gate refuses
  `include_reelcut_windows` by name.
- **NM-6 — The internal names.** The crates are `framejob-core` (lib `framejob_core`,
  `libframejob_core.a`) and `framejob-mcp` (lib `framejob_mcp`); the header is
  `core/include/framejob_core.h` (guard `FRAMEJOB_CORE_H`), the bridging header
  `app/Bridging/FrameJob-Bridging-Header.h` (guard `FRAMEJOB_BRIDGING_HEADER_H`); the dev-tools
  flag is `FRAMEJOB_DEV_TOOLS`; the shader functions are `framejob_*`; every defaults key spelled
  `Reelcut*` is `FrameJob*`, every notification `FrameJob*DidChange`, and every queue, thread and
  Metal label `com.kgalligan.framejob.*` or "Frame Job …". The FFI is still three files in
  lockstep; the `rc_*` exports and their Swift wrappers are untouched. Why: the owner's choice 1
  names each of these. Risk accepted: the person's stored settings under the old keys are not
  read (NM-7).
- **NM-7 — No migration code.** Nothing reads an old folder, an old defaults key or domain, or
  the `.reelcut` extension; the owner moves what he wants kept by hand (`designs/adr/rename.md`,
  "Owner's hand steps"). Two guards only: (1) `tools/proof/budget.py` refuses every paid
  request while `~/Library/Application Support/Reelcut Proofs/` exists, and the refusal names
  the guarded `mv`; without it P-3 and P-6's month would restart at $0 in a new ledger. It
  refuses before it creates or writes anything under `Frame Job Proofs/` — no folder, no ledger,
  no `refused` event — because a folder it made would make the owner's `mv` nest the old folder
  inside it. (2) The proof tooling keeps refusing and never touching the old app domains
  (`com.kgalligan.Reelcut`, `com.kgalligan.Reelcut.debug`) as it refuses the new ones, and its
  sweep removes the proofs' probe domains under both the old and the new prefixes. Why: the
  owner's choice 3 (no real use yet, 2026-10-09); a guard exists only where a silent new start
  would cost money or touch the owner's own preferences. Risk accepted: old preferences,
  grants, recordings and keys look gone until moved, and a `.reelcut` package opens only after
  it is renamed.
- **NM-8 — The residue check runs in `make test`.** From R1, `tools/proof/name_residue.py`
  (stdlib only) lists every line of every tracked or untracked-unignored file that matches
  `reelcut` case-insensitively, and every path that does, and fails on any that is not
  allowed: a path under `HISTORY` (kept whole), a line matching one of `KEPT_PATTERNS` (an issue
  citation `kpgalligan/reelcut#N`, an archived file's name, `.claude/litecode/reelcut/`,
  `devel/reelcut…` — real until the owner's renames), or a file in `COUNTED` whose count
  equals its pinned number exactly. Its `--selftest` scores a stray-line mutant and a count
  mutant. Why: 4,926 lines in 662 files at the pinned commit (the road map's inventory) are
  too many to trust to a reading; the check makes the allow-list explicit and makes any
  new or missed site fail loudly. Risk accepted: a pinned count can hide a swapped line in a
  counted file.
- **NM-9 — Five phases, the code in one.** R0 the plan; R1 the code, build, tooling, MCP
  surface and the screens catalog together, because a proof drives the app by its product
  path, socket, domain and tool names, so any split breaks every proof between the halves; R2
  the mark and the icon; R3 the documents; R4 the close. Every phase is gated in the worktree
  `~/devel/reelcut-rename` (branch `rename`) and fast-forward merged into main alone; main stays
  usable meanwhile. The GitHub repository's rename and the local folder's come last, only on
  the owner's OK. Why: the owner's choice 4. Risk accepted: R1 is one large change.
- **NM-10 — The Rasterize side is a recorded diff, never written from here.** `agent/src` is
  byte-identical with `~/devel/rasterize/agent/src` (`diff -r` exited 0 on 2026-10-13). R1
  changes exactly three lines in it — `main.ts`'s comment naming the two apps, the scratch
  prefix in `priceTable.test.ts`, and `priceTable.ts`'s user-agent — and the shared user-agent
  becomes `framejob-agent` in both apps. The same diff is recorded in the road map for
  kpgalligan/rasterize to apply; no agent here writes `~/devel/rasterize`. Why: one diff
  applied to both is AI-1's rule, and Rasterize already sends Reelcut's user-agent. Risk
  accepted: the two trees differ by those three lines until Rasterize applies them.
- **NM-11 — The mark and the icon.** `app/Assets.xcassets/AppIcon.appiconset` is replaced by
  `designs/frame-job/AppIcon.appiconset`, with its own `Contents.json`. `BrandMark` draws the
  content of `designs/frame-job/frame-job-icon.svg` without its tile: four `#1F8564` corner
  brackets, the `#F2C14E` frame, and the `#F4653F` playhead and its head; the wordmark reads
  "Frame Job". Why: the owner's new logo. Risk accepted: the mark's colours are the icon's,
  not the theme's, in both appearances, as the old mark's were; how it looks is a person's
  check (R2's manual-checks row).
