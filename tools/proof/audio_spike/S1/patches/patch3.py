import sys

d = sys.argv[1]
p = d + '/src/main.swift'
s = open(p).read()
rep = [
    ('    case ("own", "limiter48"): return OwnTruePeakLimiter2(taps: 48, beta: 9)',
     '    case ("own", "limiter48"): return OwnTruePeakLimiter2(taps: 48, beta: 9)\n'
     '    case ("own", "limiter64"): return OwnTruePeakLimiter2(taps: 64, beta: 10)'),
    ('        ("own48", { OwnTruePeakLimiter2(taps: 48, beta: 9) }),',
     '        ("own48", { OwnTruePeakLimiter2(taps: 48, beta: 9) }),\n'
     '        ("own64", { OwnTruePeakLimiter2(taps: 64, beta: 10) }),'),
]
for a, b in rep:
    assert a in s, a
    s = s.replace(a, b)
open(p, 'w').write(s)
print("patched")
