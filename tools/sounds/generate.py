"""Moonhush sound generator.

Every sound is synthesized from scratch (no samples, no recordings), so the
output is fully owned by the project. Each loop is built to be perfectly
circular: noise is shaped in the frequency domain over the whole loop (FFT
noise is periodic), slow envelopes are periodic too, and one-shot events
(drops, crackles, chirps) wrap around the end. Playing a file on repeat
therefore has no audible seam.

Usage: python3 generate.py [out_dir] [seconds]
"""
import os
import subprocess
import sys

import numpy as np
from scipy.io import wavfile

SR = 44100
SEED = 7


# ---------- building blocks ----------

def freqs(n):
    return np.fft.rfftfreq(n, 1 / SR)


def shaped_noise(rng, n, shape):
    """Periodic noise of length n whose magnitude spectrum is shape(f)."""
    f = freqs(n)
    spec = np.fft.rfft(rng.standard_normal(n)) * shape(np.maximum(f, 1e-3))
    spec[0] = 0
    x = np.fft.irfft(spec, n)
    return x / (np.std(x) + 1e-12)


def lp(fc, order=2):
    return lambda f: 1 / np.sqrt(1 + (f / fc) ** (2 * order))


def hp(fc, order=2):
    return lambda f: 1 / np.sqrt(1 + (fc / f) ** (2 * order))


def bp(lo, hi, order=2):
    return lambda f: lp(hi, order)(f) * hp(lo, order)(f)


def resonant(fc, q):
    return lambda f: 1 / np.sqrt(1 + (q * (f / fc - fc / f)) ** 2)


def tilt(power):
    """1/f^power slope: 0.5 is pink, 1 is brown."""
    return lambda f: 1 / np.maximum(f, 20) ** power


def mul(*shapes):
    def s(f):
        out = np.ones_like(f)
        for sh in shapes:
            out = out * sh(f)
        return out
    return s


def envelope(rng, n, max_hz):
    """Periodic slow random signal in [0, 1]."""
    x = shaped_noise(rng, n, lp(max_hz, 3))
    x = (x - x.min()) / (x.max() - x.min())
    return x


def periodic_sine(n, hz, phase=0.0):
    t = np.arange(n) / SR
    loop = n / SR
    hz = round(hz * loop) / loop  # whole number of cycles per loop
    return np.sin(2 * np.pi * hz * t + phase)


def place(out, kernel, start, gain=1.0):
    """Add kernel into out at start, wrapping around the end."""
    n = len(out)
    idx = (start + np.arange(len(kernel))) % n
    np.add.at(out, idx, kernel * gain)


def burst(rng, dur, shape, decay):
    """Short filtered noise burst with exponential decay."""
    m = max(int(dur * SR), 16)
    x = shaped_noise(rng, m, shape)
    t = np.arange(m) / SR
    env = np.exp(-t / decay) * np.minimum(1, t / 0.0015)
    return x * env


def stereo(rng, n, make, width=0.6):
    """Two channels sharing a common part, so the image is wide but stable."""
    common = make(rng, n)
    left = make(rng, n)
    right = make(rng, n)
    a = np.sqrt(1 - width ** 2)
    return np.stack([a * common + width * left, a * common + width * right])


def pan(x, p):
    """p in [-1, 1]; constant-power pan of a mono signal."""
    ang = (p + 1) * np.pi / 4
    return np.stack([x * np.cos(ang), x * np.sin(ang)])


def a_weight(f):
    f2 = f ** 2
    ra = (12194 ** 2 * f2 ** 2) / ((f2 + 20.6 ** 2) * np.sqrt((f2 + 107.7 ** 2) * (f2 + 737.9 ** 2)) * (f2 + 12194 ** 2))
    return ra / 0.7943  # 0 dB at 1 kHz


