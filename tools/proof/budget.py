"""Road map 13 P3 — the proofs' ledger and the monthly budgets (spec §11 P-3, P-6).

Every paid proof request — the relay's POSTs in `assistant_prompt_eval.py`, the
AssemblyAI live rows in `cloud_captions_live.py` — is RESERVED here at its
worst case before it is sent, and refused (`budget: …`) when this UTC month's
recorded spend plus that worst case would pass the service's budget. The
reply is then SETTLED at what it cost.

**The ledger** is `LEDGER`, outside the repo (it survives `rm -rf
tools/proof/work` and a clone, and every worktree shares it) and outside the
app's spend folder (P-5). This file is its only writer: one JSON object per
line, each appended with one `os.write` to a file opened `O_APPEND|O_CREAT`
0600 in a folder made 0700. A line carries `format`, `at` (UTC), `service`,
`kind` (`reserve`, `settle`, `refused`) and `id`, plus its kind's fields —
never a key, a header, a body or a text. Only a keyed live run points a
`SpendLedger` at `LEDGER`; rehearsals and verifications use scratch files.

**The unmoved ledger** (spec §11 NM-7): while the folder of the ledger's
name before rename R1, `OLD_LEDGER_FOLDER`, exists, a `SpendLedger` at
`LEDGER` refuses every request, naming the owner's guarded `mv`
(`designs/rename.md`, "The owner's hand steps", step 3), before it makes a
folder, opens the ledger or writes any line: a folder made here would make
that `mv` nest the old one inside it, and the month would restart at $0.

**The fold** for a service and a month: a `reserve` made in the month counts
its largest `settle`'s dollars, or its `worst` while it has none; a `settle`
with no `reserve` counts its own dollars in its own month; a `refused` counts
nothing. The read, the fold and the append run under one `flock(LOCK_EX)` on
the file. It FAILS CLOSED: a line that is not an object of `format` 1 with its
kind's fields, or a file that cannot be read or written, refuses by name.

**The worst cases.** Anthropic: each token class at its dearest rate over
every row and `above_200k` tier of `agent/prices/anthropic.json`
(`anthropic_worst_row`). AssemblyAI: the planned seconds at `AssemblyAIRates`'
two rates added (`assemblyai_worst`), read from `app/Sources/CloudEstimate.swift`
— the one hand-kept price (P-1), never respelled here.

Standard library and `prices.py` only.
"""

import datetime
import fcntl
import json
import math
import os
import re
import sys
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
import prices  # noqa: E402

LEDGER = os.path.expanduser("~/Library/Application Support/Frame Job Proofs/spend.jsonl")
OLD_LEDGER_FOLDER = os.path.expanduser("~/Library/Application Support/Reelcut Proofs")
BUDGETS = {"anthropic": 25.00, "assemblyai": 5.00}
FORMAT = 1
CLOUD_ESTIMATE = os.path.join(ROOT, "app", "Sources", "CloudEstimate.swift")

NAMES = {"anthropic": "Anthropic", "assemblyai": "AssemblyAI"}
COMMON = ("format", "at", "service", "kind", "id")
FIELDS = {
    "reserve": ("proof", "run", "row", "worst"),
    "refused": ("proof", "run", "row", "worst", "month_total", "budget"),
    "settle": ("dollars", "basis"),
}
NUMBERS = ("worst", "dollars", "month_total", "budget")
STAMP = "%Y-%m-%dT%H:%M:%SZ"
WORST_CLASSES = ("input", "cache_write_5m", "cache_write_1h", "cache_read", "output")


class BudgetRefused(Exception):
    """A paid request that may not be sent. Its text always begins `budget: `."""

    def __init__(self, text):
        if not text.startswith("budget: "):
            text = "budget: " + text
        super().__init__(text)


def _utc_now():
    return datetime.datetime.now(datetime.timezone.utc)


