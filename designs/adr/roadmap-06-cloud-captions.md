# Captions from the cloud (AssemblyAI) — road map 6

- **Status:** C1 Built and reviewed (2026-09-21; follow-up issues #28–#33 closed by 2026-09-22).
  C2, the relay, is Deferred by the user (2026-09-21). It is designed below and not built.
- **Original:** `archive/reelcut-roadmap-6.md` (3992 lines). It is the full record. Sections cited
  below as "orig §x" refer to it.
- **Spec decisions:** R6-1..R6-16 in spec §11 (`designs/reelcut-design.md`), which stay binding:
  - R6-1: one command with two engines. A cloud caption is an ordinary text clip.
  - R6-2: audio leaves the machine only when someone names the cloud engine, with the price shown.
    The tool's default is always `apple`.
  - R6-3: a transcript is a per-media asset in the package.
  - R6-4: we delete the uploaded transcript right away and record that we did.
  - R6-5: the app never holds a key of Reelcut's. The key is the person's, in a `0600` file.
  - R6-6: the protocol boundary is the base URL plus the credential.
  - R6-7: no `async` exception.
  - R6-8: a fallback to Universal-2 is allowed and is reported.
  - R6-9: a proof-launched app never opens the person's stored key.
  - R6-10: the caption path clamps `speed`, the source length and `ms × 600`.
  - R6-11: a media whose delete is unconfirmed is HELD.
  - R6-12: no tool reads or writes the key or the region.
  - R6-13: the estimate shows a held media's price separately.
  - R6-14: a lost submit reply gets bounded list recovery and never a second POST.
  - R6-15: the transcript marker holds the audio identity plus the request, with no display-cache
    fields.
  - R6-16: current cached transcripts can be reused without a key.

## Context

Road map 2's File ▸ Generate Captions… used Apple's on-device recogniser. That recogniser had a
ceiling of about one minute per task, a few languages, a TCC grant an agent cannot obtain, and
dictation-grade accuracy. The user asked for a second engine, AssemblyAI Universal-3.5 Pro. The
ask pictured a bucket plus a web service that would mint signed upload and read URLs. The design
rejected the bucket: AssemblyAI's `POST /v2/upload` already is a private, auto-deleted bucket.
It also showed that the web service exists for one reason only, which is to keep an API key out of
the binary. So the real question was *who pays AssemblyAI*:

- **C1:** the person brings their own key. No server is needed. This is built.
- **C2:** Reelcut pays. A relay is then required, and it must know who is calling. This is deferred.

## Decisions

**Engine choice is a popup and an argument, not a new command (R6-1).** `TranscriptionEngine` is
`apple` | `assemblyai`. `CloudTranscriber` takes the same `Transcriber.Job`, `CancelToken`, frame
and `Outcome` as the on-device engine. The sheet's commit and the tool's placement do not know which
engine ran. (orig §1, §5a)

**The cloud unit is the whole MEDIA file, not the clip window (R6-3).** There is one upload per
media, and the provider's words are cached VERBATIM in `cache/transcripts/<media id>.json`, with a
`.complete.json` marker beside it. Every clip's cues are derived at run time, so re-cuts, splits and
re-runs cost nothing. The price is that a long file used briefly is billed in full, and the estimate
line says so before the button. Rejected: windowed transcription, either by extracting windows or
by using `audio_start_from`/`audio_end_at`. It re-bills every re-cut and cannot be cached under a
media stamp. (orig §0, §7)

**We delete the uploaded transcript ourselves, immediately (R6-4).** A `DELETE` follows the fetch
in the same run. The cache file records `remote_deleted`, and a keyed run's first act (the janitor)
retries every `false`. AssemblyAI's ≤ 48 h upload retention is the backstop. Its transcript
retention is indefinite, which is why the delete is mandatory. A retry is promised only when the
id was saved in the package (#29). Otherwise the report sends the person to the dashboard.
(orig §4, §10.15)

**The key is a `0600` file, not the Keychain (R6-5, C0 q7).** It lives at `~/Library/Application
Support/Reelcut/assemblyai-key`, is created `0600` in a directory made `0700`, and is never chmod'ed
afterwards. C0 measured what happens to a login-keychain item written by one ad-hoc signature:
- The next build blocks on a `SecurityAgent` modal, even with `kSecUseAuthenticationUIFail`.
- It gets `errSecInvalidOwnerEdit` on delete.
- Every `make app` produces a new ad-hoc signature.
- The data-protection keychain answers −34018 `errSecMissingEntitlement`.

The file is recorded as the weaker choice. `SecretStore` (`read`/`write`/`remove`, with `FileStore`
and `MemoryStore` conformers) is the seam for a future `KeychainStore` under a stable Developer ID
signature, plus a one-time migration. (orig §3 q7, §5d)

**Key hygiene rules.**
- The key is never a `transcribe` argument, because arguments land in agent transcripts and logs.
- It is never a launch argument, because `ps` shows those.
- It is never in `UserDefaults`, the package or a log.
- `RC_ASSEMBLYAI_KEY` in the environment is the one override, for proofs, and is read only when the
  store is empty.
- The Settings field shows a FIXED-length mask, because a key-length mask leaks the length.
- Server sentences relayed verbatim (402, 4xx, transcript `error`) pass through
  `AssemblyAIClient.withoutCredential(_:)`. A server that echoes the header must not put the key
  into an MCP refusal (reader review R2·1).
- The `Makefile` has `unexport RC_ASSEMBLYAI_KEY`, because `xcodebuild` writes every task's
  environment into `XCBuildData/*.xcbuilddata`. `tools/proof/makefile_env_proof.py` proves it.
- The client follows no redirects, because a redirect would forward `authorization`.

(orig §4 R6-5, §10.12, §10.13 H·2, R2·1)

**A proof-launched app never opens the person's stored key (R6-9).**
- `-RCSecretFolder <path>` overrides the store's folder.
- With `-RCAssemblyAIEndpoint` set and no secret folder, `store()` is an EMPTY `MemoryStore`.
- Both arguments are read from the argument domain only.
- The fake server logs an `authorization` value only when it is one of the two allow-listed
  dummies.

C2's relay would need a configuration key of its own, not this launch argument. (orig §5d)

**The protocol boundary is the base URL plus the credential (R6-6).** `AssemblyAIConfiguration`
resolves the base URL: `-RCAssemblyAIEndpoint` wins, then the region default
`ReelcutAssemblyAIRegion` (`us`/`eu`). A non-`https` base URL is accepted only for a loopback host.
C0 q3 measured that ATS does not block loopback HTTP, so `project.yml` gets no ATS key. The fake
server, the EU endpoint and a same-protocol relay are all just configurations. (orig §3 q3, §5c)

**Upload format is 16 kHz mono 16-bit FLAC, written through `AVAudioFile`, with the WAV as
fallback.** C0 q2 measured the options:
- FLAC gives 0 ms word-timing delta against the WAV at 48.1% of its bytes.
- AAC-LC 48 kbps shifted words by up to 38 ms, which is more than half a frame, so it was rejected.
- `AVAssetWriter` has no FLAC file type on macOS 26 and throws an uncatchable ObjC exception.

The on-device engine still gets the WAV. (orig §3 q2, §5a)

**Extract the whole asset from time zero, and `audio_track_start_ms` is always 0.** C0 q4 measured
that the extractor KEEPS a late audio track's leading empty edit, so an extract millisecond equals
a media millisecond. The field stays in the cache file so that a future macOS which trims the edit
can be caught by re-running q4. (orig §3 q4, §5b)

**The mapping from provider words to a clip.** A word at media ms `[s,e)` becomes `m = s × 600`
ticks. It belongs to a clip when `in ≤ m < in + content_length`, and it lands at
`start + (m − in)/speed`, clamped to the clip. Reversed clips are refused. Speed, source length and
`ms × 600` go through clamped doors (R6-10):
- `Transcriber.placed`
- `Transcriber.contentLength`, bounded to `maxSourceTicks` = 1e15 because Swift sums it
- `MediaTranscript.sourceTicks(milliseconds:)`, clamped to ±`Ticks.max/600`

A second guard in `CloudTranscriber.transcribe` drops words past the clip end. (orig §5b, §10.10,
§10.11)

**The cue builder gets a fifth rule: a speaker change flushes the open cue.** `CaptionCues.Word`
gained `speaker: String?`. With speaker labels off, every speaker is nil and the output is
byte-identical to before. (orig §5f)

**The request names both models in documented order, and a fallback is reported (R6-8).**
`speech_models: ["universal-3-5-pro","universal-2"]` is sent. `speech_model_used` is cached, and
the report or `note` says when the model that ran was not 3.5 Pro. (orig §4)

**The run's shape.** It is synchronous on a serial `work` queue, uses `URLSession` delegate and
completion handlers, and adds no `async` (R6-7). The steps:

1. Janitor.
2. Group jobs by media and compare the marker with the stamp: cached, upload, or HELD.
3. For each media: extract, upload, submit, poll every 3 s up to `pollCeiling`, fetch, write the
   file THEN the marker (and the marker only if the file landed, reader review R1·3), delete.
4. Derive the cues.

One media's failure is reported and the run carries on. The exceptions are a cancel and a 401/403,
which end the run because every later upload would fail the same way. Cancel is checked before the
janitor and between janitor items (R1·2). (orig §5a, §10.13)

**A media whose delete is unconfirmed is HELD, not re-fetched (R6-11).** The cache file is the only
record of the remote id, and a fetch would overwrite it and orphan the transcript. A current cache
is still served, `refresh` is refused, and the hold releases once a janitor delete succeeds. The
accepted cost: a long DELETE outage blocks re-transcription of already-transcribed media.
(orig §10.10)

**`delete` answers three states: `deleted`, `failed` or `notSent`.** Transcript ids from a package
are untrusted input. `isPlainIdentifier` gates every interpolated id, because the reader review
showed `../upload` and `../../etc/passwd` reaching the API host with the person's key. A `notSent`
id is in neither janitor list: it is not claimed as deleted and not held for ever. `poll` throws
`.malformed` on such an id. (orig §10.13 R3·1, sceptic finding 6)

**A lost submit reply gets bounded list recovery, never a second POST (R6-14, #28).** The run takes
up to three looks at `GET /v2/transcript?limit=200`, 2.5 s apart, with a 5 s timeout each. It
accepts exactly one plain id whose `audio_url` is byte-equal to the upload URL. Otherwise it
returns an explicit dashboard warning. (orig §10.14)

**The transcript marker is audio identity plus request (R6-15, #30).** `TranscriptSourceStamp`
holds size, rounded modification second, duration and audio presence. The request part holds
provider, models, language, speaker labels and keyterms. Thumbnail and peaks constants no longer
re-bill. Old wide markers decode by projection. The region is deliberately not in the stamp.
(orig §5b, §10.19)

**Keyless reuse of cached transcripts, all or nothing (R6-16, #32).** With no key, a batch is
admitted only if every media is current and decodable. A keyless run skips the janitor entirely and
reports pending deletes as deferred. (orig §5a, §10.20)

**The chrome.**
- Reelcut ▸ Settings… ⌘, is a window, not a sheet. It has one headed pane, "Transcription", with
  no one-tab tab bar. It holds the key field, Save/Remove, the region popup, and Verify
  (`GET /v2/transcript?limit=1`), which runs on `CloudTranscriber`'s work queue (R6-12).
- A Verify answer belongs to the latest request and its captured inputs. When the inputs have
  changed, it says "Settings changed…" (#33).
- The sheet gains Engine, Speakers, Vocabulary (capped at 1000 through the single
  `TranscriptOptions.keyterms`) and Transcribe again.
- The pure `CloudEstimate` prices the run before the button. The per-file reasons are the summary
  label's tooltip.
- The estimate and the run classify a media in two places ON PURPOSE. A probe row compares them.

(orig §5d, §5e, §10.11, §10.16)

**The MCP mirror adds four arguments and no new tool.** `transcribe` gains `engine`, `speakers`,
`vocabulary` and `refresh`. Cloud-only arguments under `apple` are refused by name. A bad
`language_code` is relayed from the server's 400 at submission (C0 q5), so no second language table
is kept. `truncated` never appears for the cloud engine. A throw after billing names the bill in
the sentence (R5·2). The tool never reads the sheet's remembered engine (R6-2). (orig §5g)

**Rejected alternatives.**
- A bucket in C1.
- Webhooks in the app, because it has no public endpoint.
- The `prompt` field, because vocabulary is its structured, cappable form.
- Persisting speakers and vocabulary.
- Streaming transcription, which is a different product.
- AAC upload.
- The Keychain on ad-hoc builds.

(orig §7)

## C2 — the relay (designed, deferred)

**What blocks it (orig §6b):** a relay that spends Reelcut's AssemblyAI money must know who is
calling. That needs a licence key, Sign in with Apple, an App Store receipt or a Reelcut account.
None exists, and each would be a road map of its own. A rate limit is not a substitute. The user
deferred C2 on 2026-09-21: people supply their own key, and an integrated AI offering has not been
designed (orig §10.18).

**Two shapes (orig §6c):**
- **C2a, a same-protocol proxy.** The relay swaps the licence for the real key, streams the upload
  through, and meters on `audio_duration`. It needs zero app changes (R6-6). It is limited by the
  host's body ceiling: a Cloudflare Worker allows 100–500 MB, while AWS API Gateway allows 10 MB and
  a Lambda URL 6 MB, which rules out AWS.
- **C2b, a bucket relay (recommended).** The relay mints a presigned PUT, the app uploads to the
  bucket directly, and the relay hands AssemblyAI a presigned GET that is fresh at submit time and
  valid 24 h. A webhook with a per-job secret triggers the fetch, the transcript is stored in KV
  for 24 h, the object and the AssemblyAI transcript are deleted, and usage is metered. It has no
  body limit and never holds the audio.

**Protocol sketch (orig §6d):** `authorization: Bearer <licence>`.
- `POST /v1/jobs {bytes,seconds,content_type}` returns the job plus a presigned upload. It can
  refuse with 401, 402 or 413.
- The app does `PUT <upload.url>`.
- `POST /v1/jobs/{job}/submit {language_code,speaker_labels,keyterms_prompt}`.
- `GET /v1/jobs/{job}` returns the status and AssemblyAI's transcript verbatim.
- `DELETE /v1/jobs/{job}` is the app's acknowledgement.

The relay also owns these backstops:
- a 24 h bucket lifecycle rule
- a sweeper for jobs never submitted within 1 h and never fetched within 1 day
- idempotent submit
- metering on AssemblyAI's `audio_duration`, never on the app's declared seconds
- never returning an AssemblyAI URL, id or error body unwrapped

R2 is the suggested bucket, because it has no egress fee.

**App side (orig §6e):** `ReelcutRelayTransport` would be a second `TranscriptTransport`
conformer, and `CloudTranscriber` would not change. Settings gains a Provider row and a licence
field. The fake server grows the relay protocol, and proof rows 2–11 run over both transports.

## What it built — where it lives now

All paths are in `app/Sources/` unless another folder is given:
- `CloudTranscriber.swift` (+`Media`, +`Report`): the engine enum, the run, the janitor, the hold,
  and `Report.deletionWarnings`.
- `CloudProgress.swift`: progress bands and detail strings.
- `CloudEstimate.swift`: the pure estimate and its reasons.
- `AssemblyAIClient.swift` (+`Session`, +`Submission`): the calls upload, submit, poll, delete and
  verify, plus the `Tuning` constants. `withoutCredential`, `isPlainIdentifier`, and R6-14 recovery
  live here.
- `AssemblyAITranscript.swift`: the wire values and `TranscriptOptions.keyterms`.
- `TranscriptStamp.swift`: the marker (R6-15).
- `AssemblyAIConfiguration.swift`: endpoint, region, `store()` (R6-9) and the loopback rule.
- `AssemblyAILanguages.swift`: the 21-code table, dated 2026-09-17.
- `SecretStore.swift`: `SecretStore`, `FileStore`, `MemoryStore`, and `writeAll` with its EINTR
  retry.
- `MediaTranscript.swift`: cache paths, file, loader and the mapping.
- `MediaCacheFiles.swift`: `transcriptsKind`.
- `Transcriber+Extract.swift`: the shared extractor, `writeFLAC` and `extractUpload`.
- `Transcriber+Jobs.swift` and `Transcriber+Languages.swift`: split out as size tolls.
- `CaptionLayout.swift`: `Word.speaker` and the fifth rule.
- `SettingsWindowController.swift`: Settings and `showSettings`. The menu item is in
  `AppDelegate+Menus.swift`.
- `TranscribeSheetController.swift` (+`Cloud`, +`Commit`): the sheet.
- `AgentServer+CloudCaptions.swift`: the cloud handler. `AgentServer+Captions.swift` dispatches on
  `engine`, and `AgentCatalog+Captions.swift` holds the catalog entry.
- `Makefile`: `unexport RC_ASSEMBLYAI_KEY`.

The proofs live in `tools/proof/`:
- `assemblyai_fake.py`: the fake server, with scenarios, `stall`, `drop_reply` and
  `echo_authorization`.
- `cloud_captions_probe.py`: compiled from source.
- `cloud_captions_proof.py`: MCP. `--live` runs it against the real API under a ledger capped at
  $0.25.
- `cloud_captions_live.py` and `cloud_live_ledger.py`, with `cloud_live_selftest.py`.
- `makefile_env_proof.py`.
- `cloud_spike/`: the C0 instruments.

## Known limits

- **The whole file is billed**, whatever part of it the clips use. A three-hour file used for two
  minutes costs about $0.63 at $0.21/h.
- **Two media entries over one file upload it twice**, because the cache is per media id.
- **A relink during a run** caches the OLD file under the OLD stamp. The next run sees the mismatch
  and re-transcribes.
- **A language code AssemblyAI refuses costs the upload.** It is a 400 at submit, and the orphaned
  upload is left to the provider's ≤ 48 h retention.
- **`transcribe` over MCP cannot be cancelled.** If a client gives up, the janitor cleans up on the
  next run.
- **The key file is readable by anything running as the person.** The FileStore's folder is `0700`
  only if FileStore created it. `ExportPresetsStore` and `FFmpegRewrap` create the same folder at
  the umask mode, so the key FILE stays `0600` but the folder may be listable.
- **A janitor 404 is a failure, which means a hold, not "already gone".** C0 q6 measured that a
  truly deleted transcript answers 200 with the sentinel `audio_url: "http://deleted_by_user"`.
  What the service answers for another account's well-formed id is unmeasured.
- **A prolonged DELETE outage holds every already-transcribed media** (R6-11, accepted).
- **Submit recovery covers only the newest 200 transcripts and three looks.** A crash between POST
  and reply cannot be recovered. There is no durable pending-submission journal and no account-wide
  janitor.
- **The transcript identity uses modification seconds and recorded duration**, with no content
  hash.
- **Client log lines (`AssemblyAIClient+Session.swift`) are block-buffered under a file redirect.**
  An instance log is a lower bound on requests, so count them through a pty.
- **This Mac's 16 kHz extract is not bit-deterministic.** One sample flips about one time in five,
  and an AAC source (`media/speech.mov`) varies by 60–115 samples. Rows that want bytes must use a
  population of runs and an uncompressed fixture.
- **Measured C0 numbers behind the constants** (orig §3, §8):
  - Processing runs at about 147× real time: an hour took 24.4 s.
  - `audio_duration` rounds UP.
  - Word placement does not drift over an hour.
  - `pollCeiling` = max(300 s, seconds/49).
  - `deleteTimeout` = 5 s; the worst DELETE seen was 1.70 s.
  - `retryBackoff` = 1 s, `requestTimeout` = 60 s, `maxMediaSeconds` = 36 000, `maxKeyterms` = 1000.
  - Rate: $0.21/h, plus $0.02/h for speakers, dated 2026-09-17.

## Open items

- C2, the relay, is deferred by the user and blocked on caller identity. Tracked in
  `designs/reelcut-remaining.md` §5f.
- `KeychainStore` waits for a stable Developer ID signature. Tracked in
  `designs/reelcut-remaining.md` §5f.
- Person checks, tracked in `designs/reelcut-remaining.md` §4f (the mic-input row and the tainted
  build databases in §4j):
  - the q7 Keychain prompt
  - the Settings window and the sheet looked at, and the reasons tooltip
  - Verify and a real 402 against the live service
  - a real 20-minute recording: how the progress feels and whether cue timing matches by eye
  - the EU region
  - the fallback report card
  - a 10-hour file
  - how a held media feels
  - ⌘, in a document window
  - `recording_proof.py` with a wired input
- Reader-review residue nits (tracked in `designs/reelcut-remaining.md` §5a and §5b):
  - "retried at the next run" is false for a `notSent` id
  - two row-I checks say "five" and assert six
  - a stale 2.5 s comment in `cloud_captions_proof.py`
- An `endpoint` (host) key in `transcribe`'s result (R6-12 residue). Tracked in
  `designs/reelcut-remaining.md` §5d.
- Items the reader review left UNJUDGED:
  - the 21 pairs of refusals
  - the sheet's Stop during upload, submit, wait and save
  - a server that drips bytes under the idle timeout
  - a second reader for fixes R1·1, R1·2, R1·3, R2·1 and H·3
  - the re-aimed mutants that were never re-run

  Tracked in `designs/reelcut-remaining.md` §5b.
- Candidates not started: windowed transcription (deferred until the estimate is seen to bite) and
  a per-speaker caption label/colour. Tracked in `designs/reelcut-remaining.md` §5d.
- Accepted limits a later phase may revisit: #28's bounded recovery, the janitor's 404 hold,
  #30's identity, the block-buffered client log, the support folder's mode. Tracked in
  `designs/reelcut-remaining.md` §5e and §5d.
- The rest of the app against a hand-written `speed` (H·4). Tracked in
  `designs/reelcut-remaining.md` §5a.

## Where to look in the original

- orig §0–§1: why no bucket, and why the question is who pays; the one-paragraph decision.
- orig §2: AssemblyAI facts read 2026-09-17, with sources and the measured corrections.
- orig §3 (q1–q8, §3a–§3c): the C0 spike, covering the round trip, the upload format, ATS, a late
  track, a bad language code, the delete sentinel, the Keychain, and the one-hour ceiling. Also the
  spend ($0.4353) and what each row overturned.
- orig §4: R6-1..R6-8 as first written.
- orig §5a–§5k: the C1 spec (run, cache, client, credential, sheet, fifth rule, MCP, tolls, proof
  rows 1–21, person checks, limits), with dated revisions.
- orig §6: the full C2 design.
- orig §7: not built, and why. orig §8: the constants. orig §9: how the build was split.
- orig §10.1–§10.8: the c1-tolls pipeline (size tolls, compiler-forced widenings).
- orig §10.9–§10.12: c1-parts, c1-run, c1-chrome and c1-close, with scores, mutants, live rows and
  spend ($0.00128).
- orig §10.13: the seven-reader review, its findings R1·1–R7·3, H·1–H·12, the mutant matrix, and
  both sceptic passes.
- orig §10.14–§10.20: #28, #29, #33, the final build, the C2 deferral, #30 and #32.
