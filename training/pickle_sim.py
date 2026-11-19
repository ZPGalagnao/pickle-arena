"""Pickle Arena - shared ball physics and shot planner.

This file is the Python twin of `lib/game/physics.dart` and
`lib/game/shot_planner.dart`. Both use the exact same closed-form equations so
that the neural networks trained here behave correctly inside the Flutter game.

Coordinate system (metres):
    x : sideways, court spans [-HALF_W, HALF_W]
    y : along the court, net at y = 0, each baseline at +/- HALF_L
    z : height above the ground

Ball model: gravity + linear air drag (a = -DRAG * v - g). Linear drag has an
exact analytic solution, so we never need numeric integration.
"""
from __future__ import annotations

import numpy as np

# ---------------------------------------------------------------- constants
G = 9.81            # gravity (m/s^2)
DRAG = 0.30         # linear drag coefficient (1/s) - wiffle balls slow down a lot
GT = G / DRAG       # terminal speed
REST = 0.70         # vertical restitution on bounce
FRIC = 0.80         # fraction of horizontal speed kept on bounce
ROLL_VZ = 0.35      # rebound slower than this -> ball just rolls (dead ball)

HALF_W = 3.05       # 20 ft wide court
HALF_L = 6.705      # 44 ft long court
KITCHEN = 2.134     # 7 ft non-volley zone
NET_H = 0.88        # net height (m)

T_MIN = 0.35        # fastest allowed flight time of a shot (s)
T_MAX = 3.2

# Shot kinds
DRIVE, SOFT, LOB = 0, 1, 2
SHOT_NAMES = ["drive", "soft", "lob"]
ZONE_X = np.array([-2.0, 0.0, 2.0])  # left / centre / right aim lines (canonical)


# ------------------------------------------------------------ ball physics
def kfac(t):
    """(1 - e^{-ct}) / c : horizontal distance factor."""
    return (1.0 - np.exp(-DRAG * t)) / DRAG


def propagate(x, y, z, vx, vy, vz, t):
    """Exact free-flight state after time t (ignores the ground)."""
    e = np.exp(-DRAG * t)
    k = (1.0 - e) / DRAG
    a = vz + GT
    return (x + vx * k, y + vy * k, z + a * k - GT * t,
            vx * e, vy * e, a * e - GT)


def time_to_ground(z, vz):
    """First t > 0 where z(t) = 0. Newton's method from a drag-free guess.

    The drag-free landing time is always past the apex of the dragged
    trajectory, and z(t) is concave, so Newton converges monotonically.
    """
    z = np.asarray(z, dtype=float)
    vz = np.asarray(vz, dtype=float)
    t = (vz + np.sqrt(np.maximum(vz * vz + 2.0 * G * np.maximum(z, 0.0), 0.0))) / G
    t = np.maximum(t, 1e-3)
    a = vz + GT
    for _ in range(14):
        e = np.exp(-DRAG * t)
        f = z + a * (1.0 - e) / DRAG - GT * t
        fp = a * e - GT
        fp = np.where(np.abs(fp) < 1e-9, -1e-9, fp)
        t = np.maximum(t - f / fp, 1e-5)
    return t


def bounce(vx, vy, vz):
    return vx * FRIC, vy * FRIC, -vz * REST


def segments(x, y, z, vx, vy, vz, n=3):
    """Split a trajectory into flight segments between bounces.

    Returns a list of (t_start, state_tuple, duration, rolling_mask).
    Once a ball is rolling, later segments have ~0 duration (dead ball).
    """
    x, y, z, vx, vy, vz = [np.asarray(v, dtype=float).copy() for v in (x, y, z, vx, vy, vz)]
    t0 = np.zeros_like(x)
    rolling = np.zeros(x.shape, dtype=bool)
    out = []
    for _ in range(n):
        dur = np.where(rolling, 1e-6, time_to_ground(z, vz))
        out.append((t0.copy(), (x, y, z, vx, vy, vz), dur, rolling.copy()))
        x, y, z, vx, vy, vz = propagate(x, y, z, vx, vy, vz, dur)
        z = np.zeros_like(z)
        vx, vy, vz = bounce(vx, vy, vz)
        rolling = rolling | (vz < ROLL_VZ)
        t0 = t0 + dur
    return out


def state_at(segs, t):
    """Ball state at absolute time t (t measured from the start of segs).

    Returns (x, y, z, vx, vy, vz, n_bounces_before_t). Beyond the last listed
    bounce (or once rolling) the ball is dead: n_bounces = len(segs).
    """
    t = np.asarray(t, dtype=float)
    shape = np.broadcast_shapes(t.shape, segs[0][0].shape)
    out = [np.zeros(shape) for _ in range(6)]
    NB = np.full(shape, len(segs), dtype=int)
    done = np.zeros(shape, dtype=bool)
    for i, (t0, st, dur, roll) in enumerate(segs):
        inside = (~done) & (t >= t0) & (t <= t0 + dur) & (~roll)
        if np.any(inside):
            s = propagate(*st, np.clip(t - t0, 0.0, None))
            for j in range(6):
                val = np.maximum(s[j], 0.0) if j == 2 else s[j]
                out[j] = np.where(inside, val, out[j])
            NB = np.where(inside, i, NB)
        done = done | inside
    return (*out, NB)


