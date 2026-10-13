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
  **Updated 2026-09-30:** the plan is to open-source Reelcut, with every AI
  feature bring-your-own-key (the AssemblyAI key here, the assistant's
  Anthropic key under AI-8). No Reelcut-run relay is planned; C2 stays iced
  (#125), and the owner called a change to this "increasingly unlikely".
  **Amended by NM-4** (rename R0): `~/Library/Application Support/Reelcut/`
  is now `~/Library/Application Support/Frame Job/` (the file keeps its
  name, `assemblyai-key`).
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
  the reader does not.** A clip's `speed` is bounded to 0.1–10 (×0.1 – ×1000
  since #190) by the OPS
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
  **Amended 2026-10-01, by the owner's decision of 2026-09-30 (#41): the
  reader refuses an out-of-range `speed`, and the clamps above stay as a
  second layer.**
  - `Project::validate`'s `check_clips` (`core/src/model_query.rs`) refuses
    any clip whose `speed` is outside `SPEED_MIN`..=`SPEED_MAX`. That covers
    the timeline and every nest, and every source kind.
  - The bounds are `core/src/edit_clip_timing.rs`'s constants: `set_speed`
    clamps to them and `rate_stretch` stays inside them. The reader reads
    them, not a copy, so widening the range (#190) moves the reader with it.
  - The sentence names the clip and the value as JSON spells it:
    `clip 12's speed 2500.0 is outside ×0.1–×1000`.
  - It refuses rather than clamps. As D7-1 does for times, the file fails to
    open at any format version and is not rewritten.
  - A person sees the sentence through `ReelCoreError` in NSDocument's
    open-failure alert, and an agent through `open_project`. `finish` runs
    the same `validate`, so no edit can produce such a clip.
  - No persisted key changes, so `RC_FORMAT_VERSION` stays 10.
  - The premise "because the reader does not" now reads "and the reader
    refuses one too". Every clamp and bound above is KEPT unchanged as
    defence in depth. `cloud_captions_probe.py`'s `jobs` rows feed them a
    snapshot decoded without the reader.
  - The DECLINED sentence above is overturned.
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
  a key named `endpoint` — is recorded as GitHub issue #94 rather
  than guessed at here. The
  Settings window's **Verify** runs on `CloudTranscriber`'s own `work`
  queue, one of the seams `app/CLAUDE.md` lists, and adds no queue (R6-7).
  **Amended by NM-5 and NM-6** (rename R0): "Reelcut ▸ Settings…" is now
  "Frame Job ▸ Settings…"; `ReelcutAssemblyAIRegion` is now
  `FrameJobAssemblyAIRegion`.
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
- **R6-17 — `transcribe`'s seven refusals have one precedence, and the
  answer is the winner's own sentence.** The seven are (1) an unknown clip,
  (2) a scope with nothing to transcribe, (3) a misspelt `engine`, (4) a
  cloud-only argument under `apple`, (5) no credential, (6) a media over the
  ten-hour limit and (7) a media HELD by R6-11 (named under `refresh`, the
  one way a held media is reached). When two apply the order is
  1 > 2 > 3 > 4 > 5 > 7 > 6. The scope is read before `engine`; under `apple`
  no key, length or hold is consulted; a keyless run runs no janitor, so it
  holds nothing, and builds no client, so it measures no length (R6-16); a
  held media is never fetched, and the ten-hour check is the head of the
  fetch. A per-media winner (6 or 7) arrives as "The transcription failed:
  clip N: …", followed only by R6-4 and R6-16's deletion lines; every other
  winner is its own sentence alone, and no answer carries a loser's words.
  1–5 restate spec §7.9's order; 5 > 7, 5 > 6 and 7 > 6 are new, recorded
  from `cloud_captions_proof.py`'s row RP (issue batch B24, #80), which
  observed all 21 pairs in this order before this entry was written.
- **R6-18 — A request's only timeout is an idle one; a server that drips
  holds it for as long as it drips (accepted).** `timeoutIntervalForRequest`
  resets on every byte, `timeoutIntervalForResource` is URLSession's
  default, and the poll ceiling is read only between polls, so no request
  has a total deadline. Measured by `cloud_captions_probe.py`'s section
  `drip`: a reply dripped a byte every 100 ms under a 1.5 s idle timeout
  (85 bytes over 8.71 s) was waited out and the run completed in 10.70 s
  (DR1), while the same timeout against a socket silent for 12 s failed the
  run in 2.09 s (DR0, the CONTROL) — the `--only drip` run that observed it;
  the full probe run measured 9.37 s and 2.31 s. Stop ends a dripping upload
  or poll, because the token cancels the running task (read from the code;
  row ST·upload measured it against a silent upload, 0.03 s); it is not
  heard inside a submit, which takes no token, so the submit's id always
  arrives and is deleted (R6-14
  read across; the sheet's Stop during a 6 s submit finished 6.0 s later,
  row ST·submit); and MCP `transcribe`'s cloud arm has no Stop at all.
  Accepted because the far end is AssemblyAI or a relay speaking its
  protocol (R6-6), and a total deadline would fail a large upload on a slow
  line; C2 revisits it. DECLINED for now: a per-request resource timeout.
- **R6-19 — A Stop bounds a DELETE; it never skips one.** The three
  DELETEs a keyed run sends — the janitor's (`retryDeletes`), `refusing`'s
  on every throwing exit of `poll` and of `fetch`'s refusal, and `fetch`'s
  own after the write — read the run's cancel token, and none is cancelled
  at the press: the token is read as a STOP, never attached to the task.
  A DELETE is cut `deleteAfterStop` = 2 s of WALL CLOCK after the later of
  the Stop and its own start. 2 s is above C0's slowest DELETE (1.70 s), so
  a Stop during a submit or a wait still deletes the transcript it
  orphaned (rows ST·submit, ST·wait); wall clock, because a server that
  drips resets an idle timeout on every byte and would stretch any bound
  read from one (R6-18). A cut DELETE answers `failed` and is owed under
  R6-4 unchanged: the janitor's stays in its file with `remote_deleted:
  false` and puts its media in `janitorFailed` (R6-11 holds it); `fetch`'s
  writes `remote_deleted: false`, is reported, and is retried by the next
  keyed run, or R6-4's dashboard sentence names it when its file did not
  land. `poll`'s cut DELETE has no cache file and is reported nowhere, as
  any failed DELETE there already was — a defect, not a decision. Fixed by
  R6-20 (issue batch B43, #201). Nothing
  else changes: no other request gains a total deadline, the submit still
  takes no token (R6-14, R6-18), and MCP `transcribe`'s cloud arm still
  has no Stop, so its DELETEs run as before. DECLINED: cancelling a DELETE
  at the press, which would orphan the transcript of every Stop during a
  submit or a wait (issue batch B35, #187 item 5).
- **R6-20 — A transcript refused after it was made, whose DELETE failed, is
  reported for the dashboard and never retried.** It covers every
  `refusing`: `poll`'s throwing exits (R6-19's cut DELETE among them),
  `requireEchoedID`, and `fetch`'s refusal of words that repeat the key.
  The DELETE's answer rides on the thrown `Refusal`, and the run keeps the
  media in `Report.refusedUndeleted`, so the report card, the MCP `note` and
  the failure text all say R6-4's dashboard sentence for it ("Delete it in
  your AssemblyAI dashboard"), once per media, and never the retry sentence.
  There is no retry because no file holds the id. A DELETE that answered,
  or was never sent, is owed nothing. DECLINED: writing the media's cache
  file as a tombstone, which would replace a current transcript or an older
  id still owed a delete (R6-11). DECLINED: a second persisted id list,
  which R6-11 already declined (issue batch B43, #201).
- **R6-21 — A cached transcript is not re-checked for the key when it is
  read (accepted).** Since issue batch B34 (a861f8c, 2026-09-30) a
  transcript whose words carry the key is refused before any write. Before
  B34 only a server that put the key in the words could have made such a
  file, and the stand-in does that only in the probe's section `echo` row
  E3, which B34 itself added. Reelcut has never been released (R6-5,
  2026-09-30). R6-16 serves a current batch with no key at all, where no
  check is possible. DECLINED: a read-time check when a key is present,
  which would make one package current with a key and stale without one,
  and turn a cache hit into a paid re-fetch (issue batch B43, #200 item 1).
- **R6-22 — With Speakers on, each speaker's Subtitles cues are their own
  colour, and nothing else marks them** (issue batch B46, #93; the owner,
  2026-09-30). Colour only, no label: AssemblyAI's "A"/"B" would read as a
  bug (naming speakers is #192). The palette is
  `CaptionStyle.speakerPalette`, broadcast subtitling's white, yellow,
  cyan, green (`[1,1,1,1]`, `[1,1,0,1]`, `[0,1,1,1]`, `[0,1,0,1]`), a named
  table with no setting, assigned in order of each speaker's first
  appearance among the run's placed cues in timeline order, cycling after
  four. A speaker is a label within ONE media's transcript (R6-3):
  AssemblyAI letters each file's speakers afresh, so "A" in two media is
  two speakers. Subtitles only: the five word styles keep their own
  colours and still close a page at a speaker change. Automatic whenever
  speaker labels are on: no checkbox, no `transcribe` argument; this
  deliberately changes a Speakers run from all-white cues to coloured
  ones. A cue with no speaker (the on-device engine, Speakers off, a word
  AssemblyAI left unlabelled, an imported file) writes no colour and takes
  no slot, so such a run places byte-identical clips and W-7's
  byte-identical Subtitles still holds for it. Persisting speakers stays
  rejected (road map 6).
- **R6-23 — Every string a server sends is checked for the key whole, and
  every one the app relays is bounded** (issue batch B56, #205).
  (a) `fetch` refuses words when any string literal in the served `words`
  JSON repeats the key. The strings are found by a lexical scan of the
  bytes and each is decoded from its JSON escapes, so every object key and
  every string value is seen, at any depth, and every value of a repeated
  key. The raw bytes are checked too. The refusal applies whether or not
  `TranscriptWord` decodes the field: R6-3 keeps the bytes verbatim, so a
  field Reelcut never reads would otherwise carry an escaped key onto
  disk. The scan is lexical, not a `JSONSerialization` tree walk, because
  a parser keeps only a repeated key's first value. This replaces B43's
  decoded-fields check. R6-20 applies to the refusal.
  (b) The model and language the server names are cut to 64 Unicode
  scalars (63 + "…"). That is B43's rule (#200), recorded here.
  (c) The three sentences relayed as the service wrote them (a 402, any
  other 4xx, a transcript's `error`) are cut to 300 Unicode scalars (299 +
  "…"). The cut comes after the key filter, so it never splits the key
  into a piece the filter cannot see. 300 is a ceiling against a broken or
  hostile server, not a measured length.
  DECLINED: bounding inside `withoutCredential`, because the two kinds of
  string take different limits. DECLINED: a tree walk (see (a)).
  DECLINED: paraphrasing a sentence.
- **R6-24 — A transcript id the person's key cannot delete holds its media
  for ever (accepted)** (#44; the owner, 2026-10-01). `AssemblyAIClient
  .delete` answers `.failed` for any non-2xx answer (`classify`), a 404
  included, so a well-formed transcript id from another account puts its
  media in `janitorFailed`, and R6-11 holds that media in every run, since
  every run's DELETE fails again. What AssemblyAI answers for a foreign id
  is unmeasured, and no one will measure it: that needs a second account.
  **Why accepted:** every person uses their own key (R6-5, R6-12), so a
  foreign id comes only from a hand-edited or imported cache file; the
  risk is low. Also held by this entry: a malformed cache file's deletion
  ids cannot be recovered, and a retry needs the originating account's or
  region's key. Source: `archive/reelcut-roadmap-6.md` §10.10, §10.20.
  Treating a 404 as deleted is not decided here.
