"""Pickle Arena - train the AI opponent ("PickleBrain").

Two small neural networks (MLPs) are trained on data produced by the physics
simulator in `pickle_sim.py`:

1. Trajectory Predictor (multi-output regression + classification)
   Input : ball position/velocity + a "query plane" y_p on the AI's side.
   Output: where the ball will be when it reaches that depth (x, height, time),
           whether it reaches it at all, how many bounces happen before it,
           and where/when the next bounce is.
   The AI asks this network "if I stand at depth y_p, where and when do I hit
   the ball?" for several depths and picks the best legal one.

2. Shot Selector (policy network, 9-way softmax)
   Input : AI contact point, opponent position, incoming ball speed,
           two-bounce flag, AI power/control stats.
   Output: probability of each of 9 shots = {drive, soft(dink/drop), lob}
           x {left, centre, right}.
   Labels come from Monte Carlo roll-outs: every shot is simulated many times
   with execution noise against a simulated opponent; the expected rally win
   rate of each option becomes a soft target (policy distillation).

Run:  python training/train_ai.py            (from the pickle_arena folder)
Writes: assets/ai/pickle_brain.json   (weights loaded by the Flutter game)
        training/outputs/*.png, metrics.json
"""
from __future__ import annotations

import json
import os
import sys
import time
from datetime import date

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pickle_sim as ps  # noqa: E402

ROOT = os.path.dirname(HERE)
OUT_DIR = os.path.join(HERE, "outputs")
ASSET_PATH = os.path.join(ROOT, "assets", "ai", "pickle_brain.json")
SEED = 42

# Execution noise model (shared with lib/game/shot_planner.dart)
NOISE_X = np.array([0.40, 0.28, 0.45])   # sideways aim error per shot kind (m)
NOISE_Y = np.array([0.45, 0.30, 0.50])   # depth error (m)
NOISE_C = np.array([0.07, 0.06, 0.10])   # net-clearance error (m)


def noise_factor(control, in_speed, contact_z):
    return ((1.30 - 0.06 * control) * (1.0 + in_speed / 25.0)
            * (1.0 + np.maximum(0.0, 0.6 - contact_z) * 0.6))


# =====================================================================
# 1. Trajectory predictor dataset
# =====================================================================
PRED_INPUTS = ["ball_x", "ball_y", "ball_z", "ball_vx", "ball_vy", "ball_vz", "plane_y"]


def make_predictor_data(n_shots: int, rng: np.random.Generator):
    """Canonical frame: opponent on y > 0 hits toward the AI on y < 0."""
    n = n_shots
    hx = rng.uniform(-3.6, 3.6, n)
    hy = rng.uniform(0.3, 8.5, n)
    hz = rng.uniform(0.15, 2.0, n)
    kind = rng.integers(0, 3, n)
    tx = rng.uniform(-3.9, 3.9, n)
    ty = -rng.uniform(0.2, 7.8, n)
    power = rng.uniform(1, 6, n)
    clr = rng.normal(0.0, 0.12, n)
    vx, vy, vz, _ = ps.plan_shot(kind, hx, hy, hz, tx, ty, power, clr)
    # 15% completely random launches so the network generalises
    m = rng.random(n) < 0.15
    vx = np.where(m, rng.uniform(-4, 4, n), vx)
    vy = np.where(m, -rng.uniform(3, 20, n), vy)
    vz = np.where(m, rng.uniform(-6, 9, n), vz)

    ratio = -hy * ps.DRAG / vy
    _, _, zn = ps.net_crossing(hx, hy, hz, vx, vy, vz)
    keep = (ratio < 0.98) & (zn > ps.NET_H + 0.02)
    hx, hy, hz, vx, vy, vz = (a[keep] for a in (hx, hy, hz, vx, vy, vz))

    segs = ps.segments(hx, hy, hz, vx, vy, vz, n=2)
    t_end = segs[0][2] + segs[1][2]          # until the 2nd bounce
    obs_per_shot, planes_per_obs = 4, 2
    rows_x, rows = [], []
    for _ in range(obs_per_shot):
        tau = rng.uniform(0, 1, len(hx)) * t_end * 0.97
        ox, oy, oz, ovx, ovy, ovz, nb = ps.state_at(segs, tau)
        ok = (nb < 2) & (oy > -8.7)
        o = [a[ok] for a in (ox, oy, oz, ovx, ovy, ovz)]
        for _ in range(planes_per_obs):
            top = np.minimum(o[1] - 0.05, -0.2)
            yp = rng.uniform(0, 1, len(o[0])) * (top + 9.0) - 9.0
            rows_x.append(np.stack([*o, yp], axis=1))
            rows.append(_predictor_labels(*o, yp))
    X = np.concatenate(rows_x).astype(np.float32)
    Y = {k: np.concatenate([r[k] for r in rows]).astype(np.float32) for k in rows[0]}
    return X, Y