# ------------------------------------------------------------ shot planner
def velocity_for(x0, y0, z0, tx, ty, T):
    """Launch velocity that lands exactly on (tx, ty) after flight time T."""
    k = kfac(T)
    vx = (tx - x0) / k
    vy = (ty - y0) / k
    vz = (GT * T - z0) / k - GT
    return vx, vy, vz


def net_crossing(x0, y0, z0, vx, vy, vz):
    """(t, x, z) when the ball crosses y = 0. Assumes it does cross."""
    ratio = np.clip(-y0 * DRAG / np.where(vy == 0, 1e-9, vy), 0.0, 0.999999)
    t = -np.log(1.0 - ratio) / DRAG
    x, _, z, *_ = propagate(x0, y0, z0, vx, vy, vz, t)
    return t, x, z


def _clearance(x0, y0, z0, tx, ty, T):
    vx, vy, vz = velocity_for(x0, y0, z0, tx, ty, T)
    _, _, zn = net_crossing(x0, y0, z0, vx, vy, vz)
    return zn - NET_H


def _speed(x0, y0, z0, tx, ty, T):
    vx, vy, vz = velocity_for(x0, y0, z0, tx, ty, T)
    return np.sqrt(vx * vx + vy * vy + vz * vz)


def solve_flight_time(x0, y0, z0, tx, ty, clearance, vmax, t_floor):
    """Smallest flight time that clears the net by `clearance`, respects the
    player's max hitting speed `vmax`, and is at least `t_floor`."""
    args = [np.asarray(a, dtype=float) for a in (x0, y0, z0, tx, ty, clearance, vmax, t_floor)]
    x0, y0, z0, tx, ty, clearance, vmax, t_floor = np.broadcast_arrays(*args)
    lo = np.full(x0.shape, T_MIN)
    hi = np.full(x0.shape, T_MAX)
    for _ in range(30):
        mid = 0.5 * (lo + hi)
        ok = _clearance(x0, y0, z0, tx, ty, mid) >= clearance
        hi = np.where(ok, mid, hi)
        lo = np.where(ok, lo, mid)
    t_clear = hi
    lo = np.full(x0.shape, T_MIN)
    hi = np.full(x0.shape, 1.5)
    for _ in range(30):
        mid = 0.5 * (lo + hi)
        ok = _speed(x0, y0, z0, tx, ty, mid) <= vmax
        hi = np.where(ok, mid, hi)
        lo = np.where(ok, lo, mid)
    t_speed = hi
    return np.maximum(np.maximum(t_clear, t_speed), t_floor)


def shot_params(kind, x0, y0, power):
    """Base clearance, max speed and minimum flight time for a shot kind.

    `power` is the character stat (1..6). Returns arrays.
    """
    kind = np.asarray(kind)
    vmax_drive = 15.0 + 1.0 * np.asarray(power, dtype=float)
    clearance = np.select([kind == DRIVE, kind == SOFT], [0.20, 0.28], 0.60)
    vmax = np.select([kind == DRIVE, kind == SOFT], [vmax_drive, 13.0], 16.0)
    return clearance, vmax


def default_depth(kind, hitter_y):
    """Distance past the net (on the far side) that each shot aims for."""
    kind = np.asarray(kind)
    near_net = np.abs(hitter_y) < 4.0
    soft_depth = np.where(near_net, 1.3, 1.6)
    return np.select([kind == DRIVE, kind == SOFT], [5.3, soft_depth], 5.6)


def plan_shot(kind, x0, y0, z0, tx, ty, power=4.0, clearance_offset=0.0):
    """Velocity for a shot of `kind` from (x0,y0,z0) aimed at ground point (tx,ty)."""
    kind = np.asarray(kind)
    clearance, vmax = shot_params(kind, x0, y0, power)
    dist = np.hypot(tx - x0, ty - y0)
    t_floor = np.select([kind == DRIVE, kind == SOFT],
                        [T_MIN, 0.6 + 0.07 * dist],
                        1.85 + 0.03 * dist)
    T = solve_flight_time(x0, y0, z0, tx, ty, clearance + clearance_offset, vmax, t_floor)
    vx, vy, vz = velocity_for(x0, y0, z0, tx, ty, T)
    return vx, vy, vz, T


def in_court(x, y, side_sign):
    """Is ground point inside the court half on side `side_sign` (+1 far, -1 near)?"""
    return (np.abs(x) <= HALF_W) & (y * side_sign >= 0.0) & (np.abs(y) <= HALF_L)


if __name__ == "__main__":
    # tiny sanity check: a drive from the near baseline to the far court
    vx, vy, vz, T = plan_shot(DRIVE, 0.0, -6.5, 0.8, 1.0, 5.3)
    segs = segments(vx * 0 + 0.0, -6.5, 0.8, vx, vy, vz)
    t0, st, dur, _ = segs[0]
    x, y, z, *_ = propagate(*st, dur)
    print(f"drive v=({float(vx):.2f},{float(vy):.2f},{float(vz):.2f}) T={float(T):.3f}s "
          f"lands at ({float(x):.3f},{float(y):.3f}) after {float(dur):.3f}s")
    tn, xn, zn = net_crossing(0.0, -6.5, 0.8, vx, vy, vz)
    print(f"net crossing at t={float(tn):.3f}s height={float(zn):.3f}m")
