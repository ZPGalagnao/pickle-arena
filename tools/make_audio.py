"""Builds the final game audio from free recordings (see AUDIO_CREDITS.md).

Run after tools/make_sounds.py:
    python tools/make_audio.py <folder with the downloaded files>

It trims, fades, mixes and converts the recordings to small OGG files in
assets/audio, and removes the synthesized WAVs they replace.
"""
from __future__ import annotations

import glob
import os
import sys

import numpy as np
import soundfile as sf

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "audio")
rng = np.random.default_rng(3)


def load(path, start=0.0, dur=None, mono=True, sr=SR):
    x, r = sf.read(path, dtype="float32", always_2d=True)
    a = int(start * r)
    b = len(x) if dur is None else min(len(x), a + int(dur * r))
    x = x[a:b]
    if mono:
        x = x.mean(axis=1)
    if r != sr:
        n = int(len(x) * sr / r)
        t_old = np.linspace(0, 1, len(x), endpoint=False)
        t_new = np.linspace(0, 1, n, endpoint=False)
        if x.ndim == 1:
            x = np.interp(t_new, t_old, x).astype(np.float32)
        else:
            x = np.stack([np.interp(t_new, t_old, x[:, c]) for c in range(x.shape[1])], axis=1).astype(np.float32)
    return x


def fade(x, fin=0.01, fout=0.05, sr=SR):
    x = x.copy()
    a, b = int(fin * sr), int(fout * sr)
    if a > 0:
        ramp = np.linspace(0, 1, a)
        x[:a] = (x[:a].T * ramp).T
    if b > 0:
        ramp = np.linspace(1, 0, b)
        x[-b:] = (x[-b:].T * ramp).T
    return x


def norm(x, peak=0.9):
    m = float(np.max(np.abs(x))) + 1e-9
    return (x / m * peak).astype(np.float32)


def trim_lead(x, thresh=0.02):
    idx = np.argmax(np.abs(x) > thresh * np.max(np.abs(x)))
    return x[max(0, idx - int(0.003 * SR)):]


def band(x, lo, hi, sr=SR):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / sr)
    X[(f < lo) | (f > hi)] = 0
    return np.fft.irfft(X, len(x)).astype(np.float32)


def pop(freq, dur, bright=0.6):
    """Hollow plastic 'pop' of a pickleball (adds the highs the 8 kHz recording lacks)."""
    t = np.arange(int(dur * SR)) / SR
    n = len(t)
    tone = np.sin(2 * np.pi * freq * t) * np.exp(-t / 0.012)
    tone += 0.45 * np.sin(2 * np.pi * freq * 1.48 * t) * np.exp(-t / 0.008)
    click = band(rng.uniform(-1, 1, n).astype(np.float32), 2500, 9000) * np.exp(-t / 0.0025) * bright
    return (tone + click).astype(np.float32)


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n, dtype=np.float32)
    for p in parts:
        out[: len(p)] += p
    return out


def write(name, x, peak=0.9, sr=SR, quality=0.4):
    """quality: 0 = best/biggest .. 1 = smallest (Vorbis compression level)."""
    path = os.path.join(OUT, name + ".ogg")
    data = norm(x, peak)
    channels = 1 if data.ndim == 1 else data.shape[1]
    # write in small blocks: libsndfile's Vorbis encoder overflows the stack on big writes
    with sf.SoundFile(path, "w", sr, channels, format="OGG", subtype="VORBIS", compression_level=quality) as out:
        for i in range(0, len(data), 2048):
            out.write(data[i:i + 2048])
    return path


def loop_crossfade(x, xf, sr=SR):
    """Make a seamless loop by blending the tail into the head."""
    n = int(xf * sr)
    head, body, tail = x[:n], x[n:-n], x[-n:]
    ramp = np.linspace(0, 1, n)
    if x.ndim == 2:
        ramp = ramp[:, None]
    blended = tail * (1 - ramp) + head * ramp
    return np.concatenate([blended, body]).astype(np.float32)


