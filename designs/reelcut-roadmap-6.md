# Reelcut — road map 6: captions from the cloud (AssemblyAI Universal-3.5 Pro)

**Status: DESIGNED, not built; the spike (C0) RAN on 2026-09-20 and §3 is
its record.** No C1 FEATURE code is in the tree; spec §11's R6 decisions
and §5h's three tolls are (§10), and the spike's instruments are, in
`tools/proof/cloud_spike/`. All eight of §3's rows were measured on that
date, nothing is owed by a row, and the sections each row overturned — §2's
two open questions, §5a's upload format, §5d's credential store, §5h's
`project.yml` bullet and toll 1's sentence, three of 5i's claims and §8's
constants — were REWRITTEN here rather than left standing beside the record
(§3a lists every one). Everything in §2 was read from AssemblyAI's own
documentation on 2026-09-17, is cited, and now carries what the service
actually answered where the two differ. The baseline this was written
against: schema version 8, `OP_NAMES` 57, the catalog at 77 tools, road map
4's S1 and road map 5's E1/E2 landed.

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
  `api.assemblyai.com` directly and the key lives in a `0600` file of the
  person's own (§5d, C0's q7). This is what this document builds as **C1**, and it is the
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
FLAC (the WAV as the fallback when that write refuses — §5a, C0's q2),
uploaded to `POST /v2/upload`, transcribed by `POST /v2/transcript`
with `speech_models: ["universal-3-5-pro", "universal-2"]`, polled to
completion, read back as words, written VERBATIM to
`cache/transcripts/<media id>.json` under the package's stamp-and-marker
discipline, and DELETED from AssemblyAI; the clips' cues are then built from
the cached words through the existing `CaptionCues` and `CaptionLayout`,
so a cloud caption is the same text clip an on-device one is.** The key is
the person's own, in a `0600` file under `~/Library/Application
Support/Reelcut/` (the Keychain is what q7 overturned; `KeychainStore` is
deferred to a stable signing identity — §5d, R6-5), entered once in a new
Reelcut ▸ Settings… window; the base URL and the credential are the one seam a
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
| Direct upload | `POST /v2/upload`, raw bytes, `authorization: <key>`, MEASURED to take `content-type: application/octet-stream`; answers `{"upload_url": …}`, a private URL only AssemblyAI's servers can read; max **2.2 GB** | [FAQ: upload URLs](https://www.assemblyai.com/docs/faq/why-cant-i-access-urls-from-the-upload-endpoint-directly), [FAQ: limits](https://www.assemblyai.com/docs/faq/are-there-any-limits-on-file-size-or-file-duration-for-files-submitted-to-the-api) |
| Transcript limits | **5 GB** and **10 hours** per `audio_url` | same FAQ |
| Upload retention | uploads deleted after transcription, within 24 h and at most 48 h, "regardless of configuration" | [Data retention](https://support.assemblyai.com/articles/2240096256-does-assemblyai-offer-zero-data-retention) |
| Transcript retention | **indefinite** with no TTL and no BAA; a TTL can be set on the account (minimum 1 h) | same |
| Deletion | `DELETE /v2/transcript/{id}` deletes the transcript and the upload "right away"; MEASURED (§3 q6): 200 in 0.35–1.70 s, and a GET afterwards answers **200, not 404**, with `audio_url: "http://deleted_by_user"`, `text: "Deleted by user."` and no words — a second DELETE answers 200 too | [DELETE](https://www.assemblyai.com/docs/api-reference/transcripts/delete), §3 q6 |
| Status values | `queued`, `processing`, `completed`, `error` (+ `error` text) | GET reference |
| Words | `words[]`: `text`, `start`, `end` in **milliseconds**, `confidence` 0–1, `speaker` (null unless `speaker_labels`) | GET reference |
| Duration | `audio_duration` in **seconds**, integer, and MEASURED (§3 q1) to round UP — 10.389 s bills as 11 | GET reference, §3 q1 |
| Language | `language_code` optional (omit → detection); `language_detection`; `language_confidence` in the response — MEASURED (§3 q1): detection answered `en` with confidence 0.9994, and an explicit `"en"` answered `language_code: "en_us"` with NO confidence | POST/GET references, §3 q1 |
| Universal-3.5 Pro languages | 18 languages, 21 codes: `en en_au en_uk en_us es fr de it pt ar da nl fi he hi ja zh no sv tr vi`; dialects need no code; other languages fall back to Universal-2 when both models are named and detection is on | [Supported languages](https://www.assemblyai.com/docs/speech-to-text/pre-recorded-audio/supported-languages) |
| Options used here | `speaker_labels` (needs `punctuate: true`, the default); `keyterms_prompt` up to 1000 terms on Universal-3.5 Pro; `prompt` up to 1500 words (not used, §7) | POST reference |
| Options refused here | `webhook_url` (a desktop app has no public endpoint; polling is the design), `multichannel`, `disfluencies` (default false — "um" is not a caption) | POST reference |
| Price | async Universal-3.5 Pro **$0.21 per hour** of audio; speaker labels **+$0.02/h**; $50 of free credit on a new account | [Pricing](https://www.assemblyai.com/pricing) |
| Time to transcribe | "the vast majority of files … complete in under 45 seconds"; MEASURED (§3 q1, q8): 2.8 s for 10 s of audio and 24.4 s for an hour, about **147× real time** | [FAQ: how long](https://www.assemblyai.com/docs/faq/how-long-does-it-take-to-transcribe-a-file), §3 q1/q8 |
| Signed URLs | S3 presigned, Azure SAS and GCP signed URLs are accepted as `audio_url` and must be FRESH at submission | [Common errors](https://www.assemblyai.com/docs/pre-recorded-audio/guides/common_errors_and_solutions), [S3 guide](https://www.assemblyai.com/blog/transcribing-audio-files-in-an-s3-bucket-with-assemblyai) |
| EU | `api.eu.assemblyai.com` in place of `api.assemblyai.com` | POST reference |
| Retries | AssemblyAI's own guidance: retry after a 5xx or a failed upload | [Retrying requests](https://www.assemblyai.com/blog/customer-issues-retrying-requests) |

Both rows this table left to C0 are answered in §3. The upload endpoint
takes `content-type: application/octet-stream` (q1), and a bad
`language_code` is refused **at submission**, a 400 in a quarter of a second
with the sentence "Language code xx is not supported." (q5) — the upload it
was submitted against is spent, and nothing is transcribed or billed.

---

## 3. C0 — the spike, run on 2026-09-20

Instruments in `tools/proof/cloud_spike/`, tracked as `silence_spike/` and
`recording_spike.py` are; that directory's README says how to run a row
again, what costs money, and what each of `--selftest`'s seven checks scored
when it was broken on purpose. Every number below is in
`tools/proof/work/cloud_spike/answers.json` (untracked, rebuildable) and
every paid call is in `ledger.json` beside it. **All eight rows RAN**; the
runner exited 0 with every reservation closed.

**The host is an input to half of these answers.** macOS 26.5.1, Xcode 26.2
(17C52), Apple Swift 6.2.3, Python 3.14.5, the default route over Wi-Fi.
Upload throughput measured **0.549–0.606 MB/s** for the 337 kB fixture and
**23.1 MB/s** for the 115 MB hour — the small number is per-request overhead,
not the link, and it is the large one a progress estimate should lean on.
Both probe bundles were ad-hoc signed with the hardened runtime,
`flags=0x10002(adhoc,runtime)`, which is what `make app` produces.

The fixture is road map 4's, remade by the runner: `say -o` with two
`[[slnc]]` pauses, **10.389 s**, whose truth pauses this host measured on its
digital silence at **2.72–4.29 s and 6.68–7.81 s** — road map 4's numbers to
the hundredth, so no timing below rests on a fixture that drifted.

### q1 — the round trip

**Measured.** Upload 336 532 bytes in 0.565–0.578 s; `POST /v2/transcript`
answered 200 in 0.264–0.279 s; `completed` after **2.8 s and three polls** at
one second — so the true processing time is under three seconds and what was
measured is the poll grid. `speech_model_used` was `universal-3-5-pro` in all
three calls. `audio_duration` came back **11** for a 10.389 s file: an
integer, rounded UP, and that is what bills. 23 words, confidence 0.87–1.00,
and the text in order is "The quick brown fox jumps over the lazy dog. Pack
my box with 5 dozen liquor jugs. How vexingly quick daft zebras jump!" — the
three pangrams, with "five" normalised to "5" and terminal punctuation the
recogniser chose. **No word overlapped either truth pause at all**; the
overlap list is empty, so "crosses by more than 33 ms" never arose. `speaker`
was null in the plain and `language_code` calls and `"A"` in the
`speaker_labels` one. Detection answered `language_code: "en"` with
`language_confidence` **0.9994**; asking for `"en"` explicitly answered
`language_code: "en_us"` and NO `language_confidence`. Each DELETE answered
200 in 0.48–0.52 s.

Two things §2 left open were answered on the way. The upload endpoint takes
`content-type: application/octet-stream` without complaint, and
`speech_models: ["universal-3-5-pro", "universal-2"]` was never refused, so
the runner's retry-without-the-field arm never fired.

`list_match` is **proven**: `GET /v2/transcript?limit=200` returned the
spike's own transcript, its `audio_url` equal to the upload URL byte for
byte, with the fields `audio_url, completed, created, error, id, region,
resource_url, status`. In the run this record is written from, the
entry was present in the ONE look the row took, straight after the submit.
The second look, five seconds on, runs only when the first finds nothing,
so it did not run, and no latency was recorded for the look itself. An
earlier, pre-fix reading of this row saw the entry absent at once and
present five seconds later, and it is what the caution below about list lag
was written from; `answers.json` no longer holds that reading, so it is an
anecdote here and not a measurement.

**Verdict.** §1's round trip is what the service does, at the timings §5a's
progress plan assumed. No timing pad is needed anywhere: the words do not
touch the pauses, so 5b's mapping needs no epsilon and 5i's live claim (20)
can assert "no word crosses a known pause" outright rather than "by more than
a frame". `audio_duration` rounding UP to the whole second is what the
estimate in 5e should round with. A transcript whose submit reply is lost CAN
be found again by its `audio_url`, and in this run it was there at once; a
recovery look should still tolerate a few seconds of list lag, which is a
caution carried from the earlier reading above and not something this run
measured.

### q2 — the upload format

**Measured.** The control first: **the same WAV uploaded twice gave word
starts identical to the millisecond**, every one of the 23, so the service
has no run-to-run jitter on this fixture and any delta below is the format's.

| Format | Bytes | Of the WAV | max │Δstart│ vs WAV run 1 |
|---|---|---|---|
| WAV 16 kHz mono 16-bit | 336 532 | 100% | — (0 against its own second run) |
| FLAC 16 kHz mono 16-bit | 161 991 | 48.1% | **0 ms** |
| AAC-LC 48 kbps mono `.m4a` | 64 396 | 19.1% | **38 ms** |

AAC at **64 kbps was refused by the encoder** at 16 kHz mono
("Cannot Encode Media"); 48 000 was the next bitrate tried and it wrote, and
the probe stops at the first that writes, so nothing lower was attempted. Its
38 ms is not the priming delay §3 suspected: the
deltas grow monotonically 0 → 38 ms across ten seconds, and the container's
2112-sample priming — visible as `source_start: 0.132` in the track's one
segment — is hidden from BOTH decoders that were asked, AVFoundation
(lag 0 samples) and `ffmpeg -ignore_editlist 1` (lag 0 samples). So the
offset the design feared is not there, and what is there is a lossy codec
moving word boundaries by up to a frame and a bit.

FLAC needed a different writer. **`AVAssetWriter` on this host has no
`org.xiph.flac` file type** — its list is `public.aiff-audio`,
`com.apple.m4a-audio`, `com.microsoft.waveform-audio`,
`com.apple.coreaudio-format`, `com.apple.quicktime-movie` and their kin — and
it refuses with an Objective-C exception Swift cannot catch, so the probe
writes FLAC through `AVAudioFile`, the `ExtAudioFile` path this row's
question named as the alternative. Its output is padded to a block boundary
(10.656 s of samples for a 10.389 s input); that decoded at lag 0, gave the
same 23 words with the same starts, and billed the same `audio_duration` of
11.

**Verdict — 5a changes.** FLAC passes the rule §9 set (max │Δ│ under half a
frame at 30 fps, with the control below that too) and halves the bytes, so
**the extractor writes FLAC and falls back to the WAV when the FLAC write
refuses**, and §8's format row says so. AAC is refused for C1: 38 ms is more
than half a frame, and buying 29% more of a file for a caption that is a
frame late is the wrong trade. The claim in 5i·2 about the upload's byte
length becomes a claim about the container (a FLAC stream whose decode is
sample-for-sample the WAV), which is the weaker claim §9 said it would
become.

### q3 — App Transport Security

**Measured.** A loopback `http.server` on an ephemeral port, and one plain
HTTP GET at it from three builds of the same probe, at `127.0.0.1` and at
`localhost`:

| Build | `http://127.0.0.1:<p>/` | `http://localhost:<p>/` |
|---|---|---|
| bare Mach-O, no plist at all | 200 `ok` | 200 `ok` |
| `RCSpikeQ3.app`, ad-hoc signed, hardened runtime, **no ATS key** | 200 `ok` | 200 `ok` |
| the same with `NSAllowsLocalNetworking: true` | 200 `ok` | 200 `ok` |

The app itself has no outgoing HTTP code today (`git grep URLSession -- app`
is empty), so an ad-hoc-signed bundle around the probe IS the "signed app"
row of this question, and it is the row that matters: it is signed the way
`make app` signs, with the hardened runtime on.

**Verdict.** ATS does not block plain HTTP to loopback on macOS 26.5.1, with
or without the key, bundled or not. **`project.yml` gains nothing** — the
`NSAppTransportSecurity` bullet in 5h is struck, the stand-in server of 5i
stays HTTP with no certificate to pin, and 5c's "not `https` is accepted only
for a loopback host" line stands on a measurement instead of a hope.

### q4 — a late audio track

**Measured.** `ffmpeg -itsoffset 1.5` over a black picture, written twice
(`late.mov`, PCM; `late.mp4`, AAC). The audio track's segments say what the
container holds: an **EMPTY edit of 1.5 s** at the head of the `.mov` and of
1.453 s at the head of the `.mp4` (its source start is
`kCMTimeInvalid`), then the speech. An extract of the WHOLE file at the
shipped settings, `reader.timeRange = (.zero, asset.duration)` and
`startSession(atSourceTime: .zero)`, came out 11.89 s for a 10.389 s
recording, and cross-correlated against `speech.wav` at
**+24 019 samples (1.501 s)** for the `.mov` and **+24 010 (1.501 s)** for the
`.mp4`, correlation 0.998 and 1.000.

**Verdict — 5b stands.** The offset is **KEPT**: the extract begins where the
picture begins and the silence is written out, so a word's time in the
extract is its time in the media and nothing is 1.5 s early.
`audio_track_start_ms` stays **0** and the mapping does not add it. The field
stays in the cache file as the record of a question that was asked and
answered, with a comment that it is 0 on this host's AVFoundation — a later
macOS that trimmed the empty edit would be caught by a re-run of this row.

### q5 — when a bad `language_code` is refused

**Measured.** `language_code: "xx"` at `POST /v2/transcript` answered **400 in
0.24 s**, body:

```json
{"error": "Language code xx is not supported. See https://www.assemblyai.com/docs/concepts/supported-languages."}
```

The upload it was submitted against is spent — nothing was transcribed and
nothing was billed.

**Verdict — 5g and 5k stand as written.** The refusal is at submission, in
seconds, in a sentence a person can act on, so the tool RELAYS the server's
sentence and does not carry a second dated table of language codes. §5k's
"costs the upload if q5 answers at submission" is the answer: the upload
(337 kB here, up to 55 MB for an hour) is spent and left to AssemblyAI's ≤ 48 h
retention. The popup's 21 rows are still worth having, because they stop the
mistake before the upload rather than after it.

### q6 — what a deleted transcript answers

**Measured.** `DELETE /v2/transcript/{id}` answered **200** in 0.35–1.70 s
across the whole spike (the slowest was the FLAC call's), returning the
transcript's own JSON. A `GET` afterwards answered **200, not 404**, with
`status: "completed"`, `audio_url: "http://deleted_by_user"`,
`text: "Deleted by user."` and the words gone. A second `DELETE` of the same
id answered **200** again.

**Verdict — 5i·20 changes.** The live proof row must assert the SENTINEL, not
a 404: after the delete, a GET answers 200 with `audio_url` equal to
`http://deleted_by_user`. The janitor of R6-4 gets a free property out of
this — a repeated DELETE is idempotent and answers 200, so a retry of a
recorded failure cannot make things worse.

### q7 — the Keychain from an ad-hoc-signed bundle

**Measured**, eight steps a sequence, every one in its own process under a
20 s bound with `stdin` closed, three sequences. Builds A and B are the same
source with one different generated nonce, so their cdhashes differ exactly
as two `make app` runs differ — `5db12c2a…` and `ba7b3264…` in the run
`answers.json` holds, and a fresh pair every re-run, which is the point.

*Signed bundle, login (file) keychain.* A adds: `errSecSuccess`. A reads:
success, the value matches. A reads with the interaction door shut
(`kSecUseAuthenticationUIFail`): success. **Each of those three steps
returned in about 90 ms of wall clock and blocked on nothing.** (The
instrument's `security_agent_seen` is `true` for every step of the row,
including the first one chronologically, so it only ever saw an agent
already alive on this host and cannot tell a modal raised for THIS step
from that: what distinguishes A's steps is that they returned at once.)
Then B — the same bundle id, the same service, a
new cdhash — reads: **BLOCKED for the whole 20 s with `SecurityAgent`
running**, and blocked the same way with `kSecUseAuthenticationUIFail` set,
which does not turn that ACL confirmation into a refusal. B's delete answered
**−25244 `errSecInvalidOwnerEdit`**, "Invalid attempt to change the owner of
this item", and the item was still there afterwards.

*Bare Mach-O, login keychain.* A third identity: its `add` answered −25299
(the item exists), its reads blocked the same 20 s, and its delete answered
−25244.

*Data-protection keychain (`kSecUseDataProtectionKeychain`).* `add` and
`delete` answered **−34018 `errSecMissingEntitlement`** from the ad-hoc
signed bundle, and every read answered −25300 (not found). It is not
available to an unsandboxed app signed ad hoc with no keychain access group.

Cleanup: the item's OWNER (build A) deleted it, status 0, and `attrs` answers
"not found" on both keychains. `cleanup_blocked` is **false**, nothing is
left behind, and `com.kgalligan.reelcut.assemblyai` — the service C1 would
use — was never read, written or asked about.

**Verdict — 5d changes.** A login-keychain item written by one ad-hoc
signature cannot be read by the next one without a modal, and cannot be
deleted by it at all. Every `make app` is a new ad-hoc signature, so on this
tree's build the key would be unreachable after the first rebuild and an
agent-driven instance could never answer the prompt. **C1 stores the key in a
`0600` file** under `~/Library/Application Support/Reelcut/`, which §7's last
bullet reserved for exactly this answer, and 5d says plainly that it is the
weaker choice and why. `SecretStore` stays a protocol with `read`, `write`
and `remove`, so a build signed with a stable Developer ID identity — where
the ACL names one identity across builds and this whole problem does not
arise — can carry a `KeychainStore` conformer later without touching anything
above it. R6-5's sentence about "in their Keychain" is corrected to name the
file, and 5i·17's probe claim is against the file store, still never the real
item.

### q8 — the ceilings

**Measured.** `hour.wav`, the fixture looped to exactly 3600.0 s,
115 200 044 bytes. Upload **4.98 s at 23.1 MB/s**. Submit 200 in 0.38 s.
`completed` after **24.4 s and eight polls** at three seconds —
**147× real time** — with `audio_duration` exactly **3600** and 7 967 words.
DELETE 200 in 1.29 s.

Drift: the loop period is 10.388 625 s, and each occurrence of the loop's
first word was placed at its nearest loop index. 227 of the 347 loops were
found that way (the recogniser does not always spell the first word the same)
and the residual ran **+16.0 ms to +122.2 ms**, with none ambiguous and no
trend across the hour. **Nothing accumulates**: the spread is the
recogniser's own per-word placement, not a clock that slips.

**Verdict — §8 gets numbers.** `pollCeiling`'s divisor is
floor(3600 ÷ 24.4 ÷ 3) = **49**, clamped into [2, 60] and unchanged by it, so
the ceiling is `max(300 s, audio seconds / 49)` — three times the measured
rate, which is the margin a queue can eat. `deleteTimeout` of 5 s stands: the
slowest DELETE the whole spike saw was 1.70 s. 5a's progress plan can advance
its 0.65–0.95 band against **150× real time** and hold at 0.95, and an hour
of audio is ~25 s of waiting, not minutes. The ten-hour ceiling implies about
four minutes of processing and, at FLAC, 550 MB of upload.

### 3a. What C0 changed in this document

| Section | The claim before | The claim now | Why |
|---|---|---|---|
| §2, the two open rows | the upload's `content-type` and when a bad `language_code` is refused were "left to C0" | `application/octet-stream` is accepted; a bad code is a 400 at submission | q1, q5 |
| §2, Deletion | "deletes the transcript and the upload right away" | it does, and a GET afterwards answers **200** with `audio_url: "http://deleted_by_user"` and `text: "Deleted by user."`; a second DELETE answers 200 | q6 |
| §2, Duration | `audio_duration` in seconds, integer | and it rounds UP: 10.389 s billed as 11 | q1 |
| §2, Time to transcribe | "under 45 seconds" for the vast majority | 2.8 s for 10 s of audio, 24.4 s for an hour — about 147× real time on this host | q1, q8 |
| §1, the upload format | a temporary 16 kHz mono WAV | the FLAC with the WAV as fallback, as §5a | q2 |
| §0 and §1, where the key lives | "the person's own Keychain", "in the Keychain, entered once" | a `0600` file of the person's own, as §5d and R6-5 | q7 |
| §5a, the upload format | a temporary 16 kHz mono WAV | a 16 kHz mono **FLAC** through `AVAudioFile`, the WAV as the fallback when that write refuses | q2 |
| §5b, `audio_track_start_ms` | "0 unless the spike says otherwise" | 0, measured: an empty edit at the head of a late track is KEPT by the extract | q4 |
| §5d, the credential | `KeychainStore` over the login keychain | a `0600` file; `KeychainStore` deferred to a stable signing identity, `SecretStore` unchanged | q7 |
| §5h, `project.yml` | `NSAppTransportSecurity` `NSAllowsLocalNetworking: true` | nothing: loopback HTTP is not blocked | q3 |
| §5h, toll 1 | "`reelcut-remaining.md` §3 does not list it" | it does, at 934 | read back |
| §5i·2 | the upload body is a RIFF WAV of `2 × 16000 × seconds` bytes | the upload body is a FLAC stream whose decode is sample-for-sample that WAV | q2 |
| §5i·10, §5i·17, §5i·20 | the ATS row, `KeychainStore` through `MemoryStore`, "what q6 recorded" | loopback needs no key; the file store; the `deleted_by_user` sentinel | q3, q7, q6 |
| §8 | `pollCeiling`'s divisor and the format row were guesses | divisor 49; FLAC; `deleteTimeout` checked against 1.70 s measured | q8, q2, q6 |

Everything else in §1, §4, §5 and §6 stands as written. q1 and q5 confirmed
their sections rather than changing them, and q4 confirmed 5b's mapping,
which was the row most likely to overturn it.

### 3b. Spend and deletion

Twenty-six paid calls over the day, every one of them the synthetic `say`
fixture or that fixture looped. No recording of this machine, no file of the
user's, and no header, payload or record carrying a name, an email, a
hostname or a path.

| Row | Uploaded | Bytes | Calls | Billed `audio_duration` | Outcome |
|---|---|---|---|---|---|
| q1 | `speech.wav` | 336 532 | 12 | 11 s each | deleted |
| q2 | `speech.wav` | 336 532 | 4 | 11 s each | deleted |
| q2 | `speech_aac_48000.m4a` | 64 396 | 2 | 11 s each | deleted |
| q2 | `speech.flac` | 161 991 | 2 | 11 s each | deleted |
| q5 | `speech.wav` | 336 532 | 2 | — (refused at submission) | `no_transcript` |
| q6 | `speech.wav` | 336 532 | 2 | 11 s each | deleted |
| q8 | `hour.wav` | 115 200 044 | 2 | 3600 s each | deleted |

**Totals: 7 462.8 s of audio — 2 h 04 m — and $0.4353 at §2's published
$0.21 an hour, against a $2.00 budget the ledger enforced before every
upload.** (q1 and q2 ran more than once: q1 to add the `list_match` look and
the speaker and confidence readings, q2 once in its own run and once in the
full one, q8 twice because the first reading of its drift was the
instrument's fault, not the service's.)

**Every transcript the spike created was deleted.** Twenty-six reservations,
twenty-four transcripts created and twenty-four closed `deleted`; no
reservation is open and none is `unresolved`. The two `no_transcript` rows are q5's refused submits:
those two uploads were never transcribed, cannot be deleted by us (there is no
transcript id to delete), and are left to the provider's own upload
retention, which §2 records as within 24 h and at most 48 h "regardless of
configuration". `find_own` was called only with upload URLs this spike's own
ledger recorded, and nothing about any other transcript on the account was
deleted, read, counted or written down. `--leakcheck` over the instruments,
the work directory, this document, `tools/proof/README.md`, `CLAUDE.md` and
the handoff directory answers `clean`: the key is in none of them, and each
of the 26 upload URLs is in `ledger.json` and nowhere else.

### 3c. The review pass

The spike went through one litecode pipeline on 2026-09-20. The adversary
read the plan before a line was written and turned up five gaps, all taken:
a base-URL variable that could have paired the real key with any host
(removed; the client refuses every pair but the real host with a real key
and loopback with the selftest's dummy); `urllib` forwarding `authorization`
across a redirect (the client follows none); a submit whose reply is lost
leaving a transcript nobody knows to delete (`find_own`, and the ledger's
`unresolved`); `--remake` sitting beside the ledger it could erase; and
q7's cleanup running outside its timeout. The first review of the finished
work re-added the ledger to the cent and found no path for the key, bar two
`pgrep` children that inherited the environment (fixed), and caught five
sentences in this document that `answers.json` did not support: §1 still
saying WAV and Keychain, "no SecurityAgent process existed", two AAC
bitrates never tried, q1's ranges, and a count of 23 reservations for 26.
The second review found one more of the same kind, written by the fix
itself ("present in BOTH looks" where the row takes a second look only
when the first finds nothing), and five smaller ones; all six were closed
by hand after it, since the pipeline runs no second fix pass, and
`cloud_rows.py` now writes `own_entry_after_5s` only when that look ran.
An independent scan for the key over the tree, the work directory, the
handoff directory and every session transcript found it in no file.
**The rule this record is held to: a number here is one `answers.json` or
`ledger.json` holds, or the sentence says it is an anecdote.**

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
  credential is the person's own, in a `0600` file of their own under
  `~/Library/Application Support/Reelcut/`, or a relay's token (C2). It is
  never an argument of `transcribe` — an argument is written into every
  agent transcript and every log — and never a launch argument, which `ps`
  shows to every user. `RC_ASSEMBLYAI_KEY` in the environment is the one
  override, for proofs, and it is read only when the store has nothing.
  The file rather than the Keychain because C0's q7 measured what an ad-hoc
  signature does to a login-keychain item: the next `make app` cannot read
  it without a modal and cannot delete it at all (§3 q7, §5d). A build
  signed with a stable identity could keep it in the Keychain, and
  `SecretStore` is the protocol that lets that be a later conformer.
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
   temporary **FLAC** at the shipped settings' rate and width (16 kHz mono
   16-bit, `Transcriber+Extract.swift`'s extractor, range = the whole asset,
   `NSTemporaryDirectory()`, deleted in a `defer`) — half the bytes of the
   WAV for a decode that is sample-for-sample the same, C0's q2; the WAV is
   the fallback when the FLAC write refuses, and the cache file records
   which was sent. FLAC is written through `AVAudioFile`, NOT
   `AVAssetWriter`, which has no `org.xiph.flac` file type on macOS 26 and
   refuses it as an Objective-C exception (q2). Then: refuse by name a media
   over **10 hours** (AssemblyAI's ceiling) before extracting; **upload**
   it; **submit**; **poll** every 3 s until `completed` or `error`, with the
   ceiling in §8; **fetch**; **write** the cache file then its marker;
   **delete** remotely and record the answer. One media's failure is reported under `problems`
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
q8's measured rate — **147× real time**, so an hour of audio is about 25 s
of waiting — and holding at 0.95, fetch and cache to 1.0. The detail
line says the phase and the file — "Uploading intro.mov · 41 MB of 115" —
and while waiting, the seconds waited, so a stuck queue is visible rather
than silent.

**Revised 2026-09-20 (c1-run), adding to this section and replacing nothing
in it.** Built. Three things this text left open, settled by the code that
now exists:

- **The shares.** "A media's share" is proportional to the SECONDS of audio
  each media to upload carries (`CloudProgress.init(seconds:)`), and a media
  served from the CACHE — or held by R6-11 — is not in the list at all:
  neither costs a second of work and a slice for one would make the bar
  stall. With nothing to upload the bar goes 0 → 1. `CloudProgress.waiting`
  is the clock against q8's 147×, capped at 1, which is what "holds at 0.95"
  means; the published number is `max(previous, computed)`, so an upload
  retried from zero never lowers it.
- **The detail strings**, pinned: `Extracting <file>` ·
  `Uploading <file> · <a> MB of <b>` · `Waiting for AssemblyAI · <n> s` ·
  `Saving <file>`, `<file>` being the media's own name. Megabytes are
  1 000 000 bytes and whole numbers.
- **Step 2 gains a third answer**, spec §11's R6-11: a media in THIS run's
  `janitorFailed` is neither cached nor uploaded but HELD — no fetch, no
  file write, one `Problem` per clip on it, counted as a failure for the
  closing throw, and the hold releases in the first run whose janitor
  confirms the delete. A current cache without `refresh` is still served.
  The reason is that `cache/transcripts/<id>.json` is the one record of a
  remote transcript's id and a fetch REPLACES it, so a re-fetch after a
  failed janitor would orphan that transcript for ever and make the run's
  own note ("the next run retries it") false.

### 5b. The transcript cache

**Revised 2026-09-20 (c1-parts), replacing this paragraph's second
sentence.** `cache/transcripts/<media id>.json` and
`<media id>.complete.json`, the peaks pair's shape (a sidecar, not a child,
so either can be deleted alone). The PATHS live in a new
`MediaTranscript.swift`; the post KIND does not. `transcriptsKind` sits
beside `speechKind` in `MediaCacheFiles.swift` (`:75`), as 5h `:911` already
said it would, because a notification's `userInfo` is where the four kind
constants are compared and a fifth spelling of one of them somewhere else is
the drift this project warns about. That file measured **555** lines, not
550, and 556 after the one constant.

`TranscriptStamp`, this section's marker type, landed in
`AssemblyAITranscript.swift` rather than `MediaTranscript.swift`: the cache
file stood at 436 lines with it against the 400-line cap on a new file, and
a stamp is a record of the REQUEST before it is anything about a file.

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
  "uploaded_format": "flac",
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
future rule, and never argued with. `audio_track_start_ms` is q4's answer, and it is **0**: C0 measured that an
extract of a file whose audio starts 1.5 s after its picture KEEPS that
1.5 s at its head, so a word's millisecond in the extract is its millisecond
in the media and the mapping adds nothing (§3 q4). The field stays, written
0 with a comment naming the row, because a later macOS that trimmed the
empty edit would move every caption of such a file and a re-run of q4 is
what would catch it. `uploaded_format` is `"flac"` or `"wav"`, q2's answer
and its fallback, so a cache file says what was actually sent. The marker is a `TranscriptStamp`:
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

**Revised 2026-09-20 (c1-parts), adding to this section and replacing
nothing in it.** Built, in TWO files rather than one: `AssemblyAIClient.swift`
(338) holds the five calls, §8's numbers, the named errors and the two
members that touch `credential`, `delegate` and `session`, and
`AssemblyAIClient+Session.swift` (179) holds `Reply`, the status classifier,
the two readers that cut a served body apart, the delete-then-throw helper,
the cancellable wait and `SessionDelegate`. One file stood at 487 against the
400-line cap; `request` and `send` stayed behind because `private` on a
stored property does not cross a file and moving them would have widened the
credential to pay a size toll. The wire VALUES went further out again, to
`AssemblyAITranscript.swift` (374), which is the file this section's text
never named. §8 gains two numbers the build needed and this section did not
name: **`retryBackoff` 1 s** (what an upload retry waits first) and
**`requestTimeout` 60 s** (every call's own ceiling, `deleteTimeout`'s 5 s
apart). Both are `Tuning` fields a probe replaces wholesale.

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
loopback host — and C0's q3 measured that plain HTTP to `127.0.0.1` and to
`localhost` is NOT blocked by App Transport Security on macOS 26.5.1, from a
bare binary or from an ad-hoc-signed hardened-runtime bundle, with or
without an ATS key. The stand-in server of 5i speaks HTTP and has no
certificate to pin.

### 5d. The credential, the region and the settings window

**Revised 2026-09-20 (c1-parts), adding R6-9 to this section and changing no
sentence of it.** Spec §11's R6-9 settles a hole this section left: R6-5's
"the store first, `RC_ASSEMBLYAI_KEY` when the store has nothing" is the
right order for a person and the wrong one for a proof, because 5i's proofs
launch the app with `RC_ASSEMBLYAI_KEY=proof-key` against a stand-in that
writes every header to disk — so on a machine where the person had saved a
real key, the STORE would win and the real key would go into that log, and
5i·1's "key unset → refused by name" row could never pass. R6-9's four rules:
`-RCSecretFolder <path>` overrides the store's folder; with
`-RCAssemblyAIEndpoint` set and `-RCSecretFolder` absent NO `FileStore` is
built at all and `store()` answers an empty `MemoryStore`; both arguments are
read ONLY from the argument domain, so a persisted default can redirect
neither; and the order is unchanged. Beside them the fake logs an
`authorization` value only when it is `proof-key` or `wrong-key`. **C2's
relay needs a configuration key of its own, not this launch argument** — a
relay is a configuration a person sets, not a proof's override.

`SecretStore` is a protocol with `read()`, `write(_:)`, `remove()`, and
**C0's q7 decided which conformer ships: a file, not the Keychain.**
`FileStore` writes the key to `~/Library/Application Support/Reelcut/
assemblyai-key` with `POSIXPermissions: 0o600`, created with those
permissions and not chmod'ed after, in a directory it creates at `0o700`;
`MemoryStore` is the probe's, so no proof ever reads or writes a person's
real credential. The key is never in `UserDefaults`, never in the package,
never in a log; the Settings window shows it masked and offers Remove.

**Why not the Keychain**, which is the better place and was the plan. q7
measured a login-keychain item written by one ad-hoc signature and read by
the next: the second build blocks on a `SecurityAgent` modal — even with
`kSecUseAuthenticationUIFail`, which does not turn that ACL confirmation
into a refusal — and its DELETE answers `errSecInvalidOwnerEdit`, so the
item cannot even be cleaned up by the build that finds it. Every `make app`
is a new ad-hoc signature. An agent-driven instance has nobody to click the
modal, and a person would meet one after every build. The
data-protection keychain is not a way out either: `SecItemAdd` with
`kSecUseDataProtectionKeychain` answers `errSecMissingEntitlement` (−34018)
from an unsandboxed ad-hoc-signed app with no keychain access group. **The
file is the weaker choice and this paragraph is the record of that**: it is
readable by anything running as the person, where a Keychain item is
readable only by one signed identity after one confirmation. A build signed
with a stable Developer ID identity does not have q7's problem, and
`KeychainStore` is then one more `SecretStore` conformer and a migration
that reads the file once and removes it — a later phase, named here so it is
not rediscovered.

**Reelcut ▸ Settings… ⌘,** is new chrome — the app has had nothing to
persist beyond view state — and it is a window, not a sheet:
`SettingsWindowController.swift` (≤ 400), one pane for now,
"Transcription": the key (an `NSSecureTextField` and Save / Remove; a
`FileStore` write on Save), the region popup (United States /
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
  through; a code AssemblyAI refuses comes back as its own sentence — C0's
  q5 measured that as a **400 at submission in 0.24 s**, "Language code xx
  is not supported.", so the cost of a wrong code is one wasted upload and a
  quarter of a second, and the tool relays rather than carrying a second
  dated table of codes. The on-device engine's two-part language refusal is
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

**Revised 2026-09-20 (c1-run), adding to this section and replacing nothing
in it.** Built. The sentences, as they landed, each pinned by a row of
`cloud_captions_proof.py`:

- `engine must be "apple" or "assemblyai" (got "<x>").`
- `<arg> only applies with engine "assemblyai". Pass engine: "assemblyai",
  or leave it out.` — the FIRST of `speakers`, `vocabulary`, `refresh`
  present is the one named, in that order.
- `No AssemblyAI API key is set. Set one in Reelcut ▸ Settings ▸
  Transcription, or RC_ASSEMBLYAI_KEY for a proof.`
- `“<file>” is longer than AssemblyAI's 10-hour limit for one file.`
- R6-11's, one per clip on a held media: `AssemblyAI has not confirmed
  deleting its earlier transcript, so it was not uploaded again; the next
  run retries the delete`
- the `note`'s three parts, space-joined: `vocabulary was capped at 1000
  terms (AssemblyAI's limit); <N> were given.` · `AssemblyAI transcribed
  media <id> with <model>, not universal-3-5-pro.` · `AssemblyAI has not
  confirmed deleting the transcript of media <id>; the next run retries
  it.` (once per media id).

`language` with the cloud engine: absent or `"auto"` is detection (the
wire's absent `language_code`); anything else is trimmed and passed through,
and an EMPTY string is refused by name rather than sent as a language called
"". `vocabulary` is trimmed, empties dropped, de-duplicated KEEPING THE
FIRST spelling and cut from the end at `maxKeyterms`. The Apple arm's result
gains `engine: "apple"` and nothing else. The handler is
`AgentServer+CloudCaptions.swift`; `AgentServer+Captions.swift` dispatches on
`engine` and `transcriptionScope` stays `private` — the cloud arm is handed
`jobs` and `frame` by value.

### 5h. Files, tolls, seams

Tolls, each a pure move, its own commit, gated alone before any feature
code, so what changes afterwards is attributable:

| Toll | File | Now | Cut |
|---|---|---|---|
| 1 | `Transcriber.swift` | 934 — over the cap since it landed, and `reelcut-remaining.md` §3 lists it at that number (this table said it did not; read back 2026-09-20) | the language block (`Language`, the two cached lists, `named`, `defaultLanguage`, `language(matching:)`, ~190) → `Transcriber+Languages.swift`; the extractor (`extractSettings`, `extractAudio`, ~130) → `Transcriber+Extract.swift`; `jobs`, `contentLength`, `hasTranscribableClip` (~110) → `Transcriber+Jobs.swift`. Widenings: `contentLength` and `extractAudio` internal, because the cloud run calls both |
| 2 | `AgentCatalog+Files.swift` | 601 (this table said 609; read back 2026-09-20) | the three caption entries (`import_captions`, `transcribe`, `export_captions`) → `AgentCatalog+Captions.swift`, spliced where they were, `AgentCatalog+Audio.swift`'s precedent |
| 3 | `TranscribeSheetController.swift` | 505, +≈150 to come | `finish`, `summary`, `truncationText`, `viewDidDisappear` and the menu-command extension → `TranscribeSheetController+Commit.swift` |

Then the feature, in ≤ 400-line files:

- `Transcriber+Extract.swift` — the extractor generalised AFTER its move:
  `extractAudio(url:range:to:)`, the job form calling it (behaviour
  byte-identical, the WAV a fixture can compare), and beside it the FLAC
  writer C0's q2 chose for the upload — `AVAudioFile` at the same 16 kHz
  mono 16-bit, because `AVAssetWriter` has no FLAC file type on macOS 26 and
  refuses it as an Objective-C exception. The on-device engine keeps the WAV
  it hands the recogniser; only the upload changes.
- `CloudTranscriber.swift` — 5a's run.
- `MediaTranscript.swift` — 5b: paths, the file and marker types, the
  loader, the mapping, the janitor's list.
- `AssemblyAIClient.swift`, `AssemblyAIConfiguration.swift`,
  `AssemblyAILanguages.swift` — 5c and the table.
- `SecretStore.swift` (`FileStore`, `MemoryStore`), `CloudEstimate.swift`
  — 5d and 5e's pure parts.
- `SettingsWindowController.swift`; `AppDelegate+Menus.swift` (544) takes
  the one item (Reelcut ▸ Settings… ⌘,) and no more.
- `TranscribeSheetController.swift` — the Engine popup and the three cloud
  rows; `TranscribeSheetController+Commit.swift` — the report's new lines.
- `CaptionLayout.swift` (444) — `Word.speaker` and the fifth rule, ~15 lines.
- `AgentServer+CloudCaptions.swift`; `AgentServer+Captions.swift` (409) —
  the dispatch; `AgentCatalog+Captions.swift` — the entry.
- `MediaCacheFiles.swift` — ONE constant (`transcriptsKind`) and nothing else.
- `project.yml` — the usage string's rewording, and NOTHING else: C0's q3
  measured that plain HTTP to loopback is not blocked from an
  ad-hoc-signed hardened-runtime bundle with no ATS key at all, so the
  `NSAppTransportSecurity` / `NSAllowsLocalNetworking` bullet this list
  carried is struck. No entitlement either: the app is not sandboxed and the
  hardened runtime does not gate outgoing connections.
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

**Revised 2026-09-20 (c1-parts), adding to this section and replacing
nothing in it.** Two of the three instruments are built and their record is
§10.9. The fake gained what the rows needed and this section did not name: a
`POST /__control/scenario` that replaces the scenario whole and resets the
counters, `slow_upload` (a body read in pieces, which is how an upload is
cancelled mid-body), `fail: [{route, status, times}]`, `audio_seconds`,
`unsupported_language_codes`, and `GET /__control/words`, which answers the
exact bytes it served so "byte-equal to what was served" is a comparison
rather than two encoders agreeing. R6-9 (e) is its redaction rule. The probe
gained rows this section numbered none of: **W** the WAV against the baseline
TREE, **F** the FLAC's STREAMINFO, decode and determinism, **FB** the WAV
fallback, **Q** `wholeAsset` against an explicit range, **R** the redirect,
**L** the loopback table, **C** R6-9 (a)–(c), **V** the served bytes to disk
and back, **G** the fake's redaction, **N** the language table, **S**
`CloudTranscriber`'s unreachability and **K** the credential in no child's
output.

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
log holds one `POST /v2/upload` whose body is a FLAC stream that decodes to
the audio the on-device engine's WAV holds — **revised 2026-09-20 (c1-run),
replacing this clause's "sample for sample" and "byte-identical across two
runs"**: this Mac's 16 kHz extract is not bit-deterministic
(`designs/reelcut-remaining.md` §5), so the claim is a POPULATION, written
the way `cloud_captions_probe.py`'s rows W and Q are — N uploads through
`refresh`, each decoded by `AVAudioFile` and by `ffmpeg`, beside N on-device
WAV extracts: ONE length, at most two distinct byte strings differing in a
single 16-bit sample, with a CONTROL that an altered decode in the same
population IS seen. **And the fixture for that half is the `say` AIFF, not
`media/speech.mov`**, which c1-run measured at four distinct byte strings of
one length out of four extracts, ~130 bytes apart: an AAC decode this host
does not repeat, where the AIFF is the two-string population §5 recorded.
One `POST /v2/transcript` with `authorization: proof-key`,
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
again; a **`relink_media`** relink to a different file uploads, and a
relink back uploads again (one transcript per media, not a history) —
**revised 2026-09-20 (c1-run), replacing the op name `set_media`, which
this tree does not have**; a split
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
**(10)** the built app reaches the loopback fake over plain HTTP with no
ATS key in `project.yml` at all — C0's q3 measured that it needs none, and
this claim is what guards that measurement against a later macOS; **(11)** a
scenario with `remote_deleted` failing (the DELETE answers 500) leaves the
flag false, and the next run's FIRST request is that DELETE.

**Revised 2026-09-20 (c1-run), adding a second arm to row 11 and replacing
nothing above it.** Row 11 also proves spec §11's **R6-11**, the HOLD: with
the DELETE failing twice, run 1 uploads and leaves the flag false; run 2
under `refresh: true` is REFUSED in R6-11's own sentence and makes EXACTLY
one request — that DELETE, no upload and no submit — with the cache file's
sha256 and its `transcript_id` unchanged; and run 3, once the failures are
spent, issues the DELETE of run 1's id FIRST and only then an upload, after
which the file holds a new id. The failures are spelled as a `times: 2`
count rather than as a scenario cleared between runs, because the fake's
`POST /__control/scenario` replaces the scenario WHOLE and forgets every
transcript with it — including the id whose delete is the thing being
retried.

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
DELETE; **(17)** `FileStore` over a temporary directory — its `0600` mode, its
round trip and its removal — with `MemoryStore` everywhere else, so no
proof ever touches the person's real credential; **(18)** the Settings pane's rows and the sheet's popup rows and
hint texts as structural reads, and the Settings window photographed
through `cacheDisplay` (a window, not a sheet, so it CAN be) with the key
field empty; **(19)** the fifth rule at its boundaries through the `cues`
mode.

**Live**, skipped BY NAME when `RC_ASSEMBLYAI_KEY` is unset or the host
has no route to `api.assemblyai.com`, its rows counted: **(20)** the
fixture's round trip against the real service — `speech_model_used` is
`universal-3-5-pro`, the words contain the fixture's sentence in order,
no word touches a known pause at all (§3 q1 measured none, so the row can
be outright and needs no frame of tolerance), the DELETE answers
200 and a GET afterwards answers **200** with `audio_url`
`http://deleted_by_user` and `text` "Deleted by user." (q6); and **(21)** the second
run is served from the cache in under a second with no upload.

Mutants, each named in the record with its score: the stamp comparison
deleted (5: uploads twice); the `in` term dropped (3, 5); the DELETE
removed (2, 4); the retry removed (6); the fifth rule removed (7, 19);
`speech_models` pinned to Universal-2 (2); the janitor removed (11); the
env-var override reading BEFORE the store (17, with a store holding a
value); the store's file written 0644 (17); the 401 arm not ending the run (6: two uploads where one is
right); the rate constant halved (14). Every earlier proof re-run against
the final binary and quoted "against the N it had at the time".

### 5j. What only a person at the machine can check

- **What q7's prompt actually says**, and whether "Always Allow" survives
  a rebuild. C0 measured that a rebuilt ad-hoc-signed binary BLOCKS on a
  `SecurityAgent` modal for the whole twenty-second bound (§3 q7) — nobody
  was at the machine to read it. That is why the key goes in a file (5d),
  and it is the one q7 question a person can still answer. Also
  `designs/reelcut-remaining.md` §4.
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
- **A code AssemblyAI refuses costs the upload**, measured: q5's 400 came
  back in 0.24 s, so the cost is the upload (337 kB for the fixture, about
  55 MB for an hour of FLAC) and no billing at all. That upload cannot be
  deleted by us — there is no transcript id — and is left to AssemblyAI's
  own ≤ 48 h upload retention. The popup's 21 rows cannot be wrong; the
  tool's pass-through can.
- **The key is in a `0600` file, not the Keychain** (5d, q7): readable by
  anything running as the person. The Keychain is the better place and is
  unreachable from a binary that is re-signed ad hoc on every build. A
  Developer ID build can have it back.
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
- ~~**A second key vault** (a `0600` file) unless q7 forces it.~~ **q7
  forced it** (§3 q7): the `0600` file is what 5d ships, and it is the
  KEYCHAIN that is deferred — to a build signed with a stable identity,
  where the ACL names one signer across builds. `SecretStore` is the seam
  that makes that a later conformer and a one-time migration.

---

## 8. Numbers a person may want to change before the build

| Constant | Value | Where it comes from |
|---|---|---|
| `AssemblyAIRates.perHour` | $0.21, dated 2026-09-17 | §2; shown as "at AssemblyAI's published rate" so a stale number reads as one. C0 spent $0.4353 over 26 calls and 2 h 04 m of audio at that rate, which is the rate arithmetic checked end to end |
| `AssemblyAIRates.speakersPerHour` | +$0.02 | §2 |
| `pollInterval` | 3 s | AssemblyAI's SDKs' default |
| `pollCeiling` | `max(300 s, audio seconds / 49)` | q8 MEASURED an hour of audio completing in 24.4 s — 147× real time — and the divisor is floor(147 ÷ 3), clamped into [2, 60]: three times the measured rate is the margin a queue can eat |
| `uploadRetries` | 1 | AssemblyAI's own guidance is "retry"; one is enough to cover a dropped socket, and two uploads of a 100 MB file are the cost of a third |
| `pollFailuresTolerated` | 3 | consecutive 5xx or transport errors |
| `maxMediaSeconds` | 36 000 | AssemblyAI's 10-hour ceiling — about four minutes of processing at q8's measured rate, and about 550 MB of FLAC |
| `maxKeyterms` | 1000 | §2 |
| `retryBackoff` | 1 s | added 2026-09-20 (c1-parts): what an upload retry waits before the second attempt. One second is longer than a dropped socket's own retry and shorter than anything a person would notice on a run that is minutes long |
| `requestTimeout` | 60 s | added 2026-09-20 (c1-parts): every call's own ceiling, `deleteTimeout`'s 5 s apart. It bounds a request whose socket has gone quiet; the poll LOOP's bound is `pollCeiling`, which is a different thing |
| `deleteTimeout` | 5 s | the janitor's budget per item; the slowest DELETE C0 TIMED was **1.70 s**, q2's FLAC row, of the eleven `answers.json` holds a time for (24 were made), so 5 s is nearly three times the worst measured |
| upload format | **FLAC**, 16 kHz mono 16-bit, the WAV as the fallback | q2 MEASURED zero word-timing delta against the WAV at 48.1% of its bytes, with the service's own run-to-run jitter at zero too; AAC-LC 48 kbps was refused at 38 ms, more than half a frame at 30 fps |

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

What C0 overturned, and what the plan did about it — **C0 ran on
2026-09-20 and §3 is the record; §3a is the table of every change**. q2: a
smaller upload format IS offset-free, and it is FLAC and not AAC, so 5a's
extractor writes it and 5i·2's claim about the WAV's byte length became a
claim about the container. q4: the extract KEEPS a late track's offset, so
`audio_track_start_ms` stays 0 and the mapping adds nothing — 5b stands.
q7: a rebuilt ad-hoc-signed binary cannot read its own Keychain item without
a modal and cannot delete it at all, so the `0600` file is what ships,
recorded as weaker, and `KeychainStore` waits for a stable signing identity.
q3: ATS did NOT block the probe, from a bare binary or a signed bundle, so
the stand-in stays plain HTTP and `project.yml` gains nothing. q5: a bad
code is refused AT SUBMISSION with the server's own sentence, so the tool
relays it and carries no second dated table. What remains for C1 is the
build itself.

---

## 10. C1 — the record

### 10.1 The split, a named deviation from §9

§9 says C1 is one `/litecode` pipeline. It is being run as FIVE sequential
pipelines instead, because one implementer and one reviewer cannot hold the
whole of §5h, and because the tolls must be gated alone:

1. **c1-tolls** — spec §11 gains R6-1..R6-8, then §5h's three tolls, each a
   pure move gated alone. No feature code. **This section is its record.**
2. c1-parts — the seams of §5h and the pure parts: the extractor
   generalised plus the FLAC writer, `MediaTranscript`, `SecretStore`, the
   configuration, the languages table, the client, the cue builder's fifth
   rule; the probe.
3. c1-run — `CloudTranscriber`, the MCP mirror, the stand-in server, the
   MCP proof.
4. c1-chrome — the Settings window, the sheet, the estimate, the report card.
5. c1-close — the live rows, the mutants not yet run, every earlier proof
   re-run, the record, the README.

**"Its own commit" per toll becomes "its own TREE OBJECT."** Nothing is
committed between pipelines, so each toll's gate is followed by a snapshot
of the working tree into a temporary index, and the hash is written here so
a toll can later be turned into a commit of its own. A toll's diff reads
`git diff <Tn-1> <Tn>`; the whole pipeline's CODE is `git diff cfcd0959 <T5>`
(T3 plus the review's one header fix, below).
An untracked file shows in a diff against the BASELINE as wholly deleted,
which is noise — for one of those, `git show <tree>:<path> | diff - <path>`.

| Tree | What it holds |
|---|---|
| `cfcd09598e7ea7ec31ec229c943d1edfc51fc0d3` | the baseline, `HEAD^{tree}` at `7f04e59` |
| **T0** `44f77338cdcb1cd2cfdb537c8322f77027fe0986` | spec §11's R6-1..R6-8, and nothing else |
| **T1** `55beb03dcd0c20118e56f0931dbbcfdf9aff0fe5` | toll 1 |
| **T2** `634ea96b7123b34e02ec0809fca3cccb0d4548f4` | toll 2 |
| **T3** `2eaa126c54d6a1e41f91948150885f0b944537dc` | toll 3 |
| **T5** `8f1bfc9edf3a9c5c5a5ea7a32ee87173c9d1860e` | T3 plus the records and the review's one fix — the last CODE tree |

T0 holds the decisions and T1–T3 hold code: every record — this section,
`reelcut-remaining.md` §3, `reelcut-app-notes.md` and `app/CLAUDE.md` — was
written after T3, so that every number in them is one a run printed.

The pipeline's reader review found one wrong sentence and it was fixed after
T3: the file header of `Transcriber+Languages.swift` had the two lists the
wrong way round (`languages()` is the locales this Mac has an ON-DEVICE
model for; `supportedLanguages()` is every locale the framework names), and
five header lines were rewritten to say what the code and the two function
doc comments below them already said. No code line moved, no line count
changed — the file is still 172 lines, so every number in these records is
still the one a run printed — and `make typecheck` (0 errors, 4 warnings),
`make app` (exit 0), the parity grep (empty), `phase4_proof.py` (84/84) and
`source_mirror_probe.py` (40/40) were run again on the fixed tree and answer
as they did at toll 1. T5 is the working tree after that fix (T4 is a
convenience row in the pipeline's own `04-impl-notes.md`, not here); the tree
including this paragraph is named in the pipeline's `06-fix-notes.md`, which
is the only thing that changed after it.

### 10.2 Spec §11, before the code

R6-1..R6-8 are §4's text word for word, appended after D4-6, with exactly
three reference fixes, because a bare `§` in the spec means the spec's own:
R6-5's `(§3 q7, §5d)` names this file, R6-5's `(C2)` reads "road map 6's
C2", and R6-6's `§6d` reads "road map 6 §6d". R6-3's `§5.6` IS the spec's
and stands. The two bullets those fixes lengthened were re-wrapped at the
section's own width; no word changed. T0 is that edit alone.

### 10.3 The CONTROL run, R0

Before any toll, at T0: `make app` exit 0, a fresh instance on port 4951
with the parity log empty, **`phase4_proof.py` 84/84** and, with no
instance running, **`source_mirror_probe.py` 40/40**. Those two are the
scores tolls 1 and 3 had to equal on this host, and they are called a
CONTROL for that reason. phase4's exact-sentence rows read the host's own
grant word back: **`notDetermined`** — this Mac has never granted Speech
Recognition to a proof instance, which is a property of the host, not of
the tolls (TCC attributes a shell-launched binary to the terminal, and the
prompt needs a frontmost app).

### 10.4 Toll 1 — `Transcriber.swift`

| File | Before → after |
|---|---|
| `app/Sources/Transcriber.swift` | 934 → 553 |
| `app/Sources/Transcriber+Languages.swift` | new, 172 (lines 210–363) |
| `app/Sources/Transcriber+Jobs.swift` | new, 117 (lines 415–514) |
| `app/Sources/Transcriber+Extract.swift` | new, 143 (lines 680–806) |
| `tools/proof/cloud_spike/extract.swift` | 320 → 320 (one comment names the file the settings were copied from) |

Two widenings, both named in §5h:

- **W1 `contentLength(of:)`**, `private static func` → `static func`. **No
  compiler error demanded it** — its one caller, `jobs`, moved with it —
  and it is made because §5h names it for the cloud run. It is the one
  widening in this pipeline the compiler did not arbitrate.
- **W2 `extractAudio(_:cancel:)`**, `private func` → `func`, same
  signature. Compiler-forced: with no widening, `make typecheck` printed
  exactly one error, `app/Sources/Transcriber.swift:356:35: error:
  'extractAudio' is inaccessible due to 'private' protection level`
  (`transcribe`, its one caller, stayed behind).

Nothing else widened: `languageLock`, `cachedLanguages`, `cachedSupported`,
`extractSampleRate` and `extractSettings` are still `private`, every reader
of them having moved with them. Stored instance properties (`work`,
`delivery`, `sink`, `recognizer`) cannot live in an extension and stayed,
with `Job`, `Truncation`, `Outcome`, `TranscribeError`, `CancelToken`,
Authorization, all of Running and Recognition, and `TaskSink`.

Gate: `make typecheck` 0 errors and the 4 AVFoundation warnings; the move
check PASS on A, B, C and D with its `--control` FAIL; `make app` exit 0;
the parity grep empty; **`phase4_proof.py` 84/84, byte-identical to R0's
output**, and **`source_mirror_probe.py` 40/40**, whose output differs from
R0's in one line, the probe's own build time.

### 10.5 Toll 2 — `AgentCatalog+Files.swift`

| File | Before → after |
|---|---|
| `app/Sources/AgentCatalog+Files.swift` | 601 → 487 |
| `app/Sources/AgentCatalog+Captions.swift` | new, 165 (lines 51–61, 213–234, 274–367) |
| `app/Sources/AgentCatalog.swift` | 524 → 525 (one pointer comment, +1 line) |

No widening at all: `fileTools` and the two new functions are members of
the same internal extension of `AgentServer`. `captionImportTools()`
returns `import_captions`' row; `captionTools()` returns `transcribe`'s and
`export_captions`' with their `// MARK: Captions` note and
`captionFormatNames` / `captionFormatProperty`, the hoisted local only they
read, which moved with them.

The catalog's ORDER is a contract (`recording_probe.py` reads the last
eleven names), so the rows are SPLICED back at the two points they left
rather than appended: `fileTools`'s `return [` became `var rows:
[[String: Any]] = [` (`AgentCatalog+Clips.swift:242`'s precedent), the array
is closed and reopened after `import_media` and after `remove_media` with
`rows += captionImportTools()` and `rows += captionTools()` between, and
`return rows` closes the function. Each splice carries a three-line comment
saying it is a splice and why.

Gate: `make typecheck` 0/4; the move check PASS with its `--control` FAIL;
`make app` exit 0; the parity grep empty; **`op_catalog_proof.py` 23/23**
(the core declares 57 ops, every one a tool, beside 20 app-state tools);
and the published answer itself — `tools/list` captured from the app built
BEFORE the toll (T1) and from the app built after it, the array order kept
and each object's keys sorted, **`cmp` silent over 77 tools**, with
`import_captions` at index 67 and `transcribe` and `export_captions` at 72
and 73 in both. CONTROL: the same before-capture with `transcribe` and
`export_captions` swapped makes `cmp` fail (char 200178, line 2418), so the
comparison can see an order change.

### 10.6 Toll 3 — `TranscribeSheetController.swift`

| File | Before → after |
|---|---|
| `app/Sources/TranscribeSheetController.swift` | 505 → 380 |
| `app/Sources/TranscribeSheetController+Commit.swift` | new, 145 (lines 380–463 and 465–505) |
| `app/Sources/EditorViewController.swift` (FROZEN) | 1123 → 1123 (two comments name the new file; zero net lines) |

Ten widenings, **every one of them compiler-forced**, and the compiler was
asked twice. With the move made and nothing widened, `make typecheck`
named nine stored properties, each "inaccessible due to 'private'
protection level" from `TranscribeSheetController+Commit.swift`: **W3**
`document`, **W4** `snapshot`, **W5** `token`, **W6** `bar`, **W7**
`statusLabel`, **W8** `detailLabel`, **W9** `stopButton`, **W10**
`didStart`, **W11** `didFinish` — `private` dropped in place, nothing else
on the line. With those nine made it named the tenth, **W12** `finish`,
at `TranscribeSheetController.swift:343:13` and `:359:56`, `begin` having
stayed behind. `summary`, `truncationText` and every other private member
of the class are still `private`. `override func viewDidDisappear()` is
legal in an extension because it is an Objective-C method
(`MediaRowView.swift`'s `extension TimelineView` is the precedent).

Gate: `make typecheck` 0/4; the move check PASS with its `--control` FAIL;
`make app` exit 0; the parity grep empty; **`phase4_proof.py` 84/84,
byte-identical to R0's output**.

### 10.7 The final tree, and the mirrors

On T3: `make test` **721 tests over 39 binaries, 0 failed, 0 ignored** —
the last recorded count, unmoved, as it must be with no Rust touched —
`make lint` clean, `cargo fmt --check` clean, `make typecheck` 0 errors and
4 warnings, `make app` exit 0. Every instance this pipeline launched was
killed by the PID `lsof -t -iTCP:4951 -sTCP:LISTEN` named, and `pgrep -f
"MacOS/Reelcut"` prints nothing.

**The op table's four mirrors are unchanged**: `OP_NAMES` 57 (printed by
`op_catalog_proof.py`), the catalog 77 tools (printed by the `tools/list`
capture), `RC_FORMAT_VERSION` 8, and no FFI change — no Rust, header,
`ReelCore.swift`, op-table or catalog-CONTENT line was touched at all.

### 10.8 What no script reaches, said rather than papered over

`extractAudio`, `languages()` and `defaultLanguage` sit below the Speech
Recognition grant, which no agent-driven instance can obtain (§10.3), and
toll 3's `finish`, `summary`, `truncationText`, `viewDidDisappear` and the
menu command have no MCP or harness caller at all. `phase4_chrome.py` was
NOT run: `tools/proof/README.md` says it photographs the TextPane Animation
section and runs the cue builder, never this sheet. For those bodies the
evidence is the move check's A — each block present in its new file exactly
once as one contiguous run, byte-identical and in order — plus the
typecheck and the link. That is weaker than a picture and is recorded as
what it is.

### 10.9 c1-parts — the seams, the pure parts, the stand-in and the probe

The second of §10.1's five pipelines. Its baseline is c1-tolls' final working
tree `515e6a8032071626f8c2a77030db4b249495602b`; nothing was committed.

| Tree | What it holds |
|---|---|
| `515e6a8032071626f8c2a77030db4b249495602b` | the baseline, c1-tolls' last |
| **S1** `0d57f6b4bdc28a2c8343e1483666b0cfb8958253` | the whole Swift side, typechecking 0/4, before either instrument existed |
| **S2** `f6598273c83b5468e7ee80a554af33392a615d6b` | S1 plus the fake, the probe, §5's dated revisions and the README, before this record |

**A named deviation from the plan's step order.** The spec asked for the
seams alone at S1, with the parts after. The seven files were written whole
instead, so S1 is "the Swift side, typechecking, before either instrument
existed" and not "the seams alone". What S1 was for — every later file
compiled against ONE shape — holds trivially, because they all landed
together; what is lost is the ability to read a seams-only diff. The same
step's "run `phase4_chrome.py` for a cue BEFORE capture" was also missed:
`CaptionLayout.swift` was already edited. The replacement is stronger and is
in `work/cloudprobe/cues-before/` — the harness's own `main.swift` compiled
against `git archive 515e6a80 app/Sources` under `-D HARNESS_REFERENCE_BUILD`,
the tree as it stood with FOUR cue rules, run over the twenty `words-*.json`
fixtures `phase4_chrome.py` writes. All twenty `cues-*.json` are `cmp`-silent
against it, and an edited copy of `cues-exactly-42.json` makes `cmp` fail at
char 36, line 4, which is the CONTROL.

#### What landed

Spec §11 gained **R6-9** before any code: a proof-launched app never opens
the person's stored key, in four rules plus the fake's redaction. §5b, §5c,
§5d, §5i and §8 carry dated 2026-09-20 revisions saying what each replaces.

| File | Lines | What it is |
|---|---|---|
| `app/Sources/CloudTranscriber.swift` | 102 | NEW. `TranscriptionEngine`, and `CloudTranscriber` with `run` as final code and `transcribe` throwing "the AssemblyAI engine is not built yet". Nothing constructs it |
| `app/Sources/AssemblyAITranscript.swift` | 374 | NEW, and not named by §5h. `TranscriptOptions`, `TranscriptRequest`, `TranscriptWord`, `TranscriptResponse`, `TranscriptStamp`, `JSONValueRange`, `encodeOrNull` |
| `app/Sources/AssemblyAIClient.swift` | 338 | NEW. 5c's five calls, §8's numbers, the ten named errors, `request` and `send` |
| `app/Sources/AssemblyAIClient+Session.swift` | 179 | NEW, and not named by §5h either — see below |
| `app/Sources/AssemblyAIConfiguration.swift` | 179 | NEW. The two resolvers, `store()` (R6-9), the loopback rule |
| `app/Sources/AssemblyAILanguages.swift` | 59 | NEW. The 21-code table, dated 2026-09-17, in §2's order |
| `app/Sources/SecretStore.swift` | 212 | NEW. The protocol, `FileStore`, `MemoryStore` |
| `app/Sources/MediaTranscript.swift` | 379 | NEW. 5b: the paths, `Header`, `File`, the read/write plumbing, the janitor's list, THE MAPPING, `Loader` |
| `app/Sources/Transcriber+Extract.swift` | 143 → 305 | the static extractor, the job form calling it, `writeFLAC`, `extractUpload`, `UploadFormat`, `Upload`, `wholeAsset` |
| `app/Sources/Transcriber.swift` | 553 → 584 | `Job.media`, and `CancelToken` holding a `URLSessionTask` beside the speech task |
| `app/Sources/Transcriber+Jobs.swift` | 117 → 117 | one line: `media:` at the one `Job(` site |
| `app/Sources/CaptionLayout.swift` | 444 → 473 | `Word.speaker`, the fifth rule, the header's "four rules" → five |
| `app/Sources/MediaCacheFiles.swift` | 555 → 556 | ONE line: `transcriptsKind`, beside `speechKind` |
| `tools/proof/harness/main.swift` | 881 → 901 | the `cues` mode reads an optional `speaker`, the call guarded by `#if !HARNESS_REFERENCE_BUILD` |
| `tools/proof/assemblyai_fake.py` | 489 | NEW. 5i's stand-in, whole |
| `tools/proof/cloud_captions_probe.py` | 2638 | NEW. Nine sections, seven mutants (the seventh is 05-review's finding 1) |

**Two files the spec's list did not name, each a size toll paid where it
fell.** `AssemblyAIClient.swift` stood at **487** lines with its transport in
it, against the 400-line cap a new file has; `Reply`, the classifier, the two
body readers, the wait, the log line and `SessionDelegate` went to
`AssemblyAIClient+Session.swift`, and `request` and `send` stayed behind
because `private` on a stored property does not cross a file and moving them
would have widened `credential` to pay a size toll. `MediaTranscript.swift`
stood at **436** with `TranscriptStamp` in it; the stamp went to
`AssemblyAITranscript.swift`, which is where the request it records already
lives. Both are recorded in the files' own headers and in §5b and §5c.

#### The gate

`make typecheck` **0 errors, 4 warnings** at S1 and again at S2 — the same
four AVFoundation deprecations, no fifth. `make app` exit 0. `make test`
**721 tests over 39 binaries, 0 failed, 0 ignored** — unmoved, as it must be
with no Rust touched. `make lint` clean, `cargo fmt --check` clean.

Against the binary, on port 4953, the parity grep empty both times:
**`phase4_proof.py` 84/84**, and, on a freshly launched instance,
**`op_catalog_proof.py` 23/23** ("the core declares 57 ops and every one of
them is a tool"). With no instance running, **`source_mirror_probe.py`
40/40** and **`phase4_chrome.py` 59/59**. Every instance was killed by the
PID `pgrep -f "MacOS/Reelcut"` named, and it prints nothing now.

**The four mirrors are unchanged, and it was read back rather than assumed**:
`ReelCore.swift`, `ReelOps.swift`, all six `AgentCatalog*.swift` and
`project.yml` are byte-identical to the baseline tree
(`git show <tree>:<path> | diff -`), `git diff <tree> -- core` is empty, and
`RC_FORMAT_VERSION` is 8 in both `core/src/format.rs` and the header. No
`rc_*` export, no header line, no op, no tool.

#### `cloud_captions_probe.py` — 186/186, three times; 196/196 after the fix

Sections and what each measures are in `tools/proof/README.md`. No skips:
`say`, `ffmpeg`, `git` and C0's `late.mov` were all present on this host.
Numbers a run printed:

- **12**, the mapping: six clip windows against expectations computed in
  Python from §5b's sentence. A word straddling `in` is excluded, one
  starting exactly AT `in` is included, one starting exactly at the window's
  end is excluded, one ending past the window is clamped to the clip's end, a
  split pair partitions with none lost or doubled, and the speaker is carried.
  The spec's own wording for this row said a later `in` gets ONE word; the
  fixture's window legitimately holds two, so the row was corrected to assert
  both and "nothing from before its window" — the code was right and the
  sentence was not. **05-review's finding 1 added a second request, run
  2026-09-20:** the five degenerate speeds — `0`, `-2`, NaN, `+infinity` and
  `greatestFiniteMagnitude` — each answer the three words the guard's rule
  puts them at instead of trapping (the first four are degenerate and read as
  1; the largest finite speed is finite and positive, so the guard passes it
  through UNCHANGED and the oracle places its words with that speed), and each
  is checked to have reached the mapping as itself (`0.0`, `-2.0`, `nan`,
  `inf`, `1.7976931348623157e+308`). Ten rows, all ok.
- **13**, the stamp: each of the four request fields and each of the ten
  `CacheStamp` fields invalidates; the marker's bytes are the stamp's, keys
  sorted at both levels, with `language_code` written as `null` rather than
  dropped; the region changes the base URL (`https://api.assemblyai.com` /
  `https://api.eu.assemblyai.com`) and appears in no stamp — the CONTROL.
- **15**, the client over `URLProtocol`: `Tuning.shipped` equals §8 field for
  field; `pollCeiling` is 300 s for 10 s and for an hour and 36000/49 for ten
  hours; one retry on a 5xx and on a transport error, each measured waiting
  **0.274 s** and **0.272 s** against a `retryBackoff` of 0.25 — the two
  numbers that run printed; none on 400 or 401 (the 401 refused as
  `keyRefused(401)`, which carries its status code — the spec's row said
  plain `keyRefused`); three failed polls tolerated
  and the fourth throwing `server` with a DELETE last; the ceiling ending as
  `timedOut` with a DELETE last; every 5c status answering its own error with
  the 400 and 402 sentences relayed verbatim; and the four `words` shapes —
  absent, `null` and `{}` each `.malformed` with a DELETE last, while `[]` is
  a `Fetched` whose `wordsJSON` is the two bytes `[]`, zero words, and no
  delete (the CONTROL).
- **16**, the cancel token against the fake: a 16 MB upload cancelled at its
  first progress callback answers `cancelled`, the fake logs exactly one
  upload and no submit, and it received **655 360 of 16 777 216** bytes with
  `complete` false. A cancel during polling answers `cancelled` and issues a
  DELETE of the id the fake served.
- **17** and R6-9: the file is `0600` and the directory it creates is `0700`,
  both read off the filesystem; the rename leaves no temporary sibling; the
  store wins over the environment with both holding dummies; a
  whitespace-only environment value is no key; `-RCSecretFolder` makes the
  store a `FileStore` on that path, `-RCAssemblyAIEndpoint` alone makes it an
  EMPTY `MemoryStore`, and the same two keys persisted in a defaults suite
  move neither — all by TYPE and path string, with nothing read. The loopback
  table and nine endpoint strings, one process each.
- **19**, the fifth rule: three words that are ONE cue with no speaker key
  are TWO with A,A,B; every speaker explicitly nil is BYTE-EQUAL to no
  speaker key at all; A-then-nil breaks; a change coinciding with a length
  break is ONE break; and the frame of gap survives, exactly 20 000 ticks in
  the tight case. The spec's wording expected exactly one frame; `CaptionCues`'
  rule is "a frame before the next cue OR where the last word ended, whichever
  is earlier", so a quiet gap is larger — the row asserts `>= frame` and a
  second fixture, words 10 000 ticks apart, measures the clamp making exactly
  20 000. Again the code was right and the row's sentence was not.
- **V**: a served `words` holding `0.98`, `"]` and non-ASCII comes back from
  the client, out of the written file and out of a `remoteDeleted` rewrite
  **byte-equal to the 354 bytes the fake served**; the document's keys are
  sorted with `words` last; `undeleted` lists exactly the false ones by media
  id; and a cache file with its `words` key removed, and one with
  `"words":null`, each make `File.init(data:)` throw, `read` answer nil,
  `isCurrent` answer false and the janitor's list empty.
- **W/F/FB/Q**: the extractor and the FLAC — below.
- **R/G/N/S/K**: a 302 is `redirected(302)` and the second fake's log stays
  EMPTY; `not-on-the-list` is logged as the redaction marker, scored under
  `failures`, and is in no file under the fake's folder; no logged header
  holds the host's user name or home path; 21 codes in §2's order, unique,
  dated 2026-09-17; `CloudTranscriber(` occurs in no `app/Sources` file but
  its own and its placeholder throws its sentence; a child handed a
  credential echoes it in neither stdout, stderr nor its answer; and every
  `subprocess` call in the probe passes `env=` (11 of them).

#### The FLAC, measured

The fixture is road map 4's `say -o` speech: **166 218 frames, 10.389 s**, a
336 532-byte WAV. The FLAC is **161 992 bytes, 48.1% of the WAV** — the same
figure C0's q2 measured against the service — with STREAMINFO **16000 Hz, 1
channel, 16 bits** and a total-sample count equal to the WAV's own 166 218.
Two runs of `writeFLAC` over one WAV are byte-identical. It decodes, through
`AVAudioFile` and again through `ffmpeg`, to the WAV's samples as a prefix
with a tail of **0 frames** — no padding at all. The fallback, forced by a
`flac:` closure calling the REAL `writeFLAC` at an unwritable path, answers
`.wav` and the framework's own sentence is *"The operation couldn't be
completed. (com.apple.coreaudio.avfaudio error 2003334207.)"*.

#### A host fact that changed how two rows are written

**This Mac's 16 kHz extract is not bit-deterministic.** Measured: over ten
separate processes of one binary over one fixture, and over five trials of
three decodes inside one process, decodes of the same audio land on one of
exactly **two** byte strings that differ in **one byte** — one 16-bit
sample's low bit, at offset 132 098 of 336 532 — in either direction, about
**one decode in five**. It does not depend on the range asked for, on the
binary, or on the order within a process, and a first attempt to explain it
as a cold-decode effect was tested and disproved.

The first shape of rows W and Q compared one decode against one decode and
failed about a third of the time, in whichever row drew the short straw. That
was not softened away: the rows now decode each side five to six times and
assert the thing a real change breaks — one length, at most two distinct
strings across the whole population, those two differing in a single sample —
with a CONTROL row that measures ONE range form disagreeing with ITSELF at
that same byte, which is what makes the comparison about this host rather
than about the code. So:

- **W**: five decodes by the BASELINE tree's `Transcriber().extractAudio(job:)`
  and five by today's, over two windows. Today's tree is indistinguishable
  from the baseline's: one length (336 532 and 132 072 bytes), one or two
  distinct strings, and no baseline decode further than one sample from
  every decode of today's.
- **Q**: nine decodes over three processes — `wholeAsset`, the explicit
  `[0, asset.duration)` range, `wholeAsset` again. All nine agree on the
  frame count (166 218) and the length, and are drawn from one population of
  at most two strings differing at 132 098; `wholeAsset` alone, six times,
  disagrees with itself in exactly the same way. So the app never needs
  `AVAsset.duration`, which is the deprecated getter it may not call.
- **Q, q4's row**: C0's `late.mov` extracted whole keeps 1.5 s of silence at
  its head, which is why `audio_track_start_ms` is written 0.

#### Mutants, each a tree COPY with one text asserted to occur once

| `--mutant` | Score | The named row among its failures |
|---|---|---|
| `mapping-no-in` | 180/186 before 05-review's fix; re-aimed after it, 14/24 (`--only mapping`) | all six of row 12's window rows |
| `no-fifth-rule` | 179/186 | seven of row 19's |
| `no-retry` | 182/186 | both retry rows and both backoff measurements |
| `store-0644` | 184/186 | "the FILE is 0600 (got 0o644)" |
| `env-first` | 185/186 | "with BOTH holding a dummy, the STORE wins" |
| `stamp-drops-field` | 185/186 | "options.speaker_labels changing INVALIDATES" |
| `no-speed-guard` | 14/15 (`--only mapping`) | "a degenerate `speed` is GUARDED, not trapped on" |

None kept the full score. The last one is 05-review's finding 1 reverted in a
tree COPY: with the guard gone the probe binary dies mid-row on *"Double value
cannot be converted to Int64 because it is either infinite or NaN"*, which is
the trap the guard exists to stop, and the row carries that sentence as its
failure. `mapping-no-in` was re-aimed at the same line's new text (`/ speed`)
and still takes row 12 down — 14/24 over `--only mapping`, every window row
and four of the five degenerate rows among its failures.

#### 05-review's findings, fixed (2026-09-20)

- **Finding 1, should-fix.** `MediaTranscript.project` divided by `job.speed`
  unguarded, so a `Job` carrying `0`, a negative, NaN or an infinity made
  `Ticks(_:)` trap. It now takes the same local guard its twin
  `Transcriber.project` has always had — `job.speed.isFinite && job.speed > 0
  ? job.speed : 1` — three lines, no other change. Proved by the ten new rows
  above and the `no-speed-guard` mutant.
- **Finding 2, should-fix.** Row 15's record claimed the two retries were
  "each measured waiting 0.271–0.278 s"; the run recorded in the handoff's
  `04-checks.txt` printed 0.274 s and 0.272 s and "throws `server`". Both
  sentences now quote that run.
- **Findings 3–6 were nits.** The row-wording corrections (3) are now in the
  row 12, 15 and 19 bullets above, where the deviation belongs; 4 (a
  `progress` read outside the sink's lock), 5 (`EINTR` reported as
  `unwritable`) and 6 (`make test`'s count said to be carried forward) were
  left. `make test` was re-run after the fix all the same and printed 721
  passed, 0 failed over 39 binaries with the core byte-identical to the
  baseline tree.

#### What this pipeline did NOT reach, said rather than papered over

- **`CloudTranscriber.transcribe` has no body and no caller.** Its placeholder
  is proved to throw its sentence and proved unreachable by a grep of
  `app/Sources`; nothing about 5a's run — the janitor, the grouping, the
  progress bands, the auth arm that ends a run — is built or measured. That
  is c1-run's.
- **No row drives the built APP at anything in this pipeline.** `phase4_proof`
  and `op_catalog_proof` prove the app still does what it did; every new part
  is reached by a probe compiled from `app/Sources`, never over MCP, because
  no tool and no menu reaches any of it yet.
- **`verify()`, `delete()` and `upload`'s progress are exercised only against
  the stand-in.** No call to `api.assemblyai.com` was made by anything in
  this pipeline, deliberately. 5i's live rows 20–21 remain c1-close's.
- **The one-sample flip above is a HOST fact, not a fixed thing.** If a later
  macOS makes the extract deterministic, W and Q will simply see one distinct
  string and still pass.

### 10.10 c1-run — the run, the MCP mirror, and the proof

Built 2026-09-20. `CloudTranscriber.transcribe` has 5a's body; the
`transcribe` tool dispatches on `engine`; `tools/proof/cloud_captions_proof.py`
exists and drives the BUILT binary over MCP against the stand-in. Nothing in
this pipeline called `api.assemblyai.com`, and after it the cloud engine is
reachable only through `transcribe {engine: "assemblyai"}` — File ▸ Generate
Captions… behaves exactly as it did.

**Nothing in the core, the FFI or the op table moved.**
`git diff <pipeline 2's tree> -- core app/Sources/ReelCore.swift
app/Sources/ReelOps.swift project.yml` is EMPTY. `OP_NAMES` is still 57, the
catalog still 77 tools, `RC_FORMAT_VERSION` still 8. `make test` printed
**721 passed, 0 failed over 39 binaries**; `make lint` and
`cargo fmt --check` are clean; `make typecheck` is 0 errors and exactly 4
warnings.

#### Spec §11, before the code

- **R6-10** — the caption path clamps a clip's `speed` at BOTH ends, because
  the ops bound it (`edit_clip.rs`'s `SPEED_MIN`/`SPEED_MAX`) and the reader
  does not (`model_query.rs:189`'s `validate` checks duration and start and
  never speed). `Transcriber.placed` is the ONE door both mappings convert
  through and clamps the offset into `[0, duration]` in `Double`;
  `Transcriber.contentLength` bounds the source length to
  `maxSourceTicks` = 1e15 — not `i64::MAX`, because Swift SUMS it
  (`MediaTranscript.swift:317`, `TranscribeSheetController.swift:264` over at
  most `MAX_CLIPS` = 4096 jobs) — and `Transcriber.jobs` bounds `Job.sourceIn`
  the same way. Declined: bounding `speed` in `validate`.
- **R6-11** — a media whose remote delete this run could not confirm is HELD:
  not fetched, not under `refresh`, its cache file left byte for byte, one
  `Problem` per clip, released by the first run whose janitor confirms the
  delete. A current cache without `refresh` is still served. Declined: a
  second file listing orphaned ids, and serving the old words under
  `refresh`.

This closes `designs/reelcut-remaining.md` §5's speed-guard bullet for the
CAPTION path and for nothing else; the rest of the app against such a file is
recorded there as unmeasured residue.

#### What landed, with every file's `wc -l` before → after

| File | Before | After |
|---|---|---|
| `app/Sources/CloudTranscriber.swift` | 102 | **296** |
| `app/Sources/CloudTranscriber+Media.swift` | — | **183** (new) |
| `app/Sources/CloudProgress.swift` | — | **141** (new) |
| `app/Sources/AgentServer+CloudCaptions.swift` | — | **247** (new) |
| `app/Sources/AgentServer+Captions.swift` | 409 | **439** |
| `app/Sources/AgentCatalog+Captions.swift` | 165 | **215** |
| `app/Sources/Transcriber+Jobs.swift` | 117 | **178** |
| `app/Sources/MediaTranscript.swift` | 379 | **383** |
| `app/Sources/Transcriber.swift` | 584 | **583** |
| `tools/proof/assemblyai_fake.py` | 489 | **501** |
| `tools/proof/cloud_captions_probe.py` | 2638 | **3280** |
| `tools/proof/cloud_captions_proof.py` | — | **1479** (new) |

Every new file is under the 400-line cap and `Transcriber.swift` came back
one line under where it was. `AgentServer+Captions.swift` took 30 lines for
the dispatch and is 161 under the ~600 cap.

The fake gained ONE scenario key, `transcript_error_first` — with
`transcript_error` set, only the first N SUBMITTED transcripts end in
`error`, so 5i·6's "the OTHER media's cues still land" is reachable. Absent
is every transcript, which is what it always meant.

#### The scores, each from the run that printed it

- **`cloud_captions_proof.py` — 115/115, no skip**, in 45–50 s, three times.
  Three instances on 4955, 4956 and 4957, each with its own fake on port 0,
  each killed by its own PID, each with a row that `grep "Reelcut: "` on its
  log is empty. `ffmpeg` and `say` were both present, so row 2 ran both
  decoders and row 5 both relinks.
- **`cloud_captions_probe.py` — 283/283** (the run captured in the handoff's
  `04-checks.txt` printed "in 12 s"; this line first said 133 s, which no
  captured run printed): pipeline 2's 196 plus
  the 87 this pipeline added (the mapping section's `projected` and its
  near-`Int64.max` job, the whole `jobs` section, the whole `run` section,
  and hygiene's two replaced S rows).
- `source_mirror_probe.py` **40/40** — `contentLength`'s other reader, whose
  6 200 000 row is untouched by the clamp.
- Against the new binary on 4958: `phase4_proof.py` **84/84**,
  `op_catalog_proof.py` **23/23**, `op_argument_proof.py` **133/133**, the
  parity grep empty.

#### Mutants, each built in a tree COPY and each named with its score

Each is `app/`, `project.yml` and `Makefile` copied with `core` a SYMLINK to
the tree's already-built one, one text asserted to occur exactly once,
`xcodegen generate` plus the Makefile's `xcodebuild` line inside the copy
under a 900 s wall, then every row on port base 4960. Full score is 115.

| Mutant | Score | The rows that caught it |
|---|---|---|
| `stamp-always-stale` | 107/115 | row 5's six cache rows, and row 11's two |
| `mapping-no-in` | 111/115 | row 3's two oracle rows, row 5's split pair and later `in` |
| `no-delete` | 91/101 | row 2's DELETE, row 4's `remote_deleted`, row 5's cache — and rows 7, 11 and H then THROW, because R6-11 holds every media whose delete never lands (scored as three row failures, not a traceback) |
| `no-retry` | 113/115 | row 6's two 5xx-once rows |
| `no-fifth-rule` | 114/115 | row 7's speaker break |
| `universal-2-only` | 112/115 | row 2's `speech_models`, row 4's two `requested` rows |
| `no-janitor` | 109/115 | row 11's two retry rows and all four of its hold rows |
| `auth-carries-on` | 114/115 | row 6's "one upload attempted, not one per media" |
| `no-hold` | 111/115 | row 11's four hold rows |

Three of the nine (`mapping-no-in`, `no-retry`, `no-fifth-rule`) are the
probe's own `MUTANTS` texts, imported rather than spelled again. The probe
gained two of its own for R6-10: **`no-speed-clamp`** (the clamp taken out of
`Transcriber.placed`) fails the mapping section at its first request — a
TRAP, which is the point — and **`no-length-clamp`** (the bound taken out of
`contentLength`) scores 28/30 on the `jobs` section, failing `1e300` by trap
and `greatestFiniteMagnitude` by answer.

#### What this pipeline measured that nothing had

- **`media/speech.mov`'s extract is not repeatable at all.** Four extracts,
  four distinct byte strings of ONE length (167 930 bytes), spans 105–228
  bytes — about 60–115 samples. The `say` AIFF over the same code is two
  strings differing in one byte, which is what §5 recorded. So row 2's byte
  population uses the AIFF and the .mov's own spread is printed as a row
  beside it, named as the reason. This is a second, LARGER non-determinism
  than the one `designs/reelcut-remaining.md` §5 holds, and it is about the
  AAC decode rather than about the resampler.
- **The progress bar, end to end.** 63 `(fraction, detail)` pairs over a
  two-media run, non-decreasing, each inside its phase's band of its own
  media's share, holding at exactly the 0.95 point of each share once
  `waited × 147` passed the audio's own seconds, ending at exactly 1.0, with
  an upload retried from zero never lowering it.
- **No extract survives a failed run.** Measured at both ends: in the probe,
  `reelcut-upload-*` in the probe binary's own temporary directory before,
  during (the CONTROL — one IS there) and after a cancelled, an errored and a
  401'd run; over MCP, the same glob over both spellings of the host's
  temporary folder around the built app's runs.
- **The credential is nowhere.** `proof-key` appears in no app log, in none
  of the 158 MCP answers and refusals the run accumulated, and in no file the
  run wrote — the fake keeps its request log in memory, so there is not even
  that. No logged header or JSON body holds this host's user name or home
  path.

#### The tree

**`870fa0ec4d017fa6c4b2f8a40d1a0bf7ef5cd222`** — every line this pipeline
wrote except this paragraph, by the request's temp-index recipe (never the
real index; nothing was committed, added, stashed or checked out). It is
measured before the paragraph rather than after it because a hash of a tree
cannot be written into that tree; re-run the recipe for the current one. The
baseline is pipeline 2's `10bbbb05eb219319f84f7d5e6c13c775090ba31a`, and
`git diff` of that baseline over `core`, `ReelCore.swift`, `ReelOps.swift`
and `project.yml` is empty.

#### Limits and deviations, said rather than papered over

- **A service whose DELETE never succeeds stops re-transcription.** R6-11's
  hold is per RUN and releases only when a janitor retry succeeds, so a
  prolonged outage of `DELETE /v2/transcript/{id}` leaves every already-
  transcribed media held: cached words are still served, `refresh` is
  refused in R6-11's sentence, and a NEW media is unaffected. The
  `no-delete` mutant is that state, and its score is what it looks like.
  Accepted: the alternative is orphaning a transcript at the far end for
  ever, which is what R6-11 was written for.
- **A 404 from the janitor is a failure, not a delete.** C0's q6 measured
  that a real deleted transcript answers 200, so a 404 means something else
  and is not treated as "already gone". Recorded, not fixed.
- **The fake's scenario cannot be half-replaced.** `POST /__control/scenario`
  resets the transcript table with the scenario, so row 11's hold arm spells
  "the failure stops" as `times: 2` rather than as a cleared `fail`. Same
  observable sequence, one fewer control endpoint.
- **Row 3's placed clips are checked by COUNT and by start**, within one
  frame, not by duration: `CaptionLayout.place` snaps and abuts, which is its
  own tested behaviour, and re-deriving it here would be a second spelling of
  it. The cues themselves are compared tick for tick against the Python
  oracle.
- **Row 4 reads the three cache-sizing constants off whichever of the
  import's markers has landed**, not off the peaks one by name: which pass
  finishes first is the import's business, and pinning it made the row flaky
  on a busy host (seen, then fixed).
- **`make app`'s own `xcodebuild` is what a mutant runs**, so a mutant costs
  about a minute of build and a minute of rows. Nine of them is twenty
  minutes; they were run one at a time, never beside another build.
- **Not reached, and c1-chrome's or c1-close's:** the Engine popup and the
  three cloud rows in the sheet, `CloudEstimate`, the Settings window, the
  report card, `project.yml`'s usage string, the harness pins, probe rows 14
  and 18, 5i's live rows 20–21, and every earlier proof re-run.
