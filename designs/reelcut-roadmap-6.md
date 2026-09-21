# Reelcut — road map 6: captions from the cloud (AssemblyAI Universal-3.5 Pro)

**Status: C1 is BUILT AND REVIEWED** — captions from the cloud shipped over
the five pipelines §10 records, the last of them (c1-close) on 2026-09-21,
with 5i's LIVE rows run against `api.assemblyai.com` and every earlier proof
re-run against the final binary (§10.12); the READER REVIEW road map 2 §0's
practice owes each phase ran on 2026-09-21 and its record is **§10.13**,
whose closing subsections hold the independent SCEPTIC pass over that review
and the fix pass that answered its six findings (same day). **C2, the relay, is DESIGNED and not
built**, and §6b is what blocks it. The spike (C0) RAN on 2026-09-20 and §3
is its record: all eight of its rows were measured on that date, nothing is
owed by a row, and the sections each row overturned — §2's two open
questions, §5a's upload format, §5d's credential store, §5h's `project.yml`
bullet and toll 1's sentence, three of 5i's claims and §8's constants — were
REWRITTEN here rather than left standing beside the record (§3a lists every
one). Everything in §2 was read from AssemblyAI's own documentation on
2026-09-17, is cited, and now carries what the service actually answered
where the two differ. The baseline the design was written against, kept as
written: schema version 8, `OP_NAMES` 57, the catalog at 77 tools, road map
4's S1 and road map 5's E1/E2 landed — and C1 changed none of them.

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
  retention (indefinite) is why the delete is not optional. A next-run retry
  is promised only when the transcript's deletion ID was saved in the
  project. If that write and the remote delete both fail, the report says
  automatic retry is unavailable and directs the person to delete the
  transcript in their AssemblyAI dashboard.
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
  R6-14 sends this POST once. If its reply is lost, times out, is 5xx or
  lacks a decodable plain id, `AssemblyAIClient+Submission.swift` looks at
  `GET /v2/transcript?limit=200` up to three times with a 5-second request
  timeout and 2.5 seconds between looks. Only one distinct plain id whose
  `audio_url` equals this upload's encoded URL byte for byte is accepted.
  A 4xx or redirect on the POST retains its original error. A refused key
  on recovery, an ambiguous match or exhaustion reports the explicit
  dashboard warning; no second POST and no guessed DELETE follow.
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