def main(src):
    f = lambda p: os.path.join(src, p)
    crowd = sorted(glob.glob(f("x/crowd/*/*.mp3")))
    crowd_by = {os.path.basename(p).split(" - ")[2].strip(): p for p in crowd}
    swish = f("x/swishes/swishes/swish-1.wav")
    swish2 = f("x/swishes/swishes/swish-3.wav")
    ann = f("x/announcer/Sports")
    written = []

    # ---- paddle and court (recordings + synthesized brightness)
    bat = trim_lead(load(f("pingpongbat.ogg")))[: int(0.25 * SR)]
    bat = fade(bat, 0.001, 0.08)
    board = trim_lead(load(f("pingpongboard_0.ogg")))
    written.append(write("hit_power", mix(bat * 1.0, pop(1350, 0.15, 0.9) * 0.55), 0.95))
    written.append(write("hit_soft", mix(bat * 0.9, pop(980, 0.12, 0.35) * 0.3), 0.7))
    written.append(write("serve", mix(bat * 0.95, pop(1150, 0.13, 0.5) * 0.4), 0.8))
    sw = fade(load(swish), 0.002, 0.03)
    written.append(write("hit_high", mix(bat * 0.9, pop(1100, 0.12, 0.45) * 0.35, np.pad(sw * 0.35, (int(0.02 * SR), 0))), 0.8))
    slow_board = load(f("pingpongboard_0.ogg"), sr=int(SR * 1.35))  # pitched down = duller court bounce
    t = np.arange(int(0.1 * SR)) / SR
    thump = (np.sin(2 * np.pi * 140 * t) * np.exp(-t / 0.02)).astype(np.float32)
    written.append(write("bounce", mix(fade(trim_lead(slow_board), 0.001, 0.05) * 0.8, thump * 0.6), 0.6))
    written.append(write("swing", mix(sw, fade(load(swish2), 0.002, 0.03) * 0.5), 0.6))

    # ---- crowd (Gregor Quendel, CC-BY 4.0) and applause (CC0)
    written.append(write("crowd_cheer", fade(load(crowd_by["04"], 0.2, 4.0), 0.15, 1.4), 0.85))
    written.append(write("crowd_big", fade(load(crowd_by["03"], 1.0, 6.0), 0.2, 2.0), 0.9))
    written.append(write("crowd_aww", fade(load(crowd_by["07"], 3.0, 3.0), 0.3, 1.2), 0.5))
    written.append(write("applause", fade(load(f("applause-clapping-church-crowd-immersive.wav"), 4.0, 5.0), 0.3, 1.8), 0.8))
    amb = load(crowd_by["10"], 2.0, 26.0, sr=32000)
    written.append(write("crowd_ambience", loop_crossfade(amb, 2.0, sr=32000), 0.6, sr=32000, quality=0.6))

    # ---- announcer (Aimee Smith / WinterWalrus, CC-BY 4.0)
    for name, rel in [("vo_ace", "golf/ace.wav"), ("vo_match_point", "tennis/match_point.wav"),
                      ("vo_game_point", "tennis/game_point.wav"), ("vo_congrats", "tennis/congratulations.wav"),
                      ("vo_victory", "bowling/victory.wav"), ("vo_game_over", "tennis/game_over.wav")]:
        written.append(write(name, fade(trim_lead(load(os.path.join(ann, rel))), 0.003, 0.05), 0.9))

    # ---- music (CC-BY 3.0): stereo, compressed
    game = load(f("Shakex20andx20Bake_0.mp3"), mono=False)
    written.append(write("music_game", game, 0.8, quality=0.75))
    menu = load(f("Viktorx20Krausx20-x20Wellx20oiledx2Cx20shinyx20Oscillators.mp3"), 0, 150, mono=False)
    written.append(write("music_menu", fade(menu, 0.5, 4.0), 0.8, quality=0.75))

    # remove the synthesized versions these replace
    for old in ["hit_power", "hit_soft", "hit_high", "serve", "bounce", "swing", "crowd_cheer", "crowd_aww",
                "applause", "crowd_ambience", "music_game", "music_menu", "win_fanfare", "lose"]:
        p = os.path.join(OUT, old + ".wav")
        if os.path.exists(p):
            os.remove(p)
    for p in written:
        i = sf.info(p)
        print(f"{os.path.basename(p):24s} {i.duration:6.2f}s {os.path.getsize(p) / 1000:7.1f} KB")
    total = sum(os.path.getsize(os.path.join(OUT, x)) for x in os.listdir(OUT))
    print(f"assets/audio total: {total / 1e6:.2f} MB, {len(os.listdir(OUT))} files")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
