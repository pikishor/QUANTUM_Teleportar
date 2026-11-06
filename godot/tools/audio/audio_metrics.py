#!/usr/bin/env python3
"""Loudness and spectrum measurements shared by the audio generators and tools/audio/check_audio.py (numpy only).

  lufs_like(x)        K-weighted (38 Hz high-pass, +4 dB shelf above 1.7 kHz) mean-square level in LU-like dB over the whole signal (ITU-R BS.1770 shape, no gating)
  short_term(x, ms)   the same over the first `ms` milliseconds after the onset (the part of a shot that a player hears as its loudness)
  crest_db(x)         peak / RMS in dB over the active part (samples above peak - 40 dB)
  centroid_hz(x, ms)  magnitude-weighted spectral centroid of the first `ms` after the onset (all of it when ms is None)
  band_share(x, lo, hi, ms)   share (0..1) of the energy that lies in [lo, hi] Hz
"""
import numpy as np

SR = 44100


def _k_weight(x):
    n = len(x)
    size = 1 << int(np.ceil(np.log2(max(n, 16))))
    X = np.fft.rfft(x, size)
    f = np.fft.rfftfreq(size, 1.0 / SR)
    hp = (f ** 2 / (f ** 2 + 38.0 ** 2))
    shelf = 1.0 + (10 ** (4.0 / 20.0) - 1.0) * (f ** 2 / (f ** 2 + 1700.0 ** 2))
    return np.fft.irfft(X * hp * shelf, size)[:n]


def mono(x):
    x = np.asarray(x, dtype=np.float64)
    return x.mean(axis=0) if x.ndim == 2 else x


def lufs_like(x):
    y = _k_weight(mono(x))
    return -0.691 + 10.0 * np.log10(max(float(np.mean(y ** 2)), 1e-12))


def onset(x, rel_db=-30.0):
    x = mono(x)
    pk = float(np.max(np.abs(x))) + 1e-12
    idx = np.nonzero(np.abs(x) > pk * 10 ** (rel_db / 20.0))[0]
    return int(idx[0]) if len(idx) else 0


def _head(x, ms):
    x = mono(x)
    if ms is None:
        return x
    i = onset(x)
    return x[i:i + int(ms * SR / 1000.0)]


def short_term(x, ms=250.0):
    return lufs_like(_head(x, ms))


def rms_db(x):
    return 10.0 * np.log10(max(float(np.mean(mono(x) ** 2)), 1e-12))


def peak_db(x):
    return 20.0 * np.log10(max(float(np.max(np.abs(x))), 1e-9))


def crest_db(x):
    x = mono(x)
    pk = float(np.max(np.abs(x)))
    act = x[np.abs(x) > pk * 10 ** (-40.0 / 20.0)]
    return 20.0 * np.log10(pk / (np.sqrt(np.mean(act ** 2)) + 1e-12))


def centroid_hz(x, ms=None):
    y = _head(x, ms)
    w = np.hanning(len(y)) if len(y) > 8 else np.ones(len(y))
    S = np.abs(np.fft.rfft(y * w))
    f = np.fft.rfftfreq(len(y), 1.0 / SR)
    return float(np.sum(f * S) / (np.sum(S) + 1e-12))


def band_share(x, lo, hi, ms=None):
    y = _head(x, ms)
    S = np.abs(np.fft.rfft(y * (np.hanning(len(y)) if len(y) > 8 else 1.0))) ** 2
    f = np.fft.rfftfreq(len(y), 1.0 / SR)
    return float(np.sum(S[(f >= lo) & (f < hi)]) / (np.sum(S) + 1e-12))


def limiter(x, ceil_db=-1.0, look=0.004, wrap=False):
    """Look-ahead peak limiter (min-filtered gain, smoothed by a moving average of the same length: the output never exceeds the ceiling). x: (n,) or (ch, n);
    the gain is shared by the channels. wrap=True treats the signal as a loop (no seam)."""
    x = np.asarray(x, dtype=np.float64)
    m = np.max(np.abs(x), axis=0) if x.ndim == 2 else np.abs(x)
    n = len(m)
    w = max(int(look * SR), 2)
    ceil = 10 ** (ceil_db / 20.0)
    g = np.minimum(1.0, ceil / (m + 1e-12))
    if wrap:
        gp = np.concatenate([g[-2 * w:], g, g[:2 * w]])
    else:
        gp = np.concatenate([np.ones(2 * w), g, np.ones(2 * w)])
    win = np.lib.stride_tricks.sliding_window_view(gp, 2 * w + 1)
    gmin = win.min(axis=1)                                          # len(gp) - 2w, centred on gp[w:-w]
    c = np.concatenate([[0.0], np.cumsum(gmin)])
    avg = (c[2 * w + 1:] - c[:-(2 * w + 1)]) / (2 * w + 1)           # centred moving average; len = len(gmin) - 2w = n ... aligned with g
    avg = avg[:n]
    return x * (avg if x.ndim == 1 else avg[None, :])