def finish(x, rms_db=-26.0, max_db=-19.0):
    """Normalize perceived loudness (A-weighted RMS) so every sound plays at
    a similar level in the mixer, then soft-limit the peaks."""
    x = x - x.mean(axis=1, keepdims=True)
    mono = x.mean(axis=0)
    weighted = np.fft.irfft(np.fft.rfft(mono) * a_weight(np.maximum(freqs(len(mono)), 1e-3)), len(mono))
    rms = np.sqrt(np.mean(weighted ** 2))
    gain = 10 ** (rms_db / 20) / (rms + 1e-12)
    # bass-heavy sounds would get boosted too far by A-weighting alone
    gain = min(gain, 10 ** (max_db / 20) / (np.sqrt(np.mean(x ** 2)) + 1e-12))
    gain = min(gain, 0.9 / (np.abs(x).max() + 1e-12))  # keep crackles and drops off the limiter
    x = x * gain
    knee = 0.6
    over = np.abs(x) > knee
    x[over] = np.sign(x[over]) * (knee + (1 - knee) * np.tanh((np.abs(x[over]) - knee) / (1 - knee)))
    return x * 0.75  # headroom for AAC overshoot on sharp transients


# ---------- sounds ----------
#
# v2: each sound is built around the events that make it recognizable
# (droplets, swells, gusts, crackles, chirps, beats), with only a quiet
# noise bed underneath. v1 leaned on steady filtered noise, so most sounds
# blurred into the same hiss.

def tv_filter(x, gain_at, frame=4096, hop=1024):
    """Time-varying filter by circular overlap-add. gain_at(t_sec, f) returns
    the magnitude response for the frame centred at t_sec."""
    n = len(x)
    win = np.hanning(frame + 1)[:-1]
    f = np.maximum(np.fft.rfftfreq(frame, 1 / SR), 1e-3)
    out = np.zeros(n)
    for start in range(0, n, hop):
        idx = (start + np.arange(frame)) % n
        spec = np.fft.rfft(x[idx] * win) * gain_at((start + frame / 2) / SR, f)
        np.add.at(out, idx, np.fft.irfft(spec, frame) * win)
    return out / 1.5  # sum of squared hann windows at 75% overlap


def plip(rng, f0, tau, rise):
    """A water drop: a short sine whose pitch rises as the bubble closes."""
    m = int(tau * 6 * SR)
    t = np.arange(m) / SR
    freq = f0 * np.exp(rise * t)
    ph = 2 * np.pi * np.cumsum(freq) / SR
    return np.sin(ph) * np.exp(-t / tau) * np.minimum(1, t / 0.0008)


def knock(rng, modes, tau, click=0.3):
    """A tap on a surface: a few damped resonant modes plus a contact click."""
    m = int(tau * 6 * SR)
    t = np.arange(m) / SR
    x = sum(a * np.sin(2 * np.pi * fm * t + rng.uniform(0, 6.28)) * np.exp(-t / (tau * d))
            for fm, a, d in modes)
    x = x + click * shaped_noise(rng, m, hp(2000)) * np.exp(-t / 0.0015)
    return x * np.minimum(1, t / 0.0005)


def white_noise(rng, n):
    return stereo(rng, n, lambda r, m: shaped_noise(r, m, lp(9000, 2)), 0.8)


def pink_noise(rng, n):
    return stereo(rng, n, lambda r, m: shaped_noise(r, m, mul(tilt(0.5), lp(11000), hp(25))), 0.8)


def brown_noise(rng, n):
    return stereo(rng, n, lambda r, m: shaped_noise(r, m, mul(tilt(1.0), hp(30), lp(4000))), 0.7)


def fan(rng, n):
    air = stereo(rng, n, lambda r, m: shaped_noise(r, m, mul(tilt(0.6), bp(100, 3000))), 0.5)
    blades = 1 + 0.35 * periodic_sine(n, 17.0) + 0.1 * periodic_sine(n, 34.0, 1.0)
    whir = stereo(rng, n, lambda r, m: shaped_noise(r, m, resonant(420, 9)), 0.3) * 0.5
    motor = 0.10 * periodic_sine(n, 100) + 0.05 * periodic_sine(n, 200) + 0.025 * periodic_sine(n, 300)
    return air * blades * 0.8 + whir * blades + motor