**Revised 2026-09-20 (c1-chrome), recording what "one pane" became and
adding nothing to this section's rules.** The pane is a HEADING — the string
`SettingsWindowController.paneTitle`, "Transcription", the first arranged
subview of the window's content — inside a window titled Settings, and not a
tab bar with one tab: a tab strip with a single tab is chrome that says
nothing and has to be torn out when the second pane arrives. That is what
makes the `transcribe` tool's and the catalog's sentence sending a caller to
Settings and then to Transcription true without either sentence being edited,
and a `hygiene` row pins both byte-identical to pipeline 3's tree. Verify
runs on `CloudTranscriber`'s own `work` queue through a new
`CloudTranscriber.verify(completion:)` that captures the CLIENT and not
itself; no queue was added (spec §11's R6-12). Two things this section did
not name and the build needed: the initialiser takes a store FACTORY, so the
offscreen harness can hand it a `MemoryStore` — `Harness.pinDefaults`
REPLACES the argument domain and would otherwise leave `store()` pointing at
the person's real `FileStore` — and the masked placeholder is FIXED length,
because a mask as long as the key leaks its length.

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

**#33's current-answer rule (2026-09-21).** Verify's answer belongs to the
latest invocation and the effective credential, persisted region and resolved
base URL captured for it. An older completion cannot change the latest
request's status or controls. If the owning request's inputs changed while it
was in flight, its answer is `Settings changed since this check began. Verify
again.` in ordinary muted text, whether the server accepted or refused the
old key. Verify is enabled only when an effective credential exists and no
current request is checking those same inputs. Saving a typed key that equals
the captured effective key leaves that input current.

### 5e. The sheet

**Revised 2026-09-20 (c1-chrome), recording two deviations and adding no
rule.** (1) The summary's DURATION is what `rc_timecode_format` prints —
`02:00:00.000` for two hours, the on-device summary's own spelling with
`frames: false` — so this section's "1:42:10" is an illustration of the
SHAPE and not of the format; the probe pins the format once exactly and the
rest by its shape. (2) A third clause joins the tail, spec §11's R6-13: a
media R6-11 will HOLD is counted as "N file(s) waiting on an earlier
delete" rather than as a file to upload, and its `reasons` line carries what
it would cost if the janitor clears the delete, so its price is neither in
the total nor hidden. The reasons themselves are the summary label's
TOOLTIP, which this section did not say and the card has no room for; the
note under the button is the three things about the CALL — no key, a
vocabulary that was cut, a scope with nothing in it.

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

**Revised 2026-09-21 (#29).** A failed DELETE promises a next-run retry
only when the fetched transcript JSON was saved and therefore retains its
deletion ID. If the initial write failed too, the optional `note` (or the
failure message when the run throws) names the media, says Reelcut cannot
retry automatically, and directs dashboard deletion. A confirmed DELETE
needs no cleanup note even when the cache write failed. The UI report card
uses the same per-media rule and retains its held-media explanation.

`language` with the cloud engine: absent or `"auto"` is detection (the
wire's absent `language_code`); anything else is trimmed and passed through,
and an EMPTY string is refused by name rather than sent as a language called
"". `vocabulary` is trimmed, empties dropped, de-duplicated KEEPING THE
FIRST spelling and cut from the end at `maxKeyterms`. The Apple arm's result
gains `engine: "apple"` and nothing else. The handler is
`AgentServer+CloudCaptions.swift`; `AgentServer+Captions.swift` dispatches on
`engine` and `transcriptionScope` stays `private` — the cloud arm is handed
`jobs` and `frame` by value.

**Revised 2026-09-21 (the reader review, §10.13), correcting two sentences
above and replacing nothing else in this section.**

- The `engine` bullet reads `"apple"` **(default, whatever the sheet last
  chose)**. The parenthesis is about the SHEET's own default and reads, over
  the tool, as the opposite of R6-2: a tool call's default is `"apple"` FULL
  STOP, and `TranscriptionEngine.defaultsKey` is read by nothing in
  `AgentServer+CloudCaptions.swift`. Row 8 is what proves it — every proof
  instance is launched with that key pinned to `assemblyai` and the fake's log
  still comes back empty. The tool's own `engine` description already says
  "The default is NEVER what the sheet last chose".
- The refusal ORDER reads "… then the credential, **then a media over ten
  hours, then the network**". A media over ten hours is not a position in a
  run's refusal order: it is one MEDIA's problem, checked at the head of
  `fetch` before that media's extract and upload and therefore AFTER every
  earlier media's whole round trip. MEASURED — a two-media project whose
  first media was rewritten to forty thousand seconds answered `uploaded:
  [3]`, `audio_seconds: 11` and one `skipped` entry carrying the limit's own
  sentence, with the other media's four routes in the fake's log. It becomes
  a refusal of the RUN only when it is the only media there is, which is row
  H's case and is what row H measures.

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

**Revised 2026-09-20 (c1-chrome), adding to this section and replacing
nothing in it.** Rows 14 and 18 landed as two named SECTIONS of
`cloud_captions_probe.py`, `estimate` and `chrome`, so `--only` can reach
either. Row 18 photographs the Settings WINDOW through `tools/proof/harness/`
— the harness gained a `settings` mode beside `welcome` — and reads the
SHEET structurally, because a sheet cannot be put up offscreen at all. The
`mapping` section gained nine rows for R6-10's extension, ONE CHILD PER
MILLISECOND, and the `run` section one row for the closing publish's detail.
Three rows this section numbered none of: the sheet's controls against what
a RUN would receive (`runRequest()`), the estimate against the run's own
`Report` over two rounds, and `project.yml` diffed against pipeline 3's
tree.

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

**Revised 2026-09-21 (c1-close), saying how rows 20 and 21 are MEASURED and
replacing nothing above it.** There is no fake to read a request log from, so
what the app's client did is counted from the app's OWN lines: every live
instance is launched under a `pty` (a redirected `print` is block-buffered on
Darwin and loses the tail of the buffer — see `reelcut-remaining.md` §5),
drained by a thread that never raises, and `<method> <path> → <status>` is
parsed out of those lines. Row 20 is reserved in
`work/cloudlive/ledger.json` BEFORE the call and then made to say what the
app did rather than what the row expected: exactly one upload answering 200,
exactly one `POST /v2/transcript` line of any status and exactly one
transcript id, and every FURTHER id or unaccounted submit writes an `extra`
reservation — a fact, not an authorisation — which the $0.25 and
six-transcription gate then counts against, so an unaccounted submit stops
the money instead of hiding. Row 21's "no upload" is the strongest form the
lines can carry: the client says NOTHING AT ALL since the mark — zero lines,
hence zero `POST /v2/upload` and zero `POST /v2/transcript` — beside the
result's `cached`/`uploaded` keys and a cache file unchanged byte for byte.
The numbers these produced on this host, and the spend to the cent, are
§10.12.

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
| `submitRecoveryAttempts` | 3 | R6-14: bounded looks at the newest account page after an ambiguous single submit; C0 §3 q1 found an exact URL match |
| `submitRecoveryDelay` | 2.5 s | gap between the looks, allowing short list visibility lag |
| `submitRecoveryTimeout` | 5 s | each recovery GET's own request ceiling; an outage remains bounded |
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
relays it and carries no second dated table. What remained for C1 was the
build itself. **Revised 2026-09-21 (c1-close):** it is built, over the five
pipelines of §10.1; what remains is C1's reader review, a run of its own
(§10.12), and C2, which §6b blocks. **Revised again 2026-09-21 (the reader
review):** that review RAN, and its record is §10.13; what remains is C2.

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
  (`MediaTranscript.swift:317`, `TranscribeSheetController.swift:264` as of
  c1-run; `:333` and `:388` after c1-chrome, over at
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

**Corrected 2026-09-21 (the reader review, §10.13, L15).** That sentence is
about the new files under `app/Sources`, and it is FALSE of the table it
stands under: `assemblyai_fake.py` is **501** there, the new
`cloud_captions_probe.py` **3280** and the new `cloud_captions_proof.py`
**1479**. The 400-line cap `app/CLAUDE.md` sets is a rule about app SOURCE
files; `tools/proof/`'s instruments have never been held to it, and this
paragraph and §10.11's twin should have said so. Nothing about the code
changes; the claim does.

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

### 10.11 c1-chrome — everything a person touches

Built 2026-09-20. Reelcut ▸ Settings… ⌘, exists; the Generate Captions sheet
has an Engine popup and AssemblyAI's three rows; `CloudEstimate` prices a run
before it runs; the report card says what the cloud run said. **Nothing in
this pipeline called `api.assemblyai.com`**, no live row ran, and `README.md`
is untouched — both are c1-close's.

**Nothing in the core, the FFI or the op table moved.**
`git diff c9b80435 -- core app/Sources/ReelCore.swift app/Sources/ReelOps.swift`
is EMPTY, and `AgentCatalog+Captions.swift` is byte-identical to pipeline 3's
(`git show c9b80435:<path> | diff - <path>`, the recipe for an untracked
file). `make test` printed **721 passed, 0 failed over 39 binaries**;
`make lint` and `cargo fmt --check` are clean; `make typecheck` is 0 errors
and exactly 4 warnings.

#### Spec §11, before the code

- **R6-10, EXTENDED** to the one INTEGER multiply on the caption path. The
  rule covered every `Double → Ticks` conversion and not `ms × 600`, whose
  input is the PROVIDER's JSON and a hand-edited
  `cache/transcripts/<id>.json`. `MediaTranscript.sourceTicks(milliseconds:)`
  is now the one door, clamping in `Int` to ±`Ticks.max / 600` BEFORE the
  multiply — deliberately NOT to `maxSourceTicks`, because this number is
  never summed (it is compared with the window, with a non-negative
  `sourceIn` subtracted) and 1e15 sits INSIDE a window end a hand-written
  project can reach, so a bound there would drag a far word INTO a window.
  A negative stays negative so it keeps failing the `>= sourceIn` test.
  Every value that did not trap answers what it always did.
- **R6-12** — the key and the region are a PERSON's settings and no tool
  reads or writes either. DECLINED: a `region` key in `transcribe`'s result.
  Every proof instance runs under `-RCAssemblyAIEndpoint`, where the region
  is not where the run spoke, so such a key could be proved only where it is
  false; the honest shape (the base URL's HOST under `endpoint`) is residue
  in `designs/reelcut-remaining.md` §5. Verify runs on `CloudTranscriber`'s
  `work` queue and adds no queue (R6-7).
- **R6-13** — the estimate never counts a HELD media as "to upload" and
  never hides its price: its own clause in `describe`, its own line in
  `reasons`, carrying what it would cost if the janitor clears the delete.

#### What landed, with every file's `wc -l` before → after

| File | Before | After |
|---|---|---|
| `app/Sources/CloudEstimate.swift` | — | **328** (new) |
| `app/Sources/SettingsWindowController.swift` | — | **376** (new) |
| `app/Sources/TranscribeSheetController+Cloud.swift` | — | **313** (new) |
| `app/Sources/TranscribeSheetController.swift` | 380 | **540** |
| `app/Sources/TranscribeSheetController+Commit.swift` | 145 | **215** |
| `app/Sources/AppDelegate+Menus.swift` | 544 | **549** |
| `app/Sources/CloudTranscriber.swift` | 296 | **317** |
| `app/Sources/MediaTranscript.swift` | 383 | **399** |
| `app/Sources/AssemblyAITranscript.swift` | 374 | **399** |
| `app/Sources/AgentServer+CloudCaptions.swift` | 247 | **243** |
| `tools/proof/harness/main.swift` | 901 | **954** |
| `tools/proof/cloud_captions_probe.py` | 3280 | **4753** |
| `tools/proof/cloud_captions_proof.py` | 1479 | **1494** |

Every new file is under the 400-line cap — **of the app's own sources;
corrected 2026-09-21 by the reader review, §10.13, L15, as §10.10's twin
sentence is** — and `MediaTranscript.swift` and
`AssemblyAITranscript.swift` are at **399** of their own 400 and
`TranscribeSheetController.swift` at **540** of the ~600. (Every number in
this table is the FIX-PASS tree's, measured after 05-review's findings were
fixed; the three files that grew there are named in "The fix pass" below.) `MediaTranscript`
went over its cap once during the build at 411 and the doc comment was cut
until it fitted, which is the whole of what that cap is for.
`AgentServer+CloudCaptions.swift` came DOWN four lines: `keyterms` moved to
`extension TranscriptOptions` in `AssemblyAITranscript.swift` verbatim, so
the sheet's Vocabulary field and the tool's `vocabulary` argument cap and
de-duplicate through ONE function. `AppDelegate.swift` was not touched at
all — `showSettings` is an `extension AppDelegate` at the foot of
`SettingsWindowController.swift`, `CaptionImporter.swift`'s
command-at-the-foot precedent.

#### The scores, each from the run that printed it

- **`cloud_captions_probe.py` — 469/469, no skip**, in 88 s on the fix-pass
  tree and again in 24 s on the final one with the fixture already made
  (463/463 in 228 s on the tree the review read, before the fix pass added
  six rows). The per-section counts, each printed by its OWN `--only`
  run on the fix-pass tree: `--only estimate` **96/96**, `--only chrome`
  **76/76**, `--only hygiene` **27/27**. Those are the sections' TOTALS, not
  what this pipeline added to them: the `hygiene` section holds pipeline 2's
  rows as well as this pipeline's, and no run has ever printed that split.
  05-review's finding 3 was that the earlier "283 plus the 180 this pipeline
  added … four hygiene rows" breakdown was arithmetic nobody ran; it is
  withdrawn rather than patched.
- **`cloud_captions_proof.py` — 115/115, no skip**, in 51 s against the new
  binary, three instances on 4970–4972 each with its own fake on port 0,
  each killed by its own PID, each with a row that `grep "Reelcut: "` on its
  log is empty. **The row COUNT is unchanged and that is the point**: this
  pipeline changed no tool, no schema and no op, and every instance now
  launches with `-ReelcutCaptionEngine assemblyai`, which turns row 8 from a
  row that could not fail into one that can.
- Against the new binary, one FRESH instance per script on 4973 and 4974,
  each with `-RCAssemblyAIEndpoint http://127.0.0.1:9` and a disposable
  `-RCSecretFolder`: `phase4_proof.py` **84/84**, `op_catalog_proof.py`
  **23/23**, `op_argument_proof.py` **133/133**, every parity grep empty.
- With no instance running: `phase4_chrome.py` **59/59**,
  `source_mirror_probe.py` **40/40**.

#### Mutants, each a tree COPY with one text asserted to occur once

Probe mutants, full score 463 — these five were measured on the tree the
review read, before the fix pass added six rows (the full score is 469 now):

| Mutant | Score | The rows that caught it |
|---|---|---|
| `rate-halved` | 438/463 | twenty-four `estimate` rows — every price, every `money`, both rate sentences and the `reasons` line — and the Settings paragraph's own dated rate |
| `no-credential-check` | 462/463 | row 18's disabled-button row, with an empty store |
| `masked-shows-value` | 461/463 | row 18's two Save rows: the field is not empty afterwards, and the key is in a view's `stringValue` |
| `no-ms-clamp` | 459/463 | four of the nine ms rows, each by a TRAP — `Int64.min`, `Int64.max`, and either side of `Int64.max / 600` |
| `empty-closing-detail` | 462/463 | the run section's new row: a pair published mid-run with no detail |

Proof mutant, full score 115: **`agent-reads-remembered-engine`** —
the tool falling back to `UserDefaults`'s `ReelcutCaptionEngine` when a call
named no engine — scores **110/115**, failing row 8's "the fake's log is
EMPTY" and four of row 1's, because every instance is launched with that key
pinned to `assemblyai`. Before this pipeline that mutant was invisible: with
the key absent the fallback answered `.apple` and every row passed.

#### What this pipeline measured that nothing had

- **The Settings window, photographed.** Two processes per appearance,
  byte-identical each time, light ≠ dark, 460 × 340 points at the display's
  backing scale (measured scale **1** on this host's offscreen window, the
  same as `welcome`'s). No Auto Layout ambiguity to chase.
- **A Mac with NO on-device speech model can still transcribe in the
  cloud.** The sheet built with `languages: []` and a key: under On this Mac
  the button is dead and the note names the missing model; under AssemblyAI
  the same sheet is live, its note says nothing about an on-device model,
  and a click sets `didStart` and holds a `CloudTranscriber`. That is what
  the dispatch-on-`engine`-as-first-statement rule buys, and it is measured
  rather than argued.
- **The estimate and the RUN agree, twice.** Empty cache: the estimate says
  upload, the run uploads, same id. Second round: the estimate says cached,
  the run reads the cache, neither uploads. The two classifications are
  DIFFERENT code (`CloudEstimate.fate` and `CloudTranscriber.transcribe`)
  and were deliberately not merged; this row is what would catch them
  drifting.
- **The vocabulary is one function.** `func keyterms(` is declared once in
  `app/Sources`, and a `chrome` row compares the sheet's own split-and-cap
  against `TranscriptOptions.keyterms` on the same text. The cap NOTE reads
  three ways and all three are rows: 1001 distinct terms names 1000 and
  1001; 1001 pieces of which only 401 survive says nothing (a list that
  shrank on duplicates lost nothing); exactly 1000 distinct says nothing.
- **Save and Remove really went through R6-9's folder.** The `chrome` op
  builds `SettingsWindowController` with its DEFAULT store factory under
  `-RCSecretFolder <a folder under tools/proof/work/>`, writes, finds the
  file at `0600` in that folder, scans every view's `stringValue`,
  `placeholderString`, `toolTip`, `accessibilityValue()` and
  `accessibilityLabel()` plus the window title for the dummy — none holds it
  — then removes it and finds it gone.

#### Limits and deviations, said rather than papered over

- **The summary's duration is `rc_timecode_format`'s**, `02:00:00.000`, not
  §5e's illustrative `1:42:10`. Recorded as a dated revision in §5e. The
  probe pins the format exactly once and every other row by its shape,
  because re-deriving a timecode in Python would be a second spelling of the
  core's.
- **The reasons are a TOOLTIP.** §5e names the summary line and the note but
  gives the per-file "why" no home, and the card has no room for four lines
  of it. It is `summaryLabel.toolTip`, and nobody has hovered it at the
  machine — `designs/reelcut-remaining.md` §4 carries that.
- **`Settings ▸ Transcription` is not a contiguous string in the TOOL's
  file.** The sentence is split across two source lines there, so the
  hygiene row greps for the contiguous string (exactly one file, the
  catalog) and pins each file's sentence BYTE-IDENTICAL to pipeline 3's tree
  separately. The spec for this pipeline assumed one grep would do both.
- **The estimate's facts are cached per media for the life of the sheet**,
  which is what keeps a keystroke in the Vocabulary field from stat-ing two
  files per media. Nothing can change them under an open sheet; if a future
  phase lets a document change under one, this cache is where it breaks.
- **One row of the spec's chrome list is a text scan and not a call**:
  "`openAccount` is never invoked" is checked by asserting the probe's own
  chrome source does not name it, because invoking it would open a browser.
- **No mutant was built for the Settings window's PHOTOGRAPH.** The four
  chrome mutants aim at behaviour; a mutant that moved a control would be a
  mutant of a picture nobody has looked at yet, which §4 owes a person.
- **The root `CLAUDE.md`'s table still calls this road map "DESIGNED and not
  built".** It has been wrong since c1-run and is not this pipeline's to
  change — the row describes the whole of C1, and C1 is not finished until
  c1-close. It is named here so it is not rediscovered.

#### The fix pass (05-review, 2026-09-20)

Findings 1 and 2 (both `should-fix`) and nits 4 and 5 were fixed; finding 3
is the withdrawn breakdown above. Each code fix has a row that was made to
FAIL on purpose, as a mutant over a tree COPY.

| Finding | The fix | The row | The mutant, `--only chrome` |
|---|---|---|---|
| 1 | `refresh()`'s `.apple` arm sets `summaryLabel.toolTip = nil`, so the cloud reasons stop hovering over the on-device summary | "18: and going back to On this Mac TAKES THEM DOWN", with "18: under AssemblyAI the summary HANGS its reasons off the label's tooltip" as its CONTROL | `stale-tooltip` **75/76**, failing that row alone |
| 2 | `settingsChanged` calls `applyEngine()` before `refresh()`, so a region changed in the Settings window under an open card rewrites the hint the way `beginCloud` reads it at click time | "18: a REGION changed in the Settings window under an open card rewrites the hint's jurisdiction" — the probe posts `didChangeNotification` with the suite's region moved to `eu` and back, and reads `hintLabel.stringValue` three times | `stale-region-hint` **75/76**, failing that row alone |
| 4 (nit) | `sync()` builds ONE store and passes it to both reads | "18: ONE sync builds ONE store" — a counting factory over a `MemoryStore`, `sync()` called once, the count read back | `two-stores-per-sync` **75/76**, failing that row alone |
| 5 (nit) | no code change: the row that clicks Generate now MEASURES its cancel | "18: and Stop ENDS it" (`didFinish` inside the row's bound, `The transcription was cancelled.` on the card, the button reading Close, the one clip still on the timeline) and "18: and it stopped before anything was uploaded — the fake's request log is still empty" | none — nothing was fixed to revert |

`applyEngine`'s doc comment now names its third caller, which is the only
other line the fixes moved. The three files that grew:
`TranscribeSheetController.swift` 528 → **540**,
`SettingsWindowController.swift` 372 → **376**,
`cloud_captions_probe.py` 4640 → **4753**; every cap still holds.

Re-run after the fixes, each score from the run that printed it:
`make typecheck` **0 errors / 4 warnings** (the baseline four AVFoundation
deprecations), `make app` **BUILD SUCCEEDED**, `make lint` clean and
`cargo fmt --check` clean, `cloud_captions_probe.py` **469/469** with the
three new mutants at **75/76** each, `cloud_captions_proof.py` **115/115**
against the new binary (4970–4972, each fake on port 0, each instance killed
by its own PID, `grep -c "Reelcut: "` **0** on all three logs, no instance
left), and `phase4_chrome.py` **59/59**. `make test`, `phase4_proof.py`,
`op_catalog_proof.py`, `op_argument_proof.py` and `source_mirror_probe.py`
were NOT re-run: the fixes touched two app-side chrome files and the probe,
`core` is byte-identical to the tree those scores were printed on, and no
tool, schema or op moved.

#### The tree

**`5cc64c21215641e7a99cd3e7d95ace8c6f03a13d`** — every line this pipeline
and its fix pass wrote except this paragraph, by the request's temp-index
recipe (never the real index; nothing was committed, added, stashed or
checked out). It is measured before the paragraph rather than after it
because a hash of a tree cannot be written into that tree; re-run the recipe
for the current one. The tree the review read was
`2f82b87ed86c2ba39b40581fc215babc191acb5d`. The
baseline is pipeline 3's
`c9b8043522c5a91b6045102d182758fd5859d153`, and
`git diff` of it over `core`, `ReelCore.swift` and `ReelOps.swift` is empty
(`AgentCatalog+Captions.swift` is untracked, so it is compared with
`git show <tree>:<path> | diff - <path>`, which is identical).

### 10.12 c1-close — the live rows, the re-runs, and what C1 is

The fifth and last of §10.1's five pipelines, 2026-09-21. Its baseline is
c1-chrome's final working tree `d22d0f4de4b031eed7a6377c697726aac8c16213`.
**It changed no product file at all** — `git status` over `app/Sources` is
byte for byte what pipeline 4 left — and `git diff d22d0f4d -- core` is
empty. What it added is `tools/proof/cloud_captions_live.py` and
`tools/proof/cloud_live_ledger.py`, a `--live` flag and a pty-backed
`Instance` in `cloud_captions_proof.py`, the section-C runner under the
gitignored `tools/proof/work/c1-close/`, and the documents below.

#### The five pipelines, as trees

Nothing was committed between them; each pipeline snapshotted its working
tree into a TEMPORARY index (never the real one) and wrote the hash into its
own record. A record's paragraph cannot hold a hash of the tree that holds
it, so each pipeline's own number is the tree BEFORE its closing paragraph
and the next pipeline's baseline is the tree after it; both are given.

| Pipeline | The tree its own record names | What the NEXT pipeline took as its baseline |
|---|---|---|
| 1 · c1-tolls (§10.1–§10.8) | **T5** `8f1bfc9edf3a9c5c5a5ea7a32ee87173c9d1860e`, the last CODE tree; T0–T3 are §10.1's table | `515e6a8032071626f8c2a77030db4b249495602b` |
| 2 · c1-parts (§10.9) | **S2** `f6598273c83b5468e7ee80a554af33392a615d6b` | `10bbbb05eb219319f84f7d5e6c13c775090ba31a` |
| 3 · c1-run (§10.10) | `870fa0ec4d017fa6c4b2f8a40d1a0bf7ef5cd222` | `c9b8043522c5a91b6045102d182758fd5859d153` |
| 4 · c1-chrome (§10.11) | `5cc64c21215641e7a99cd3e7d95ace8c6f03a13d` (the review read `2f82b87ed86c2ba39b40581fc215babc191acb5d`) | `d22d0f4de4b031eed7a6377c697726aac8c16213` |
| 5 · c1-close (this section) | at the end of this section | — |

#### The gate, before a line was written

`make typecheck` **0 errors, exactly 4 warnings** (the baseline four
AVFoundation deprecations — three in `CompositionBuilder.swift`, one in
`Exporter.swift`), `make app` **BUILD SUCCEEDED**, `make test` **721 passed,
0 failed over 39 binaries**, `make lint` clean, `cargo fmt --check` clean,
`git diff d22d0f4d -- core` empty. Re-run on the final tree after the live
module landed: `cloud_captions_probe.py` **469/469 in 17 s**,
`cloud_captions_proof.py` **115/115 in 52 s** — the row count unchanged,
which is the point, since `--live` runs rows 20–21 INSTEAD of rows 1–11 and
the flag is off by default.

#### The mutants — twelve already scored, one gap run here

5i's list was read against §10.9–§10.11 and every mutant it names already
has a score from the pipeline that aimed it. They are NOT re-run; this is the
table, with the section that measured each:

| Mutant | Score | Against | Recorded in |
|---|---|---|---|
| `mapping-no-in` | 180/186, re-aimed 14/24 (`--only mapping`) · 111/115 | probe · proof | §10.9 · §10.10 |
| `no-fifth-rule` | 179/186 · 114/115 | probe · proof | §10.9 · §10.10 |
| `no-retry` | 182/186 · 113/115 | probe · proof | §10.9 · §10.10 |
| `store-0644` | 184/186 | probe | §10.9 |
| `env-first` | 185/186 | probe | §10.9 |
| `stamp-drops-field` | 185/186 | probe | §10.9 |
| `no-speed-guard` | 14/15 (`--only mapping`) | probe | §10.9 |
| `stamp-always-stale` | 107/115 | proof | §10.10 |
| `no-delete` | 91/101 | proof | §10.10 |
| `universal-2-only` | 112/115 | proof | §10.10 |
| `no-janitor` | 109/115 | proof | §10.10 |
| `auth-carries-on` | 114/115 | proof | §10.10 |
| `no-hold` | 111/115 | proof | §10.10 |
| `no-length-clamp` | 28/30 (`--only jobs`) | probe | §10.10 |
| `rate-halved` | 438/463 | probe | §10.11 |
| `no-credential-check` · `masked-shows-value` · `no-ms-clamp` · `empty-closing-detail` | 462 · 461 · 459 · 462 of 463 | probe | §10.11 |
| `agent-reads-remembered-engine` | 110/115 | proof | §10.11 |
| `stale-tooltip` · `stale-region-hint` · `two-stores-per-sync` | 75/76 each (`--only chrome`) | probe | §10.11 |

**The one gap, run here.** §10.10 described `no-speed-clamp` — R6-10's clamp
taken out of `Transcriber.placed` — in a sentence and recorded no N/M for it.
Run on 2026-09-21 in a tree COPY, `--mutant no-speed-clamp --only mapping`:
**1/2**, the probe built in 63.7 s and the mapping mode then DIED at its
first request with *"Fatal error: Double value cannot be converted to Int64
because the result would be greater than Int64.max"* — the trap the clamp
exists to stop, carried as that row's failure sentence rather than as a
traceback. No mutant in this table kept a full score.

#### The LIVE rows — RUN on this host, not skipped

`python3 tools/proof/cloud_captions_proof.py --live --port-base 4980`:
**37/37 checks, no skip**, twice (8 s and 11 s), the second time on the final
files. Thirty-six of the thirty-seven are the live module's own, which is
exactly `LIVE_ROW_COUNT`, printed beside the number the run actually made;
the thirty-seventh is the probe-build row. The preconditions all held —
`RC_ASSEMBLYAI_KEY` present (the word, never the value), a TCP connect to
`api.assemblyai.com:443` inside 5 s, `say` on the host, the ledger clean and
the gate open — so **nothing here is a skip standing in for a pass**.

What the rows measured, each from the run that printed it:

- **The dummy arm (L0), free.** An instance with NO endpoint override, a
  DUMMY key in the environment and `-RCSecretFolder` on an EMPTY directory:
  the real service answered `POST /v2/upload → 401` and the run was refused
  with *"AssemblyAI refused the API key — check it in Reelcut ▸ Settings"*.
  The captured client lines were EXACTLY that one line — zero `POST
  /v2/transcript` of any status, no id — no cache file and no marker were
  written, and the secrets folder was `[]` before and after. That is R6-9's
  arm proved against nothing billable, and it is the gate the real key is
  only used behind.
- **Row 20 (L1), the round trip.** One `POST /v2/upload → 200`, exactly one
  `POST /v2/transcript` line of any status and it a `200`, exactly one
  transcript id. `speech_model_used` is **`universal-3-5-pro`** in the result
  and in the cache header. `audio_seconds` is **11** — `math.ceil(166218
  frames / 16000)` from the app's own extractor — and equals the header's
  `audio_duration`, which is §3 q1's rounding-up, measured again. The
  provider's **23 words** hold all 23 of the fixture's spoken tokens in
  order; this host's WAV holds two pauses (**2.72–4.29 and 6.68–7.81 s**, road
  map 4's own numbers) and **no word overlaps one by a single millisecond**,
  outright and with no tolerance. `remote_deleted` is true, there is exactly
  one `DELETE /v2/transcript/<id> → 200` of that one id, and a GET afterwards
  answers **200** with `audio_url` `http://deleted_by_user` and text *"Deleted
  by user."* (q6's sentinel).
- **The provider's bytes, won in a race.** A reader thread GETs the app's own
  transcript id every 0.25 s and keeps the first `completed` body in memory;
  it **won with 12 GETs of its own** on the final run, and the cache file's
  `words` span (row 4's cut) occurs CONTIGUOUSLY in that body and decodes
  equal to its `words`. The row is a SKIP BY NAME when the app's DELETE wins;
  it did not, on either run.
- **Row 21, the cache.** `cached` holds the media and `uploaded` is empty,
  the answer came back in **0.00 and 0.01 s**, the cues are run 1's cue for
  cue, the cache file's sha256 is unchanged, and "no upload" is measured as
  the client saying NOTHING AT ALL: the captured lines since the mark are
  `[]`, so zero uploads and zero submits.
- **The key is nowhere.** One in-process comparison over the captured lines,
  every MCP answer and refusal, the package, the secret folder,
  `work/cloudlive/` and BOTH instances' `/tmp/reelcut-<port>.log` files:
  `leaked False, found False`, and only that boolean is printed. Both
  instances' parity greps are empty and `reader_failed` is false on both.

#### The spend, to the cent, from `work/cloudlive/ledger.json`

Two live runs, **six reservations**, and this is the whole of C1's spend on
AssemblyAI:

- **2 transcriptions**, one per run, of the eleven-second `say` fixture.
  Both `created`, both `billed` **11 s** (AssemblyAI's own `audio_duration`),
  both closed **`deleted`** with the q6 sentinel passing for each.
- **22 billed seconds at $0.21 an hour = $0.00128.** The ledger's own
  conservative total — planned seconds for every reservation that was never
  billed — is `total_seconds()` **66.0** and `dollars()` **$0.0038**, which
  is what the $0.25 gate counts against. Two of the six transcription slots
  are used: the four `no_transcript` (the dummy arms) and `no_upload` (row
  21) rows do not count.
- **No `extra` reservation was ever written**, which is the interesting
  number: `account` writes one per submit or id the ledger had not accounted
  for, and the submit-line count seen (1 per run) equalled the created count
  (1 per run) every time.
- **No open and no `unresolved` row**, at the start of each run and at the
  end of both.

#### Section C — every earlier proof, once, against the final binary

`tools/proof/work/c1-close/rerun.py` (gitignored, beside its
`results.json`): one script per FRESHLY launched instance on 4985, each
instance in its own process group with `-RCAssemblyAIEndpoint
http://127.0.0.1:9` and a disposable `-RCSecretFolder`, each killed by its
own pid, each parity grep empty; the no-port scripts with NO instance alive;
every child started from an environment the runner popped
`RC_ASSEMBLYAI_KEY` out of at its second statement. **41 scripts, 40 at their
score.** Each is quoted as it printed, against the N it had at the time:

- **MCP:** phase1 66/66, phase2 **86/86** (the request's table said 85; road
  map 7's D3 pipeline added the row — "its measurement of the defect became a
  check of the fix" — and 86 is the newest recorded total), phase3 123/123,
  phase3_silence_scope 8/8, phase4 84/84, phase5 88/88, phase6 168/168,
  phase7 92/92, phase8 79/79, phase9 216/216, patch_door 261/261, refusal
  116/116, remaining 79/79, clip_catalog 24/24, op_catalog 23/23,
  op_argument 133/133, silence2 91/91, e1 99/99 (with the reference build on
  4986), e2 61/61.
- **No port:** op_schema_probe 28/28, phase9_probe 48/48, refusal_probe
  15/15, remaining_probe 170/170, preview_validity_probe 19/19 (5 skipped by
  name), preview_refresh_probe 0/0 (58 skipped by name), transition_sheet
  39/39, recording_probe **858/858** (43 skipped by name: 2 the reference
  tree, 41 "no shareable display — the console is locked or every display is
  asleep"; 899 is the unlocked total and 858 + 43 is the locked one, which
  this host is), marquee 28/28, source_mirror 40/40, silence2_probe 76/76,
  phase2–phase9 chrome 26/26 · 33/33 · 59/59 · 36/36 (45 skipped, the
  reference tree) · 70/70 · 78/78 · **144/144** (6 skipped by name, the
  probe could not become key — the documented alternative to 150) · 62/62,
  e1_chrome 21/21, e2_chrome 35/35.
- **The one FAIL: `recording_proof.py`, and it is HOST STATE, named.** The
  row "the microphone file is not SHORTER than the movie by more than two
  frames" failed twice, with different numbers each time — microphone
  1227200 vs movie 1276325 ticks (−81.9 ms, `mic_offset` −106.6 ms) and
  1176000 vs 1304000 (−213.3 ms, `mic_offset` −171.9 ms). `system_profiler
  SPAudioDataType` names *Kevin's AirPods Max* as this Mac's default INPUT
  device as well as its default output: a Bluetooth capture session's first
  sample lands AFTER the screen stream's, so `mic_offset` is NEGATIVE where
  R0 measured +66 and +70 ms with the microphone LEADING. The script already
  skips its TONE rows by name for a Bluetooth OUTPUT and has no such arm for
  a Bluetooth INPUT, so the row fails rather than skipping. **It is not a
  regression**: C1 touched no recording file at all (`git diff 7f04e59 --
  app/Sources` names none), and nothing else in the 41 moved. It is in
  `designs/reelcut-remaining.md` §4 for a person with a wired input, and the
  re-run was carried on past it by name rather than stopped for good.
- **The leak sweep**, in process, over every file under `work/c1-close/`
  (including `results.json`) and every instance log this runner wrote:
  **False**, printed as the boolean and nothing else.

#### Limits and deviations, said rather than papered over

- **The live module is TWO files, not one.** `cloud_captions_live.py` came
  out at 692 lines written whole, and the standing rule caps a NEW file at
  400. The money half — the ledger gate, the line parsing, the deletions and
  the CONTROLs — went to `cloud_live_ledger.py` (288 lines) and is imported
  by `cloud_captions_live.py` (389 lines), so every name the spec pins is
  still reachable on that module. Two files under the cap rather than one
  over it.
- **`print` is BLOCK-buffered under a file redirect, and it is not fixed.**
  `AssemblyAIClient+Session.swift:98` prints one line per request; with
  stdout redirected to a file, Darwin buffers it 4096 bytes at a time and
  cuts the last line in half. MEASURED: `/tmp/reelcut-4960.log` holds exactly
  4096 bytes of client lines and 4970–4972 hold NONE, and §10.10's row K read
  such a log. The live rows COUNT those lines, so a live instance gets a
  `pty` and a draining reader instead; instances A, B and C are unchanged,
  because their rows do not count lines. Any future row that wants a count
  has to use the pty — an instance log is a LOWER BOUND. Also
  `designs/reelcut-remaining.md` §5.
- **`find_own` has no caller, by measurement** — a deviation from this
  pipeline's request, which expected one. `cloud_spike/aai.py`'s `find_own`
  matches a transcript by the UPLOAD URL, and the app never exposes its
  upload URL (`AssemblyAIClient+Session.swift`'s `note` prints a method, a
  path and a status, deliberately no URL), so the live rows hold one only
  after a GET by an id they already know. **One page of the account's
  transcript list is therefore never fetched, by anything, ever.** A submit
  whose id never surfaces closes `unresolved` in the ledger — named for a
  person — rather than being chased. No run has printed such a row.
  **Superseded for the app by #28 (§10.14):** a run whose own submit reply
  is ambiguous now makes at most three newest-page looks for its exact
  uploaded URL. The live ledger described here is unchanged.
- **The app's `submit` does not retry today** (`AssemblyAIClient.swift:183–
  193`, one `send`); only `upload` does, once, and an upload bills nothing.
  Row 20's submit-count rows therefore guard a REGRESSION and a second
  media, not a present behaviour. They are still what makes the ledger count
  what the app did rather than what the row expected.
- **The root `CLAUDE.md`'s road-map-6 row is still wrong, and this pipeline
  did not change it.** It has said "DESIGNED and not built" since c1-run
  (§10.11 named it). The implementer's own operating rules forbid an
  agent-authored instruction to edit a `CLAUDE.md`, so the one-line
  replacement is written out verbatim in this pipeline's
  `04-impl-notes.md` for a person to apply, and the row is named here so it
  is not rediscovered a third time. `app/CLAUDE.md` was read against the tree
  and holds no false map entry. **APPLIED 2026-09-21**, after this
  pipeline's second review, by the session's orchestrator and by hand: that
  one table row, the replacement text verbatim, on the root file's own
  standing rule that a phase updates a map entry. No rule text changed.
- **Two live runs, not one.** The second was made to add the racing reader's
  own GET count, which §10.12 was asked to hold and the first run did not
  print. It cost one more transcription inside the six and $0.00064, and it
  is also the run that proves the rows against the FINAL files.
- **`recording_proof.py` launches its own second instance on its hardcoded
  4896**, outside this pipeline's 4980–4989 range. It was not edited; it is
  named here because a reader counting ports will find it.
- **`results.json` was rewritten mid-way.** The section-C runner's first
  session recorded 17 scripts; a later `--only` run without `--resume`
  replaced the file, and the 17 were re-run to fill it back in (which is why
  their second timings are shorter — the fixtures were already made). The
  console output of every session is what the numbers above are quoted from,
  and the final `results.json` holds all 41.

#### What is owed

- ~~**C1's reader review**~~ — RAN 2026-09-21, over the whole of C1, and its
  record is **§10.13**. Of the residue bullets it was handed, three are
  closed there (the two c1-parts nits and the order-dependent probe row), one
  is narrowed (the hand-written `speed`) and the `Makefile` finding is fixed;
  the rest stand with their reasons.
- **§5j's five questions**, carried WHOLE into `designs/reelcut-remaining.md`
  §4 — the q7 prompt, the Settings window looked at, a real twenty-minute
  recording over a home upstream, the EU region, and the report card when the
  FALLBACK ran. Nothing in this tree has ever seen Universal-2 answer for a
  language the newer model declines.
- ~~The root `CLAUDE.md` row~~ — applied 2026-09-21, above.
- **`recording_proof.py` with a wired or built-in input**, above.
- **C2** waits on §6b, and `KeychainStore` on a stable signing identity.

#### The fix pass (05-review, 2026-09-21)

All four `should-fix` findings and the one nit were fixed. **No live call was
made and nothing was spent**: the fix pass ran with `RC_ASSEMBLYAI_KEY`
removed from every process it started, and finding 4 — the only one on the
money path — was proved with stubs instead of the network.

| Finding | The fix | How it was proved |
|---|---|---|
| 1 (`remaining.md`) | the live-spend sentences say **two** transcriptions (one per live run), **22 billed seconds**, **$0.00128**, and that no `extra` reservation was ever written | read back against `work/cloudlive/ledger.json` and the spend section above, which are where those three numbers were printed |
| 2 (§5i) | a **Revised 2026-09-21 (c1-close)** paragraph on §5i saying how rows 20 and 21 are MEASURED — the pty-counted client lines, the ledger's reservation and its `extra` rows, and "no upload" as ZERO lines of any kind — pointing here for the numbers | the form the section's other revisions take; it adds and replaces nothing above it |
| 3 (`remaining.md` §5) | the c1-close residue block is blank-lined off and MOVED below the list it had been inserted into, so the order-dependent probe bullet belongs to that list again, and its heading says **Three things** over its three bullets | the counts are the section's own `- **` lines: three under the c1-close heading |
| 4 (`cloud_captions_live.py`) | `dummy_arm` takes the `Client`, closes its reservation on its MEASURED outcome and, when the arm does NOT hold, runs `cleanup` over its own captured lines before returning — so a submit that got through is deleted and proved gone even though `run` returns before the real instance exists. `Captured` (in `cloud_live_ledger.py`) stands in for the stopped instance's pty | `tools/proof/cloud_live_selftest.py`, a new stub-only self-test: **9/9** on the tree, **6/9** on a tree COPY with the fix's branch reverted (its text asserted to occur exactly once), the three failures being the missing DELETE, the missing q6 sentinel GET and a reservation closed `no_transcript` while holding a `transcript_id` |
| 5 (nit) | the dummy arm's refusal detail and the exception text `run_row` prints both pass the run's own `Scrubber` (`scrubbed` in `cloud_live_ledger.py`; `live_scrubber` in the proof module) | row C of the self-test: a refusal carrying a registered secret leaves `<scrubbed>` in the details and the secret in none of them |

The spec's Files list also asked for the root `CLAUDE.md`'s road-map-6 row;
no fix here touched it, and the orchestrator applied it by hand after the
second review (above).

Files: `cloud_captions_live.py` 389 → **399**, `cloud_live_ledger.py`
288 → **312**, `cloud_captions_proof.py` 1640 → **1643**, and the new
`cloud_live_selftest.py` **219** — every cap holds, the live module by one
line.

Re-run after the fixes, each score from the run that printed it:
`cloud_live_selftest.py` **9/9** (and **6/9** reverted, above),
`python3 -m py_compile` clean on the four scripts, and
`cloud_captions_proof.py` WITHOUT `--live` **115/115 in 52 s** against the
final binary on ports 4980–4982 — three "the startup parity check said
nothing" rows, no instance left running. The LIVE rows were NOT re-run: that
would spend money the ceiling is there to stop, and the fix's own branch has
a row that fails on purpose without the network. `make typecheck`, `make
app`, `make test`, `make lint` and `cargo fmt --check` were not re-run
either: the fix pass touched three proof scripts and two documents and no
product file at all.

The fix pass's own tree is **`d246836f063f2c1fe44f16e435ae54c7e2fe505f`**, by
the same temp-index recipe and measured before this sentence, which is the
only line it does not contain; it supersedes the pipeline hash below.

#### The tree

**`e29b2e4cd9c8f9370511cc782b422156dd37d2f2`** — every line this pipeline
wrote except this paragraph, by the request's temp-index recipe (never the
real index; nothing was committed, added, stashed or checked out). It is
measured before the paragraph rather than after it because a hash of a tree
cannot be written into that tree; re-run the recipe for the current one. The
baseline is pipeline 4's `d22d0f4de4b031eed7a6377c697726aac8c16213`, and
`git diff` of it over `core` is empty — as is every product file: this
pipeline changed proofs and documents only.

### 10.13 The reader review (2026-09-21)

C1's owed reader review, run as one `/litecode` pipeline on the tree as it
STANDS. **No live call was made and nothing was spent**: every process this
run started had `RC_ASSEMBLYAI_KEY` removed or replaced by an allow-listed
dummy, `cloud_captions_proof.py --live` was never passed, and no request left
loopback. Ports 4990–4999, every instance killed by its own pid.

**The named deviation.** The repo's practice is several readers in parallel
and several sceptics per finding. litecode runs one agent at a time, so this
was SEVEN SEQUENTIAL single-context readers, 1 → 7, each writing its lines
here before the next started, with ONE independent sceptic at the end. A
finding the sceptic did not reach is recorded UNJUDGED, never refuted.

#### The baseline (step 0)

`git diff --stat f03ebcc6e4769f7195812d51d562518a2e4d9b67` listed the 25
untracked files as deletions and nothing else, so the tree is c1-close's.
Every command ran under rule H's runner at a flat 1800 s. `built` says whether
the instrument's own `built … in … s` line appeared — the two Python
instruments' binaries were already current, so **neither baseline wall holds a
build**, and Interfaces' `900 + 3 × wall` is the limit every later cell that
BUILDS is held to.

| Command | Score | `wall=` | built |
|---|---|---|---|
| `make test` | 721 passed, 0 failed, 39 binaries | 1.4 s | no |
| `make lint` | clean | 0.2 s | no |
| `cd core && cargo fmt --check` | clean | 0.4 s | — |
| `make typecheck` | 0 errors, exactly 4 warnings (3 `CompositionBuilder`, 1 `Exporter`) | 38.7 s | — |
| `make app` | BUILD SUCCEEDED | 4.7 s | nothing new |
| `python3 -m py_compile` (six cloud scripts) | clean | 0.2 s | — |
| `cloud_live_selftest.py` | 9/9 | 0.2 s | — |
| `cloud_captions_probe.py` | 469/469 | 17.4 s | **no** |
| `cloud_captions_proof.py --port-base 4990` | 115/115, no skip | 51.1 s | **no** |
| `phase4_proof.py 4993` | 84/84 | 3.6 s | — |
| `op_catalog_proof.py 4994` | 23/23 | 0.2 s | — |
| `op_argument_proof.py 4995` | 133/133 | 1.6 s | — |
| `phase4_chrome.py` | 59/59 | 72.7 s | — |
| `source_mirror_probe.py` | 40/40 | 1.1 s | — |
| `grep "Reelcut: " /tmp/reelcut-499?.log` | prints nothing | — | — |

**The `wall=` column above is the step-0 capture's own, and
`04-checks.txt` does not hold it** — that file holds the CLOSING runs. Where
the two disagree for the same script (`op_catalog_proof.py` 0.2 s here
against 61.0 s there, `op_argument_proof.py` 1.6 s against 68.4 s,
`source_mirror_probe.py` 1.1 s against 60.1 s, `make app` 4.7 s against
46.7 s) nothing in the evidence explains the difference, so read this table's
SCORES as the baseline and not its walls (the reader review's fix pass, the
sceptic pass's "did not reach" list).

Every score is the recorded one, so **there is no finding R0·1**. The three
MCP baselines each ran against a fresh instance launched with BOTH
`-RCAssemblyAIEndpoint http://127.0.0.1:9` and `-RCSecretFolder` under
`tools/proof/work/c1-review/`, killed by pid after its one script. The
existing probe and harness launches ran AS THEY STAND and nothing in
`run_probe`, `pinDefaults` or the 469 baseline was edited to satisfy the
launch-argument rule (Objections 3).

#### Reader 1 — the run and the client

**The question, as refined and put:** for each exit the run has — the janitor,
the upload's retries, the submit, the poll's four refusals, a body the client
cannot read, a 401 anywhere, and a cancel at each phase — does a RUN against
the fake show (a) at most one `POST /v2/transcript` per media per run, (b)
every id the fake minted either DELETEd or in a cache file with
`remote_deleted:false`, (c) no `reelcut-upload-*` left, (d) a marker only
beside a readable file, and (e) a wall inside what `Tuning` promises?

(a), (c) and (e) hold and the existing rows already say so (section 15's
retries, tolerated poll failures, ceiling, 401 and three `words` shapes; row T's
three failing paths with its CONTROL). **(b) and (d) do not**, and (d) was the
worse of the two. Three findings, all reproduced by running, all three FIXED
with a row that was then made to fail against the fix reverted in a tree copy.

- **R1·1** `app/Sources/AgentServer+CloudCaptions.swift:220` — two media for
  which AssemblyAI answered `audio_duration: 9223372036854775807` →
  `report.uploaded.reduce(0) { $0 + $1.audioSeconds }` overflows and Swift's
  `+` TRAPS → the whole app is killed after both media have been uploaded and
  billed, and the MCP socket closes with no answer at all. The three trials
  that pin it to the arithmetic: one media at `Int.max` answers
  `9223372036854775807`; two at half of it answer `9223372036854775806`; two
  at `Int.max` kill the process. **FIXED** — the sum saturates through
  `addingReportingOverflow`. Row **O** in `cloud_captions_proof.py` (12
  checks, the first two trials its controls); mutant **`audio-seconds-plus`**
  reverts it and scores **123/124**, the one failure being "two media at
  Int.max — the instance is still alive after the call".
- **R1·2** `app/Sources/CloudTranscriber.swift:182` and
  `+Media.swift:49` — `retryDeletes()` read no cancel token and `transcribe`
  checked the token for the FIRST time after the janitor returned, so a Stop
  the person had already pressed still paid the whole janitor bill. MEASURED
  with the new `stall` fake key: three owed ids and a DELETE route that
  answers nothing cost a pre-cancelled run **15.15 s** and three DELETEs, and
  cleared none of them. **FIXED** — the check moved above the janitor and
  `retryDeletes(cancel:)` gained a DEFAULTED token it reads between items, so
  `retryDeletes()` still means what it meant. Row **J** in
  `cloud_captions_probe.py` (6 checks, three of them CONTROLs: the cache
  really did owe three, an un-cancelled run still sends all three, and that
  still costs it the 15 s); mutant **`janitor-deaf`** reverts the check and
  scores **41/43**. `cloud_captions_proof.py`'s `no-janitor` mutant was
  RE-AIMED at the new line (its patch text occurs once, checked).
- **R1·3** `app/Sources/CloudTranscriber+Media.swift`'s `fetch` —
  `MediaTranscript.write`'s `Bool` was discarded and the marker written
  regardless, so a write that failed left the NEW stamp over the OLD file and
  `isCurrent` matched them: the next run served an earlier request's words as
  the answer to a request it was never made from. MEASURED over MCP: run 1
  caches `alpha`; run 2 asks with `speakers: true`, uploads, cannot write
  (the file's `UF_IMMUTABLE` flag stops the atomic rename while the folder
  stays writable), and rewrites the marker to `speaker_labels: true`; run 3
  answers `cached: [2]` and serves `alpha`. **FIXED** — the marker is written
  only when the file landed. Row **M** in `cloud_captions_proof.py` (5 checks,
  one a CONTROL that the write really was stopped); mutant
  **`marker-over-stale-file`** scores **130/132**, the two failures being the
  marker row and the "uploads rather than serving the stale file" row.
- **R1·4** (lead L2) `app/Sources/AssemblyAIClient.swift:184` — a `POST
  /v2/transcript` whose REPLY is lost after the transcript was made orphans
  it for ever: no id, no DELETE, no cache file, and no later run finds it.
  Reproduced with the new `drop_reply` key — the fake still held
  `t_b913de347e7e` after a second run that uploaded again. The only recovery
  is to LIST the account's transcripts and match by `audio_url`, which is a
  new interaction and a decision. **FILED #28.** (`remaining.md` §5's bullet
  is about the LEDGER's side of this; the APP's side was recorded nowhere.)
- **R1·5** (lead L3) with `cache/transcripts/` unwritable, the result's `note`
  says "the next run retries it" and no run can: nothing holds the id.
  Reproduced over MCP; run 2 minted a second transcript and cleared neither.
  Saying the true thing needs a new field on `Report.Uploaded`, which
  Interfaces pinned. **FILED #29.**
- **H·1**, `AssemblyAIClient+Session.swift:165` reading `progress` outside the
  lock: **REFUTED as a race**, by this reader's own reading of every writer.
  `Sink.progress` is written once, in `open(_:progress:)`, BEFORE
  `sinks[identifier] = sink` is published under the lock, and never again;
  `close` removes the sink and nils nothing. A reader reaches the field only
  through `sink(_:)`, which takes the SAME lock, so the write happens-before
  the read through that lock's release/acquire pair — and, independently,
  `didSendBodyData` cannot fire until `task.resume()`, which is after `open`
  returned. There is no second writer and no window, so there is no row that
  could fail and the field is left a `var`. Interfaces' `let`-plus-`init`
  form was therefore NOT taken.

Leads L1's second half — "a dripping server may never time out", since
`timeoutIntervalForRequest` is an IDLE timer — is **UNREPRODUCED**: the new
`stall` key answers nothing at all, which is exactly what the idle timer is
for, and a fake that drips a byte under the timer would be a second timing
instrument this review did not build. What WAS measured is the bounded half,
R1·2. L4 became R1·1 and L3 became R1·5.

#### Reader 2 — the credential

**The question, as refined and put:** name every sink a credential string can
reach — the app's stdout and stderr, every MCP result, refusal, `problems`
entry and `note`, the cache file, the marker, the fake's upload files, every
Settings view's readable text, the window title, the field editor and the undo
manager — and every HOST a request carrying it can go to; then SHOW a run with
`proof-key` whose bytes were searched. The person's own secret folder, login
keychain and `~/Library/Logs/DiagnosticReports` were never opened, listed or
searched, and no live call was made.

The existing rows already answer the sinks the reader could enumerate by
reading: section 17's store rows (0600, the rename, the siblings, the resolver
order), section 18's `exposedText` sweep over every `stringValue`,
`placeholderString`, `toolTip`, AX value, label, title and help, row G's
redaction, and rows K and X over every app log and MCP answer. **One sink was
not enumerated, and it is somebody else's text.**

- **R2·1** `app/Sources/AssemblyAIClient+Session.swift:49-54` and
  `AssemblyAIClient.swift`'s `poll` — three sentences are relayed from the
  server VERBATIM (a 402's, a 4xx's and a transcript's `error`), and a server
  that echoes the `authorization` header it received puts the key straight
  into an MCP refusal. MEASURED with the new `echo_authorization` fake key:
  `transcribe: The transcription failed: clip 3: forced 400 on submit for
  proof-key` came back over MCP, with the app's own log clean. That makes
  `AgentServer+CloudCaptions.swift`'s header sentence — "**No credential is
  ever in an answer.** Not in a `ToolError`, not in a `Problem`, not in the
  `note`" — false on that branch. **FIXED** — a new
  `AssemblyAIClient.withoutCredential(_:)`, in the one file that can see the
  `private` `credential`, replaces it with `<redacted>` in all three relayed
  sentences. Row **E** in `cloud_captions_proof.py` (6 checks over the three
  branches, three of them CONTROLs that the sentence really was relayed);
  mutant **`key-relayed-verbatim`** scores **131/138** — the six E rows and,
  **row K as well**, which before this review could not fail on that path
  because nothing drove it.
- **H·2**, the `Makefile`: **FIXED.** One directive, `unexport
  RC_ASSEMBLYAI_KEY`, above `.PHONY`, which covers every recipe in the file.
  GNU Make 3.81 is this host's and takes it (smoke-tested both ways on a
  throwaway makefile: `ABSENT` with the directive, `PRESENT` without).
  `tools/proof/makefile_env_proof.py` (**203** lines, new) builds a tree COPY
  with `core` a symlink, runs `make app` in it with the person's variable
  POPPED and `RCDUMMY-makefile-env-proof-5d1c` in its place, and searches
  every file under the copy's `build/` and `Reelcut.xcodeproj/` IN PROCESS.
  **2/2**: the build made the binary, and **no file of 448 holds the dummy**.
  `--mutant no-unexport` removes the directive in the copy and scores
  **1/2**, the dummy landing in
  `build/Build/Intermediates.noindex/XCBuildData/<hash>.xcbuilddata/task-store.msgpack`
  and one attachment beside it — which is `remaining.md` §5's measurement,
  reproduced and then closed. **It measures the `app` recipe ONLY and says so
  in its own header and in its first printed line**: `app` is the one recipe
  that runs `xcodebuild`.
- **H·3**, `writeAll`'s `EINTR`: **FIXED**, with the seam Interfaces named.
  `writeAll(_:_:using:)` is internal, its default IS `write(2)`, and it now
  retries on `EINTR` and on nothing else. Section 17 gains three rows driving
  an injected writer that answers `-1`/`EINTR` once and the real call after:
  the key lands, a CONTROL says the interruption really happened, and a
  second writer answering `-1`/`EACCES` still earns `Permission denied` on
  the first answer. Mutant **`eintr-unwritable`** removes the retry line and
  scores **39/40**, the one failure being the retry row — the CONTROL and the
  other-errno row still pass, which is what makes the mutant aimed.
- **L10**, the harness's `pinDefaults` and an unshielded `store()`:
  **REFUTED as a defect, by grep and reading, and then made checkable.**
  There is exactly ONE place that builds a controller without a `store:`
  argument — `chromeSettings`'s
  `SettingsWindowController(defaults: defaults, environment: [:])`, which then
  pushes Save and Remove through the default
  `{ AssemblyAIConfiguration.store() }`. It is reached only through
  `chrome_child`, which passes BOTH `-RCAssemblyAIEndpoint` and a disposable
  `-RCSecretFolder`, so `store()` answers a `FileStore` on a folder under
  `work/`. The harness's own `settings` mode passes
  `store: { MemoryStore() }` explicitly, which is what makes `pinDefaults`'
  argument-domain wipe harmless there. `modeHygiene`, the one mode launched
  with NEITHER argument, reaches no store at all. **What shields the Save and
  Remove buttons is the LAUNCHER and not the mode's code**, so three rows
  were added to section 18's hygiene block: that the mode really does build
  it with no `store:` (the CONTROL), that the one chrome launch passes both
  arguments, and that `chrome_child` is the only way a chrome row is reached.
  No scores in this review were taken before that reading.
- **L11**, the store's modes and a hostile credential: **REFUTED as a leak,
  and one nuance recorded.** A credential holding a CR/LF is not smuggled
  into a second header: `URLRequest.setValue` DROPS such a header entirely,
  measured against the fake — four requests went out with no `authorization`
  name in the log at all and no `X-Reelcut-Smuggled` — so the failure mode is
  a request with no credential, which any real server answers 401 and the
  client reports as "AssemblyAI refused the API key". A non-ASCII credential
  IS sent and is refused the same way. The nuance: `FileStore.makeDirectory`
  `mkdir`s at `0700` only when it is the FIRST thing to make
  `~/Library/Application Support/Reelcut/`, and `ExportPresetsStore.write`
  and `FFmpegRewrap.convert` both create that folder with
  `withIntermediateDirectories: true` and no attributes — so a person who
  saved an export preset before their first key has that folder at the
  umask's mode. The key FILE is still `0600`, so this changes who can LIST
  the folder and not who can read the key; K4 already records the real
  exposure. Both sentences in `SecretStore.swift` and `app/CLAUDE.md` are
  true as written (they say the existing directory's mode is left alone on
  purpose); this is a limit, not a false claim.

#### Reader 3 — the cache and the stamp

**The question, as refined and put:** for a relink and back, a file edited to
the same size, each of the four request fields, the region, `refresh`, a held
media, two media over one file, an untitled document, and a cache file that is
truncated, empty, huge, doubly-keyed or hostile — what is uploaded, what is
billed twice, what DELETE path leaves the machine, and are the served `words`
bytes in the file verbatim?

Rows 4, 5 and 11 and section 13 already answer the first list, and section V
answers the verbatim claim over `TRICKY_WORDS` (an escaped `"]`, a non-ASCII
run, a `1e-3`). **What no row asked is where the id in the cache file COMES
FROM.**

- **R3·1** `app/Sources/AssemblyAIClient.swift` — a cache file's
  `transcript_id` is interpolated into `DELETE /v2/transcript/<id>` with no
  validation, and that file rides inside a `.reelcut` package, so it is
  somebody else's string. MEASURED against the fake: ids of `../upload`,
  `a/b`, `?x=1`, a thousand `x`s and `../../../../etc/passwd` produced

  ```
    DELETE '/v2/transcript/../upload'
    DELETE '/v2/transcript/a/b'
    DELETE '/v2/transcript/%3Fx=1'
    DELETE '/v2/transcript/xxxxxxxx…'
    DELETE '/v2/transcript/../../../../etc/passwd'
  ```

  — `URL.appendingPathComponent` does not resolve `..` and `URLSession` sends
  the path as written, so a package's author chooses the path a DELETE
  carrying the person's key lands on at the API host. (`?` IS percent-encoded,
  so no query is smuggled.) All five then failed, which put their media in
  `janitorFailed`, which R6-11 turns into a HOLD **for ever**. **FIXED** —
  `AssemblyAIClient.isPlainIdentifier(_:)` is the one gate both calls that
  interpolate an id go through: `delete` sends NOTHING (there is nothing to
  delete and nothing is owed, so no media is held over a string), and `poll`
  throws `.malformed`. Row **I** in `cloud_captions_probe.py` (3 checks, one a
  CONTROL that a well-formed id beside them still went out); mutant
  **`any-id-on-the-wire`** scores **44/46**, the two hostile-id rows failing
  and the CONTROL passing (that score is from the 3-check row and the 488-row
  probe; the fix pass below added two checks to row I and re-aimed the
  mutant's patch text at the gate's new line). **What the gate ANSWERS
  changed in the fix pass**: it answered `true`, which made the janitor report
  and RECORD a delete that was never sent — see below.
- **R3·2** `app/Sources/ProjectDocument.swift:719-723` — the comment "Caches
  written to the temporary directory before a Save As are orphaned there,
  **which costs nothing** — they regenerate on demand" became false when
  `cache/transcripts/` joined `thumbs/` and `peaks/` there: a transcript with
  `remote_deleted:false` orphaned in `/tmp` is an id AssemblyAI is still
  holding that no janitor will ever find. **FIXED as a false COMMENT,
  corrected NET-ZERO** (five lines in, five out) — that file takes nothing on.
- **L8's second half**, whether
  `AgentServer+CloudCaptions.swift:134`'s "This document has nowhere to keep
  its transcript cache, so it cannot be transcribed with AssemblyAI. Save it
  first." is reachable: **REFUTED — it is not, by any input.**
  `intendedCacheDirectory` returns nil on no path: with no `fileURL` it mints
  `/tmp/Reelcut/<uuid>/`. MEASURED — `new_project` with no path, then
  `transcribe engine: "assemblyai"`, answered a full result with cues and the
  four expected routes. The refusal is defensive dead code, and the sheet's
  twin at `TranscribeSheetController+Cloud.swift:238` is the same. It was left
  standing: `cacheDirectory` is `URL?` by signature and a handler that ignored
  the optional would be the worse shape. Reader 5 holds whether any PROSE
  promises it.
- **L5**, the stamp's width: **verified by reading and FILED #30 (`spec`).**
  `TranscriptStamp.source` is the whole `CacheStamp`, `thumbnailHeight`,
  `maxThumbnails` and `peakBucketsPerSecond` included, so a build that changes
  the filmstrip's height re-bills every transcript everywhere. Section 13
  already asserts exactly that, one row per field, as DESIRED behaviour —
  which is what makes it a decision and not a patch, and any narrowing
  re-bills once for everybody.
- **L6**, a foreign account's id: the measurement above is the same shape —
  five ids the service never minted, five failures, five permanent holds — and
  R3·1's gate removes the case where the id is not even well formed. An id
  that IS well formed and belongs to another account still answers 404 → K10 →
  held, which is K9/K10 as recorded and is **LEFT LISTED**: what the real
  service answers for another account's id stays UNMEASURED and no proof here
  can learn it.

#### Reader 4 — the mapping and the cue builder

**The question, as refined and put:** against a Python oracle in integers,
rounding half AWAY from zero, for speeds {0.1, 0.5, 1, 3.7, 10} and words on
`in`, on `in + content_length`, on a split's tick and straddling it, does every
word land in exactly one half tick for tick; do the five refusals fire in
`Transcriber.jobs`'s own sentences; does the fifth rule fire on a speaker
change and on nothing else; and **does `Transcriber.project` still equal the
pre-C1 arithmetic** wherever `scaled = t / speed × 600 000` is below 2^63?

Section 12's oracle, section `jobs`'s refusals and the `cues` section's fifth
rule already answer the first three and passed unchanged, so this reader did
not re-report them. The fourth had no row at all, and now has one.

- **The pre-C1 equality: HOLDS.** A new `pre_c1_project` in
  `cloud_captions_probe.py` is
  `git show cfcd0959:app/Sources/Transcriber.swift:675-679` in Python —
  `ReelTime.ticks(seconds:)`'s half-away rounding and its 0-out-of-range guard
  (`ReelCore.swift:416-420`), then `min(start + max(0, offset),
  start + duration)` — which rounds BEFORE the clamp where today's `placed`
  clamps in `Double` first. Over **5 speeds × 9 seconds**, including
  `1e-9`, the two ticks either side of the clip's own end
  (`1.0000008333`, `1.9999991667`), the end exactly, and `1e6`, today's
  `Transcriber.project` answers the pre-C1 tick every time. The reordering
  moved nothing: the clamp is to an integer `duration`, so rounding before or
  after it lands in the same place.
- **The CONTROL beside it**, and it is called one: at `t = 1e14`, speed 1,
  where `scaled` is past 2^63, the two differ BY DECISION — the old line's
  `ReelTime.ticks` answered 0 out of range and so placed the word at the
  clip's START, and today's `placed` clamps in `Double` and places it at the
  clip's END. That is spec §11's R6-10 and this review's K28, recorded as a
  control and not re-litigated.
- **H·4 — the rest of the app against a hand-written `speed`: MEASURED, and
  CLEAN.** A scratch package whose one clip's `speed` was rewritten in the
  saved `project.json` to **1e300** and then to **1e-300**, driven on its own
  instance through `open_project`, `get_project`, `render_frame` (at `t: 0`,
  which wrote its PNG) and `transcribe engine: "assemblyai"`, and then through
  the offscreen harness, which rendered the whole editor including the
  timeline to a PNG for both. **No trap, no expiry, nothing to file.** The two
  answers are R6-10's clamps working: at 1e300 the cue collapses to
  `start: 0, end: 0` (the clip's start), and at 1e-300 the window
  `in + duration × speed` holds no word at all and the run answers "No speech
  was recognised". `remaining.md` §5's bullet narrows to exactly those five
  callers at those two values.
- **R4·1**, found while extending H·4's input past what H·4 named:
  `"duration": 9223372036854775807` on a clip **kills the app during
  `open_project`** — the socket closes with no answer and the process is
  gone. 2^62 and 1e18 open, draw and transcribe normally. `Project::validate`
  (`core/src/model_query.rs:320`) refuses a duration `<= 0` and puts **no
  upper bound on one at all**, so every downstream `start + duration` in
  Swift has to defend itself separately. C1 touched none of that code and
  R6-10 already recorded that the core DECLINED such a bound once, so this is
  a decision: **FILED #31 (`spec`).**

#### Reader 5 — the MCP mirror

**The question, as refined and put:** do the pinned refusals name the earlier
one when two are present at once; does every argument reader hold at its
extremes; does a stranger key die at the gate by name; is the result's key set
exactly Interfaces' and `truncated` absent; and — the part with no row —
**does every sentence of the catalog's `transcribe` entry and of §5g hold
against EVERY branch of the handler?**

Rows 1, 7, 8 and 9 already answer the first four and passed unchanged, and
the four mirrors are untouched: `git diff cfcd0959 -- core app/Sources/ReelOps.swift
app/Sources/ReelCore.swift app/Bridging` is empty, with `op_catalog_proof.py`
**23/23** and `op_argument_proof.py` **133/133** at the baseline. The gate was
seen refusing a stranger by name in passing, on a call this reader mistyped:
`render_frame does not take at. It takes burn_in_timecode, format, max_width,
path, t and project.` **The prose is where the findings were.**

- **R5·1** `app/Sources/AgentCatalog+Captions.swift:76-82` — the comment that
  names the UI path the tool mirrors, which the root `CLAUDE.md` requires,
  said "The sheet's ENGINE popup and its three cloud rows are c1-chrome's
  work and **are not there yet**: until they land, `engine: "assemblyai"` is
  reachable from here and **from nowhere in the UI**". c1-chrome landed:
  `TranscribeSheetController.swift:101` is the popup and
  `+Cloud.swift` is the three rows. **FIXED** — the comment now names the
  popup and the rows, and names the two things the sheet has that the tool
  deliberately has not (the region, R6-12; the remembered engine, R6-2).
- **R5·2** `app/Sources/AgentServer+CloudCaptions.swift`'s catch — a run that
  throws after a bill said nothing about the bill. `cloudFields` is never
  reached on a throwing path, so `uploaded` and `audio_seconds` are not in
  the answer at all. MEASURED: a project whose one media the fake answered
  `words: []` for — an array, so a real answer about audio nobody spoke in —
  uploaded, was billed, and came back as the bare sentence `transcribe: No
  speech was recognised in the audio that was transcribed.` with one upload
  in the fake's log. **FIXED** — the facts go in the SENTENCE, which is the
  one channel a throw has, and the result KEYS are unchanged: `AssemblyAI had
  already been billed for 1 media file (6 audio seconds) before this
  failed.` — the number is the one printed instance in the evidence, the fix
  pass's `bill-promises-cache` capture of row B over `speech.mov`; this
  record said 11 until the second sceptic pass found no run had printed it.
  The sum saturates, R1·1's rule. Row **B** in `cloud_captions_proof.py` (8
  checks after the fix pass, three of them CONTROLs, `tools/proof/README.md`'s
  own count; it was 4 and two when first written — that there really was an
  upload, and that a refusal costing nothing carries no such sentence);
  mutant **`silent-about-the-bill`**. **The sentence ENDED there
  only after the fix pass**: as first written it went on "…; their
  transcripts are cached in the project, so another run makes no request for
  them", which is false on the branch R1·3's own fix created (issue #29) —
  see the fix pass below, where row B gained the case that shows it and the
  mutant `bill-promises-cache` that reverts it.
- **L12 — §5g's refusal ORDER: the sentence is imprecise, and it is
  CORRECTED** as a dated revision on §5g rather than rewritten. "then a media
  over ten hours, then the network" names a per-MEDIA problem as a position
  in the run's order. MEASURED: a two-media project whose first media's
  `duration` was rewritten to forty thousand seconds answered `uploaded: [3]`,
  `audio_seconds: 11`, one `skipped` entry carrying the limit's own sentence,
  and the other media's four routes in the log. It refuses the RUN only when
  it is the only media, which is row H's case.
- **L15's half that is §5g's**, the `engine` bullet's "(default, whatever the
  sheet last chose)": it reads, over the tool, as the opposite of R6-2.
  **CORRECTED in the same dated revision.** The tool's own `engine`
  description was already right ("The default is NEVER what the sheet last
  chose") and row 8 already proves it, so nothing in the product changed.
- **L7**, the sheet's dead Generate button with no key and every media
  cached, is Reader 6's and is judged there.
- **What this reader did NOT drive**: the PAIRWISE refusal question — every
  pair of the seven pinned refusals presented at once, with the fake's log in
  the state §5g promises. Row 1 drives three of them one at a time and row 7
  drives the readers' extremes; the 21 pairs have no row and this review did
  not build one. **UNJUDGED**, and named here so the next reader does not
  read the single-refusal rows as an answer to it.

#### Reader 6 — the chrome

**The question, as refined and put:** is there a sequence of clicks and keys
after which Generate starts a run whose uploads, region or price differ from
what the card showed at that instant; does Save / Remove / Verify hold against
an answer arriving after the field, the store or the region changed; does Stop
during EACH phase end inside a stated bound; and is every sentence the report
card can show true of the branch that makes it?

Section 18's rows already answer the card's arithmetic, the sheet's four
states, the report card's lines, the Settings window's rows and both
appearances through the harness, and they passed unchanged. This reader's work
was the handed row and the two leads.

- **H·5 — the order-dependent Stop row: FIXED.** The row read "it stopped
  before anything was uploaded — the fake's request log **is still empty**",
  which is a claim about the whole SECTION's shared fake rather than about
  the click, and was true only because of where the block happens to sit. It
  now takes the fake's request count BEFORE the child runs and asserts that
  **nothing new** arrived across the click. Made to fail as the plan asked:
  in a COPY of the probe (`tools/proof/work/c1-review/h5_probe.py`, outside
  the tree) with one `GET /v2/transcript?limit=1` sent into the shared fake
  just above the block — which is exactly what a later phase adding a
  clicking row above it would do — and BOTH assertions present, the run
  scores **76/77**: `FAIL 18 OLD: … the fake's request log is still empty`
  and `ok 18: … the fake saw NOTHING NEW across this click`.
- **L7 — no key, everything cached: the button is dead and the run would
  send nothing. FILED #32 (`spec`).** `refresh`'s
  `startButton?.isEnabled` gates on a credential above the cache, and
  `AgentServer+CloudCaptions.swift:119` refuses the tool the same way, though
  R6-3 makes a package's transcripts travel with it and
  `CloudTranscriber.transcribe` classifies every media as cached before it
  opens a socket. It is a decision rather than a patch because a keyless run
  also cannot run the JANITOR, and a package can arrive carrying an id
  somebody else owes AssemblyAI a DELETE for.
- **L14 — Verify's answer announced as current: FILED #33 (`bug`), and NOT
  DRIVEN.** `verifyClicked` reads the key and the region at click time and
  its completion says "Key accepted" unconditionally, so an answer about key
  A lands beside a field holding key B or a region it never spoke to; and the
  completion's unconditional `verifying = nil` / `verifyButton.isEnabled =
  true` lets the first of two verifies clobber the second. Found by reading,
  LATE, while the named-mutant matrix was already running against
  `app/Sources` as it then stood — and a product edit mid-matrix would have
  built later cells from a different tree than earlier ones, which is the one
  thing that table must not do. The issue names the row it needs and the
  `stall {route: "verify"}` key that makes it possible.
- **What this reader did NOT drive, and is UNJUDGED**: Stop during each of
  the six phases. Today only EXTRACT has a row (section 18's cancel row, now
  H·5's), and the plan asked for upload, submit, wait, save and the janitor
  besides. Reader 1's row J measures the janitor's half of it from the
  probe's side — a pre-cancelled token now costs nothing — but the SHEET's
  Stop during an upload, a submit, a wait or a save has no row here and this
  review built none.

#### The twelve handed findings, each with one verdict

| # | What was handed | Verdict |
|---|---|---|
| H·1 | `AssemblyAIClient+Session.swift` reads `progress` outside its lock | **REFUTED as a race** by Reader 1's own reading of every writer: written once before the sink is published under the lock, read only through the same lock, and `didSendBodyData` cannot fire before `resume()`. No row could fail, and it says so; the field stays a `var` and Interfaces' `let` form was not taken |
| H·2 | a person's ordinary `make app` writes the key to disk | **FIXED** — `unexport RC_ASSEMBLYAI_KEY` above `.PHONY`, covering every recipe; `makefile_env_proof.py` **2/2**, `--mutant no-unexport` **1/2** with the dummy in `task-store.msgpack` |
| H·3 | `SecretStore.swift`'s `writeAll` turns `EINTR` into `unwritable` | **FIXED** — retries `EINTR` and nothing else, through Interfaces' injected-writer seam; three rows in section 17, mutant `eintr-unwritable` **39/40** |
| H·4 | the rest of the app is UNMEASURED against a hand-written `speed` | **MEASURED, CLEAN** at 1e300 and 1e-300 over five callers; nothing to file. The neighbouring input is worse and is **FILED #31** |
| H·5 | one `chrome` probe row leans on the ORDER of its section's shared fake log | **FIXED** — a count before the click, compared after; demonstrated in a probe COPY outside the tree, **76/77**, old assertion failing and new one holding |
| H·6 | `cloud_captions_live.py:118-119` asserts `no_transcript` on a branch that closes `deleted` | **FIXED** — each branch now names the outcomes IT can produce (`no_transcript`, or `deleted` or `unresolved`) and says which branch ran. It had been invisible because `StubProof.check` RECORDS without scoring, so the self-test gained the row that would have caught it: arm A asserts that exactly TWO of the arm's own checks failed and names them. **14/14** on the tree, **13/14** against the assertion reverted in a COPY of the live module |
| H·7 | `:387-388`'s skip reason is false on the branch that ran `cleanup` | **FIXED** — the reason now names the branch: "a submit reached the wire under the dummy folder, so `cleanup` ran and the key WAS used — to delete what that submit made, and for nothing else" |
| H·8 | the live self-test's stub always answers the q6 sentinel | **FIXED** — `StubClient(gone=False)` answers a transcript that is still THERE, and arm **D** asserts the reservation closes `unresolved`, that the DELETE and the sentinel GET were both made (so it is not unresolved for want of trying), and that `ledger.unresolved()` names it, with arm A as its control. **14/14** on the tree, **10/12** — the two D rows failing — against `cloud_live_ledger.py`'s `else "unresolved"` turned into `else "deleted"` in a COPY |
| H·9 | `remaining.md` §5's "Five things" heading stands over nine bullets | **FIXED** — the heading says **NINE**, which is that block's own `- ` lines counted, and says when and why it grew |
| H·10 | the app's client log lines are block-buffered | decided by Z5 — see the mutant table |
| H·11 | the root `CLAUDE.md` row and `app/CLAUDE.md`'s queue-seam clause, hand-edited | **JUDGED, and NOT edited** (this run edits no `CLAUDE.md`). Both are correct as map and rule text: `CLAUDE.md:34` names what the document is and where to start and carries no status paragraph, and its "§10 its record per pipeline" still covers §10.13; `app/CLAUDE.md`'s queue clause names exactly the two queues C1 added and there is no third — `grep "DispatchQueue(\|OperationQueue("` over C1's ten files answers `CloudTranscriber.swift:101` and `AssemblyAIClient.swift:139` and nothing else. **One sentence elsewhere in `app/CLAUDE.md` is now false** and its exact replacement is written out for the orchestrator in the run's notes, unedited here |
| H·12 | `cloud_captions_proof.py:1561` overrides `--port-base` under `--mutant` | **FIXED** before any mutant ran — `--port-base` defaults to `None` and resolves to 4955, or 4960 under `--mutant`, with an explicit flag winning either way. Verified by the first mutant cell, whose three instances bound 4990, 4991 and 4992 |

#### Reader 7 — the proofs and the record

**The question, as refined and put:** which claims would pass against a named
mutant of TODAY's tree; which conjuncts are vacuous; is the fake faithful to
what §3 MEASURED; and does every sentence of §10.1–§10.12 and the §5
revisions that carries a number, a count or "every" hold to the run that
printed it?

**Vacuous conjuncts: one found, and it was this review's own.** Three sweeps
over both cloud instruments and the self-test — a literal-truth assertion, a
comparison of a thing with itself, and an empty-collection claim — found
nothing in the tree. The four "the fake's log is EMPTY" rows in
`cloud_captions_proof.py` (:493, :511, :1117, :1292) each call `scenario(…)`
first, and `Fake.reset` clears `requests`, so each is a claim about its own
row. **The one that was NOT reset is the `chrome` section's**, which is H·5
and is fixed. The self-test had a worse shape and it was this review's to
find: `StubProof.check` RECORDS a row without scoring it, so every check made
INSIDE `dummy_arm` was invisible to the file's own count — which is how H·6's
assertion stood on a branch it was false on. Two rows now score them. One
vacuous row was written BY this reader in the course of the H·8 work — a
`check(…, True, "")` control — and was removed before it landed.

**The fake against §3's measured answers, row by row.** q1, `audio_duration`
is the audio's seconds rounded UP: `int(math.ceil(seconds))`, taken from the
uploaded body's own WAV `data` chunk or FLAC STREAMINFO. ✓ q5, an unsupported
`language_code` is a **400 at SUBMISSION** with the service's sentence
verbatim: `_submit` answers it before minting anything. ✓ q6, a deleted
transcript answers **200** with `audio_url: "http://deleted_by_user"` and
`text: "Deleted by user."`, and a second DELETE answers 200 too:
`deleted_bytes`, and `fake.deleted` is a set. ✓ And the one value §3 did NOT
measure — `words` after a delete, recorded cut at 300 bytes inside the KEY —
the fake invents as `null`, **and says so in its own header**, with the
reason (it is the value that exercises the client's "a completed body with no
words ARRAY is `.malformed`" rule). That is the honest shape and this reader
found nothing else invented.

**L15, "Every new file is under the 400-line cap": FALSE of its own table,
and CORRECTED** as dated revisions on §10.10 and §10.11. Both sentences stand
directly under tables listing `assemblyai_fake.py` at 501, the new
`cloud_captions_probe.py` at 3280 and 4753 and the new
`cloud_captions_proof.py` at 1479 and 1494. The cap `app/CLAUDE.md` sets is
about the app's own sources; `tools/proof/`'s instruments were never held to
it and the paragraphs should have said so. Nothing about the code changed.
**L15's other half**, §5g's `"apple"` "(default, whatever the sheet last
chose)", is Reader 5's and is corrected in the same dated revision there.

#### The mutant table — twelve named mutants of TODAY's tree

Each is a COPY: `--mutant` for the ten under `app/Sources`, `--fake-mutant`
for Z11, which is a mutant of the INSTRUMENT and cannot be one of `--mutant`'s
rows (both instruments copy `app/` only and load the fake from the working
tree). **No old binary was scored and `--live` was never passed.** Every patch
text was asserted to occur exactly once before it was applied. Each cell is
one CLAIM GROUP: a probe SECTION, or a proof ROW.

Every cell below is RUN except Z8's and the four the plan names, and **no cell
EXPIRED**: the longest was Z12's probe cell at 328 s against a 1173 s limit,
where `run_probe`'s own 180 s per-row timeout is what answered the ceiling
row rather than the outer wall.

**The probe, thirteen sections × ten mutants** (Z8 not run, Z11 through
`--fake-mutant`):

| section | Z1 | Z2 | Z3 | Z4 | Z5 | Z6 | Z7 | Z9 | Z10 | Z12 | Z11 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 12 the mapping | passes | passes | passes | passes | passes | passes | passes | **fails** | passes | passes | not run |
| R6-10 the hand-written speed | passes | passes | passes | passes | passes | passes | passes | passes | passes | passes | not run |
| 13 the stamp | passes | passes | passes | passes | passes | passes | passes | passes | passes | passes | not run |
| 15 the client | passes | **fails** | passes | passes | passes | passes | passes | passes | passes | **fails** | not run |
| 16 the cancel token | passes | **fails** | passes | passes | passes | passes | passes | passes | passes | passes | not run |
| 17 the secret store | passes | passes | passes | passes | passes | **fails** | **fails** | passes | passes | passes | not run |
| 19 the fifth rule | passes | passes | passes | passes | passes | passes | passes | passes | passes | passes | not run |
| W/F/FB/Q the extractor | passes | passes | passes | passes | passes | passes | passes | passes | passes | passes | not run |
| V the served words | passes | passes | passes | **fails** | passes | passes | passes | passes | passes | passes | not run |
| P/T/J/I the run | passes | passes | **fails** | passes | passes | passes | passes | passes | passes | passes | not run |
| 14 the estimate | passes | passes | passes | passes | passes | passes | passes | passes | **fails** | passes | not run |
| 18 the chrome | passes | passes | passes | passes | passes | passes | passes | passes | passes | passes | not run |
| R/G/N/S/K redirect, redaction | **fails** | passes | passes | passes | passes | passes | passes | passes | passes | passes | **fails** |

Scores: Z1 486/488, Z2 480/488, Z3 485/488, Z4 484/488, Z6 486/488, Z7
487/488, Z9 479/488, Z10 484/488, Z12 487/489, Z11 (hygiene only) 29/30 and
487/488 whole. **Z5 scored 488/488 — it was caught by NOTHING**, which is
R7·3 below; against the sharper row it is **489/490**.

**Every cell above is from the 488-row probe**, and the `P/T/J/I the run`
cell under Z5 says so: at 488 rows Z5 `passes` there — that is what
`probe-z5-key-in-note`'s **488/488** means — and it is the sharper row ADDED
to that same section afterwards that catches it, **489/490, `fails`**
(`probe-z5b`). The cell read `fails` until the reader review's fix pass,
where it contradicted both this paragraph and the run (finding 2 of the
sceptic pass).

**The MCP proof, its rows × the seven it scores** (Z6, Z7 and Z10 are `not
run` here — no tool reaches the resolver's argument table or the estimate):

| row | Z1 | Z2 | Z3 | Z4 | Z5 | Z9 | Z12 | Z11 |
|---|---|---|---|---|---|---|---|---|
| 1 · 2 · 3 · 5 · 6 · 7 · 8 · 9 · 10 · 11 · H · O · M · E · B | passes | passes | passes | passes | passes | passes | passes | passes |
| 4 the cache file's bytes | passes | passes | passes | **fails** | passes | passes | passes | passes |
| T the temporary extract | control | control | **fails** | control | control | control | control | control |
| K/X the key and the identity | passes | passes | passes | passes | **fails** | passes | passes | passes |

Scores, all 142 rows: Z1 141/142, Z2 141/142, Z3 137/142, Z4 140/142,
**Z5 140/142 (row K, and row T — R7·1's instrument failure)**, Z9 141/142,
Z12 141/142, Z11 141/142. **The one failure in each of Z1, Z2, Z9, Z12 and
Z11 was the SAME row and it was the instrument's, not the mutant's** — R7·1
below — so those five cells are `passes` and the mutant survived the MCP
proof. **Z5 failed TWO rows, not one**: row K, which is the catch, and that
same instrument row, which is why its score is 140. This line read
`Z5 141/142 (row K)` until the reader review's fix pass, where the count
hid the second failure the run printed (finding 1 of the sceptic pass;
`04-checks.txt`'s `proof-z5-key-in-note` is the line).

**When each cell was measured, exactly.** The ten probe cells and the eight
MCP cells above were scored against the instruments AS THEY STOOD when the
matrix ran — a **488**-row probe and a **142**-row proof whose row T still
carried R7·1's doubled glob. Two things changed afterwards, both because of
what the matrix showed, and both re-scored rather than assumed: the probe
gained Z5's sharper row (488 → **490**, and Z5's cell was run again:
**489/490**), and the proof's row T was fixed (its control now passes, so the
one failure that appeared in Z1, Z2, Z9, Z12 and Z11 — and the second of
Z5's two — is gone; Z9 was run again after row 5's split moved, and **that
re-run printed no line into `04-checks.txt`, so no score for it is claimed**,
which is R7·2). The pre-fix scores are left above because they are what those
runs printed; the paragraph under each table says what they mean.

**Z8, `store-under-endpoint`: NOT RUN — it would open the person's store.**
Removing `if argument(endpointArgument, …) != nil { return MemoryStore() }`
makes a proof-launched app with an endpoint and no secret folder build a
`FileStore` on `AppSupport.directory`, which is R6-9 (b)'s whole point.
Its column is `not run — would open the person's store`, and the row that
would have failed is named by READING: the probe's section 17,
**`17 · R6-9 (b): with an endpoint and no secret folder the store is an EMPTY
MemoryStore — the person's file is never opened`**, which asks
`AssemblyAIConfiguration.store()` for its TYPE in a child launched with the
endpoint alone (`run_probe(… extra=["-RCAssemblyAIEndpoint", …])`) and would
read `FileStore` where it asserts `MemoryStore`.

#### Reader 7's findings

- **R7·1** `cloud_captions_proof.py`'s `temp_folders` / `temp_uploads` — on
  this host `tempfile.gettempdir()` and `DARWIN_USER_TEMP_DIR` are the SAME
  folder under two names, so every `reelcut-upload-*` was globbed TWICE,
  while row T's CONTROL compared that doubled list's length against a
  de-duplicated SET taken during the run. The row therefore failed whenever
  the folder held one leftover from any earlier run — which is why it failed
  in **every one of the eight** MCP mutant cells and passed on the tree, and
  why each of those cells' 141/142 read as a catch it was not. **FIXED** —
  the folders are de-duplicated by real path, `temp_uploads` answers a set,
  and the control compares `set(during) - set(before)`.
- **R7·2** the proof's row 5 split at **2.5 s**, where none of the fake's
  five words starts — raised as a finding, **then REFUTED by this reader's
  own re-run.** The split was moved to **3.0 s**, exactly where the fake's
  fourth word starts, and the reader's notes say the proof was run again
  against Z9 with row 5 on that boundary. **That re-run left no line in
  `04-checks.txt`, so neither a score NOR THE RUN ITSELF is evidenced** (the
  second sceptic pass: an event no evidence line shows is a reader's word) — this sentence said `142/142` until the reader
  review's fix pass took the number out (the sceptic pass's "did not reach"
  list). What stands is the READING, and it is what refutes the finding:
  the reason is defence in depth and not a blunt row.
  `CloudTranscriber.transcribe:293` filters every mapped word by
  `$0.start < job.start + job.duration` before it builds a cue, so a word the
  `<=` window doubled at the boundary is dropped a SECOND time by a SECOND
  guard and never reaches a result. **No MCP row can catch Z9**, and the
  probe's section 12 catches it only because it calls `MediaTranscript.words`
  directly, below that filter. The split is LEFT on the boundary — a row
  that exercises the tick is worth more than one that does not — and the
  comment beside it now says why it cannot fail rather than claiming it can.
- **R7·3** **Z5 survived the whole 488-row probe.** A mutant that puts the
  credential into every `AssemblyAI: …` line the client prints was caught by
  nothing there: the one row that reads a child's stdout drives the
  `secrets` mode, which makes no request and so prints no client line at all.
  **FIXED with a sharper row** — the `run` section's real round trip now
  asserts the dummy is in NO line the child printed, with a CONTROL that it
  printed at least four client lines to look in. 490/490 on the tree,
  **489/490** against Z5, the new row the one failure.
- **H·10, the block-buffered client lines: DECIDED, and the answer is to
  change NOTHING.** The plan made it conditional on Z5: "if row K `passes`
  against Z5, instances A-C become pty-backed". **Row K FAILS against Z5** —
  measured, `FAIL K: the dummy key is in NO app log` — so a file-redirected
  log's 4096 buffered bytes are more than enough for that row to see a key in
  every line. K15's open question, "whether K can fail at all is NOT known",
  is answered: it can. The instances stay as they are and the product is
  unchanged.

#### What this review did NOT reach — UNJUDGED, by name

litecode runs one agent at a time and this review WAS the readers; the
independent SCEPTIC pass the practice calls for is the part it could not do
for itself. What follows is recorded UNJUDGED rather than refuted, so the next
reader does not mistake a gap for an answer. **The sceptic pass HAS since run
— "The sceptic pass, and the fix pass that answered it" below** — and it
reached none of these five: they stay UNJUDGED, and the last one is answered
only for the two fixes it attacked.

- **The 21 PAIRS of pinned refusals.** Row 1 drives three one at a time and
  row 7 drives every reader at its extremes; no row presents two at once and
  asks which is named. Reader 5.
- **Stop during the upload, the submit, the wait and the save**, from the
  SHEET. Row J measures the janitor's half from the probe's side and section
  18's cancel row measures the extract's; the other four phases have no row.
  Reader 6.
- **L14**, the Verify answer announced as current, found by reading and
  **FILED #33 without being driven** — late, with the mutant matrix already
  running against `app/Sources` as it then stood. The issue names the row it
  needs and the `stall {route: "verify"}` key that makes it possible.
- **L1's second half**, "a dripping server may never time out": UNREPRODUCED.
  The new `stall` key answers nothing at all, which is what an idle timer is
  FOR; a fake that drips a byte under the timer is a second timing instrument
  this review did not build.
- **Every fix's own sceptic.** Seven product fixes landed, each with a row
  made to fail against the fix reverted in a tree copy. Nobody but their
  author has tried to break them. **Partly answered**: the sceptic pass below
  broke TWO of the seven — R5·2's sentence on the unwritable-cache branch and
  R3·1's gate reporting a delete it never sent — and both are fixed there.
  The other five have still had no reader but their author.

#### The closing scores

Every number below is from the run that printed it, on the tree as this
review leaves it. No `EXPIRED` line anywhere: the longest cell was Z12's
probe at **328 s** against its 1173 s limit.

| Command | Score | `wall=` |
|---|---|---|
| `make test` | 721 passed, 0 failed, 39 binaries | 1.5 s |
| `make lint` | clean | 0.2 s |
| `cd core && cargo fmt --check` | clean | 0.4 s |
| `make typecheck` | 0 errors, exactly 4 warnings | 38.9 s |
| `make app` | BUILD SUCCEEDED | 46.7 s |
| `python3 -m py_compile` (seven cloud scripts) | clean | 0.2 s |
| `cloud_live_selftest.py` | **14/14** (was 9/9) | 0.2 s |
| `cloud_captions_probe.py` | **490/490** (was 469) | 33.7 s |
| `cloud_captions_proof.py --port-base 4990` | **142/142** (was 115), no skip | 50.8 s |
| `makefile_env_proof.py` | **2/2** | 57.1 s |
| `makefile_env_proof.py --mutant no-unexport` | **1/2**, the leak row failing | 55.2 s |
| `cloud_captions_probe.py --fake-mutant fake-logs-any-key --only hygiene` | **29/30**, row G failing | 0.6 s |
| `phase4_proof.py 4993` | 84/84 | 3.0 s |
| `op_catalog_proof.py 4994` | 23/23 | 61.0 s |
| `op_argument_proof.py 4995` | 133/133 | 68.4 s |
| `phase4_chrome.py` | 59/59 | 132.2 s |
| `source_mirror_probe.py` | 40/40 | 60.1 s |
| `grep "Reelcut: " /tmp/reelcut-499?.log` | prints nothing | — |

**No own instance is left alive** (`pgrep -f "MacOS/Reelcut"` is empty), and
an in-process search over the scratch directory, `tools/proof/work/c1-review/`
and all ten `/tmp/reelcut-499?.log` read **162 files**: `proof-key` and
`wrong-key` appear only in the instruments' own captured console text, which
is what those two allow-listed dummies are for, and
**`RCDUMMY-makefile-env-proof-5d1c` appears in none of them**. The one place
it DID land is the `--mutant no-unexport` cell's own tree copy — 2 files of
661, both under `XCBuildData/`, which is the measurement — and that work
folder, which this run made, was then removed.

**Left behind on purpose, and named so nobody hunts it:** Z3
(`extract-kept`) leaves `reelcut-upload-*.flac` files in the per-user
temporary directory, which is what that mutant is. They are not this run's to
delete — `/var/folders/…/T/` is the person's — and R7·1's fix is what keeps
them from failing row T's control in a later run.

#### The sceptic pass, and the fix pass that answered it (2026-09-21)

The independent SCEPTIC the practice calls for — the part this review could
not do for itself — was run afterwards against the tree above. It started
nothing, bound no port and read no key; it read `03-spec-final.md`,
`04-impl-notes.md`, `04-checks.txt` and the diff. Its verdict was
**fix-required** on six findings: four where a sentence in the record is not
what the run printed, one where a sentence a FIX wrote is false on a branch,
and one nit where a refusal is reported as a success. All six are fixed, in
one pass, below. **No live call was made in it either, and nothing was
spent.**

**The four record findings** — each corrected from `04-checks.txt`'s own
printed lines and from `wc -l` on the day, never from memory:

1. **The MCP mutant scores said `Z5 141/142 (row K)`**; the run printed
   **140/142** (`04-checks.txt`, `proof-z5-key-in-note`). Z5 failed TWO rows:
   row K, the catch, and row T, R7·1's instrument failure. The count hid the
   second. **Corrected above**, with the second failure named.
2. **The probe table's `P/T/J/I the run` × Z5 cell said `fails`** while the
   same section's score line says Z5 was caught by NOTHING at 488 rows
   (`probe-z5-key-in-note`, **488/488**). **Corrected to `passes`**, with the
   488-row and 490-row runs named separately: the sharper row added to that
   same section afterwards is what catches it, **489/490** (`probe-z5b`).
3. **`designs/reelcut-remaining.md` §3's two "before" counts were not the
   baseline tree's.** `git show f03ebcc6…` holds `cloud_live_ledger.py` at
   **312** (§3 said 288) and `cloud_captions_proof.py` at **1643** (§3 said
   1494, copied from the stale sentence higher up). **Both corrected**, and
   the older sentence date-revised rather than rewritten: its 1494 is what
   `wc -l` gives at c1-chrome's own tree `5cc64c21…`, and c1-close took the
   file to 1643.
4. **`tools/proof/README.md` said the probe has 488 rows**, the pre-R7·3
   count, while the tree scored **490/490**. **Corrected**, and the sharper
   Z5 row — "no line the child printed holds the dummy", with its CONTROL —
   is now in the list of new rows beside J and I.

**Finding 5, a sentence a fix wrote, false on one branch (`should-fix`).**
R5·2's bill sentence ended "…their transcripts are cached in the project, so
another run makes no request for them". On the branch R1·3's own fix created
— `MediaTranscript.write` answers `false`, so the marker is correctly NOT
written and nothing is cached — the media is in `report.uploaded` all the
same, which is issue **#29**'s unwritable cache. A caller who believed the
sentence paid for the same media twice. **FIXED** in
`AgentServer+CloudCaptions.swift`: the sentence now ends `before this
failed.` and promises nothing about a cache this method cannot see. Row **B**
gained four checks, one of them the branch itself — run 1 caches, the cache
file is made `UF_IMMUTABLE` the way row M does it, run 2 re-fetches under a
different request, is billed, cannot write, and throws — plus two CONTROLs
(that there was a file to make unwritable, and that the flag really stopped
the write). Mutant **`bill-promises-cache`** puts the old clause back:
**144/146**, the two failures being row B's "names the bill" and "promises
NOTHING about a cache that was never written", both in row B and both for the
reason the fix names.

**Finding 6, the nit that was a false record (`nit`, fixed anyway).** R3·1's
gate made `delete` answer **`true`** with no request, so
`CloudTranscriber+Media.swift`'s janitor wrote `remote_deleted: true` into the
cache file and put the media in `janitorDeleted`: the run reported deleting a
transcript it never asked about, and erased the one record that something was
owed. **What it answers now, and why.** `AssemblyAIClient.delete` answers
**three** states — `deleted`, `failed`, `notSent` — because "never sent" is
neither "gone" nor "owed", and the janitor puts a `notSent` media in
**NEITHER list**: not `janitorDeleted`, so no delete is claimed and no cache
file is rewritten, and not `janitorFailed`, so **R6-11's hold cannot trap the
media for ever on an id that can never be sent** — which was the whole reason
the gate answered `true` in the first place. The media is fetched again
ONLY when its stamp is stale or `refresh` is asked (a current stamp serves
the cache, as ever), and until then every run's janitor refuses the same
string as cheaply — no request, and a log line that carries no id. `fetch`
reads the same answer (`== .deleted`), so a server that echoes back an id
that is not one cannot have a delete recorded for it either. Row **I** gained
two checks: none of the five hostile ids is in `janitorDeleted`, and their
cache files still say `remote_deleted: false`. Mutant
**`refused-id-reported-as-deleted`** (`return .notSent` → `return .deleted`)
fails exactly those two and no other: **490/492** whole, and **48/50** on the
`run` section alone, where the R6-11 row beside them still passes — so the fix
did not trade one answer for the other. `any-id-on-the-wire` was re-aimed at
the gate's new line and `no-delete` at `fetch`'s.

**What the fix pass did NOT do.** It did not re-run the twelve-mutant matrix
(the cells above are what those runs printed, against the instruments as they
then stood, and the paragraph under each table says so); it did not re-run
`op_catalog_proof.py`, `op_argument_proof.py`, `phase4_chrome.py` or
`source_mirror_probe.py`, none of which any of these six changes can reach —
no op, no schema, no catalog entry, no chrome file and no Rust changed; and it
did not touch the five things named UNJUDGED above, which stay UNJUDGED. Two
numbers the sceptic could not find in the evidence are now REWORDED to claim
only what was printed: R7·2's `142/142` re-run and the step-0 table's `wall=`
column.

**The fix pass's own scores**, each from the run that printed it, on the tree
it leaves:

| Command | Score |
|---|---|
| `make test` | 721 passed, 0 failed, 39 binaries |
| `make lint` · `cargo fmt --check` | clean |
| `make typecheck` | 0 errors, exactly 4 warnings (8 diagnostic lines) |
| `make app` | BUILD SUCCEEDED |
| `python3 -m py_compile` (seven cloud scripts) | clean |
| `cloud_live_selftest.py` | 14/14 |
| `cloud_captions_probe.py` | **492/492** in 207 s |
| `cloud_captions_proof.py --port-base 4990` | **146/146** in 60 s, no skip |
| `cloud_captions_proof.py --mutant bill-promises-cache` | **144/146** |
| `cloud_captions_probe.py --mutant refused-id-reported-as-deleted` | **490/492** (48/50 on `--only run`) |
| `phase4_proof.py 4993` | 84/84 |
| `grep "Reelcut: " /tmp/reelcut-499?.log` | prints nothing |
| `git diff f03ebcc6… -- core/` | empty |

No own instance is left alive. Nothing was committed, added, stashed or
checked out, no `CLAUDE.md` was edited, and the `app/CLAUDE.md` sentence
`04-impl-notes.md` writes out is still owed to whoever may edit that file.

#### The tree

**`6056b1e9de52d64a0f00650517d3086edb34b0a7`** — every line this review wrote
except this paragraph, by the request's temp-index recipe (never the real
index; nothing was committed, added, stashed or checked out). It is measured
before the paragraph rather than after it because a hash of a tree cannot be
written into that tree; re-run the recipe for the current one. The baseline is
c1-close's **`f03ebcc6e4769f7195812d51d562518a2e4d9b67`**, and `git diff` of it
over `core/` is empty: this review changed no Rust at all.

**The fix pass's tree: `def1209e45567cc7792661f3a9eb906a71d72b6d`** — the same recipe, measured with
this hash line held at a placeholder and then written in, over the six fixes,
the two new mutants, row B's four checks and row I's two, and every
correction above. Its baseline is the review's own `6056b1e9…`; `git diff`
of `f03ebcc6…` over `core/` is still empty.

#### The second sceptic pass, and what was done by hand after it (2026-09-21)

litecode's second review, still the sceptic, read the fix pass and ran
nothing. All six findings of the first pass were RESOLVED. It attacked the two
new code fixes and broke neither: `delete` has exactly two callers and the
`refusing` helper, no `Bool` comparison survives, `notSent` is decided on the
string before any socket so it cannot relabel a transport failure, `fetch`'s
`== .deleted` changes no branch that was right before, and the shortened bill
sentence is true on every branch that reaches it. Both new mutants' patch
texts occur once and fail only the rows named. Its verdict was still
`fix-required`, on ONE record number and five nits, and litecode runs no
second fix pass, so the session's orchestrator closed the prose by hand and
recorded the rest:

- **The bill sentence's "(11 audio seconds)" had no printed line.** The only
  printed instance is the fix pass's capture of row B, which says 6. R5·2's
  bullet above now quotes 6 and says where it came from; its "4 checks, two
  CONTROLs" is now 8 and three, the proof README's own count.
- **R7·2's re-run is a reader's word**, and its bullet now says so: no
  evidence line shows the run, let alone a score.
- **"The media is simply fetched again"** was true only of a stale stamp; the
  paragraph above now says when.
- **Three nits were NOT fixed** and are listed in
  `designs/reelcut-remaining.md` §5 under the reader review's own heading:
  the "next run retries it" sentence that is false for an id that cannot be
  sent, two probe rows that say five and assert six, and a stale 2.5 s
  comment.
- **`app/CLAUDE.md`'s one false map clause was corrected by the
  orchestrator**, as factual text and with no record citation: the client's
  entry now names `withoutCredential(_:)` as the third member that touches
  the credential and says `delete` answers three states. No rule text
  changed in either `CLAUDE.md`.

**UNJUDGED still, never refuted:** the five things this section's opening
names (the 21 refusal pairs, Stop during four of the six phases, #33, L1's
dripping server, and a second pair of eyes on R1·1, R1·2, R1·3, R2·1 and
H·3); every fix-pass score, which the second pass took on the fixer's notes
and reproduced none of, including whether `UF_IMMUTABLE` really stops row B's
second write on this host; and the re-aimed `any-id-on-the-wire` and
`no-delete` mutants, whose patch texts were counted but which were not re-run
after re-aiming.

### 10.14 #28 — recover a lost submission reply (2026-09-21)

R6-14 was recorded in spec §11 before the implementation. The decision uses
C0 §3 q1's measured byte-equal `audio_url` list match and AssemblyAI's
[list endpoint](https://www.assemblyai.com/docs/pre-recorded-audio/api-reference/transcripts/list),
which returns newest rows with `id` and `audio_url` and caps a page at 200.
`submit` moved by itself from `AssemblyAIClient.swift` to
`AssemblyAIClient+Submission.swift`; that pure move passed `make typecheck`
with only the existing four AVFoundation deprecation warnings. The client
now sends one POST and, only when its answer may have been lost or cannot
yield a plain ID, makes at most three authenticated newest-page GETs. It
accepts one distinct plain ID at the exact encoded upload URL; refused
authentication and unresolved ownership carry the dashboard warning.
`CloudTranscriber` preserves that warning across a cancellation during
recovery and aborts later media on a refused key. The fake distinguishes
Verify's `limit=1` from recovery's `limit=200` and can hide transcripts for
initial list looks. The permanent probe and built-app proof have the
protocol, cancellation, placement, cache and delete cases; the
`no-submit-recovery` source-copy mutant is the deletion test.

Verification: `make test` and `make lint` passed; the post-change
`make typecheck` passed with 0 errors and the four documented warnings.
The focused normal probe passed **233/233** over `client,cancel,run,verbatim,
hygiene,submission`; the mutant exited nonzero at **52/94**, with recovery
assertions failing as intended. After the fake's list counter was made to
count every request, the `submission` section passed **94/94** again.
`make app` could not finish because this
Xcode installation lacks `MetalToolchain` (`CompileMetalFile` could not
execute `metal`). The required MCP proof command ran against the existing
05:39 binary and scored **142/144**; its new recovery row failed because
that binary predates this change, and an existing H fixture copy raced the
importer's thumbnail write. Its score cannot validate the new app. All
three owned instance logs had no `Reelcut: ` parity complaint. No live
AssemblyAI request, commit or issue write was made. Final touched app sizes:
`AssemblyAIClient.swift` **397**, `AssemblyAIClient+Submission.swift` **73**,
`CloudTranscriber.swift` **327**, all within their 400-line caps. The
unrecovered cases remain the explicit bounded limits in spec R6-14 and
remaining §5; neither a future cleanup nor a deletion is promised for them.

### 10.15 #29 — report an unrecorded deletion honestly (2026-09-21)

`CloudTranscriber.Report.Uploaded` now records whether the fetched transcript's
initial atomic JSON write succeeded, independently of its marker and remote
DELETE. The report's pure `deletionWarnings` method gives the UI card and MCP
success/failure answers one wording and order: a recorded failed DELETE is
retried at the next run; an unsaved failed DELETE cannot be retried by Reelcut
and asks for dashboard deletion. A confirmed DELETE produces no cleanup
warning. The failed MCP answer retains the original error and unchanged
billing sentence, followed by these warnings. No new request, format field,
or result key was added.

The source-compiled `cache_write` probe blocked `cache/transcripts` with a
regular file and scored all four initial-write/DELETE outcomes, the next-run
janitor with and without a saved ID, a marker-only failure, a zero-word
throw after billing, and mixed per-media warning order and deduplication.
The focused normal run, including `run`, `chrome` and #28's `submission`,
passed **236/236**. The `cache-write-assumed` source-copy mutant compiled
and scored **15/19**, failing four persistence/warning rows as intended.
`make test`, `make lint`, and Swift typecheck passed; typecheck had only the
four established AVFoundation warnings. `git diff --check` passed. Final
touched app sizes: `CloudTranscriber.swift` **356**, `+Media.swift` **218**,
`AgentServer+CloudCaptions.swift` **280**, and
`TranscribeSheetController+Commit.swift` **205**, each under 400 lines.

`make app` was attempted once and failed at `CompileMetalFile` because this
Xcode lacks `MetalToolchain`. Thus the changed source is proved through the
whole-source probe, while a fresh app build and built-app MCP proof remain
owed when the toolchain is available. No old binary was used as proof; no
live AssemblyAI request, commit or issue write was made.

### 10.16 #33 — keep Verify's answer with its request and inputs (2026-09-21)

The Settings window now captures the effective credential, persisted region
and resolved base URL for each Verify invocation, and gives that invocation
a UUID. An older completion cannot clear or answer for a newer request. The
owning completion compares current inputs before announcing success or
refusal; changed inputs yield §5d's stale sentence. Field edits, sync,
reopening, Save, Remove and region changes update Verify availability while
preserving a pending check when its inputs still match. Saving the same typed
key remains eligible for the current result. The existing single store
factory call per sync, fixed-length placeholder, notifications and transport
interface remain in place. `SettingsWindowController.swift` is **453** lines,
below its existing-file cap.

The source-compiled `settings_verify` section drove nine scenarios over
delayed loopback fakes and inspected both controller snapshots and exact
wire requests. The final `settings_verify,chrome,hygiene` run passed
**145/145**, with no skip. `verify-ignores-input` compiled and scored
**38/41**, failing the typed-key, saved-key and region behavioral rows;
`verify-ignores-owner` compiled and scored **37/41**, failing the same-input
overlap and both reply-order rows. `make test`, `make lint`, and Swift
typecheck passed; typecheck printed only the four established AVFoundation
warnings. The probe's Python compile and `git diff --check` passed. The
probe uses dummy credentials, isolated defaults suites and memory stores;
no live AssemblyAI request was made.

`make app` was attempted once and failed at `CompileMetalFile` because this
Xcode installation lacks `MetalToolchain`. A fresh built app and MCP proof
remain owed when that toolchain is available; the source-compiled probe is
the measured verification for this Settings behavior. No old binary was
substituted, and nothing was committed or written to GitHub.

### 10.17 Final build and built-app verification for #28, #29 and #33 (2026-09-21)

The earlier `make app` failures and #28's stale-binary **142/144** are the
results those runs actually produced; they are superseded as current
verification by this later run. `xcodebuild -downloadComponent MetalToolchain`
completed on this host, then `make app` built the combined current sources
and ended **BUILD SUCCEEDED**. The fresh app was driven over MCP by
`cloud_captions_proof.py --port-base 5130` with `RC_ASSEMBLYAI_KEY` unset:
**158/158** checks passed in 63 seconds. Each of its
three owned instance logs (`/tmp/reelcut-5130.log` through `-5132.log`)
existed and had zero `Reelcut: ` startup parity complaints.

For **#28**, the built-app R6-14 immediate and delayed lost-reply rows each
observed one paid submit, identified only its created transcript, confirmed
its DELETE, placed captions through MCP, wrote the cache, and served the
second run from that cache without another transcript request. For **#29**,
the issue-specific unwritable-cache and deletion-warning matrix remains the
source-compiled **236/236** proof in §10.15; the fresh built app also passed
the cloud MCP proof's cache-write, failed-DELETE retry and report/billing
rows. For **#33**, the issue-specific nine delayed Settings scenarios remain
the source-compiled **145/145** proof in §10.16; personal Settings are
intentionally outside MCP, and the fresh build now includes that changed
controller. The prior owed fresh build and general built-app cloud proof
are discharged by this run. No live AssemblyAI request was made.
