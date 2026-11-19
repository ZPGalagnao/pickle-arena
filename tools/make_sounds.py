"""Synthesizes every sound effect and music loop used by Pickle Arena.

All audio is generated from scratch with NumPy (no samples, no licenses).
Run:  python tools/make_sounds.py      ->  writes assets/audio/*.wav
"""
from __future__ import annotations

import os
import wave

import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "audio")
rng = np.random.default_rng(7)


# ------------------------------------------------------------------ helpers
def t_axis(dur):
    return np.arange(int(round(dur * SR))) / SR


def env_adsr(n, a=0.005, d=0.05, s=0.6, r=0.1):
    e = np.ones(n) * s
    na, nd, nr = int(a * SR), int(d * SR), int(r * SR)
    na, nd = max(na, 1), max(nd, 1)
    e[:na] = np.linspace(0, 1, na)
    e[na:na + nd] = np.linspace(1, s, min(nd, max(0, n - na)))
    if nr > 0 and nr < n:
        e[-nr:] *= np.linspace(1, 0, nr)
    return e


def exp_decay(n, tau):
    return np.exp(-np.arange(n) / SR / tau)


def band(x, lo, hi):
    """FFT band-pass."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X[(f < lo) | (f > hi)] = 0
    return np.fft.irfft(X, len(x))


def formant(x, centers, widths, gains):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    H = np.zeros_like(f)
    for c, w, g in zip(centers, widths, gains):
        H += g * np.exp(-0.5 * ((f - c) / w) ** 2)
    return np.fft.irfft(X * H, len(x))


def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.zeros_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def saw(freq, t):
    return 2 * ((freq * t) % 1.0) - 1


def square(freq, t, duty=0.5):
    return np.where((freq * t) % 1.0 < duty, 1.0, -1.0)


def noise(n):
    return rng.uniform(-1, 1, n)


def norm(x, peak=0.9):
    m = np.max(np.abs(x)) + 1e-9
    return x / m * peak


def write(name, x, peak=0.9):
    x = norm(x, peak)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


# -------------------------------------------------------- paddle & court
def pock(freq=1150, dur=0.12, body=0.6, click=0.5):
    t = t_axis(dur)
    n = len(t)
    tone = np.sin(2 * np.pi * freq * t) * exp_decay(n, 0.018)
    tone += 0.5 * np.sin(2 * np.pi * freq * 1.52 * t) * exp_decay(n, 0.01)
    thump = np.sin(2 * np.pi * 180 * t) * exp_decay(n, 0.025) * body
    clk = band(noise(n), 2000, 7000) * exp_decay(n, 0.004) * click
    return tone + thump + clk


def whoosh(dur=0.25, lo=400, hi=2500, rise=True):
    t = t_axis(dur)
    n = len(t)
    x = noise(n)
    out = np.zeros(n)
    seg = 8
    for k in range(seg):
        a, b = k * n // seg, (k + 1) * n // seg
        frac = k / (seg - 1)
        c = lo + (hi - lo) * (frac if rise else 1 - frac)
        out[a:b] = band(x, c * 0.6, c * 1.4)[a:b]
    return out * np.sin(np.pi * np.linspace(0, 1, n)) ** 1.5


def make_court_sounds():
    write("hit_power", pock(1250, 0.14, body=0.9, click=0.8), 0.95)
    write("hit_soft", pock(950, 0.1, body=0.3, click=0.2), 0.55)
    high = pock(1100, 0.12, 0.5, 0.4)
    high += whoosh(0.12, 800, 2200)[: len(high)] * 0.3
    write("hit_high", high, 0.75)
    write("serve", pock(1050, 0.12, body=0.5, click=0.3), 0.7)
    t = t_axis(0.12)
    write("bounce", np.sin(2 * np.pi * 150 * t) * exp_decay(len(t), 0.02) + band(noise(len(t)), 300, 1500)
          * exp_decay(len(t), 0.008) * 0.6, 0.6)
    t = t_axis(0.35)
    net = band(noise(len(t)), 200, 1800) * exp_decay(len(t), 0.08) + np.sin(2 * np.pi * 90 * t) * exp_decay(len(t), 0.05)
    write("net", net, 0.7)
    # sneaker squeak + soft footstep
    t = t_axis(0.09)
    f = 2400 + 900 * np.sin(np.pi * t / t[-1])
    squeak = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * t / t[-1]) ** 2
    write("step1", squeak * 0.6 + band(noise(len(t)), 100, 800) * exp_decay(len(t), 0.01), 0.35)
    t = t_axis(0.07)
    write("step2", band(noise(len(t)), 80, 600) * exp_decay(len(t), 0.012) + np.sin(2 * np.pi * 110 * t)
          * exp_decay(len(t), 0.015), 0.35)
    write("swing", whoosh(0.22, 500, 2600), 0.5)
    t = t_axis(0.05)
    write("ui_click", np.sin(2 * np.pi * 1800 * t) * exp_decay(len(t), 0.008) + np.sin(2 * np.pi * 900 * t)
          * exp_decay(len(t), 0.012), 0.5)


# --------------------------------------------------------------- specials
def make_special_sounds():
    # FIRE: roar + rising whoosh + crackle
    dur = 1.3
    t = t_axis(dur)
    n = len(t)
    roar = lowpass(noise(n), 500) * 3 * env_adsr(n, 0.05, 0.3, 0.7, 0.6)
    crackle = np.zeros(n)
    for _ in range(90):
        i = rng.integers(0, n - 300)
        crackle[i:i + 300] += noise(300) * exp_decay(300, 0.003) * rng.uniform(0.2, 1)
    write("special_fire", roar + whoosh(dur, 300, 3500) * 0.8 + band(crackle, 1500, 6000) * 0.6)
    # ICE: shimmering chimes + crack
    dur = 1.4
    t = t_axis(dur)
    n = len(t)
    x = np.zeros(n)
    for k in range(14):
        f = rng.choice([1568, 1760, 2093, 2349, 2637, 3136])
        st = int(rng.uniform(0, 0.7) * SR)
        seg = t[: n - st]
        x[st:] += np.sin(2 * np.pi * f * seg) * exp_decay(len(seg), 0.35) * 0.5
    crack = band(noise(n), 1000, 8000) * exp_decay(n, 0.02)
    write("special_ice", x + crack * 1.2)
    # THUNDER: zap sweep + rumble
    dur = 1.4
    t = t_axis(dur)
    n = len(t)
    f = 1800 * np.exp(-t * 4) + 120
    zap = saw(1, np.cumsum(f) / SR) * exp_decay(n, 0.15)
    rumble = lowpass(noise(n), 160) * 4 * env_adsr(n, 0.1, 0.4, 0.6, 0.6)
    write("special_thunder", zap * 0.7 + rumble + band(noise(n), 2000, 8000) * exp_decay(n, 0.03))
    # PHANTOM: eerie detuned vibrato whoosh
    dur = 1.3
    t = t_axis(dur)
    n = len(t)
    vib = 6 * np.sin(2 * np.pi * 5 * t)
    eerie = sum(np.sin(2 * np.pi * (f + vib) * t) for f in (440, 446, 659, 663)) / 4
    write("special_phantom", eerie * env_adsr(n, 0.4, 0.2, 0.8, 0.4) + whoosh(dur, 1500, 300, rise=False) * 0.5)
    # TORNADO: swirling wind
    dur = 1.4
    t = t_axis(dur)
    n = len(t)
    wind = np.zeros(n)
    base = noise(n)
    for k in range(10):
        a, b = k * n // 10, (k + 1) * n // 10
        c = 500 + 900 * (0.5 + 0.5 * np.sin(k * 1.3))
        wind[a:b] = band(base, c * 0.7, c * 1.3)[a:b]
    write("special_tornado", wind * env_adsr(n, 0.2, 0.3, 0.8, 0.5) * (1 + 0.5 * np.sin(2 * np.pi * 6 * t)))
    # slow-motion "bwoom"
    dur = 1.0
    t = t_axis(dur)
    n = len(t)
    f = 220 * np.exp(-t * 2.2) + 40
    write("slowmo", np.sin(2 * np.pi * np.cumsum(f) / SR) * env_adsr(n, 0.01, 0.2, 0.7, 0.5) +
          lowpass(noise(n), 300) * exp_decay(n, 0.3) * 2, 0.8)
    # special ready: rising arpeggio
    notes = [523.25, 659.25, 783.99, 1046.5]
    parts = []
    for f in notes:
        t = t_axis(0.09)
        parts.append((square(f, t, 0.25) * 0.4 + np.sin(2 * np.pi * f * t)) * exp_decay(len(t), 0.08))
    write("ready", np.concatenate(parts), 0.6)


def jingle(notes, step=0.12, tail=0.4, wave_fn=None):
    total = int((step * len(notes) + tail) * SR)
    x = np.zeros(total)
    for k, f in enumerate(notes):
        st = int(k * step * SR)
        t = t_axis(step + tail)
        tone = np.sin(2 * np.pi * f * t) + 0.35 * square(f, t, 0.3) + 0.2 * np.sin(2 * np.pi * 2 * f * t)
        seg = tone * exp_decay(len(t), 0.25)
        x[st:st + len(seg)] += seg[: total - st]
    return x


def make_jingles():
    write("point_win", jingle([659.25, 783.99, 1046.5]), 0.6)
    write("point_lose", jingle([392.0, 311.13], step=0.18), 0.5)
    fan = jingle([523.25, 659.25, 783.99, 1046.5, 783.99, 1046.5, 1318.5], step=0.14, tail=1.2)
    t = t_axis(len(fan) / SR)
    chord = sum(np.sin(2 * np.pi * f * t) for f in (523.25, 659.25, 783.99)) / 3
    chord *= np.clip((t - 0.85) * 4, 0, 1) * np.exp(-np.clip(t - 0.85, 0, None) * 1.2)
    write("win_fanfare", fan + chord * 1.5, 0.85)
    write("lose", jingle([392.0, 369.99, 349.23, 293.66], step=0.32, tail=0.9), 0.6)


# ------------------------------------------------------------------ crowd
def crowd(dur, n_voices=40, cheer=True, glide=1.25, vowel=((750, 1200), (900, 1500))):
    n = int(dur * SR)
    t = t_axis(dur)
    x = np.zeros(n)
    for _ in range(n_voices):
        f0 = rng.uniform(110, 290)
        start = rng.uniform(0, 0.35) * (1 if cheer else 0.5)
        f = f0 * (1 + (glide - 1) * np.clip((t - start) / 0.4, 0, 1)) * (1 + 0.02 * np.sin(2 * np.pi * rng.uniform(3, 7) * t))
        src = saw(1, np.cumsum(f) / SR) + 0.6 * noise(n)
        v = vowel[rng.integers(0, len(vowel))]
        voiced = formant(src, [v[0], v[1], 2600], [120, 180, 300], [1.0, 0.7, 0.25])
        e = np.clip((t - start) / 0.25, 0, 1) * np.clip((dur - t) / (0.4 + rng.uniform(0, 0.5)), 0, 1)
        x += voiced * e * rng.uniform(0.4, 1)
    return x


def make_crowd():
    cheer = crowd(2.6, 46, True, 1.3, ((750, 1200), (650, 1100), (450, 2000)))
    n = len(cheer)
    t = t_axis(n / SR)
    whistles = np.zeros(n)
    for _ in range(4):
        st = int(rng.uniform(0.2, 1.2) * SR)
        ln = int(0.5 * SR)
        tt = t_axis(ln / SR)
        f = 2200 + 600 * np.sin(np.pi * tt / tt[-1])
        whistles[st:st + ln] += np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * tt / tt[-1]) * 0.3
    claps = np.zeros(n)
    for _ in range(260):
        i = rng.integers(0, n - 400)
        claps[i:i + 400] += band(noise(400), 800, 5000) * exp_decay(400, 0.004)
    write("crowd_cheer", cheer + whistles * np.max(np.abs(cheer)) + claps * 0.6 * np.max(np.abs(cheer)) * np.clip((t - 0.3), 0, 1))
    aww = crowd(1.6, 36, True, 0.8, ((700, 1100), (500, 900)))
    write("crowd_aww", aww, 0.7)
    # applause
    dur = 3.2
    n = int(dur * SR)
    t = t_axis(dur)
    claps = np.zeros(n)
    for _ in range(1400):
        i = rng.integers(0, n - 400)
        claps[i:i + 400] += band(noise(400), 700, 6000) * exp_decay(400, 0.005) * rng.uniform(0.3, 1)
    write("applause", claps * env_adsr(n, 0.3, 0.5, 0.8, 1.2), 0.8)
    # ambience loop: murmuring crowd (crossfaded so it loops seamlessly)
    dur = 8.0
    n = int(dur * SR)
    x = np.zeros(n + SR)
    for _ in range(70):
        st = rng.integers(0, n)
        ln = int(rng.uniform(0.3, 1.2) * SR)
        f0 = rng.uniform(100, 240)
        tt = t_axis(ln / SR)
        src = saw(1, np.cumsum(f0 * (1 + 0.05 * np.sin(2 * np.pi * 4 * tt))) / SR) + 0.5 * noise(ln)
        syl = formant(src, [rng.uniform(400, 900), rng.uniform(1000, 1800)], [150, 200], [1, 0.6])
        syl *= np.sin(np.pi * tt / tt[-1]) ** 2
        end = min(len(x), st + ln)
        x[st:end] += syl[: end - st] * rng.uniform(0.3, 1)
    x[:SR] += x[n:n + SR]  # wrap the tail onto the start
    amb = lowpass(x[:n], 1600)
    write("crowd_ambience", amb, 0.5)


# ------------------------------------------------------------------ music
NOTE = {n: 440 * 2 ** ((i - 9) / 12) for i, n in enumerate(["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"])}


def nf(name, octave):
    return NOTE[name] * 2 ** (octave - 4)


def music(bpm, chords, melody, kick_pattern, name, energy=1.0):
    beat = 60 / bpm
    bars = len(chords)
    dur = bars * 4 * beat
    n = int(dur * SR)
    mix = np.zeros(n + SR * 2)

    def place(sig, at):
        st = int(at * SR)
        mix[st:st + len(sig)] += sig[: len(mix) - st]

    for bar, (root, quality) in enumerate(chords):
        bar_t = bar * 4 * beat
        third = 3 if quality == "m" else 4
        rf = nf(root, 2)
        # bass: 8th notes on the root, octave jumps
        for k in range(8):
            f = rf * (2 if k % 4 == 3 else 1)
            t = t_axis(beat / 2 * 0.95)
            sig = lowpass(saw(f, t), 700) * env_adsr(len(t), 0.005, 0.08, 0.6, 0.03) * 0.9
            place(sig, bar_t + k * beat / 2)
        # pad: detuned saws, soft attack
        t = t_axis(4 * beat)
        pad = np.zeros(len(t))
        for semi in (0, third, 7, 12):
            f = rf * 4 * 2 ** (semi / 12)
            pad += saw(f * 1.003, t) + saw(f * 0.997, t)
        pad = lowpass(pad, 1600) * env_adsr(len(t), 0.25, 0.4, 0.8, 0.4) * 0.12 * energy
        place(pad, bar_t)
        # drums
        for k in range(4):
            bt = bar_t + k * beat
            if k in kick_pattern:
                t = t_axis(0.25)
                f = 140 * np.exp(-t * 30) + 45
                place(np.sin(2 * np.pi * np.cumsum(f) / SR) * exp_decay(len(t), 0.09) * 1.1, bt)
            if k in (1, 3):
                t = t_axis(0.2)
                snare = band(noise(len(t)), 900, 6000) * exp_decay(len(t), 0.05) + np.sin(2 * np.pi * 190 * t) * exp_decay(len(t), 0.03)
                place(snare * 0.55, bt)
            for h in range(2 if energy < 1 else 4):
                t = t_axis(0.05)
                place(band(noise(len(t)), 6000, 10000) * exp_decay(len(t), 0.012) * (0.22 if h % 2 == 0 else 0.13),
                      bt + h * beat / (2 if energy < 1 else 4))
    # lead melody: (beat offset, note, octave, length in beats)
    for (b, note, octv, ln) in melody:
        if note is None:
            continue
        t = t_axis(ln * beat)
        f = nf(note, octv) * (1 + 0.006 * np.sin(2 * np.pi * 5.5 * t))
        sig = (square(f, t, 0.3) * 0.5 + np.sin(2 * np.pi * f * t)) * env_adsr(len(t), 0.01, 0.1, 0.55, 0.06)
        place(sig * 0.32, b * beat)
    tail = mix[n:n + SR * 2].copy()
    out = mix[:n]
    out[: len(tail)] += tail  # seamless loop
    write(name, out, 0.8)


def make_music():
    prog = [("F", ""), ("G", ""), ("A", "m"), ("C", "")] * 4
    # catchy pentatonic motif repeated with variations (in beats)
    motif = [(0, "A", 5, 0.5), (0.5, "C", 6, 0.5), (1, "D", 6, 0.5), (1.5, "C", 6, 0.5), (2, "A", 5, 1),
             (3, "G", 5, 0.5), (3.5, "A", 5, 0.5)]
    motif2 = [(0, "C", 6, 0.5), (0.5, "D", 6, 0.5), (1, "E", 6, 1), (2, "D", 6, 0.5), (2.5, "C", 6, 0.5),
              (3, "A", 5, 1)]
    melody = []
    for bar in range(16):
        if bar % 4 == 3 and bar < 15:
            continue  # breathing room
        m = motif if (bar // 2) % 2 == 0 else motif2
        for (b, nt, o, ln) in m:
            melody.append((bar * 4 + b, nt, o, ln))
    music(124, prog, melody, (0, 1, 2, 3), "music_game", energy=1.0)
    chill = [("C", ""), ("A", "m"), ("F", ""), ("G", "")] * 4
    mel2 = []
    for bar in range(16):
        if bar % 2 == 1:
            continue
        for (b, nt, o, ln) in [(0, "E", 5, 1), (1, "G", 5, 1), (2, "A", 5, 1.5), (3.5, "G", 5, 0.5),
                               (4, "E", 5, 1), (5, "D", 5, 1), (6, "C", 5, 2)]:
            mel2.append((bar * 4 + b, nt, o, ln))
    music(100, chill, mel2, (0, 2), "music_menu", energy=0.7)


if __name__ == "__main__":
    make_court_sounds()
    make_special_sounds()
    make_jingles()
    make_crowd()
    make_music()
    total = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT))
    print(f"wrote {len(os.listdir(OUT))} files, {total / 1e6:.1f} MB -> {OUT}")
