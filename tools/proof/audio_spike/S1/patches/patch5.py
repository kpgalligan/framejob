import sys

d = sys.argv[1]
p = d + '/src/main.swift'
s = open(p).read()
rep = [
    ('            OwnExpanderStage(), OwnCompressorStage(), OwnTruePeakLimiter2(),',
     '            OwnExpanderStage(), OwnCompressorStage(), OwnTruePeakLimiter2(taps: 64, beta: 10, annexToo: true),'),
    ('"own.limiter", "own.limiter12", "own.limiterS", "own.chain8"]',
     '"own.limiter", "own.limiter12", "own.limiterS", "own.limiter64a", "own.chain8"]'),
]
for a, b in rep:
    assert a in s, a
    s = s.replace(a, b)
open(p, 'w').write(s)
print("patched")