def _number(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return False
    try:
        return math.isfinite(float(value))
    except OverflowError:
        return False


def _checked(number, line):
    """The line parsed, or BudgetRefused naming its number."""
    try:
        entry = json.loads(line)
    except ValueError:
        entry = None
    if not isinstance(entry, dict):
        raise ValueError(f"line {number} is not a JSON object")
    if entry.get("format") != FORMAT or isinstance(entry.get("format"), bool):
        raise ValueError(f"line {number} is not format {FORMAT}")
    kind = entry.get("kind")
    if kind not in FIELDS:
        raise ValueError(f"line {number} has no known kind")
    for name in COMMON + FIELDS[kind]:
        if name not in entry:
            raise ValueError(f"line {number} ({kind}) has no `{name}`")
    for name in ("at", "service", "id"):
        if not isinstance(entry[name], str):
            raise ValueError(f"line {number} ({kind}): `{name}` is not a string")
    if len(entry["at"]) < 7:
        raise ValueError(f"line {number} ({kind}): `at` is not a UTC stamp")
    for name in NUMBERS:
        if name in FIELDS[kind] and not _number(entry[name]):
            raise ValueError(f"line {number} ({kind}): `{name}` is not a finite number")
    return entry


def fold(text, service, month, path="the ledger"):
    """The month's total for `service` over a ledger's text; BudgetRefused
    naming the first line that does not parse."""
    reserves, settles = {}, {}
    lines = text.split("\n")
    for number, line in enumerate(lines, 1):
        if line == "" and number == len(lines):
            continue  # the text after the last newline
        try:
            entry = _checked(number, line)
        except ValueError as problem:
            raise BudgetRefused(f"budget: the proofs' ledger {path} cannot be read: {problem}; "
                                "a person repairs it before any paid proof runs") from None
        if entry["service"] != service:
            continue
        if entry["kind"] == "reserve":
            reserves[entry["id"]] = (entry["at"][:7], float(entry["worst"]))
        elif entry["kind"] == "settle":
            settles.setdefault(entry["id"], []).append((entry["at"][:7], float(entry["dollars"])))
    total = 0.0
    for rid, (made, worst) in reserves.items():
        if made != month:
            continue
        settled = settles.get(rid)
        total += max(d for _, d in settled) if settled else worst
    for sid, settled in settles.items():
        if sid in reserves:
            continue
        mine = [d for at, d in settled if at == month]
        if mine:
            total += max(mine)
    return total


def unmoved(old_folder: str, new_folder: str) -> str | None:
    """The refusal while `old_folder`, the ledger's folder before rename R1,
    still exists; None once it is gone. Reads nothing in either folder."""
    if not os.path.exists(old_folder):
        return None
    return (f"budget: the proofs' ledger is not moved yet: {old_folder} still exists, so this "
            f"month's spend is not in {new_folder}. Move it first (designs/rename.md, the "
            f"owner's hand steps, step 3): [ -e \"{new_folder}\" ] && echo \"{new_folder} exists: "
            f"merge by hand\" || mv \"{old_folder}\" \"{new_folder}\"")


class SpendLedger:
    """One proof run's view of the ledger at `path` for one service. The
    constructor touches no file. At `LEDGER`, `old_folder` defaults to
    `OLD_LEDGER_FOLDER` (the unmoved-ledger guard); elsewhere it is unguarded
    unless `old_folder` is given."""

    def __init__(self, path, service, proof, run, now=None, old_folder=None):
        if service not in BUDGETS:
            raise ValueError(f"no budget for the service {service!r}")
        self.path = str(path)
        if old_folder is None and os.path.abspath(self.path) == os.path.abspath(LEDGER):
            old_folder = OLD_LEDGER_FOLDER
        self.old_folder = old_folder
        self.service = service
        self.proof = proof
        self.run = run
        self.now = now or _utc_now
        self._count = 0
        self._ids = threading.Lock()

    def _unmoved(self):
        if self.old_folder is None:
            return None
        return unmoved(self.old_folder, os.path.dirname(os.path.abspath(self.path)))

    def month(self):
        return self.now().astimezone(datetime.timezone.utc).strftime("%Y-%m")

    def _stamp(self):
        return self.now().astimezone(datetime.timezone.utc).strftime(STAMP)

    def _next_id(self):
        with self._ids:
            self._count += 1
            return f"{self.proof}/{self.run}/{os.getpid()}/{self._count}"

    def _line(self, kind, rid, **fields):
        entry = {"format": FORMAT, "at": self._stamp(), "service": self.service, "kind": kind,
                 "id": rid}
        entry.update(fields)
        return (json.dumps(entry, sort_keys=True) + "\n").encode("utf-8")

    def _open(self):
        folder = os.path.dirname(self.path) or "."
        os.makedirs(folder, mode=0o700, exist_ok=True)
        return os.open(self.path, os.O_RDWR | os.O_APPEND | os.O_CREAT, 0o600)

    @staticmethod
    def _read(fd):
        os.lseek(fd, 0, os.SEEK_SET)
        chunks = []
        while True:
            chunk = os.read(fd, 1 << 16)
            if not chunk:
                break
            chunks.append(chunk)
        return b"".join(chunks).decode("utf-8", "replace")

    @staticmethod
    def _append(fd, data):
        written = os.write(fd, data)
        if written != len(data):
            raise OSError(f"a short write ({written} of {len(data)} bytes)")

    def month_total(self):
        """This month's recorded spend: 0.0 when the file is absent;
        BudgetRefused when it cannot be read or a line does not parse, or
        while the ledger is unmoved."""
        if why := self._unmoved():
            raise BudgetRefused(why)
        if not os.path.exists(self.path):
            return 0.0
        try:
            fd = os.open(self.path, os.O_RDONLY)
        except OSError as error:
            raise BudgetRefused(f"budget: the proofs' ledger {self.path} could not be opened: "
                                f"{error}") from None
        try:
            fcntl.flock(fd, fcntl.LOCK_SH)
            text = self._read(fd)
        except OSError as error:
            raise BudgetRefused(f"budget: the proofs' ledger {self.path} could not be read: "
                                f"{error}") from None
        finally:
            os.close(fd)
        return fold(text, self.service, self.month(), self.path)

    def _refusal_text(self, total, worst):
        return (f"budget: ${total:.4f} of the ${BUDGETS[self.service]:.2f} "
                f"{NAMES[self.service]} budget is recorded for {self.month()} (UTC) in "
                f"{self.path}; this request's worst case is ${worst:.4f}")

    def refusal(self, worst):
        """Why a request of this worst case may not be sent, or None. Writes
        nothing."""
        if why := self._unmoved():
            return why
        try:
            total = self.month_total()
        except BudgetRefused as refused:
            return str(refused)
        if total + worst > BUDGETS[self.service]:
            return self._refusal_text(total, worst)
        return None

    def reserve(self, worst, row, gate=True):
        """The reservation's id. With `gate`, refuses (one `refused` line,
        then BudgetRefused) when the month's total plus `worst` passes the
        budget; without it, always records. While the ledger is unmoved it
        refuses first, making and writing nothing."""
        if why := self._unmoved():
            raise BudgetRefused(why)
        worst = float(worst)
        if not math.isfinite(worst) or worst < 0:
            raise BudgetRefused(f"budget: a worst case of {worst!r} cannot be reserved")
        rid = self._next_id()
        try:
            fd = self._open()
        except OSError as error:
            raise BudgetRefused(f"budget: the proofs' ledger {self.path} could not be opened: "
                                f"{error}") from None
        try:
            fcntl.flock(fd, fcntl.LOCK_EX)
            total = fold(self._read(fd), self.service, self.month(), self.path)
            budget = BUDGETS[self.service]
            if gate and total + worst > budget:
                self._append(fd, self._line("refused", rid, proof=self.proof, run=self.run,
                                            row=row, worst=worst, month_total=total,
                                            budget=budget))
                raise BudgetRefused(self._refusal_text(total, worst))
            self._append(fd, self._line("reserve", rid, proof=self.proof, run=self.run,
                                        row=row, worst=worst))
            return rid
        except OSError as error:
            raise BudgetRefused(f"budget: the proofs' ledger {self.path} could not be written: "
                                f"{error}") from None
        finally:
            os.close(fd)

    def settle(self, rid, dollars, basis, **detail):
        """Records what a reservation cost. Never raises; False when nothing
        was written (as while the ledger is unmoved)."""
        if self._unmoved():
            return False
        try:
            dollars = float(dollars)
            if not math.isfinite(dollars) or dollars < 0 or not isinstance(rid, str):
                return False
            data = self._line("settle", rid, dollars=dollars, basis=basis, **detail)
            fd = self._open()
            try:
                fcntl.flock(fd, fcntl.LOCK_EX)
                self._append(fd, data)
            finally:
                os.close(fd)
            return True
        except Exception:  # noqa: BLE001 — never raises, by contract
            return False

    def describe(self):
        try:
            total = f"${self.month_total():.4f} recorded"
        except BudgetRefused as refused:
            total = f"unreadable ({refused})"
        return (f"{self.service} {self.month()} (UTC): {total} of the "
                f"${BUDGETS[self.service]:.2f} budget in {self.path}")


# ---------------------------------------------------------------------------
# Anthropic: the worst row and the settlement.


def anthropic_worst_row(table):
    """Each class's dearest usable rate over every row and every
    `above_200k` tier of the table."""
    worst = {}
    for rate_key in WORST_CLASSES:
        found = []
        for row in (table.get("models") or {}).values():
            if not isinstance(row, dict):
                continue
            tiers = [row]
            if isinstance(row.get("above_200k"), dict):
                tiers.append(row["above_200k"])
            for tier in tiers:
                rate = tier.get(rate_key)
                if prices._usable(rate):
                    found.append(float(rate))
        if not found:
            raise ValueError(f"the price table has no usable {rate_key} rate")
        worst[rate_key] = max(found)
    return worst


def settle_anthropic(usage, model, table, reserved, whole):
    """(dollars, basis) for a reply: `table` at the table's price; `worst`
    when the table cannot price it but its counts read, each class at its
    dearest rate; `reserved`, the reservation, when the reply was not whole
    or its counts do not read."""
    if not whole:
        return float(reserved), "reserved"
    answer = prices.price(usage, model, table)
    if answer["kind"] == "dollars":
        return answer["dollars"], "table"
    if isinstance(usage, dict):
        stripped = {k: v for k, v in usage.items()
                    if k not in ("speed", "service_tier", "inference_geo")}
        iterations = stripped.get("iterations")
        if isinstance(iterations, list):
            stripped["iterations"] = [
                {k: v for k, v in one.items() if k != "model"} if isinstance(one, dict) else one
                for one in iterations]
        worst = prices.price(stripped, "worst",
                             {"models": {"worst": anthropic_worst_row(table)}})
        if worst["kind"] == "dollars":
            return worst["dollars"], "worst"
    return float(reserved), "reserved"


# ---------------------------------------------------------------------------
# AssemblyAI: the app's own dated rates.


def _enum_body(text, name):
    start = re.search(r"\benum\s+" + re.escape(name) + r"\b[^{]*\{", text)
    if start is None:
        raise ValueError(f"no `enum {name}` in {CLOUD_ESTIMATE}")
    depth, at = 1, start.end()
    while at < len(text) and depth:
        if text[at] == "{":
            depth += 1
        elif text[at] == "}":
            depth -= 1
        at += 1
    if depth:
        raise ValueError(f"`enum {name}` is not closed")
    return text[start.end():at - 1]


def _declared(body, name, literal):
    declarations = re.findall(r"^\s*static\s+let\s+" + re.escape(name) + r"\b(.*)$", body,
                              re.MULTILINE)
    if len(declarations) != 1:
        raise ValueError(f"`AssemblyAIRates` has {len(declarations)} `static let {name}` "
                         "declarations, not 1")
    found = re.fullmatch(r"\s*=\s*" + literal + r"\s*", declarations[0])
    if found is None:
        raise ValueError(f"`AssemblyAIRates.{name}` is not a plain literal: "
                         f"{declarations[0].strip()!r}")
    return found.group(1)


def assemblyai_rates(path=CLOUD_ESTIMATE):
    """`AssemblyAIRates`' three constants, read from the Swift source:
    {"per_hour", "speakers_per_hour", "read_on"}. ValueError when any is not
    declared exactly once, as a literal, inside the enum."""
    with open(path) as handle:
        body = _enum_body(handle.read(), "AssemblyAIRates")
    number = r"([0-9]+(?:\.[0-9]+)?)"
    rates = {"per_hour": float(_declared(body, "perHour", number)),
             "speakers_per_hour": float(_declared(body, "speakersPerHour", number)),
             "read_on": _declared(body, "readOn", r'"([^"\\]*)"')}
    for key in ("per_hour", "speakers_per_hour"):
        if not math.isfinite(rates[key]) or rates[key] < 0:
            raise ValueError(f"`AssemblyAIRates` {key} is not a finite rate")
    return rates


def assemblyai_worst(seconds):
    rates = assemblyai_rates()
    return float(seconds) / 3600.0 * (rates["per_hour"] + rates["speakers_per_hour"])


def assemblyai_dollars(seconds, speakers=False):
    rates = assemblyai_rates()
    return float(seconds) / 3600.0 * (rates["per_hour"]
                                      + (rates["speakers_per_hour"] if speakers else 0.0))
