# Spec §11 — decisions: Cloud captions (road map 6)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

- **R6-1 — The cloud engine is a second engine behind the same command,
  never a second command.** File ▸ Generate Captions… and `transcribe`
  are the one way captions are made from speech; the engine is a popup
  and an argument. A caption is an ordinary text clip whichever engine
  made it, laid out by the same `CaptionLayout.place`.
- **R6-2 — Audio leaves the machine only by name, with the price in
  front of the person.** The on-device engine stays the default for the
  sheet's first open and for every `transcribe` call that does not name
  `engine`. With AssemblyAI chosen, the sheet states — before the button
  is enabled — which files will be uploaded, their total duration, the
  destination and its region, the published rate and the estimate, and
  that the upload is deleted from AssemblyAI once read back. There is no
  background transcription, no transcription at import, and
  `MediaImporter.generateCaches` never touches the network: a cache pass
  that costs money and needs consent is not a cache pass.
- **R6-3 — The transcript is a per-media asset in the package.** One
  upload per media file, the provider's words stored VERBATIM (their
  milliseconds, confidence and speaker) with what was requested and what
  ran, under `cache/transcripts/`, stamped and marked on §5.6's terms so
  a relink or a changed file re-transcribes and nothing else does. Every
  clip's cues are derived from it at run time. It is the reversed
  render's kind of cache — regenerable at a cost — and it travels with the
  package for the same reason.
- **R6-4 — What was uploaded is deleted by us, immediately, and the fact
  is recorded.** `DELETE /v2/transcript/{id}` follows the fetch in the
  same run; the cache file records whether it succeeded, and a run's first
  act is to retry every recorded failure. AssemblyAI's own upload
  retention (≤ 48 h) is the backstop, never the plan; its transcript
  retention (indefinite) is why the delete is not optional. A next-run retry
  is promised only when the transcript's deletion ID was saved in the
  project. If that write and the remote delete both fail, the report says
  automatic retry is unavailable and directs the person to delete the
  transcript in their AssemblyAI dashboard.
- **R6-5 — The app never holds an AssemblyAI key of Reelcut's.** The
  credential is the person's own, in a `0600` file of their own under
  `~/Library/Application Support/Reelcut/`, or a relay's token (road map
  6's C2). It is never an argument of `transcribe` — an argument is written
  into every agent transcript and every log — and never a launch argument,
  which `ps` shows to every user. `RC_ASSEMBLYAI_KEY` in the environment is
  the one override, for proofs, and it is read only when the store has
  nothing. The file rather than the Keychain because C0's q7 measured what
  an ad-hoc signature does to a login-keychain item: the next `make app`
  cannot read it without a modal and cannot delete it at all
  (`archive/reelcut-roadmap-6.md` §3 q7, §5d). A build signed with a stable
  identity could keep it in the Keychain, and `SecretStore` is the protocol
  that lets that be a later conformer.
  **Current product scope (2026-09-21):** users supply their own AssemblyAI
  key. The user deferred C2 until an integrated AI offering is designed;
  the relay-token alternative above remains future scope (road map 6
  §10.18).
- **R6-6 — The protocol boundary is the base URL and the credential.** The
  client speaks AssemblyAI's REST API to `AssemblyAIConfiguration`'s base
  URL; the stand-in server, the EU endpoint and a same-protocol relay are
  configurations. A relay that must own the bytes (the bucket shape, road
  map 6 §6d) is one more `TranscriptTransport` conformer and nothing above
  it changes.
- **R6-7 — No `async` exception.** `URLSession` has a completion-handler
  and delegate form for every call this needs, `Transcriber`'s two-queue
  shape (a serial `work` queue and a private delivery queue the framework
  is told to call back on) carries over unchanged, and the run's body
  stays synchronous so the sheet and the off-main tool both wait the way
  they do today.