def _predictor_labels(x, y, z, vx, vy, vz, yp):
    segs = ps.segments(x, y, z, vx, vy, vz, n=3)
    # next bounce
    t0, st, dur, _ = segs[0]
    bx, by, *_ = ps.propagate(*st, dur)
    bounce = np.stack([bx, by, dur], axis=1)
    # plane crossing
    n = len(x)
    found = np.zeros(n, dtype=bool)
    px = np.zeros(n); pz = np.zeros(n); pt = np.zeros(n); pnb = np.zeros(n, dtype=int)
    for i, (t0, st, dur, roll) in enumerate(segs):
        sy, svy = st[1], st[4]
        ratio = (yp - sy) * ps.DRAG / np.where(svy == 0, -1e-9, svy)
        valid = (~found) & (~roll) & (ratio >= 0) & (ratio < 1)
        trel = -np.log(1 - np.clip(ratio, 0, 0.999999)) / ps.DRAG
        hit = valid & (trel <= dur + 1e-9)
        cx, _, cz, *_ = ps.propagate(*st, trel)
        px = np.where(hit, cx, px)
        pz = np.where(hit, np.maximum(cz, 0.0), pz)
        pt = np.where(hit, t0 + trel, pt)
        pnb = np.where(hit, i, pnb)
        found |= hit
    mask = found.astype(float)
    plane = np.stack([px, pz, pt, mask], axis=1)
    nb_onehot = np.eye(3)[pnb] * mask[:, None]
    nb = np.concatenate([nb_onehot, mask[:, None]], axis=1)
    return {"plane": plane, "reach": mask[:, None], "nb": nb, "bounce": bounce}


# =====================================================================
# 2. Shot selector dataset (Monte Carlo roll-outs)
# =====================================================================
SEL_INPUTS = ["hit_x", "hit_y", "hit_z", "opp_x", "opp_y", "in_speed",
              "opp_must_bounce", "power", "control"]
OPP_REACTION = 0.18
OPP_SPEED = 4.5
OPP_BACK_SPEED = 3.2
OPP_REACH = 1.10


def sample_selector_states(n: int, rng: np.random.Generator):
    hx = np.clip(rng.normal(0.0, 1.4, n), -3.4, 3.4)
    hy = -np.where(rng.random(n) < 0.5, rng.uniform(1.8, 3.4, n), rng.uniform(0.4, 8.2, n))
    hz = 0.12 + 1.9 * rng.beta(1.6, 2.6, n)
    # real players recover toward the middle, so opponents are mostly central
    ox = np.where(rng.random(n) < 0.75, np.clip(rng.normal(0.0, 0.8, n), -3.0, 3.0),
                  rng.uniform(-3.2, 3.2, n))
    r = rng.random(n)
    oy = np.select([r < 0.4, r < 0.8], [rng.uniform(1.9, 3.2, n), rng.uniform(5.6, 8.0, n)],
                   rng.uniform(0.6, 8.0, n))
    in_speed = rng.uniform(3.0, 18.0, n)
    must = (rng.random(n) < 0.3).astype(float)
    power = rng.uniform(1, 6, n)
    control = rng.uniform(1, 6, n)
    return np.stack([hx, hy, hz, ox, oy, in_speed, must, power, control], axis=1)


