# Reelcut — road map 6: captions from the cloud (AssemblyAI Universal-3.5 Pro)

**Status: DESIGNED, not built; the spike (C0) has NOT been run.** Nothing in
this document is in the tree. Everything in §2 was read from AssemblyAI's
own documentation on 2026-09-17 and is cited; everything in §3 is a question
the plan leans on and has not measured, and two of its rows (q2, q4) can
overturn the plan the way R0's did. The baseline this was written against:
schema version 8, `OP_NAMES` 57, the catalog at 77 tools, road map 4's S1
and road map 5's E1/E2 landed.

Road map 2's phase 4 shipped File ▸ Generate Captions… and `transcribe`
over Apple's on-device recogniser (`app/Sources/Transcriber.swift`), and it
carries the limits that recogniser has: a ceiling of about a minute per
task that is REPORTED rather than worked around, four on-device languages
on this machine, a TCC grant an agent-driven app cannot obtain, and the
accuracy of a dictation model. The user's ask (2026-09-17) is a second
engine behind the same menu item: AssemblyAI's Universal-3.5 Pro, an
external service, with — in the ask — "a way to upload clips to a bucket
somewhere from which urls can be generated", a controlling web service that
mints upload URLs and signed read URLs, and a way to delete the objects when
done. §0 comments on that shape before §1 decides; the short version is
that the bucket is not what AssemblyAI needs, the web service IS needed for
one reason the ask did not name, and the app-side work is the same under
every answer to that reason, so it is built first and alone.

---

## 0. The idea, commented

**AssemblyAI does not need a bucket.** Its API takes audio two ways: a URL
its servers can fetch (`audio_url` — a public URL or a time-limited signed
one), or a direct upload to `POST /v2/upload`, which answers with a private
URL "accessible only to AssemblyAI's backend servers", usable only as the
`audio_url` of a transcript request, and deleted by AssemblyAI after the
transcription (within 24 hours, at most 48). `DELETE /v2/transcript/{id}`
removes the transcript and that upload at once. Every part of the ask's
storage design — mint an upload URL, upload to it, mint a read URL, hand
that to AssemblyAI, delete when done — is what `/v2/upload` already does
inside AssemblyAI, with a 2.2 GB ceiling per upload that a 16 kHz mono
extract of ten hours of speech (1.15 GB) does not reach. The bucket would
be a second copy of the audio, a second lifecycle to get right, and a
second place a mistake leaks it.

**What the ask's web service is actually for is the API key.** A desktop
binary cannot hold a secret: an AssemblyAI key compiled into Reelcut is
readable by anyone with `strings`, and it is the key to an account that
bills by the hour. So the real question under the ask is *who pays
AssemblyAI* — and it is a product question, not an engineering one:

- **The person brings their own key** (they open an AssemblyAI account,
  get $50 of credit and a key, paste it into Reelcut once). Then there is
  no server, no bucket and nothing to operate: the app talks to
  `api.assemblyai.com` directly and the key lives in the person's own
  Keychain. This is what this document builds as **C1**, and it is the
  only version a proof can run offline and for free, against a stand-in
  server.