def _scatter(rng, out_lr, bank, rate, gain_range, n, pan_width=0.9, rate_env=None):
    count = rng.poisson(rate * n / SR)
    starts = rng.integers(0, n, count)
    if rate_env is not None:  # thin events where the envelope is low
        starts = starts[rng.random(len(starts)) < rate_env[starts]]
    for s in starts:
        k = bank[rng.integers(len(bank))]
        g = np.exp(rng.uniform(np.log(gain_range[0]), np.log(gain_range[1])))
        lr = pan(k * g, rng.uniform(-pan_width, pan_width))
        place(out_lr[0], lr[0], s)
        place(out_lr[1], lr[1], s)


def _splat_bank(rng, count, lo, hi):
    return [burst(rng, 0.03, resonant(np.exp(rng.uniform(np.log(lo), np.log(hi))), 2), rng.uniform(0.002, 0.008))
            for _ in range(count)]


def rain(rng, n):
    bed = stereo(rng, n, lambda r, m: shaped_noise(r, m, mul(tilt(0.5), bp(600, 7000))), 0.9)
    bed *= 0.10 * (0.8 + 0.4 * envelope(rng, n, 0.05))
    out = np.zeros((2, n))
    plips = [plip(rng, rng.uniform(900, 3200), rng.uniform(0.004, 0.012), rng.uniform(20, 60)) for _ in range(80)]
    _scatter(rng, out, plips, 16, (0.15, 1.0), n)
    _scatter(rng, out, _splat_bank(rng, 60, 1500, 8000), 45, (0.08, 0.5), n)
    _scatter(rng, out, _splat_bank(rng, 20, 500, 1500), 10, (0.2, 0.6), n, 0.6)
    return bed + out


def rain_on_roof(rng, n):
    bed = stereo(rng, n, lambda r, m: shaped_noise(r, m, mul(tilt(0.8), bp(80, 1800))), 0.6) * 0.12
    taps = np.zeros((2, n))
    bank = []
    for _ in range(50):
        base = rng.uniform(280, 750)
        bank.append(knock(rng, [(base, 1, 1), (base * 2.3, 0.5, 0.6), (base * 3.9, 0.25, 0.4)], rng.uniform(0.008, 0.02)))
    _scatter(rng, taps, bank, 22, (0.15, 1.0), n)
    # a gutter dripping into a puddle: the one steady rhythm in the scene
    drip = np.zeros(n)
    pos, k = 0, 0
    while pos < n:
        place(drip, plip(rng, rng.uniform(1100, 1300), 0.02, 25), pos, rng.uniform(0.6, 0.9))
        pos += int(SR * rng.uniform(0.55, 0.9))
    taps += pan(drip, 0.55) * 0.9
    return bed + taps


def _thunder(rng, dur):
    m = int(dur * SR)
    t = np.arange(m) / SR
    out = np.zeros(m)
    for _ in range(rng.integers(2, 5)):  # several rolls per strike
        at = rng.uniform(0, dur * 0.45)
        cutoff = rng.uniform(90, 220)
        body = shaped_noise(rng, m, mul(tilt(1.0), lp(cutoff, 3), hp(22)))
        tt = np.clip(t - at, 0, None)
        env = (t > at) * np.minimum(1, tt / rng.uniform(0.08, 0.5)) * np.exp(-tt / rng.uniform(1.2, 3.0))
        out += body * env * rng.uniform(0.5, 1.0)
    crack = shaped_noise(rng, m, bp(400, 3000)) * np.exp(-t / 0.25) * rng.uniform(0.0, 0.6)
    return (out * (0.5 + envelope(rng, m, 4.0)) + crack)