- **R6-8 — A fallback to Universal-2 is allowed and REPORTED.** The
  request names both models in AssemblyAI's documented order so a
  language Universal-3.5 Pro does not speak still gets a transcript; the
  cache and the result carry `speech_model_used`, and the sheet's report
  and the tool's `note` say so when it was not the model the person
  chose. A silent downgrade would be a wrong answer presented as the
  right one; a refusal would be no answer at all.
- **R6-9 — A proof-launched app never opens the person's stored key.**
  The stored credential is opened only for AssemblyAI's own hosts, and a
  proof never opens it. Four rules make that true. (a) `-RCSecretFolder
  <path>` overrides the folder `FileStore` reads and writes, the
  `-RCRecordingFolder` idiom — a PATH, never a key, because `ps` shows
  every argument. (b) With `-RCAssemblyAIEndpoint` set and
  `-RCSecretFolder` absent, NO `FileStore` is built at all:
  `AssemblyAIConfiguration.store` answers an empty `MemoryStore`, so an
  app pointed at a stand-in server has the environment as its only
  credential and the person's own file is never read. (c) Both arguments
  are read ONLY from `UserDefaults.standard.volatileDomain(forName:
  UserDefaults.argumentDomain)`, so a persisted default can redirect
  neither. (d) The resolution ORDER is unchanged — the store first, the
  environment second — which amends R6-5's wording and not its order.
  Beside them, the stand-in server of road map 6 §5i logs an
  `authorization` value only when it is one of the dummies `proof-key`
  and `wrong-key`; anything else is logged as a fixed redaction marker,
  answered 401, scored as a failure of the run that sent it, and written
  nowhere. Without (b) a machine where the person had saved a real key
  would send that key to a stand-in server that writes every header to
  disk, and road map 6 §5i·1's "key unset → refused by name" row could
  not pass at all.
- **R6-10 — The caption path clamps a clip's `speed` at BOTH ends, because
  the reader does not.** A clip's `speed` is bounded to 0.1–10 by the OPS
  and by nothing else: `core/src/edit_clip_timing.rs`'s `SPEED_MIN`/`SPEED_MAX`
  make `set_speed` clamp and `rate_stretch` an identity outside the range,
  while `Project::validate` (`core/src/model_query.rs:189`) checks a clip's
  duration and its start and never its speed. So a hand-written
  `project.json` reaches the app with any finite positive speed, TINY OR
  HUGE, and both ends of the caption arithmetic have to survive it. Every
  `Double → Ticks` conversion on that path therefore clamps IN `Double`
  first: a tiny speed blows up the OFFSET, which `Transcriber.placed`
  bounds into `[0, duration]` before converting (the two mappings,
  `MediaTranscript.project` and `Transcriber.project`, both end there); a
  huge one blows up the SOURCE LENGTH, which `Transcriber.contentLength`
  bounds to `Transcriber.maxSourceTicks` = 1e15 — deliberately NOT the
  core's `i64::MAX`, because Swift SUMS this number where the core does
  not: `MediaTranscript.swift:333` adds it to `sourceIn` for the window's
  end and `TranscribeSheetController.swift:395` sums it over at most
  `MAX_CLIPS` = 4096 jobs, and 4096 × 1e15 is comfortably under 2^63 (both
  citations re-pointed by `grep -n` — after c1-chrome's edits, and the second
  again on 2026-09-21 by §10.13's reader review, which found it seven lines
  short at `:388`; the first was and is correct).
  `Transcriber.jobs` bounds every `Job.sourceIn` the same way so the window
  end cannot overflow either. **Extended 2026-09-20 (c1-chrome) to the one
  INTEGER multiply on that path**, which this rule did not cover and which
  takes its input from the PROVIDER's JSON and from a hand-edited cache
  file: `MediaTranscript.words` turns a word's milliseconds into source
  ticks as `ms × 600`, and `Ticks` is `Int64`, so any `|ms| >
  Ticks.max / 600` is an overflow trap in a build with checked arithmetic.
  `MediaTranscript.sourceTicks(milliseconds:)` is now the one door that
  conversion goes through and it clamps IN `Int` to
  ±`maxWordMilliseconds` = `Ticks.max / 600` BEFORE multiplying. The bound
  is deliberately NOT `maxSourceTicks`: this number is not summed with
  anything — it is COMPARED with the window and has a non-negative
  `sourceIn` subtracted from it — and a bound of 1e15 sits inside a
  window end a hand-written file can legally reach (`sourceIn` +
  `sourceLength` ≤ 2e15), so clamping there would move a word that is far
  past the window INTO it and put a caption on somebody else's picture,
  where `Ticks.max / 600` is outside every window there can be. A negative
  millisecond stays negative for the same reason: it must keep failing the
  `≥ sourceIn` test rather than being folded to zero. Every value that did
  not trap before answers exactly what it always did. One consequence is SHARED with the on-device
  engine and MEASURED by no row: `contentLength` used to fall back to the
  clip's duration when `duration × speed` overflowed to `+infinity`, and now
  answers the 1e15 bound, so such a clip's on-device EXTRACT range is built
  from the bound rather than from the duration (c1-run's review, a nit; every
  speed the ops can write is unchanged, `source_mirror_probe.py` 40/40).
  DECLINED: bounding `speed` in `Project::validate`. The core stays untouched by this feature, and a
  reader that began refusing files it has always accepted would be a
  format change dressed as a fix.
