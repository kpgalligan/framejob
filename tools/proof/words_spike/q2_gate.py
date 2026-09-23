"""W0 residue: proves speech_rows.q2_verdict on RECORDED answers (no paid call) — the recorded row scores run, doctored copies score failed."""
import copy, json, sys
import os; HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import speech_rows
answers = json.load(open(os.path.join(HERE, "..", "work", "words_spike", "answers.json")))
recorded = answers["rows"]["q2"]["measured"]
def ask(label, mutate, want):
    m = copy.deepcopy(recorded)
    mutate(m)
    v = speech_rows.q2_verdict(m)
    ok = v["state"] == want
    print(f"{'PASS' if ok else 'FAIL'} {label}: {v['state']} ({v['reason']})")
    return ok
def setp(path, value):
    def f(m):
        d = m
        for k in path[:-1]:
            d = d[k]
        d[path[-1]] = value
    return f
def many(*fs):
    def f(m):
        for g in fs: g(m)
    return f
T = ["files", "talk.wav"]
cases = [
    ("recorded answer, unchanged", lambda m: None, "run"),
    ("words probe crashed (ok false, error)", many(setp(T+["speechtranscriber","ok"], False), setp(T+["speechtranscriber","error"], "probe crashed: SIGSEGV"), setp(T+["speechtranscriber","words"], 0)), "failed"),
    ("words probe ok but zero words", setp(T+["speechtranscriber","words"], 0), "failed"),
    ("cloud upload_only", many(setp(T+["assemblyai","outcome"], "upload_only"), setp(T+["assemblyai","upload"], {"status": 500, "seconds": 0.1})), "failed"),
    ("cloud no_transcript", many(setp(T+["assemblyai","outcome"], "no_transcript"), setp(T+["assemblyai","submit"], {"status": 400, "seconds": 0.1, "body": "bad request"})), "failed"),
    ("cloud deleted, zero words", setp(T+["assemblyai","word_count"], 0), "failed"),
    ("no files measured", setp(["files"], {}), "failed"),
    ("sf expired (a measured answer)", many(setp(T+["sfspeechrecognizer","expired"], True), setp(T+["sfspeechrecognizer","ok"], False), setp(T+["sfspeechrecognizer","segments"], 0)), "run"),
]
results = [ask(*c) for c in cases]
print(f"{sum(results)}/{len(results)} as expected")
sys.exit(0 if all(results) else 1)