def rollout_rewards(S: np.ndarray, rng: np.random.Generator, R: int = 10, K: int = 44):
    """Expected rally-win probability of each of the 9 shots for every state."""
    n = len(S)
    hx, hy, hz, ox, oy, spd, must, power, control = [S[:, i] for i in range(9)]
    opts = np.arange(9)
    kind = np.repeat(opts // 3, R)          # (9R,)
    zone = np.repeat(opts % 3, R)
    rep = lambda a: np.repeat(a[:, None], 9 * R, axis=1)  # (n, 9R)
    Hx, Hy, Hz, Ox, Oy, Spd, Must, Pow, Ctl = map(rep, (hx, hy, hz, ox, oy, spd, must, power, control))
    Kind = np.broadcast_to(kind, Hx.shape)
    Zone = np.broadcast_to(zone, Hx.shape)

    f = noise_factor(Ctl, Spd, Hz)
    tx = ps.ZONE_X[Zone] + rng.normal(size=Hx.shape) * NOISE_X[Kind] * f
    ty = ps.default_depth(Kind, Hy) + rng.normal(size=Hx.shape) * NOISE_Y[Kind] * f
    cl = rng.normal(size=Hx.shape) * NOISE_C[Kind] * f
    vx, vy, vz, _ = ps.plan_shot(Kind, Hx, Hy, Hz, tx, ty, Pow, cl)

    _, _, zn = ps.net_crossing(Hx, Hy, Hz, vx, vy, vz)
    segs = ps.segments(Hx, Hy, Hz, vx, vy, vz, n=2)
    lx, ly, *_ = ps.propagate(*segs[0][1], segs[0][2])
    good = (zn >= ps.NET_H) & ps.in_court(lx, ly, +1)

    # opponent contact candidates along the trajectory
    t_end = segs[0][2] + segs[1][2]
    tk = np.linspace(0.0, 1.0, K)[None, None, :] * t_end[..., None]
    seg3 = [(t0[..., None], tuple(s[..., None] for s in st), d[..., None], ro[..., None])
            for (t0, st, d, ro) in segs]
    X, Y, Z, VX, VY, VZ, NB = ps.state_at(seg3, tk)
    Oxe, Oye, Muste = Ox[..., None], Oy[..., None], Must[..., None]
    legal = ((Y > 0.05) & (Z >= 0.12) & (Z <= 2.3) & (NB <= 1)
             & ~((Muste > 0.5) & (NB == 0)) & ~((NB == 0) & (Y < ps.KITCHEN)))
    dx, dy = X - Oxe, Y - Oye
    run = np.maximum(0.0, np.hypot(dx, dy) - OPP_REACH)
    back = np.clip(dy / np.maximum(np.hypot(dx, dy), 1e-6), 0, 1)  # share of motion away from net
    speed = OPP_SPEED * (1 - back) + OPP_BACK_SPEED * back
    margin = tk - (OPP_REACTION + run / speed)
    feas = legal & (margin >= 0)

    ball_speed = np.sqrt(VX ** 2 + VY ** 2 + VZ ** 2)
    backpedal = np.maximum(0.0, Y - Oye)                     # metres run away from the net
    attack = (np.clip((Z - 0.95) / 0.7, 0, 1) * (Y < 4.8)
              * np.clip(1.0 - (backpedal - 1.0) / 2.0, 0.3, 1.0))
    low_near = np.clip((0.75 - Z) / 0.5, 0, 1) * (Y < 3.5)
    stretch = np.clip((0.3 - margin) / 0.3, 0, 1) * (run > 0.05)
    fast = np.clip((ball_speed - 10.0) / 8.0, 0, 1)
    deep = (Y > 6.9).astype(float)
    p_opp = np.clip(0.47 + 0.42 * attack - 0.24 * low_near - 0.22 * stretch
                    - 0.08 * fast - 0.08 * deep, 0.04, 0.96)
    p_best = np.where(feas, p_opp, -1.0).max(axis=-1)
    reward = np.where(p_best < 0, 1.0, 1.0 - p_best)    # no reachable contact -> winner
    reward = np.where(good, reward, 0.0)                 # net or out -> rally lost
    return reward.reshape(n, 9, R).mean(axis=2)


def make_selector_data(n: int, rng: np.random.Generator, chunk: int = 800):
    S = sample_selector_states(n, rng)
    rewards = np.zeros((n, 9))
    t0 = time.time()
    for i in range(0, n, chunk):
        rewards[i:i + chunk] = rollout_rewards(S[i:i + chunk], rng)
        if (i // chunk) % 10 == 0:
            print(f"   roll-outs {i + chunk:>6}/{n}  ({time.time() - t0:5.1f}s)", flush=True)
    return S.astype(np.float32), rewards.astype(np.float32)


def soft_labels(rewards, tau=0.06):
    z = (rewards - rewards.max(axis=1, keepdims=True)) / tau
    e = np.exp(z)
    return (e / e.sum(axis=1, keepdims=True)).astype(np.float32)


# =====================================================================
# 3. Keras models
# =====================================================================
def build_predictor(keras, n_in):
    inp = keras.Input((n_in,), name="state")
    h = keras.layers.Dense(128, activation="relu", name="trunk_1")(inp)
    h = keras.layers.Dense(128, activation="relu", name="trunk_2")(h)
    h = keras.layers.Dense(64, activation="relu", name="trunk_3")(h)
    plane = keras.layers.Dense(3, name="plane")(h)
    reach = keras.layers.Dense(1, activation="sigmoid", name="reach")(h)
    nb = keras.layers.Dense(3, activation="softmax", name="nb")(h)
    bounce = keras.layers.Dense(3, name="bounce")(h)
    return keras.Model(inp, {"plane": plane, "reach": reach, "nb": nb, "bounce": bounce})


def build_selector(keras, n_in):
    inp = keras.Input((n_in,), name="situation")
    h = keras.layers.Dense(96, activation="relu", name="sel_1")(inp)
    h = keras.layers.Dense(96, activation="relu", name="sel_2")(h)
    out = keras.layers.Dense(9, activation="softmax", name="shot")(h)
    return keras.Model(inp, out)


def export_dense(layer, act):
    w, b = layer.get_weights()
    r = lambda a: np.round(a.astype(np.float64), 6).tolist()
    return {"w": r(w), "b": r(b), "act": act}


def main():
    import keras
    from keras import ops

    keras.utils.set_random_seed(SEED)
    rng = np.random.default_rng(SEED)
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(ASSET_PATH), exist_ok=True)
    metrics = {}

    # ---------------------------------------------------- predictor
    print("[1/4] Generating trajectory dataset ...", flush=True)
    t0 = time.time()
    X, Y = make_predictor_data(70000, rng)
    print(f"   {len(X)} samples in {time.time() - t0:.1f}s, reach rate {Y['reach'].mean():.3f}")
    idx = rng.permutation(len(X))
    n_test = int(0.1 * len(X))
    te, tr = idx[:n_test], idx[n_test:]
    in_mean, in_std = X[tr].mean(0), X[tr].std(0) + 1e-6
    valid = Y["plane"][tr, 3] > 0.5
    pl_mean = Y["plane"][tr][valid, :3].mean(0); pl_std = Y["plane"][tr][valid, :3].std(0) + 1e-6
    bo_mean = Y["bounce"][tr].mean(0); bo_std = Y["bounce"][tr].std(0) + 1e-6

    def norm_targets(Yd, sel):
        plane = Yd["plane"][sel].copy()
        plane[:, :3] = (plane[:, :3] - pl_mean) / pl_std * plane[:, 3:4]
        return {"plane": plane, "reach": Yd["reach"][sel], "nb": Yd["nb"][sel],
                "bounce": (Yd["bounce"][sel] - bo_mean) / bo_std}

    def masked_mse(y_true, y_pred):
        m = y_true[:, 3:4]
        return ops.sum(m * ops.square(y_true[:, :3] - y_pred), axis=-1) / 3.0

    def masked_cce(y_true, y_pred):
        m = y_true[:, 3]
        p = ops.clip(y_pred, 1e-7, 1.0)
        return -ops.sum(y_true[:, :3] * ops.log(p), axis=-1) * m

    pred = build_predictor(keras, X.shape[1])
    pred.compile(optimizer=keras.optimizers.Adam(1e-3),
                 loss={"plane": masked_mse, "reach": "binary_crossentropy",
                       "nb": masked_cce, "bounce": "mse"},
                 loss_weights={"plane": 1.0, "reach": 0.5, "nb": 0.5, "bounce": 1.0})
    print("[2/4] Training trajectory predictor ...", flush=True)
    Xn = (X - in_mean) / in_std
    hist_p = pred.fit(Xn[tr], norm_targets(Y, tr), validation_split=0.1, epochs=40,
                      batch_size=512, verbose=2,
                      callbacks=[keras.callbacks.EarlyStopping(patience=5, restore_best_weights=True),
                                 keras.callbacks.ReduceLROnPlateau(patience=2, factor=0.5)])
    out = pred.predict(Xn[te], batch_size=4096, verbose=0)
    m_te = Y["plane"][te, 3] > 0.5
    plane_pred = out["plane"] * pl_std + pl_mean
    bounce_pred = out["bounce"] * bo_std + bo_mean
    mae_plane = np.abs(plane_pred[m_te] - Y["plane"][te][m_te, :3]).mean(0)
    mae_bounce = np.abs(bounce_pred - Y["bounce"][te]).mean(0)
    reach_acc = ((out["reach"][:, 0] > 0.5) == (Y["reach"][te, 0] > 0.5)).mean()
    nb_acc = (out["nb"][m_te].argmax(1) == Y["nb"][te][m_te, :3].argmax(1)).mean()
    metrics["predictor"] = {
        "samples": int(len(X)), "test_samples": int(n_test),
        "mae_plane_x_m": float(mae_plane[0]), "mae_plane_height_m": float(mae_plane[1]),
        "mae_plane_time_s": float(mae_plane[2]),
        "mae_bounce_x_m": float(mae_bounce[0]), "mae_bounce_y_m": float(mae_bounce[1]),
        "mae_bounce_time_s": float(mae_bounce[2]),
        "reach_accuracy": float(reach_acc), "bounce_count_accuracy": float(nb_acc),
        "epochs": len(hist_p.history["loss"]),
    }
    print("   predictor test:", json.dumps(metrics["predictor"], indent=1))

    # ---------------------------------------------------- selector
    print("[3/4] Generating shot-selector dataset (Monte Carlo roll-outs) ...", flush=True)
    t0 = time.time()
    S, Rw = make_selector_data(30000, rng)
    print(f"   {len(S)} situations x 9 shots x 10 roll-outs in {time.time() - t0:.1f}s")
    idx = rng.permutation(len(S))
    n_test = int(0.1 * len(S))
    te_s, tr_s = idx[:n_test], idx[n_test:]
    s_mean, s_std = S[tr_s].mean(0), S[tr_s].std(0) + 1e-6
    L = soft_labels(Rw)
    sel = build_selector(keras, S.shape[1])
    sel.compile(optimizer=keras.optimizers.Adam(1e-3), loss="categorical_crossentropy")
    print("[4/4] Training shot selector ...", flush=True)
    Sn = (S - s_mean) / s_std
    hist_s = sel.fit(Sn[tr_s], L[tr_s], validation_split=0.1, epochs=60, batch_size=256, verbose=2,
                     callbacks=[keras.callbacks.EarlyStopping(patience=6, restore_best_weights=True),
                                keras.callbacks.ReduceLROnPlateau(patience=3, factor=0.5)])
    P = sel.predict(Sn[te_s], batch_size=4096, verbose=0)
    R_te = Rw[te_s]
    chosen = P.argmax(1)
    best = R_te.argmax(1)
    exp_chosen = R_te[np.arange(len(R_te)), chosen].mean()
    metrics["selector"] = {
        "situations": int(len(S)), "test_situations": int(n_test),
        "top1_agreement_with_best_shot": float((chosen == best).mean()),
        "expected_win_rate_network": float(exp_chosen),
        "expected_win_rate_best_possible": float(R_te.max(1).mean()),
        "expected_win_rate_random_shot": float(R_te.mean()),
        "expected_win_rate_always_drive_centre": float(R_te[:, 1].mean()),
        "shot_mix": {f"{ps.SHOT_NAMES[k]}": float((chosen // 3 == k).mean()) for k in range(3)},
        "epochs": len(hist_s.history["loss"]),
    }
    print("   selector test:", json.dumps(metrics["selector"], indent=1))

    # ---------------------------------------------------- export
    names = {"plane": "linear", "reach": "sigmoid", "nb": "softmax", "bounce": "linear"}
    trunk = [export_dense(pred.get_layer(f"trunk_{i}"), "relu") for i in (1, 2, 3)]
    heads = {k: export_dense(pred.get_layer(k), a) for k, a in names.items()}
    sel_layers = [export_dense(sel.get_layer("sel_1"), "relu"),
                  export_dense(sel.get_layer("sel_2"), "relu"),
                  export_dense(sel.get_layer("shot"), "softmax")]

    # self-test vectors so the Dart port can verify it reproduces the networks
    k = 6
    st_pred_x = X[te[:k]]
    st_pred_out = pred.predict((st_pred_x - in_mean) / in_std, verbose=0)
    st_sel_x = S[te_s[:k]]
    st_sel_out = sel.predict((st_sel_x - s_mean) / s_std, verbose=0)
    planner_cases = []
    for kind, h, t in [(ps.DRIVE, (0.5, -6.4, 0.8), (1.5, 5.3)),
                       (ps.SOFT, (-1.0, -2.4, 0.45), (0.3, 1.3)),
                       (ps.LOB, (0.0, -2.5, 0.9), (-1.8, 5.6)),
                       (ps.DRIVE, (2.0, 3.0, 1.9), (-2.0, -5.0)),
                       (ps.SOFT, (1.5, 6.5, 0.6), (-0.5, -1.6))]:
        vx, vy, vz, T = ps.plan_shot(kind, *h, *t, 4.0)
        planner_cases.append({"kind": int(kind), "hit": list(h), "target": list(t), "power": 4.0,
                              "v": [float(vx), float(vy), float(vz)], "T": float(T)})
    ground_cases = []
    for z, vz in [(1.0, 3.0), (0.0, 5.0), (2.0, -4.0), (0.5, 9.0)]:
        ground_cases.append({"z": z, "vz": vz, "t": float(ps.time_to_ground(z, vz))})

    brain = {
        "name": "PickleBrain", "version": 1, "trained_on": str(date.today()),
        "physics": {"g": ps.G, "drag": ps.DRAG, "restitution": ps.REST, "friction": ps.FRIC,
                    "half_width": ps.HALF_W, "half_length": ps.HALF_L, "kitchen": ps.KITCHEN,
                    "net_height": ps.NET_H},
        "predictor": {"inputs": PRED_INPUTS, "in_mean": in_mean.tolist(), "in_std": in_std.tolist(),
                      "trunk": trunk, "heads": heads,
                      "plane_mean": pl_mean.tolist(), "plane_std": pl_std.tolist(),
                      "bounce_mean": bo_mean.tolist(), "bounce_std": bo_std.tolist()},
        "selector": {"inputs": SEL_INPUTS, "in_mean": s_mean.tolist(), "in_std": s_std.tolist(),
                     "layers": sel_layers,
                     "classes": [f"{ps.SHOT_NAMES[i // 3]}_{['left', 'centre', 'right'][i % 3]}"
                                 for i in range(9)]},
        "noise": {"x": NOISE_X.tolist(), "y": NOISE_Y.tolist(), "clearance": NOISE_C.tolist()},
        "metrics": metrics,
        "selftest": {
            "predictor": [{"x": st_pred_x[i].tolist(),
                           "plane": (st_pred_out["plane"][i] * pl_std + pl_mean).tolist(),
                           "reach": float(st_pred_out["reach"][i, 0]),
                           "nb": st_pred_out["nb"][i].tolist(),
                           "bounce": (st_pred_out["bounce"][i] * bo_std + bo_mean).tolist()}
                          for i in range(k)],
            "selector": [{"x": st_sel_x[i].tolist(), "p": st_sel_out[i].tolist()} for i in range(k)],
            "planner": planner_cases, "ground": ground_cases,
        },
    }
    with open(ASSET_PATH, "w") as f:
        json.dump(brain, f, separators=(",", ":"))
    with open(os.path.join(OUT_DIR, "metrics.json"), "w") as f:
        json.dump(metrics, f, indent=2)
    print(f"Saved model -> {ASSET_PATH} ({os.path.getsize(ASSET_PATH) / 1024:.0f} KB)")

    make_plots(hist_p, hist_s, plane_pred, Y, te, m_te, bounce_pred, sel, s_mean, s_std)


def make_plots(hist_p, hist_s, plane_pred, Y, te, m_te, bounce_pred, sel, s_mean, s_std):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.colors import ListedColormap

    fig, ax = plt.subplots(1, 2, figsize=(11, 4))
    ax[0].plot(hist_p.history["loss"], label="train"); ax[0].plot(hist_p.history["val_loss"], label="validation")
    ax[0].set_title("Trajectory predictor loss"); ax[0].set_xlabel("epoch"); ax[0].legend()
    ax[1].plot(hist_s.history["loss"], label="train"); ax[1].plot(hist_s.history["val_loss"], label="validation")
    ax[1].set_title("Shot selector loss (cross-entropy)"); ax[1].set_xlabel("epoch"); ax[1].legend()
    fig.tight_layout(); fig.savefig(os.path.join(OUT_DIR, "training_curves.png"), dpi=130); plt.close(fig)

    true_plane = Y["plane"][te][m_te, :3]
    pp = plane_pred[m_te]
    sub = np.random.default_rng(0).choice(len(pp), size=min(4000, len(pp)), replace=False)
    fig, ax = plt.subplots(1, 3, figsize=(14, 4.2))
    for i, (name, unit) in enumerate([("sideways position x", "m"), ("height at contact", "m"),
                                      ("time to contact", "s")]):
        ax[i].scatter(true_plane[sub, i], pp[sub, i], s=3, alpha=0.35)
        lo, hi = true_plane[:, i].min(), true_plane[:, i].max()
        ax[i].plot([lo, hi], [lo, hi], "r--", lw=1)
        ax[i].set_xlabel(f"true ({unit})"); ax[i].set_ylabel(f"predicted ({unit})"); ax[i].set_title(name)
    fig.suptitle("Trajectory predictor on unseen test data")
    fig.tight_layout(); fig.savefig(os.path.join(OUT_DIR, "predictor_accuracy.png"), dpi=130); plt.close(fig)

    # shot policy map: what the AI chooses depending on its contact point
    fig, ax = plt.subplots(1, 2, figsize=(11, 4.4))
    ys = np.linspace(-8.0, -0.6, 90); zs = np.linspace(0.15, 2.0, 60)
    YY, ZZ = np.meshgrid(ys, zs)
    cmap = ListedColormap(["#ef5350", "#66bb6a", "#42a5f5"])
    for a, (oy, title) in zip(ax, [(2.4, "Opponent at the kitchen line"), (7.0, "Opponent at the baseline")]):
        S = np.stack([np.zeros(YY.size), YY.ravel(), ZZ.ravel(), np.zeros(YY.size), np.full(YY.size, oy),
                      np.full(YY.size, 9.0), np.zeros(YY.size), np.full(YY.size, 4.0), np.full(YY.size, 4.0)], 1)
        P = sel.predict(((S - s_mean) / s_std).astype(np.float32), verbose=0)
        kind = (P.reshape(-1, 3, 3).sum(2)).argmax(1).reshape(YY.shape)
        a.pcolormesh(YY, ZZ, kind, cmap=cmap, vmin=0, vmax=2, shading="auto")
        a.axvline(-ps.KITCHEN, color="w", ls="--", lw=1); a.axvline(-ps.HALF_L, color="w", lw=1)
        a.set_title(title); a.set_xlabel("AI depth y (m, net at 0)"); a.set_ylabel("contact height (m)")
    handles = [plt.Rectangle((0, 0), 1, 1, color=c) for c in cmap.colors]
    fig.legend(handles, ["drive", "soft (dink/drop)", "lob"], loc="lower center", ncol=3)
    fig.suptitle("Learned shot policy (AI at x = 0)")
    fig.tight_layout(rect=(0, 0.07, 1, 1)); fig.savefig(os.path.join(OUT_DIR, "shot_policy_map.png"), dpi=130)
    plt.close(fig)
    print("Saved plots ->", OUT_DIR)


if __name__ == "__main__":
    main()
