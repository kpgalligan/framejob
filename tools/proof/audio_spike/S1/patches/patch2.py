import sys

d = sys.argv[1]
p = d + '/src/main.swift'
s = open(p).read()
rep = [
    ('    case ("own", "limiter"): return OwnTruePeakLimiterStage()',
     '    case ("own", "limiter"): return OwnTruePeakLimiter2()\n'
     '    case ("own", "limiter12"): return OwnTruePeakLimiterStage()\n'
     '    case ("own", "limiterS"): return OwnTruePeakLimiter2(vectorDetector: false)\n'
     '    case ("own", "limiter48"): return OwnTruePeakLimiter2(taps: 48, beta: 9)'),
    ('            OwnExpanderStage(), OwnCompressorStage(), OwnTruePeakLimiterStage(),',
     '            OwnExpanderStage(), OwnCompressorStage(), OwnTruePeakLimiter2(),'),
    ('"own.expander", "own.compressor", "own.limiter", "own.chain8"]',
     '"own.expander", "own.compressor", "own.limiter", "own.limiter12", "own.limiterS", "own.chain8"]'),
    ('        ("own", { OwnTruePeakLimiterStage() }),',
     '        ("own", { OwnTruePeakLimiter2() }),\n'
     '        ("own12", { OwnTruePeakLimiterStage() }),\n'
     '        ("own48", { OwnTruePeakLimiter2(taps: 48, beta: 9) }),'),
    ('("own limiter", { OwnTruePeakLimiterStage() })', '("own limiter", { OwnTruePeakLimiter2() })'),
]
for a, b in rep:
    assert a in s, a
    s = s.replace(a, b)
open(p, 'w').write(s)

p = d + '/build.sh'
s = open(p).read()
s = s.replace('OwnDSP.swift AppleHost.swift', 'OwnDSP.swift OwnLimiter2.swift AppleHost.swift')
open(p, 'w').write(s)
print("patched")