- **Reelcut pays** (the key is Reelcut's; the person is metered). Then a
  server is mandatory, and it must know WHO is calling — a licence key, a
  sign-in, a receipt — or it is a public endpoint that spends the
  project's money. That server is **C2**, and the ask's bucket design is
  one of two right shapes for it (§6c). C2 cannot be built until the
  identity question has an answer, and the design does not pretend to
  give one.

**The shape that lets either answer be a later phase**: the app speaks
AssemblyAI's own protocol to a configurable base URL with a configurable
credential (§5c). C1 sets those to `api.assemblyai.com` and the person's
key; a proof sets them to `127.0.0.1:<port>` and a nonsense string; C2 sets
them to Reelcut's relay and the person's licence, and adds at most one
transport conformer for the bucket variant. Nothing about extraction,
caching, timing, cue building or placement changes between the three.

**Three things the ask got right and this design keeps**: the audio must
leave the machine only when a person or an agent has chosen that by name,
with the destination and the price in front of them (§4, R6-2); whatever
is uploaded must be deleted afterwards, and by us, not by a retention
policy we hope about (R6-4 — AssemblyAI keeps a transcript indefinitely
by default with no TTL configured); and uploads should be the clips'
audio, not the media files — which the shipped extractor already does.

**One thing this design changes about the shipped feature's shape, and
why.** Phase 4 transcribes each clip's source WINDOW, extracted, and that
was right for a recogniser with a one-minute ceiling and no bill. A cloud
transcript is paid for and has a 10-hour ceiling, so the unit becomes the
MEDIA: one upload per file, the transcript cached in the package beside
the peaks and the speech probabilities, and every clip's captions derived
from it — so a re-cut, a split, a second run with a different scope and a
duplicate clip cost nothing and touch no network. The price of that choice
is that a three-hour file used for two minutes bills three hours (63
cents at the published rate), and the sheet says so before the button.
§7 records the windowed alternative and why it lost.

---

## 1. The decision, in one paragraph

**Generate Captions gains an Engine — "On this Mac" (today's recogniser,
unchanged, still the default) or "AssemblyAI" — and with the second the
whole audio of each media in scope is extracted to a temporary 16 kHz mono
WAV, uploaded to `POST /v2/upload`, transcribed by `POST /v2/transcript`
with `speech_models: ["universal-3-5-pro", "universal-2"]`, polled to
completion, read back as words, written VERBATIM to
`cache/transcripts/<media id>.json` under the package's stamp-and-marker
discipline, and DELETED from AssemblyAI; the clips' cues are then built from
the cached words through the existing `CaptionCues` and `CaptionLayout`,
so a cloud caption is the same text clip an on-device one is.** The key is
the person's own, in the Keychain, entered once in a new Reelcut ▸
Settings… window; the base URL and the credential are the one seam a
relay (C2) would replace. No op, no schema change, no FFI change, no new
tool: `transcribe` gains four arguments and the catalog stays at 77. No
`async` exception: `URLSession`'s delegate and completion-handler API is
complete for an upload, a poll and a delete.

---

## 2. What AssemblyAI's documentation says — read 2026-09-17

Every row is a fact the plan leans on, with where it was read. Prices and
limits change; the constants that carry them into the tree are dated (§8).

| Fact | Value | Source |
|---|---|---|
| Model name in a request | `speech_models: ["universal-3-5-pro", "universal-2"]` — an array in priority order; the two are the only values, and that pair is the documented default | [POST /v2/transcript](https://www.assemblyai.com/docs/api-reference/transcripts/submit) |
| Which model ran | the response carries `speech_model_used` | [GET /v2/transcript/{id}](https://www.assemblyai.com/docs/api-reference/transcripts/get) |
| Direct upload | `POST /v2/upload`, raw bytes, `authorization: <key>`; answers `{"upload_url": …}`, a private URL only AssemblyAI's servers can read; max **2.2 GB** | [FAQ: upload URLs](https://www.assemblyai.com/docs/faq/why-cant-i-access-urls-from-the-upload-endpoint-directly), [FAQ: limits](https://www.assemblyai.com/docs/faq/are-there-any-limits-on-file-size-or-file-duration-for-files-submitted-to-the-api) |
| Transcript limits | **5 GB** and **10 hours** per `audio_url` | same FAQ |
| Upload retention | uploads deleted after transcription, within 24 h and at most 48 h, "regardless of configuration" | [Data retention](https://support.assemblyai.com/articles/2240096256-does-assemblyai-offer-zero-data-retention) |
| Transcript retention | **indefinite** with no TTL and no BAA; a TTL can be set on the account (minimum 1 h) | same |
| Deletion | `DELETE /v2/transcript/{id}` deletes the transcript and the upload "right away" | [DELETE](https://www.assemblyai.com/docs/api-reference/transcripts/delete) |
| Status values | `queued`, `processing`, `completed`, `error` (+ `error` text) | GET reference |
| Words | `words[]`: `text`, `start`, `end` in **milliseconds**, `confidence` 0–1, `speaker` (null unless `speaker_labels`) | GET reference |
| Duration | `audio_duration` in **seconds**, integer | GET reference |
| Language | `language_code` optional (omit → detection); `language_detection`; `language_confidence` in the response | POST/GET references |
| Universal-3.5 Pro languages | 18 languages, 21 codes: `en en_au en_uk en_us es fr de it pt ar da nl fi he hi ja zh no sv tr vi`; dialects need no code; other languages fall back to Universal-2 when both models are named and detection is on | [Supported languages](https://www.assemblyai.com/docs/speech-to-text/pre-recorded-audio/supported-languages) |
| Options used here | `speaker_labels` (needs `punctuate: true`, the default); `keyterms_prompt` up to 1000 terms on Universal-3.5 Pro; `prompt` up to 1500 words (not used, §7) | POST reference |
| Options refused here | `webhook_url` (a desktop app has no public endpoint; polling is the design), `multichannel`, `disfluencies` (default false — "um" is not a caption) | POST reference |
| Price | async Universal-3.5 Pro **$0.21 per hour** of audio; speaker labels **+$0.02/h**; $50 of free credit on a new account | [Pricing](https://www.assemblyai.com/pricing) |
| Time to transcribe | "the vast majority of files … complete in under 45 seconds" | [FAQ: how long](https://www.assemblyai.com/docs/faq/how-long-does-it-take-to-transcribe-a-file) |
| Signed URLs | S3 presigned, Azure SAS and GCP signed URLs are accepted as `audio_url` and must be FRESH at submission | [Common errors](https://www.assemblyai.com/docs/pre-recorded-audio/guides/common_errors_and_solutions), [S3 guide](https://www.assemblyai.com/blog/transcribing-audio-files-in-an-s3-bucket-with-assemblyai) |
| EU | `api.eu.assemblyai.com` in place of `api.assemblyai.com` | POST reference |
| Retries | AssemblyAI's own guidance: retry after a 5xx or a failed upload | [Retrying requests](https://www.assemblyai.com/blog/customer-issues-retrying-requests) |

Not read, and left to C0: the `content-type` the upload endpoint expects
(the SDKs send `application/octet-stream`; the guide page answered 404 on
the day), and whether a bad `language_code` is refused at submission or
only after the download (q5).

---

## 3. C0 — the spike, to run before the plan leans on it

Instruments go in `tools/proof/cloud_spike/` and are tracked, as
`silence_spike/` and `recording_spike.py` are. Rows q1, q2, q5 and q6 need
a real key in `RC_ASSEMBLYAI_KEY` and cost cents; the rest cost nothing.
The fixture is road map 4's: `say -o` with two `[[slnc]]` pauses, 10.39 s,
whose level rule puts the pauses at **2.72–4.29 s and 6.68–7.81 s** on its
digital silence — the truth every timing below is measured against.

- **q1 — the round trip.** Upload the fixture's 16 kHz mono WAV, submit,
  poll, fetch, delete. Record: upload seconds and MB/s from this host,
  seconds from submit to `completed`, `speech_model_used`, the words, and
  whether any word's `[start, end)` crosses a known pause (it must not).
  Repeat with `speaker_labels: true`. Repeat with `language_code: "en"`.
  A word that straddles a pause by more than a frame is a timing fact the
  design would have to pad for.
- **q2 — the upload format** (can overturn 5a). The same fixture as WAV
  (32 kB/s), as AAC-LC 64 kbps mono in an `.m4a` (`AVAssetWriter`,
  8 kB/s) and, if `ExtAudioFile` will write it, as FLAC. Sizes, and every
  word's `start` delta against the WAV run. **The question is AAC's
  priming delay**: an encoder prepends about 2112 samples, at 16 kHz
  132 ms, that the container's edit list is supposed to hide; a decoder
  that ignores the list puts every caption 132 ms late. WAV is the default
  and needs no answer; a smaller format is taken only on a measured
  delta under half a frame at 30 fps.
- **q3 — App Transport Security.** Plain HTTP to `127.0.0.1` from the
  signed app with `NSAllowsLocalNetworking` in `project.yml`, and from a
  bare `swiftc` probe with no plist at all. The proof's stand-in server
  (5i) speaks HTTP, not TLS, and ATS is enforced on macOS; if the probe is
  blocked, the stand-in grows a self-signed certificate and the probe
  pins it.
- **q4 — a late audio track** (can overturn 5b's mapping). A fixture whose
  audio begins 1.5 s after its picture (`ffmpeg -itsoffset 1.5` on the
  audio input): does an extract of the WHOLE file, written from
  `startSession(atSourceTime: .zero)`, keep the 1.5 s at its head, or
  drop it? If it drops it, every word of such a file is 1.5 s early and
  the mapping needs the audio track's own start time — read once, stored
  in the cache file, and added on read.
- **q5 — when a bad `language_code` is refused.** `"xx"` at
  `POST /v2/transcript`: a 400 at submission (the upload is spent but
  seconds, not minutes) or an `error` status after processing. Decides
  whether the tool validates codes against a local table or relays the
  server's sentence.
- **q6 — what a deleted transcript answers.** `DELETE` then `GET`: the
  status code and body, so the live proof row can assert it.
- **q7 — the Keychain from an ad-hoc-signed bundle** (can overturn 5d).
  `SecItemAdd` / `SecItemCopyMatching` from `make app`'s binary: does it
  prompt, and does a REBUILT binary — a fresh ad-hoc signature, which every
  `make app` produces — read the item without a prompt or at all? The
  login keychain's ACL names the signing identity, and an ad-hoc identity
  is per build. Try `kSecUseDataProtectionKeychain` too. If every rebuild
  prompts, the fallback is a `0600` file under
  `~/Library/Application Support/Reelcut/`, recorded as the weaker choice
  it is.
- **q8 — the ceilings.** A 1-hour file (a real recording, or the fixture
  looped): upload time, `completed` time, and the `audio_duration`
  billed, so §8's timeout constants are numbers and not guesses.

---

## 4. Decisions for spec §11 — recorded before C1's first line

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
  retention (indefinite) is why the delete is not optional.
- **R6-5 — The app never holds an AssemblyAI key of Reelcut's.** The
  credential is the person's own, in their Keychain, or a relay's token
  (C2). It is never an argument of `transcribe` — an argument is written
  into every agent transcript and every log — and never a launch argument,
  which `ps` shows to every user. `RC_ASSEMBLYAI_KEY` in the environment
  is the one override, for proofs, and it is read only when the Keychain
  has nothing.
- **R6-6 — The protocol boundary is the base URL and the credential.**
  The client speaks AssemblyAI's REST API to `AssemblyAIConfiguration`'s
  base URL; the stand-in server, the EU endpoint and a same-protocol relay
  are configurations. A relay that must own the bytes (the bucket shape,
  §6d) is one more `TranscriptTransport` conformer and nothing above it
  changes.
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

---

## 5. C1 — the specification

No op (`OP_NAMES` stays 57), no schema change (version 8 stands), no FFI
change, no new tool (the catalog stays 77), the core untouched. Every size
toll in 5h is paid FIRST and alone as a pure move, on road map 2's terms.

### 5a. The engine and the run

`TranscriptionEngine` is `apple` | `assemblyai`, spelled those two ways in
the tool, the sheet's popup ("On this Mac", "AssemblyAI") and the
persisted key `ReelcutCaptionEngine` (the sheet remembers the last choice;
an agent call never reads it — R6-2). `Transcriber` keeps its name and its
job: it is the on-device engine and is not touched beyond the tolls.
`CloudTranscriber` (new) takes the SAME `[Transcriber.Job]`, the same
`CancelToken` (widened to hold a `URLSessionTask` beside the speech task,
under the same lock, cancelled outside it), the same `frame`, and answers
the same `Transcriber.Outcome`, so `TranscribeSheetController.finish` and
the tool's placement code do not know which engine ran.

The run, on the `work` queue, synchronous:

1. **Janitor** (R6-4): for every `cache/transcripts/*.json` whose
   `remote_deleted` is false, `DELETE` again, 5 s each, best effort.
2. **Group** the jobs by media id. For each media, in the order of its
   first clip: read `CacheStamp.stamp(for:url:)` NOW and compare with the
   transcript marker (5b). Equal → the media is **cached**, no network.
   Otherwise, or with `refresh`, the media is **to upload**.
3. For each media to upload: **extract** its whole audio track to a
   temporary WAV (`Transcriber+Extract.swift`'s extractor, the shipped
   settings, range = the whole asset, `NSTemporaryDirectory()`, deleted
   in a `defer`); refuse by name a media over **10 hours** (AssemblyAI's
   ceiling) before extracting; **upload** it; **submit**; **poll** every
   3 s until `completed` or `error`, with the ceiling in §8; **fetch**;
   **write** the cache file then its marker; **delete** remotely and
   record the answer. One media's failure is reported under `problems`
   for every clip on it and the run carries on — phase 4's rule — except
   cancellation, which throws and places nothing, and an AUTH failure
   (401/403), which ends the run at once because every later media would
   fail the same way and each costs an upload.
4. For each job: **derive** its words from the cache (5b's mapping),
   build cues with `CaptionCues.build(from:frame:clip:)`, and append. A
   clip whose window holds no words is "no speech was recognised in it",
   as today.

Progress is the bar's one number: extraction 0–0.25 of a media's share
(frames written over frames expected), upload 0.25–0.65 (`URLSession`'s
`didSendBodyData`), processing 0.65–0.95 advancing on the clock against
q8's measured rate and holding at 0.95, fetch and cache to 1.0. The detail
line says the phase and the file — "Uploading intro.mov · 41 MB of 115" —
and while waiting, the seconds waited, so a stuck queue is visible rather
than silent.

### 5b. The transcript cache

`cache/transcripts/<media id>.json` and `<media id>.complete.json`, the
peaks pair's shape (a sidecar, not a child, so either can be deleted alone).
Paths and post kind (`"transcripts"`) live in a new `MediaTranscript.swift`,
NOT in `MediaCacheFiles.swift` (550, at the cap for a file that must not
grow).

The JSON, sorted keys, `.atomic`:

```json
{
  "provider": "assemblyai",
  "transcript_id": "6f2a…",
  "requested": {
    "speech_models": ["universal-3-5-pro", "universal-2"],
    "language_code": null,
    "speaker_labels": false,
    "keyterms_prompt": []
  },
  "speech_model_used": "universal-3-5-pro",
  "language_code": "en_us",
  "language_confidence": 0.99,
  "audio_duration": 3723,
  "extracted_seconds": 3723.41,
  "audio_track_start_ms": 0,
  "fetched_at": "2026-09-17T14:02:11Z",
  "remote_deleted": true,
  "words": [
    {"text": "Hello", "start": 600, "end": 1120, "confidence": 0.98, "speaker": null}
  ]
}
```

`words` is AssemblyAI's array as it arrived — milliseconds, not ticks —
because a cache that stores the provider's answer unchanged can be
compared byte for byte with what the stand-in served, re-derived under a
future rule, and never argued with. `audio_track_start_ms` is q4's answer
(0 unless the spike says otherwise). The marker is a `TranscriptStamp`:
`source: CacheStamp` (so a relink, an edited file or a changed duration
invalidates it exactly as it invalidates the peaks) plus `provider`,
`speech_models`, `language_code`, `speaker_labels` and `keyterms_prompt`
— the REQUEST, so a run with a different language, with speakers turned
on or with a new vocabulary is a new transcript, and the sheet says which
files it will upload for that reason. `MediaTranscript.Loader` is
`MediaPeaks.Loader`'s shape: one read per media, a `pending` set.

**The mapping**, the one piece of arithmetic in the file, and the place
phase 4's "no `in` term" simplicity is given back: a word at media
milliseconds `[s, e)` is at ticks `m = s × 600` (600 000 ticks a second),
and for a clip with `in`, `speed` and `content_length = duration × speed`
(`Transcriber.contentLength`, the core's `model_query.rs` rule) the word
is the clip's when `in ≤ m < in + content_length`, landing at
`clip.start + (m − in) / speed`, its end likewise, both clamped into
`[clip.start, clip.start + clip.duration]`. A reversed clip is refused as
it is today (its speech is backwards on screen). Two clips over one media
at different `in` points get different words from one transcript; a split
clip's halves partition the words with none lost and none doubled — the
proof's claim (5i·5).

### 5c. The client — `AssemblyAIClient.swift`

A final class over one `URLSession` with its own delegate
`OperationQueue` (`Transcriber.delivery`'s twin, for the same reason: the
default is the main queue and an off-main tool must not wait on it), a
`base: URL`, a `credential: String`, and five synchronous methods that
each wait on a semaphore the delegate signals — `TaskSink.wait`'s shape:

- `upload(file:) -> URL` — `uploadTask(with: POST /v2/upload, fromFile:)`,
  `authorization: <credential>`, `content-type: application/octet-stream`,
  progress by `didSendBodyData`; the body streams from disk and is never
  in memory. One retry on a transport error or a 5xx, none on a 4xx.
- `submit(_ params: TranscriptRequest) -> String` — `POST /v2/transcript`
  with `audio_url`, `speech_models`, `language_code` (absent for auto),
  `speaker_labels`, `keyterms_prompt` (absent when empty); answers the id.
- `poll(id:) -> TranscriptResponse` — `GET /v2/transcript/{id}`; up to
  three consecutive 5xx or transport errors are tolerated and logged,
  the fourth fails the media.
- `delete(id:) -> Bool` — `DELETE /v2/transcript/{id}`.
- `verify() -> Result<Void, ClientError>` — `GET /v2/transcript?limit=1`,
  the cheapest authenticated call, for the Settings window's button.

Errors are named, in the order a person can act on them: no network
(`NSURLErrorNotConnectedToInternet` and its kin, "No network
connection"), the key refused (401/403: "AssemblyAI refused the API key
— check it in Reelcut ▸ Settings"), the account (402 or AssemblyAI's own
balance sentence, relayed verbatim), the request (400, relayed verbatim),
the server (5xx after the retries, "AssemblyAI answered <code>"), and a
transcript that ended in `status: "error"` (its `error` text, verbatim).
The client is Foundation only — no AppKit, no document — so a probe
drives it against the stand-in over a socket and, for the retry and
backoff rules, against an injected `URLProtocol` stub with no socket at
all.

`AssemblyAIConfiguration` resolves the base URL: `-RCAssemblyAIEndpoint`
from the argument domain (the `RCRecordingFolder` idiom) wins, else the
region key `ReelcutAssemblyAIRegion` (`us` → `https://api.assemblyai.com`,
`eu` → `https://api.eu.assemblyai.com`); and the credential:
`SecretStore` (5d) first, `RC_ASSEMBLYAI_KEY` in the environment when the
store has nothing. A base URL that is not `https` is accepted only for a
loopback host (q3's row is what makes that line honest).

### 5d. The credential, the region and the settings window

`SecretStore` is a protocol with `read()`, `write(_:)`, `remove()`;
`KeychainStore` implements it over `SecItemCopyMatching` / `SecItemAdd` /
`SecItemUpdate` / `SecItemDelete` with service
`com.kgalligan.reelcut.assemblyai`, account `api-key`, and whatever q7
decides about the data-protection keychain; `MemoryStore` is the probe's,
so no proof ever reads or writes a person's real item. The key is never in
`UserDefaults`, never in the package, never in a log; the Settings window
shows it masked and offers Remove.

**Reelcut ▸ Settings… ⌘,** is new chrome — the app has had nothing to
persist beyond view state — and it is a window, not a sheet:
`SettingsWindowController.swift` (≤ 400), one pane for now,
"Transcription": the key (an `NSSecureTextField` and Save / Remove; a
`KeychainStore` write on Save), the region popup (United States /
European Union → `ReelcutAssemblyAIRegion`, pinned by the harness like
every key the chrome reads), a **Verify** button (`client.verify()` on
the `work` queue, "Key accepted" or the refusal sentence on main), and
one paragraph of plain words: what is uploaded, that it is deleted after,
the rate, and a link to the account page. No key set is not an error
anywhere in this window; it is a state the sheet names (5e).

### 5e. The sheet

`TranscribeSheetController` gains, under Language, an **Engine** popup
whose choice re-populates the Language popup: On this Mac → today's
on-device list; AssemblyAI → "Detect automatically" then the 21 codes of
§2 by display name (`AssemblyAILanguages.swift`, a dated static table).
With AssemblyAI chosen the card also shows **Speakers** (a checkbox, off:
"start a new caption when the speaker changes"), **Vocabulary** (a text
field, comma-separated, trimmed and de-duplicated into `keyterms_prompt`,
capped at 1000 with the cap named — the screencast's product names and
identifiers, which is what Universal-3.5 Pro's prompting is for) and
**Transcribe again** (a checkbox, off: ignore cached transcripts).

The summary line is the estimate, and it is a pure function
(`CloudEstimate.describe`) so the probe can pin its words: "2 files to
upload · 1:42:10 of audio · about $0.36 at AssemblyAI's published rate ·
1 file already transcribed", the duration a `ReelTime.format`, the money
from §8's dated constants. The hint changes with the engine — today's
"Nothing is uploaded." for On this Mac, and for AssemblyAI: "The audio of
these files is uploaded to AssemblyAI (United States), transcribed with
Universal-3.5 Pro, and deleted from AssemblyAI once the words have been
read back. Nothing is uploaded until Generate is pressed." The button is
disabled, with the note "No AssemblyAI API key is set — Reelcut ▸
Settings…", when the credential resolves to nothing; the grant machinery
is untouched and simply not consulted for the cloud engine, which needs
no grant.

The report card at the end lists, beside today's counts: the model that
ran when it was not Universal-3.5 Pro (R6-8), the detected language and
its confidence when detection was used, and any media whose remote delete
failed ("will be retried at the next run"). The
`NSSpeechRecognitionUsageDescription` in `project.yml` loses its "Nothing
is sent anywhere" — true of the grant it describes, false of the app once
this lands — for "Captions made with a cloud service are a separate
choice, made in the Generate Captions sheet."

### 5f. The cue builder's fifth rule

`CaptionCues.Word` gains `speaker: String?` (default nil, so every caller
and the harness's `cues` mode are unchanged), and `build` gains one rule
in the one place the rules live: **a word whose speaker differs from the
open cue's flushes the cue.** With `speaker_labels` off every word's
speaker is nil and the rule never fires, so an on-device transcript is
byte-identical to today's. The harness's `cues` mode reads `speaker` off
the word list when present; `phase4_chrome.py` section 8 is unchanged.

### 5g. The MCP mirror

`transcribe {clips?, language?, place?, engine?, speakers?, vocabulary?,
refresh?}` — four new arguments, no new tool, the catalog at 77.

- `engine`: `"apple"` (default, whatever the sheet last chose) or
  `"assemblyai"`; anything else refused by name with the two spellings.
- `language` with the cloud engine: `"auto"` (default) or a code, passed
  through; a code AssemblyAI refuses comes back as its own sentence (q5
  says at what cost). The on-device engine's two-part language refusal is
  untouched.
- `speakers`, `vocabulary` (an array of strings), `refresh`: refused by
  name with `engine: "apple"`, `voice_confidence`-with-`mode: "level"`'s
  precedent — an argument that cannot do anything is a mistake, not a
  no-op.

The refusal ORDER, phase 4's rule extended: the caller's own mistakes
first (unknown clip, empty scope, misspelt engine, cloud-only arguments
under the wrong engine), then the credential ("No AssemblyAI API key is
set. Set one in Reelcut ▸ Settings ▸ Transcription, or RC_ASSEMBLYAI_KEY
for a proof."), then a media over ten hours, then the network. The result
gains `engine`, `uploaded` and `cached` (media ids), `audio_seconds`
(the sum AssemblyAI reported, what was billed), `speech_model_used` (per
uploaded media), `language_detected` with its confidence, and `note` when
R6-8's fallback ran or a remote delete failed. `truncated` is never
present for the cloud engine — there is no ceiling to report — and its
absence is a claim the proof makes. The handler lives in a new
`AgentServer+CloudCaptions.swift`; `transcribe` in `AgentServer+Captions.swift`
dispatches on `engine` and is otherwise the code it is. It stays in
`offMainTools` for the reason it is there. The catalog's `transcribe`
entry is rewritten to say both engines in one paragraph each, with the
consent sentence in the cloud one.

### 5h. Files, tolls, seams

Tolls, each a pure move, its own commit, gated alone before any feature
code, so what changes afterwards is attributable:

| Toll | File | Now | Cut |
|---|---|---|---|
| 1 | `Transcriber.swift` | 934 — over the cap since it landed, and `reelcut-remaining.md` §3 does not list it | the language block (`Language`, the two cached lists, `named`, `defaultLanguage`, `language(matching:)`, ~190) → `Transcriber+Languages.swift`; the extractor (`extractSettings`, `extractAudio`, ~130) → `Transcriber+Extract.swift`; `jobs`, `contentLength`, `hasTranscribableClip` (~110) → `Transcriber+Jobs.swift`. Widenings: `contentLength` and `extractAudio` internal, because the cloud run calls both |
| 2 | `AgentCatalog+Files.swift` | 609 | the three caption entries (`import_captions`, `transcribe`, `export_captions`) → `AgentCatalog+Captions.swift`, spliced where they were, `AgentCatalog+Audio.swift`'s precedent |
| 3 | `TranscribeSheetController.swift` | 505, +≈150 to come | `finish`, `summary`, `truncationText`, `viewDidDisappear` and the menu-command extension → `TranscribeSheetController+Commit.swift` |

Then the feature, in ≤ 400-line files:

- `Transcriber+Extract.swift` — the extractor generalised AFTER its move:
  `extractAudio(url:range:to:)`, the job form calling it (behaviour
  byte-identical, the WAV a fixture can compare).
- `CloudTranscriber.swift` — 5a's run.
- `MediaTranscript.swift` — 5b: paths, the file and marker types, the
  loader, the mapping, the janitor's list.
- `AssemblyAIClient.swift`, `AssemblyAIConfiguration.swift`,
  `AssemblyAILanguages.swift` — 5c and the table.
- `SecretStore.swift` (`KeychainStore`, `MemoryStore`), `CloudEstimate.swift`
  — 5d and 5e's pure parts.
- `SettingsWindowController.swift`; `AppDelegate+Menus.swift` (544) takes
  the one item (Reelcut ▸ Settings… ⌘,) and no more.
- `TranscribeSheetController.swift` — the Engine popup and the three cloud
  rows; `TranscribeSheetController+Commit.swift` — the report's new lines.
- `CaptionLayout.swift` (444) — `Word.speaker` and the fifth rule, ~15 lines.
- `AgentServer+CloudCaptions.swift`; `AgentServer+Captions.swift` (409) —
  the dispatch; `AgentCatalog+Captions.swift` — the entry.
- `MediaCacheFiles.swift` — ONE constant (`transcriptsKind`) and nothing else.
- `project.yml` — the usage string's rewording; `NSAppTransportSecurity`
  `NSAllowsLocalNetworking: true` (q3); no entitlement: the app is not
  sandboxed and the hardened runtime does not gate outgoing connections.
- `tools/proof/harness/main.swift` — pins `ReelcutCaptionEngine` and
  `ReelcutAssemblyAIRegion`; the `cues` mode reads `speaker`.

Seams to write FIRST, in the tree, before lanes start (R2's lesson):
`TranscriptionEngine`, `CloudTranscriber`'s signature over
`Transcriber.Job` / `Outcome` / `CancelToken`, `TranscriptRequest` /
`TranscriptResponse` (`Codable`, the fields of §2), `TranscriptStamp`,
`SecretStore`, and `AssemblyAIConfiguration`'s two resolvers. Not touched:
`ProjectDocument.swift` (1353) — `fileWrapper(ofType:)` whitelists `cache/`
whole (spec §5.6), so `transcripts/` rides into the package and out of an
untitled document's temporary cache with no line there; a scout confirms
that before the lane relies on it. `TimelineView.swift` is frozen and has
no reason to know.

### 5i. The proof

Three instruments, on the tree's terms. **`tools/proof/assemblyai_fake.py`**
is a stand-in server (`http.server`, no dependencies) speaking the five
calls of 5c with a scenario set over a control endpoint — the words to
serve, how many polls answer `processing` first, a 401, a 5xx once or
always, an `error` status, a poll that never completes — and a request
log the proof reads back: every method, path, header and JSON body, and
the upload's bytes on disk. **`cloud_captions_proof.py`** drives
`make app`'s binary over MCP, launched with
`-RCAssemblyAIEndpoint http://127.0.0.1:<port>` and
`RC_ASSEMBLYAI_KEY=proof-key`, over a project made from the `say` fixture.
**`cloud_captions_probe.py`** compiles a probe from the whole of
`app/Sources` (`recording_probe.py`'s instrument, verbatim).

Over MCP: **(1)** `engine: "nope"`, `speakers` under `apple`, and the
cloud engine with the key unset (the proof launches a second instance
without the variable) are refused by name, and none touches the fake (its
log is empty); **(2)** a two-clip project over ONE media uploads ONCE: the
log holds one `POST /v2/upload` whose body is a RIFF WAV of
`2 × 16000 × seconds` bytes within a frame and byte-identical across two
runs, one `POST /v2/transcript` with `authorization: proof-key`,
`speech_models` `["universal-3-5-pro", "universal-2"]`, no `language_code`
under `language: "auto"` and `"en"` under `"en"`, N polls, one `DELETE`
with the served id; **(3)** the placed cues equal, tick for tick and word
for word, what the proof computes IN PYTHON from the served words and the
clips' `in`/`speed`/`start` — the mapping in a second language, the
oracle — through the harness's `cues` mode for the line-breaking;
**(4)** the cache file's `words` are byte-equal to the scenario's array,
the marker decodes equal to the stamp the proof computes from the file's
size and mtime, and `remote_deleted` is true; **(5)** a second run makes
NO request and reports the media under `cached`; `refresh: true` uploads
again; a `set_media` relink to a different file uploads, and a relink
back uploads again (one transcript per media, not a history); a split
clip's two halves partition the words, a clip at a later `in` gets the
later words only, a reversed clip and an `enabled.audio`-off clip are
skipped by name; **(6)** a 401 fails the run with the key sentence and
writes no cache; a `status: "error"` fails that media with the served
`error` text verbatim, no cache, no marker, and the OTHER media's cues
still land; a 5xx once on upload is retried (two uploads in the log) and
succeeds; three 5xx fail; **(7)** `speakers: true` sends
`speaker_labels: true` and a served speaker change breaks the cue where
the rule says; `vocabulary` arrives trimmed, de-duplicated and capped;
**(8)** `transcribe` without `engine` runs the on-device path — the fake's
log stays empty — and `phase4_proof.py` scores 84/84 against the new
binary; **(9)** `truncated` is absent from every cloud result;
**(10)** the `NSAppTransportSecurity` row: the built app reaches the
loopback fake over plain HTTP (the whole script is this claim); **(11)** a
scenario with `remote_deleted` failing (the DELETE answers 500) leaves the
flag false, and the next run's FIRST request is that DELETE.

The probe: **(12)** the mapping at its boundaries — a word straddling
`in`, one ending past the window, speed 2× and 0.5×, clamping — as pure
calls; **(13)** the stamp's fields, and that each of the five request
fields changing invalidates while the region changing does not;
**(14)** `CloudEstimate.describe` over a table (one file, many, cached
and uploaded mixed, speakers on, the rate constants); **(15)** the client's
retry and backoff over an injected `URLProtocol`: one retry on 5xx, none
on 4xx, three tolerated polls, the poll ceiling ending the media with a
DELETE issued; **(16)** the cancel token cancelling an upload task
mid-body against the fake, and a cancel during polling issuing the
DELETE; **(17)** `KeychainStore` through `MemoryStore` — never the real
item; **(18)** the Settings pane's rows and the sheet's popup rows and
hint texts as structural reads, and the Settings window photographed
through `cacheDisplay` (a window, not a sheet, so it CAN be) with the key
field empty; **(19)** the fifth rule at its boundaries through the `cues`
mode.

**Live**, skipped BY NAME when `RC_ASSEMBLYAI_KEY` is unset or the host
has no route to `api.assemblyai.com`, its rows counted: **(20)** the
fixture's round trip against the real service — `speech_model_used` is
`universal-3-5-pro`, the words contain the fixture's sentence in order,
no word crosses a known pause by more than a frame, the DELETE answers
2xx and a GET afterwards answers what q6 recorded; and **(21)** the second
run is served from the cache in under a second with no upload.

Mutants, each named in the record with its score: the stamp comparison
deleted (5: uploads twice); the `in` term dropped (3, 5); the DELETE
removed (2, 4); the retry removed (6); the fifth rule removed (7, 19);
`speech_models` pinned to Universal-2 (2); the janitor removed (11); the
env-var override reading BEFORE the store (17, with a store holding a
value); the 401 arm not ending the run (6: two uploads where one is
right); the rate constant halved (14). Every earlier proof re-run against
the final binary and quoted "against the N it had at the time".

### 5j. What only a person at the machine can check

- The Keychain prompt, if q7 says there is one, from the signed bundle,
  and again after a rebuild.
- The Settings window's look in both appearances, and Verify's two
  answers.
- A real recording of twenty minutes, home upstream: the phases' feel,
  whether "Waiting for AssemblyAI · 34 s" reads as patience or as a hang,
  and the captions' timing by eye against the speech.
- The EU region with an account that has it enabled.
- The report card when the fallback ran, on a Korean or Polish recording.

### 5k. Limits recorded, not fixed

- **The whole file is billed** (R6-3): a long file used briefly costs its
  length; the estimate is what tells the person before the button. §7 has
  the windowed alternative.
- **A relink mid-run** writes a transcript of the OLD file under the OLD
  stamp; the next run sees the mismatch and re-transcribes. The ledger
  that orders cache passes is not used here — a network run is minutes,
  and holding a relink behind it would be worse than one wasted upload.
- **A code AssemblyAI refuses costs the upload** if q5 answers "at
  submission" — seconds — and the whole transcription if it answers
  "after". The popup's 21 rows cannot be wrong; the tool's pass-through
  can.
- **`transcribe` over MCP cannot be cancelled**, as it cannot today; a
  cloud run holds the connection for the whole round trip, and a client
  that gives up leaves a transcript AssemblyAI is still making, deleted
  by the janitor at the next run.
- **Two media entries over one file upload it twice** (the cache is per
  media id, as every cache in the package is). Consolidate does not
  change this.
- **A reversed clip inside a nest, a nest's own audio, a still** — not
  transcribable, as today; the cloud engine inherits `Transcriber.jobs`'s
  five refusals unchanged.
- **The sheet remembers the engine; the tool does not** (R6-2). An agent
  that wants the cloud says so every time.

---

## 6. C2 — the relay: the ask's design, specified as far as it can be

### 6a. What it is for

C2 exists for one reason: Reelcut pays AssemblyAI and the key is
Reelcut's. It is not a performance feature, not a privacy feature (the
relay is one more party that sees the audio's route), and not needed for
C1. Everything below assumes C1 is committed and its protocol boundary
(R6-6) is where the relay plugs in.

### 6b. The precondition nobody can build around

A relay must know who is calling. Otherwise it is a public endpoint that
converts anyone's HTTP into charges on the project's AssemblyAI account,
and a rate limit is not an answer — a rate-limited public endpoint is a
slower way to spend the money. The identity has to come from somewhere
the app does not invent: a licence key issued at purchase, Sign in with
Apple, a validated App Store receipt, or a Reelcut account. None of those
exists in the tree, none is a decision this document can make, and each
is a road map of its own. **Until one exists, C2 is not buildable**, and
the design's honest contribution is that C1 leaves exactly one seam for
it.

### 6c. Two shapes

**C2a — a same-protocol proxy.** The relay exposes AssemblyAI's own five
endpoints, checks the licence in the `authorization` header, swaps it for
the real key, forwards the request — the upload body streamed through,
never buffered — and meters on `audio_duration` when the poll answers
`completed`. **Zero app changes**: the base URL and the credential are
already configuration (R6-6). Its limit is the host's request-body
ceiling, which is what decides between the two shapes: a Cloudflare
Worker streams a body of up to 100 MB on the free plan and 500 MB on the
top one (a 16 kHz WAV is 115 MB an hour; q2's smaller format would
stretch that to 3–6 hours), while AWS API Gateway stops at 10 MB and a
Lambda URL at 6 MB, so on AWS this shape does not exist.

**C2b — the bucket relay, the ask's design.** The relay never touches the
bytes: it mints a presigned PUT, the app uploads straight to the bucket,
the relay hands AssemblyAI a presigned GET, and deletes the object when
the transcript has been read. Independent of any body limit, cheap to run
(control-plane only), and the shape to choose on AWS or for long
recordings. It costs the app one `TranscriptTransport` conformer (6e).

Recommendation, if and when 6b is answered: **C2b**, because the bucket
removes the one constraint that would otherwise decide the host, and
because a relay that never holds audio in memory is a relay whose bugs
cannot leak it. C2a is the shortcut to try first on Cloudflare with the
smaller upload format, since it needs no app work at all.

### 6d. The bucket relay's protocol

Every call carries `authorization: Bearer <licence>`; every answer is
JSON; every id is opaque to the app.

```
POST   /v1/jobs
       { "bytes": 115200000, "seconds": 3600, "content_type": "audio/wav" }
  →    { "job": "j_…", "upload": { "url": "<presigned PUT>", "headers": {…}, "expires_at": "…" } }
       refused: 401 (licence), 402 (quota), 413 (bytes over the plan's cap)

PUT    <upload.url>      the audio, streamed from disk by the app; the relay never sees it

POST   /v1/jobs/{job}/submit
       { "language_code": null, "speaker_labels": false, "keyterms_prompt": [] }
  →    { "status": "queued" }
       the relay: HEAD the object (it exists, its size matches), then
       POST api.assemblyai.com/v2/transcript with audio_url = a presigned
       GET good for 24 h (AssemblyAI downloads at queue time, not at
       submission), speech_models as C1 sends them, and
       webhook_url = the relay's own hook with a per-job secret

GET    /v1/jobs/{job}
  →    { "status": "queued" | "processing" | "completed" | "error",
         "transcript": { …AssemblyAI's response, verbatim… } | null,
         "error": "…" | null }
       the app polls this exactly as it polls AssemblyAI

       on the webhook: the relay fetches the transcript, stores it (KV,
       24 h TTL), DELETEs the bucket object and DELETEs the AssemblyAI
       transcript, and meters audio_duration against the licence

DELETE /v1/jobs/{job}    the app's acknowledgement once cached; the relay drops the stored transcript
```

Backstops the relay owns, because the app may vanish at any step: a
bucket lifecycle rule deleting objects after 24 h; a sweeper failing jobs
never submitted within an hour and jobs never fetched within a day, each
with its AssemblyAI DELETE; idempotent submit (a second `submit` on a job
that has one answers the same status). The relay stores no audio, logs no
audio, and keeps transcripts only until fetched or expired. `audio_duration`
from AssemblyAI, not the app's declared `seconds`, is what meters.

### 6e. The app's side

`TranscriptTransport` is the protocol 5c's client already satisfies —
`upload`, `submit`, `poll`, `delete`, `verify` — and `ReelcutRelayTransport`
is its second conformer: `upload` becomes `POST /v1/jobs` then the
presigned PUT; the other four are the relay's paths. `CloudTranscriber`
does not change. Settings gains a row (Provider: AssemblyAI with my key /
Reelcut) and the licence field the identity decision defines. The
stand-in server grows the relay's protocol beside AssemblyAI's, and the
proof's claims 2–11 run over both.

### 6f. Infrastructure notes

- AssemblyAI PULLS the object, so the bucket's egress is paid per
  transcription: S3 charges about $0.09 per GB; Cloudflare R2 charges
  nothing for egress and speaks S3's presigned-URL API. For an hour of
  WAV that is a cent on S3 and nothing on R2 — small, but it is the only
  recurring cost besides AssemblyAI's, and it is why R2 is the default
  suggestion.
- Presigned URLs must be fresh at submission (§2); mint the GET at
  `submit`, not at job creation.
- The relay needs a public HTTPS endpoint for the webhook, or it polls
  AssemblyAI itself; polling from a Worker is a cron, from a Lambda a
  step function — the webhook is simpler and AssemblyAI signs nothing, so
  the per-job secret in the URL is the authentication.
- Never return an AssemblyAI URL, id or error body to the app unwrapped;
  the app should not be able to tell which provider is behind the relay.

---

## 7. Not built, and why

- **A bucket in C1.** §0: AssemblyAI's upload endpoint is the bucket, with
  the deletion built in.
- **Windowed transcription** — extracting only the clips' source windows
  (phase 4's unit), or uploading the whole file once and submitting
  `audio_start_from` / `audio_end_at` per window. Cheaper for a long file
  used briefly; but the transcript is then a fact about a CUT rather than
  about a file, cannot be cached under a media stamp, and re-bills every
  re-run, every re-cut and every second scope. Deferred until the estimate
  line has been seen to bite; the request fields are there when it does.
- **`prompt`** (1500 words of free-text context). The vocabulary field is
  the structured form of the same lever, is capped, and can be shown back
  to the person in the report; a paragraph cannot.
- **Webhooks in the app.** No public endpoint; polling every 3 s against a
  service that answers in under a minute is fine.
- **Persisting the sheet's other rows** (speakers, vocabulary). The engine
  persists because choosing it twice is a cost decision made twice; the
  vocabulary is a fact about one recording.
- **A speaker's colour on the caption clip** (`Clip.label` per speaker).
  A good idea for a later list: `CaptionLayout.Cue` would carry a label
  and `place` would set it, which touches the shared placement path.
- **Streaming (realtime) transcription** — a different product
  ($0.45/h), for microphones, not files.
- **Apple's `SpeechAnalyzer`** as a third engine — still `async`-only and
  still behind the deployment target (spec §11).
- **A second key vault** (a `0600` file) unless q7 forces it.

---

## 8. Numbers a person may want to change before the build

| Constant | Value | Where it comes from |
|---|---|---|
| `AssemblyAIRates.perHour` | $0.21, dated 2026-09-17 | §2; shown as "at AssemblyAI's published rate" so a stale number reads as one |
| `AssemblyAIRates.speakersPerHour` | +$0.02 | §2 |
| `pollInterval` | 3 s | AssemblyAI's SDKs' default |
| `pollCeiling` | `max(300 s, audio seconds / 2)` | a queue wait is bounded below; q8 sets the divisor |
| `uploadRetries` | 1 | AssemblyAI's own guidance is "retry"; one is enough to cover a dropped socket, and two uploads of a 100 MB file are the cost of a third |
| `pollFailuresTolerated` | 3 | consecutive 5xx or transport errors |
| `maxMediaSeconds` | 36 000 | AssemblyAI's 10-hour ceiling |
| `maxKeyterms` | 1000 | §2 |
| `deleteTimeout` | 5 s | the janitor's budget per item |
| upload format | WAV, 16 kHz mono 16-bit | q2 decides otherwise only on a measured timing delta under half a frame |

---

## 9. The build's shape

Two pipelines, not one, on the memory's terms: **C0** is a spike commit
of its own (instruments plus this document's §3 filled in, as R0's and
S0's were), and **C1** is one `/litecode` pipeline whose `request.md`
carries the standing constraints — the 400-line cap for new files, the
three tolls first and alone, the four op-table mirrors (unchanged here,
and said so), the typecheck baseline of 0 errors and 4 named warnings,
the parity log empty, "commit only when asked" — and the seams of 5h
written into the tree BEFORE the pipeline starts, so every lane compiles
against one shape. C2 has no pipeline until 6b is answered.

What C0 can overturn, and what the plan does then: q2 (a smaller upload
format is offset-free → 5a's extractor writes it, and the claim about the
WAV's byte length becomes a claim about the container); q4 (the extract
drops a late track's offset → `audio_track_start_ms` becomes real and the
mapping adds it); q7 (the Keychain prompts on every rebuild → the `0600`
file, recorded as weaker); q3 (ATS blocks the probe → the stand-in speaks
TLS with a pinned certificate); q5 (refused after download → the tool
validates codes against the 21 plus Universal-2's list, read into a
second dated table).
