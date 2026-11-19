"""Synthesize crystal chime notes for matches (pentatonic, rising with the cascade combo).
python tools/make_chimes.py  -> assets/audio/chime_0..9.wav (converted to ogg by ffmpeg)"""
import numpy as np, wave, subprocess, os
SR = 44100
ROOT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
base = 523.25  # C5
steps = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21]   # major pentatonic
for i, st in enumerate(steps):
    f = base * 2 ** (st / 12)
    dur = 1.1
    t = np.arange(int(SR * dur)) / SR
    sig = np.zeros_like(t)
    # bell-ish partials (slightly inharmonic) with their own decays
    for mult, amp, dec in ((1.0, 1.0, 3.2), (2.01, 0.45, 5.0), (3.02, 0.25, 7.0), (4.17, 0.18, 9.0), (5.43, 0.10, 12.0), (0.5, 0.15, 4.0)):
        sig += amp * np.sin(2 * np.pi * f * mult * t + mult) * np.exp(-dec * t)
    # sparkle: short noisy shimmer on top
    rng = np.random.default_rng(i)
    sh = rng.standard_normal(len(t)) * np.exp(-40 * t) * 0.08
    sig += np.convolve(sh, np.ones(3) / 3, mode="same")
    att = np.minimum(1, t / 0.004)
    sig *= att
    sig = sig / np.max(np.abs(sig)) * 0.6
    p = os.path.join(ROOT, "chime_%d.wav" % i)
    with wave.open(p, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((sig * 32767).astype(np.int16).tobytes())
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", p, "-c:a", "libvorbis", "-q:a", "5", p[:-4] + ".ogg"], check=True)
    os.remove(p)
print("ok")