def thunderstorm(rng, n):
    out = rain(rng, n)
    out += stereo(rng, n, lambda r, m: shaped_noise(r, m, mul(tilt(0.5), bp(400, 5000))), 0.9) * 0.25
    k = max(4, int(n / SR / 22))
    spacing = n // k
    for i in range(k):
        strike = _thunder(rng, rng.uniform(10, 15)) * rng.uniform(3.5, 6.0)
        lr = pan(strike, rng.uniform(-0.6, 0.6))
        start = i * spacing + rng.integers(0, spacing // 3)
        place(out[0], lr[0], start)
        place(out[1], lr[1], start)
    return out


def ocean_waves(rng, n):
    swell, crash_hi, crash_mid, wash = (np.zeros(n) for _ in range(4))
    pos = 0
    while pos < n:
        period = rng.uniform(9, 14)
        big = rng.uniform(0.55, 1.0)
        m = int(period * SR * 1.6)
        t = np.arange(m) / SR
        rise = rng.uniform(2.5, 4.0)
        after = np.clip(t - rise, 0, None)
        place(swell, big * np.where(t < rise, (t / rise) ** 2, np.exp(-after / 2.5)), pos)
        hit = (t >= rise) * np.minimum(1, after / 0.25)
        place(crash_hi, big * hit * np.exp(-after / 1.3), pos)
        place(crash_mid, big * hit * np.exp(-after / 2.6), pos)
        place(wash, big * (t >= rise + 1.5) * np.minimum(1, np.clip(after - 1.5, 0, None) / 1.0) * np.exp(-np.clip(after - 1.5, 0, None) / 3.5), pos)
        pos += int(period * SR)
    low = stereo(rng, n, lambda r, m: shaped_noise(r, m, mul(tilt(1.0), bp(35, 350))), 0.5)
    hi = stereo(rng, n, lambda r, m: shaped_noise(r, m, mul(tilt(0.2), bp(2000, 9000))), 0.9)
    mid = stereo(rng, n, lambda r, m: shaped_noise(r, m, mul(tilt(0.5), bp(400, 2500))), 0.8)
    hiss = stereo(rng, n, lambda r, m: shaped_noise(r, m, mul(tilt(0.3), bp(1500, 6000))), 0.95)
    distant = stereo(rng, n, lambda r, m: shaped_noise(r, m, mul(tilt(1.0), bp(30, 250))), 0.4) * 0.06
    return low * swell * 0.9 + hi * crash_hi * 0.5 + mid * crash_mid * 0.8 + hiss * wash * 0.35 + distant


def stream(rng, n):
    bed = stereo(rng, n, lambda r, m: shaped_noise(r, m, mul(tilt(0.5), bp(250, 3000))), 0.8)
    bed *= 0.07 * (0.6 + 0.8 * envelope(rng, n, 5.0))
    out = np.zeros((2, n))
    bubbles = [plip(rng, np.exp(rng.uniform(np.log(350), np.log(1900))), rng.uniform(0.003, 0.014), rng.uniform(15, 70))
               for _ in range(150)]
    flow = 0.4 + 0.6 * envelope(rng, n, 0.4)
    _scatter(rng, out, bubbles, 90, (0.06, 0.45), n, 0.8, flow)
    return bed + out


def wind(rng, n):
    gust = envelope(rng, n, 0.12) ** 2.5
    gust2 = envelope(rng, n, 0.2) ** 2
    body = stereo(rng, n, lambda r, m: shaped_noise(r, m, mul(tilt(1.0), bp(40, 900))), 0.6)
    out = body * (0.08 + 0.92 * gust) * 0.7
    # whistling: a narrow resonance that bends upward as each gust builds
    for f0, q, g, env in [(520, 25, 0.5, gust), (980, 35, 0.3, gust2), (1650, 45, 0.15, gust * gust2)]:
        src = shaped_noise(rng, n, tilt(0.3))
        fc_at = lambda t, f0=f0, env=env: f0 * (0.8 + 0.5 * env[min(int(t * SR), n - 1)])
        whistle = tv_filter(src, lambda t, f, q=q, fc_at=fc_at: resonant(fc_at(t), q)(f))
        whistle = whistle / (np.std(whistle) + 1e-12) * env * g
        out += pan(whistle, rng.uniform(-0.6, 0.6))
    return out


def fireplace(rng, n):
    roar = stereo(rng, n, lambda r, m: shaped_noise(r, m, mul(tilt(1.0), bp(40, 350))), 0.4)
    roar *= 0.10 * (0.5 + envelope(rng, n, 2.0))
    activity = envelope(rng, n, 0.25) ** 2
    crack = np.zeros((2, n))
    clicks = []
    for _ in range(80):
        m = int(0.012 * SR)
        t = np.arange(m) / SR
        ring = np.sin(2 * np.pi * rng.uniform(2200, 5000) * t) * np.exp(-t / rng.uniform(0.0015, 0.004))
        imp = shaped_noise(rng, m, hp(1500)) * np.exp(-t / rng.uniform(0.0003, 0.001))
        clicks.append(imp + 0.6 * ring)
    pops = [knock(rng, [(rng.uniform(500, 1300), 1, 1), (rng.uniform(1800, 3200), 0.5, 0.5)], rng.uniform(0.006, 0.015), 0.8)
            for _ in range(25)]
    # crackles come in little bursts, like real burning wood
    _scatter(rng, crack, clicks, 22, (0.15, 1.0), n, 0.5, activity)
    _scatter(rng, crack, clicks, 60, (0.05, 0.3), n, 0.6, activity ** 3)
    _scatter(rng, crack, pops, 1.5, (0.5, 1.0), n, 0.4)
    return roar + crack


def night_crickets(rng, n):
    air = stereo(rng, n, lambda r, m: shaped_noise(r, m, mul(tilt(0.8), bp(60, 1500))), 0.8) * 0.04
    out = air
    for _ in range(6):
        carrier = rng.uniform(3900, 5000)
        pulses, pulse_len, gap = rng.integers(2, 5), rng.uniform(0.012, 0.02), rng.uniform(0.01, 0.018)
        m = int(pulses * (pulse_len + gap) * SR) + 1
        t = np.arange(m) / SR
        gate = ((t % (pulse_len + gap)) < pulse_len).astype(float)
        gate = np.convolve(gate, np.hanning(int(0.003 * SR)) / (0.0015 * SR), mode="same")
        chirp = np.sin(2 * np.pi * carrier * t) * gate
        distance = rng.uniform(0.2, 1.0)
        period = rng.uniform(0.45, 1.1)
        lane = np.zeros(n)
        pos = rng.integers(0, int(period * SR))
        while pos < n:
            place(lane, chirp, pos, distance * rng.uniform(0.85, 1.0))
            pos += int(period * SR * rng.uniform(0.97, 1.03))
        lane *= 0.5 + 0.5 * envelope(rng, n, 0.04)
        out = out + pan(lane, rng.uniform(-0.9, 0.9))
    return out


def heartbeat(rng, n, bpm=60):
    out = np.zeros(n)
    beat = SR * 60 / bpm
    for i in range(int(n / beat)):
        s = int(i * beat)
        for delay, f0, dur, g in [(0.0, 48, 0.09, 1.0), (0.3, 62, 0.07, 0.65)]:
            m = int(dur * 4 * SR)
            t = np.arange(m) / SR
            tone = np.sin(2 * np.pi * f0 * t * (1 - 0.25 * t))
            thud = shaped_noise(rng, m, lp(160, 3))
            k = (tone + 0.35 * thud) * np.exp(-t / dur) * np.minimum(1, t / 0.006)
            place(out, k * g * rng.uniform(0.95, 1.0), s + int(delay * SR))
    womb = shaped_noise(rng, n, mul(tilt(1.0), bp(25, 200))) * 0.03
    return pan(out + womb, 0.0) * np.sqrt(2)


SOUNDS = {
    "rain": rain,
    "rain_on_roof": rain_on_roof,
    "thunderstorm": thunderstorm,
    "ocean_waves": ocean_waves,
    "stream": stream,
    "wind": wind,
    "fireplace": fireplace,
    "night_crickets": night_crickets,
    "white_noise": white_noise,
    "pink_noise": pink_noise,
    "brown_noise": brown_noise,
    "fan": fan,
    "heartbeat": heartbeat,
}


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "out"
    secs = float(sys.argv[2]) if len(sys.argv) > 2 else 120
    os.makedirs(out_dir, exist_ok=True)
    n = int(secs * SR)
    only = sys.argv[3:] or list(SOUNDS)
    for i, name in enumerate(SOUNDS):
        if name not in only:
            continue
        rng = np.random.default_rng(SEED + i)
        x = finish(SOUNDS[name](rng, n))
        wav = os.path.join(out_dir, name + ".wav")
        wavfile.write(wav, SR, (x.T * 32767).astype(np.int16))
        m4a = os.path.join(out_dir, name + ".m4a")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "aac", "-b:a", "160k", m4a], check=True)
        os.remove(wav)
        print(name, "ok", os.path.getsize(m4a) // 1024, "KB")


if __name__ == "__main__":
    main()