- **R6-11 — A media whose remote delete this run could not confirm is not
  uploaded again in this run.** `cache/transcripts/<id>.json` is the ONLY
  record of a remote transcript's id — `MediaTranscript.undeleted`
  (`:273`) reads it and nothing else holds it — and a fetch REPLACES that
  file. So if the janitor's retry failed for a media and the run then
  re-fetched it, the id it could not delete would be overwritten and the
  transcript orphaned at AssemblyAI for ever, with the run's own note
  ("the next run retries it") made false by the same run that printed it.
  The rule: a media in this run's `janitorFailed` is HELD — not fetched,
  not under `refresh`, not with a stale stamp. Its clips are reported, one
  `Problem` each, its cache file is left byte for byte, and the hold
  releases in the first run whose janitor confirms the delete. A CURRENT
  cache without `refresh` is still served, because that path reads the
  file and never writes it. DECLINED: serving the old words under
  `refresh` — a caller who asked for a re-upload is told it did not happen
  rather than handed a cached answer — and a second persisted file listing
  orphaned ids, which is a new persisted shape for one case.
- **R6-12 — The key and the region are a PERSON's settings, and no tool
  reads or writes either.** The key is R6-5's rule already: never an
  argument, never in an answer, reachable only through Reelcut ▸ Settings…
  and `RC_ASSEMBLYAI_KEY`. The REGION is the same kind of thing for a
  different reason — it is a default a person sets once
  (`ReelcutAssemblyAIRegion`, road map 6 §5d), it changes only WHERE a
  transcript is made, and a tool argument for it would let one call put a
  customer's audio in a jurisdiction the person did not choose. So the
  Settings window is the one writer and `AssemblyAIConfiguration.region` the
  one reader. DECLINED: a `region` key in `transcribe`'s result, which road
  map 6 §5g's key list does not carry and pipeline 3 did not add. Every
  proof instance runs under `-RCAssemblyAIEndpoint`, where the region is
  NOT where the run spoke, so such a key could only ever be proved on the
  one host where it is false; the honest shape — the base URL's HOST, under
  a key named `endpoint` — is recorded as residue in
  `designs/reelcut-remaining.md` §5 rather than guessed at here. The
  Settings window's **Verify** runs on `CloudTranscriber`'s own `work`
  queue, one of the seams `app/CLAUDE.md` lists, and adds no queue (R6-7).
