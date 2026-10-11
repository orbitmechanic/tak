#!/usr/bin/env python3
"""Procedural SFX generator for Tak. Regenerate with: python3 tools/make_sfx.py"""
import math
import os
import random
import wave

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sounds")


def clamp(x):
    return max(-1.0, min(1.0, x))


def knock(f0, dur, decay, harmonics=(1.0, 0.5, 0.25), click=0.5, rng=None):
    rng = rng or random.Random(7)
    n = int(SR * dur)
    buf = []
    for i in range(n):
        t = i / SR
        env = math.exp(-decay * t)
        v = sum(a * math.sin(2 * math.pi * f0 * m * t) for m, a in enumerate(harmonics, start=1))
        if i < int(0.0015 * SR):
            v += click * rng.uniform(-1, 1) * math.exp(-t * 1400)
        buf.append(clamp(v * env * 0.7))
    return buf


def noise_sweep(dur, f_start, f_end, gain=0.5, attack=0.02, release=0.6):
    n = int(SR * dur)
    buf = []
    phase = 0.0
    last = 0.0
    rng = random.Random(11)
    for i in range(n):
        t = i / max(1, n - 1)
        white = rng.uniform(-1, 1)
        last = last + (white - last) * (f_start + (f_end - f_start) * t) * 0.06
        env = min(1.0, t / max(attack / dur, 1e-4)) * (1.0 - t) ** release
        buf.append(clamp(last * 4.0 * env * gain))
    return buf


def concat(*parts, gap=0.0):
    out = []
    for p in parts:
        out.extend(p)
        out.extend([0.0] * int(gap * SR))
    return out


def normalize(buf, peak=0.85):
    m = max((abs(x) for x in buf), default=1.0)
    return [x / max(m, 1e-6) * peak for x in buf]


def write(name, buf, gain=1.0):
    path = os.path.join(OUT, name)
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = b"".join(struct_pack(int(clamp(x * gain) * 32000)) for x in buf)
        w.writeframes(frames)
    print(name, round(len(buf) / SR, 3), "s")


def struct_pack(v):
    return (max(-32000, min(32000, v))).to_bytes(2, "little", signed=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    rng = random.Random(42)

    write("place.wav", normalize(concat(
        knock(205, 0.11, 26, click=0.7),
    )))
    write("move.wav", normalize(concat(
        noise_sweep(0.13, 0.25, 0.8, gain=0.35),
        knock(235, 0.08, 34, click=0.4),
    )))
    write("tick.wav", normalize(concat(
        knock(265, 0.06, 52, click=0.55, rng=rng),
    )))
    write("flatten.wav", normalize(concat(
        knock(118, 0.16, 18, harmonics=(1.0, 0.65, 0.4, 0.2), click=0.9),
        noise_sweep(0.07, 0.7, 0.2, gain=0.3),
    )))
    arp = [392, 494, 587, 784]
    win = []
    for k, f in enumerate(arp):
        win = concat(win, knock(f, 0.22, 9 + k, click=0.3), gap=0.085)
    write("win.wav", normalize(win))
    lose = []
    for f in [392, 311, 262]:
        lose = concat(lose, knock(f, 0.26, 8, click=0.25), gap=0.1)
    write("lose.wav", normalize(lose))
    draw = []
    for f in [330, 330]:
        draw = concat(draw, knock(f, 0.2, 10, click=0.2), gap=0.16)
    write("draw.wav", normalize(draw))
    chirp = [clamp(0.5 * math.sin(2 * math.pi * (300 + 400 * (i / SR)) * (i / SR) * 4) * math.exp(-i / SR * 22)) for i in range(int(SR * 0.09))]
    write("undo.wav", normalize(concat(chirp, knock(190, 0.05, 40, click=0.3))))


if __name__ == "__main__":
    main()
