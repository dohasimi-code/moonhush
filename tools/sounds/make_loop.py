"""Turn a real recording into a seamless Moonhush loop.

Steps: decode any format with ffmpeg, high-pass away rumble below 25 Hz, pick
the steadiest stretch of the recording (skipping a few seconds at each end,
where handling noise usually lives), crossfade its tail into its head so the
loop has no seam, normalize perceived loudness to the same level as the rest
of the library, and encode as AAC.

Usage: python3 make_loop.py input_file sound_id [seconds=120] [highpass_hz=25] [start_sec]
(a higher highpass removes traffic or handling rumble; start_sec forces where the loop begins)
Output: loops/<sound_id>.m4a next to this script.
"""
import os
import subprocess
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate import SR, finish, freqs  # noqa: E402

XFADE = 4.0  # seconds of equal-power crossfade at the loop point


def decode(path):
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-f", "f32le", "-ac", "2", "-ar", str(SR), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).reshape(-1, 2).T.astype(np.float64)


def highpass(x, fc=25.0):
    f = np.maximum(freqs(x.shape[1]), 1e-3)
    h = 1 / np.sqrt(1 + (fc / f) ** 4)
    return np.fft.irfft(np.fft.rfft(x, axis=1) * h, x.shape[1], axis=1)


def steadiest(x, length):
    """Start index of the window of `length` samples whose loudness varies least."""
    n = x.shape[1]
    trim = min(int(3 * SR), max(0, (n - length) // 2))
    hop = SR // 2
    m = x.mean(0)
    best, best_start = None, trim
    for s in range(trim, max(trim, n - trim - length) + 1, hop):
        seg = m[s:s + length]
        blocks = seg[: len(seg) // SR * SR].reshape(-1, SR)
        db = 20 * np.log10(np.sqrt((blocks ** 2).mean(1)) + 1e-9)
        score = db.std()
        if best is None or score < best:
            best, best_start = score, s
    return best_start


def make_loop(x, secs, start=None):
    want = int(secs * SR)
    fade = int(XFADE * SR)
    usable = x.shape[1] - 2 * min(int(3 * SR), x.shape[1] // 10)
    length = min(want, usable - fade) if usable > fade * 3 else x.shape[1] - fade
    if start is None:
        start = steadiest(x, length + fade)
    seg = x[:, start:start + length + fade]
    t = np.linspace(0, np.pi / 2, fade)
    head, tail = seg[:, :fade], seg[:, length:length + fade]
    body = seg[:, :length].copy()
    body[:, :fade] = head * np.sin(t) + tail * np.cos(t)  # tail fades out into head
    return body


def main():
    src, sound_id = sys.argv[1], sys.argv[2]
    secs = float(sys.argv[3]) if len(sys.argv) > 3 else 120
    hp_hz = float(sys.argv[4]) if len(sys.argv) > 4 else 25.0
    start = int(float(sys.argv[5]) * SR) if len(sys.argv) > 5 else None
    x = highpass(decode(src), hp_hz)
    loop = finish(make_loop(x, secs, start))
    out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "loops")
    os.makedirs(out_dir, exist_ok=True)
    wav = os.path.join(out_dir, sound_id + ".tmp.wav")
    from scipy.io import wavfile
    wavfile.write(wav, SR, (loop.T * 32767).astype(np.int16))
    out = os.path.join(out_dir, sound_id + ".m4a")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "aac", "-b:a", "160k", out], check=True)
    os.remove(wav)
    print(f"{sound_id}: {loop.shape[1] / SR:.1f}s loop -> {out}")


if __name__ == "__main__":
    main()