- **R6-13 — The estimate never counts a HELD media as "to upload", and
  never hides its price.** R6-11 holds a media whose earlier remote delete
  is unconfirmed: this run will not upload it, so counting it among the
  files to upload would quote a person money for work that is not going to
  happen, and R6-2's "a person is told what a run will cost before it runs"
  would be false in the other direction if it were dropped in silence. So
  it is its OWN clause of `CloudEstimate.describe` — "N file(s) waiting on
  an earlier delete" — and its line in `CloudEstimate.reasons` names the
  file and says what it would cost if the janitor clears it ("about $X more
  if it does"). The estimate reads the cache's marker and the file's stamp
  and NOTHING ELSE: whether the delete actually clears is the run's answer,
  not the estimate's, and the report card is where that is reported.
  DECLINED: hiding a held media from the card entirely, which would make a
  file silently not transcribe.
- **R6-14 — A lost submit reply permits bounded recovery, never another
  paid submit.** After one ambiguous `POST /v2/transcript`, the cloud run may
  read the newest account transcript page (`GET /v2/transcript?limit=200`)
  solely to find its own upload by byte-for-byte `audio_url` equality. Only a
  unique plain transcript id may proceed to poll, cache and delete. Unrelated
  rows are never polled, deleted, logged or saved. Three looks, 2.5 seconds
  apart and each with a 5-second timeout, tolerate short visibility lag;
  there is no POST retry. Failed or ambiguous recovery answers with an
  explicit dashboard warning, even if the person cancelled while recovery
  ran, and makes no claim of deletion or later cleanup. C0 measured an exact
  list match (road map 6 §3 q1); AssemblyAI's [list endpoint](https://www.assemblyai.com/docs/pre-recorded-audio/api-reference/transcripts/list)
  caps a page at 200 newest rows. An outage, longer lag, more than 200
  intervening transcripts or multiple matches can require manual dashboard
  cleanup. Crash recovery and a durable pending-submission journal are
  outside this rule.
- **R6-15 — A transcript marker identifies audio and the request, not display
  caches.** The source identity is exactly the file's byte size, rounded
  modification second, media duration and audio presence, together with the
  unchanged provider and requested speech models, language, speaker labels
  and vocabulary. Width, height, video presence, thumbnail height, maximum
  thumbnails, peak buckets per second, path, region and credential do not
  identify the transcript. The reader projects existing wide source stamps
  onto those four fields, including markers whose irrelevant fields differ;
  a cache hit rewrites neither the marker nor the transcript. A real later
  fetch writes the narrow marker only after its transcript write succeeds.
  Explicit refresh and remote deletion retain their existing rules. A missing
  or malformed relevant source field is a cache miss; no project format or
  marker version changes. This identity still uses modification seconds and
  recorded duration, without a content hash or path.
- **R6-16 — A current transcript batch may be reused without credentials.**
  A keyless cloud run is admitted only when the request is nonempty, refresh is
  false, and EVERY distinct job media has a readable source identity, a
  matching R6-15 marker and request, and a decodable transcript. Admission
  re-reads all files at run time and retains them before deriving any cue;
  one missing, stale, malformed or unreadable entry refuses the whole batch
  without extraction, network or partial captions. An empty words array is a
  current transcript and answers with the existing no-speech outcome. A
  keyless run skips the entire janitor, including unrelated package media,
  retains all pending deletion IDs without rewriting their files, and reports
  each as deferred: no deletion was attempted or confirmed. A later keyed
  run retries IDs only when safe to send, with the originating account and
  region's key. Keyed janitor-first ordering, failed-delete holds and
  per-media partial-success behavior remain. Generate Captions and the MCP
  `transcribe` tool share this coordinator admission, while the sheet shows
  keyless eligibility only for nonempty all-cached rows. Stop before the
  sheet's main-thread completion prevents placement of a success already
  queued, retaining its cleanup report. No endpoint is resolved for a
  keyless run and no credential is added to a tool call or project file.
