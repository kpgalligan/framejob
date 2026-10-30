"""Spike S2 analysis helpers (numpy only)."""
import numpy as np

SR = 48000
LIFT_DB = 28.7  # what -16 LUFS asks of this file (survey section 2)


def load(path, channels=1):
    x = np.fromfile(path, dtype="<f4")
    if channels > 1:
        x = x.reshape(-1, channels)
    return x.astype(np.float64)


def db(x, floor=1e-20):
    return 10 * np.log10(np.maximum(x, floor))


def rms_db(x):
    return db(np.mean(np.asarray(x, dtype=np.float64) ** 2))


def xcorr_lag(ref, sig, maxlag=SR // 2):
    """Integer lag L such that sig[n] ~ ref[n - L] (sig is late by L)."""
    n = len(ref) + len(sig)
    nfft = 1 << (n - 1).bit_length()
    R = np.fft.rfft(ref, nfft)
    S = np.fft.rfft(sig, nfft)
    c = np.fft.irfft(S * np.conj(R), nfft)
    # lags 0..maxlag at c[0..], negative lags at the end
    lags = np.concatenate([np.arange(0, maxlag + 1), np.arange(-maxlag, 0)])
    vals = np.concatenate([c[: maxlag + 1], c[-maxlag:]])
    i = int(np.argmax(vals))
    peak = vals[i]
    norm = np.sqrt(np.sum(ref ** 2) * np.sum(sig ** 2))
    # sub-sample by parabolic interpolation
    def at(k):
        return c[k % nfft]
    L = lags[i]
    y0, y1, y2 = at(L - 1), at(L), at(L + 1)
    den = y0 - 2 * y1 + y2
    frac = 0.5 * (y0 - y2) / den if den != 0 else 0.0
    return int(L), float(L + frac), float(peak / norm)


def align(out, lag, length):
    """out[n + lag] for n in 0..length-1, zero-padded."""
    y = np.zeros(length)
    seg = out[lag: lag + length] if lag >= 0 else np.concatenate([np.zeros(-lag), out])[:length]
    y[: len(seg)] = seg
    return y


def windows(x, win_s=0.4):
    w = int(win_s * SR)
    n = len(x) // w
    return x[: n * w].reshape(n, w)


def classify(dry, win_s=0.4):
    """The rule's classes on dry: pause within 6 dB of p10; speech >= p10 + 20 dB."""
    W = windows(dry, win_s)
    lv = db(np.mean(W ** 2, axis=1))
    p10 = np.percentile(lv, 10)
    pause = lv <= p10 + 6
    speech = lv >= p10 + 20
    return pause, speech, lv, p10


def class_rms(x, mask, win_s=0.4):
    W = windows(x, win_s)
    return db(np.mean(W[mask] ** 2))


OCTAVES = [63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]


def band_powers(x, mask, win_s=0.4, nfft=None):
    """Mean power per octave band over the masked windows (Hann, one FFT per window)."""
    W = windows(x, win_s)[mask]
    w = W.shape[1]
    win = np.hanning(w)
    P = np.abs(np.fft.rfft(W * win, axis=1)) ** 2
    P = P.mean(axis=0) / np.sum(win ** 2)
    f = np.fft.rfftfreq(w, 1 / SR)
    out = []
    for fc in OCTAVES:
        lo, hi = fc / np.sqrt(2), min(fc * np.sqrt(2), SR / 2)
        sel = (f >= lo) & (f < hi)
        out.append(P[sel].sum())
    return np.array(out)


def load_wav(path):
    """float32 WAV (as ffmpeg writes pcm_f32le) -> (array [frames, ch] or [frames], sr)."""
    import struct
    b = open(path, "rb").read()
    assert b[:4] == b"RIFF" and b[8:12] == b"WAVE"
    i = 12
    ch = sr = None
    while i < len(b):
        cid, size = b[i:i + 4], struct.unpack("<I", b[i + 4:i + 8])[0]
        if cid == b"fmt ":
            fmt, ch, sr = struct.unpack("<HHI", b[i + 8:i + 16])
        if cid == b"data":
            x = np.frombuffer(b[i + 8:i + 8 + size], dtype="<f4").astype(np.float64)
            return (x.reshape(-1, ch) if ch > 1 else x), sr
        i += 8 + size + (size & 1)
    raise ValueError("no data")


def psd_bins(x, mask, win_s=0.4):
    W = windows(x, win_s)[mask]
    w = W.shape[1]
    win = np.hanning(w)
    P = np.abs(np.fft.rfft(W * win, axis=1)) ** 2
    return P.mean(axis=0) / np.sum(win ** 2), np.fft.rfftfreq(w, 1 / SR)
