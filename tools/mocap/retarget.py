#!/usr/bin/env python3
"""Retarget a CMU (cgspeed MotionBuilder-friendly) BVH clip onto the walker skeleton.

World-space delta retarget: every mapped target bone gets the source bone's world rotation
relative to the BVH's frame-0 T-pose, applied on top of the target's (T-pose) rest. Limb bones
additionally align the T-pose bone directions, so small differences between the two T-poses
(cgspeed's guessed arm/leg angles) don't leak into the motion. Intermediate source joints
(LHipJoint, Neck1, ...) are handled for free because world rotations include them.

Then: pick the cleanest gait cycle (or idle window), make it loop seamlessly (pose mismatch spread
over the cycle), strip root travel (in place, heading aligned to +Z), keep the vertical bob, put
the stance foot on the ground, rotate the loop to start on a left heel strike, resample, and write
JSON for tools/mocap/build_anim.gd.

usage: retarget.py SRC.bvh REST.json OUT.json --mode walk|idle [--start S --end E] [--fps 60]
       [--cycles 1]
"""
import argparse, json, sys
import numpy as np
from scipy.spatial.transform import Rotation as R, Slerp

# target bone -> (source joint, source child joint for the bone direction or None = pure delta)
MAP = {
    "Hips": ("Hips", None),
    "Spine": ("LowerBack", None),
    "Chest": ("Spine", None),
    "UpperChest": ("Spine1", None),
    "Neck": ("Neck", None),
    "Head": ("Head", None),
}
for s, S in (("Left", "L"), ("Right", "R")):
    MAP.update({
        s + "Shoulder": (s + "Shoulder", None),
        s + "UpperArm": (s + "Arm", s + "ForeArm"),
        s + "LowerArm": (s + "ForeArm", s + "Hand"),
        s + "Hand": (s + "Hand", None),
        s + "UpperLeg": (s + "UpLeg", s + "Leg"),
        s + "LowerLeg": (s + "Leg", s + "Foot"),
        s + "Foot": (s + "Foot", None),
        s + "Toes": (s + "ToeBase", None),
    })


def parse_bvh(path):
    head, motion = open(path).read().split("MOTION")
    toks = head.split()
    joints, stack, i = [], [], 0
    while i < len(toks):
        t = toks[i]
        if t in ("ROOT", "JOINT"):
            joints.append({"name": toks[i + 1], "parent": stack[-1] if stack else -1, "ch": [], "end": False}); i += 2
        elif t == "End":
            joints.append({"name": joints[stack[-1]]["name"] + "_end", "parent": stack[-1], "ch": [], "end": True}); i += 2
        elif t == "{":
            stack.append(len(joints) - 1); i += 1
        elif t == "}":
            stack.pop(); i += 1
        elif t == "OFFSET":
            joints[stack[-1]]["off"] = np.array(list(map(float, toks[i + 1:i + 4]))); i += 4
        elif t == "CHANNELS":
            n = int(toks[i + 1]); joints[stack[-1]]["ch"] = toks[i + 2:i + 2 + n]; i += 2 + n
        else:
            i += 1
    lines = motion.strip().split("\n")
    ft = float(lines[1].split()[-1])
    data = np.array([list(map(float, l.split())) for l in lines[2:] if l.strip()])
    return joints, ft, data


def bvh_fk(joints, data):
    """World rotations (F,J,3,3) and positions (F,J,3)."""
    F, J = len(data), len(joints)
    Rg = np.zeros((F, J, 3, 3)); Pg = np.zeros((F, J, 3))
    c = 0
    for j, jt in enumerate(joints):
        rot = np.tile(np.eye(3), (F, 1, 1))
        pos = np.tile(jt["off"], (F, 1))
        for ch in jt["ch"]:
            v = data[:, c]; c += 1
            if ch.endswith("position"):
                pos[:, "XYZ".index(ch[0])] = v
            else:
                rot = rot @ R.from_euler(ch[0].lower(), v, degrees=True).as_matrix()
        p = jt["parent"]
        if p < 0:
            Rg[:, j] = rot; Pg[:, j] = pos
        else:
            Pg[:, j] = Pg[:, p] + np.einsum("fij,j->fi", Rg[:, p], jt["off"])
            Rg[:, j] = Rg[:, p] @ rot
    return Rg, Pg


def arc(a, b):
    a = a / np.linalg.norm(a); b = b / np.linalg.norm(b)
    v = np.cross(a, b); s = np.linalg.norm(v); c = np.dot(a, b)
    if s < 1e-9:
        return np.eye(3)
    return R.from_rotvec(v / s * np.arctan2(s, c)).as_matrix()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("bvh"); ap.add_argument("rest"); ap.add_argument("out")
    ap.add_argument("--mode", default="walk", choices=["walk", "idle"])
    ap.add_argument("--start", type=float, default=None, help="seconds; search window start")
    ap.add_argument("--end", type=float, default=None)
    ap.add_argument("--fps", type=float, default=60.0)
    ap.add_argument("--cycles", type=int, default=1)
    ap.add_argument("--idle-len", type=float, default=6.0)
    ap.add_argument("--hand-damp", type=float, default=0.5, help="keep this much of the source wrist motion")
    ap.add_argument("--posture", default="", help="mean fwd lean deg for Hips,Spine,Chest,UpperChest,Neck,Head")
    ap.add_argument("--lean", type=float, default=0.0, help="extra deg added to every --posture target")
    ap.add_argument("--ground", type=float, default=0.0, help="extra lift (m) of the whole clip")
    a = ap.parse_args()

    joints, ft, data = parse_bvh(a.bvh)
    names = [j["name"] for j in joints]
    Rg, Pg = bvh_fk(joints, data)
    R0, P0 = Rg[0], Pg[0]          # cgspeed's added T-pose
    Rg, Pg = Rg[1:], Pg[1:]
    F = len(Rg)

    rest = json.load(open(a.rest))
    tb = rest["bones"]; tn = [b["name"] for b in tb]
    T = len(tb)
    tg_rest = np.array([np.array(b["g_basis"]).reshape(3, 3).T for b in tb])   # columns = axes
    tg_org = np.array([b["g_origin"] for b in tb])
    tl_rest = np.array([R.from_quat(b["l_quat"]).as_matrix() for b in tb])
    tl_org = np.array([b["l_origin"] for b in tb])
    par = [b["parent"] for b in tb]
    ms = rest["motion_scale"]

    # Source -> metres: match leg length (hip joint -> ankle).
    src_leg = np.linalg.norm(P0[names.index("LeftLeg")] - P0[names.index("LeftUpLeg")]) + \
        np.linalg.norm(P0[names.index("LeftFoot")] - P0[names.index("LeftLeg")])
    tgt_leg = np.linalg.norm(tg_org[tn.index("LeftLowerLeg")] - tg_org[tn.index("LeftUpperLeg")]) + \
        np.linalg.norm(tg_org[tn.index("LeftFoot")] - tg_org[tn.index("LeftLowerLeg")])
    scale = tgt_leg / src_leg

    # --- target world rotations per frame -------------------------------------------------------
    G = np.zeros((F, T, 3, 3))
    for t in range(T):
        name = tn[t]
        p = par[t]
        if name in MAP:
            sj, sc = MAP[name]
            si = names.index(sj)
            A = np.eye(3)
            if sc is not None:
                ci = names.index(sc)
                src_dir = P0[ci] - P0[si]
                tchild = [k for k in range(T) if par[k] == t]
                tgt_dir = tg_org[tchild[0]] - tg_org[t]
                A = arc(tgt_dir, src_dir)
            D = Rg[:, si] @ R0[si].T
            G[:, t] = D @ (A @ tg_rest[t])
        else:
            G[:, t] = (G[:, p] if p >= 0 else np.eye(3)) @ tl_rest[t]
    # Damp the noisy CMU wrist data toward the forearm.
    for s in ("Left", "Right"):
        h, la = tn.index(s + "Hand"), tn.index(s + "LowerArm")
        loc = np.einsum("fji,fjk->fik", G[:, la], G[:, h])
        rest_loc = tl_rest[h]
        lq = R.from_matrix(loc); rq = R.from_matrix(np.tile(rest_loc, (F, 1, 1)))
        d = (lq * rq.inv()).as_rotvec() * a.hand_damp
        G[:, h] = G[:, la] @ (R.from_rotvec(d) * rq).as_matrix()
        # fingers follow
    for t in range(T):
        if tn[t] not in MAP and par[t] >= 0:
            G[:, t] = G[:, par[t]] @ tl_rest[t]

    # Hips position: the source hip-joint midpoint drives the target's hip joints.
    mid_s = 0.5 * (Pg[:, names.index("LeftUpLeg")] + Pg[:, names.index("RightUpLeg")]) * scale
    hips_i = tn.index("Hips")
    mid_t_rest = 0.5 * (tg_org[tn.index("LeftUpperLeg")] + tg_org[tn.index("RightUpperLeg")])
    off_rest = tg_org[hips_i] - mid_t_rest           # hips relative to hip-joint midpoint (rest)
    D_h = np.einsum("fij,kj->fik", G[:, hips_i], tg_rest[hips_i])   # hips world delta
    hips_pos = mid_s + np.einsum("fij,j->fi", D_h, off_rest)

    def local_rots(Gf):
        L = np.zeros_like(Gf)
        for t in range(T):
            pg = Gf[:, par[t]] if par[t] >= 0 else np.tile(np.eye(3), (len(Gf), 1, 1))
            L[:, t] = np.einsum("fji,fjk->fik", pg, Gf[:, t])
        return L

    L = local_rots(G)

    def fk_target(Lr, hp):
        n = len(Lr)
        Gw = np.zeros((n, T, 3, 3)); Pw = np.zeros((n, T, 3))
        for t in range(T):
            p = par[t]
            if p < 0:
                Gw[:, t] = Lr[:, t]; Pw[:, t] = tl_org[t]
            else:
                Gw[:, t] = Gw[:, p] @ Lr[:, t]
                Pw[:, t] = Pw[:, p] + np.einsum("fij,j->fi", Gw[:, p], tl_org[t])
            if t == hips_i:
                Pw[:, t] = hp
        # recompute children of hips with the overridden hips position
        for t in range(T):
            p = par[t]
            if p >= 0 and t != hips_i:
                Pw[:, t] = Pw[:, p] + np.einsum("fij,j->fi", Gw[:, p], tl_org[t])
        return Gw, Pw

    # --- choose the loop window ----------------------------------------------------------------
    s0 = int((a.start or 0.0) / ft); s1 = int((a.end or F * ft) / ft); s1 = min(s1, F)
    rv = R.from_matrix(L.reshape(-1, 3, 3)).as_quat().reshape(F, T, 4)
    mapped = [tn.index(n) for n in MAP]

    def ang(i, j):
        d = np.abs(np.sum(rv[i, mapped] * rv[j, mapped], axis=1)).clip(0, 1)
        return np.sum(2 * np.arccos(d))

    def mismatch(i, j):
        k = 4 if j + 4 < F else 0
        return ang(i, j) + ang(i + k, j + k) + 4 * abs(hips_pos[i, 1] - hips_pos[j, 1])

    if a.mode == "walk":
        lf = tn.index("LeftFoot")
        _, Pw = fk_target(L, hips_pos)
        y = Pw[s0:s1, lf, 1] - Pw[s0:s1, lf, 1].mean()
        best = None
        for lag in range(int(0.55 / ft), min(int(1.5 / ft), len(y) - 10)):
            c = np.corrcoef(y[:-lag], y[lag:])[0, 1]
            if best is None or c > best[1]:
                best = (lag, c)
        per = best[0] * a.cycles
        cand = []
        for P in range(per - 8, per + 9):
            for i in range(s0, s1 - P - 5):
                cand.append((mismatch(i, i + P), i, P))
        cand.sort()
        err, i0, P = cand[0]
        print(f"period {best[0]*ft:.3f}s (corr {best[1]:.2f}); loop {i0*ft:.2f}..{(i0+P)*ft:.2f}s mismatch {err:.3f}")
    else:
        n = int(a.idle_len / ft)
        cand = []
        for P in range(int(n * 0.8), int(n * 1.2), 4):
            for i in range(s0, s1 - P - 5, 2):
                cand.append((mismatch(i, i + P), i, P))
        cand.sort()
        err, i0, P = cand[0]
        print(f"idle loop {i0*ft:.2f}..{(i0+P)*ft:.2f}s mismatch {err:.3f}")

    seg = np.arange(i0, i0 + P + 1)
    Ls = L[seg].copy(); hp = hips_pos[seg].copy()

    # Heading: rotate so the travel direction is +Z (walk) / the hips face +Z (idle).
    if a.mode == "walk":
        d = hp[-1] - hp[0]
        yaw = np.arctan2(d[0], d[2])
    else:
        fwd = np.einsum("fij,j->fi", np.einsum("fij,kj->fik", Ls[:, hips_i], tl_rest[hips_i]), [0, 0, 1]).mean(0)
        yaw = np.arctan2(fwd[0], fwd[2])
    Yc = R.from_euler("y", -yaw).as_matrix()
    root_i = par[hips_i]
    # Hips local = its world (root is identity) -> pre-multiply the yaw correction.
    Ls[:, hips_i] = Yc @ Ls[:, hips_i]
    hp = hp @ Yc.T

    # Seamless loop: spread the end/start rotation mismatch linearly over the cycle.
    u = np.linspace(0, 1, len(seg))
    for t in mapped:
        q = R.from_matrix(Ls[:, t])
        C = R.from_matrix(Ls[0, t]) * R.from_matrix(Ls[-1, t]).inv()
        corr = R.from_rotvec(np.outer(u, C.as_rotvec()))
        Ls[:, t] = (corr * q).as_matrix()
    # In place: remove the linear travel; keep bob and sway (made periodic).
    lin = hp[0] + np.outer(u, hp[-1] - hp[0])
    hp_ip = hp - lin
    hp_ip[:, 0] -= hp_ip[:, 0].mean(); hp_ip[:, 2] -= hp_ip[:, 2].mean()
    hp_ip[:, 1] += hp[0, 1] + (hp[-1, 1] - hp[0, 1]) * 0.5
    travel = np.linalg.norm((hp[-1] - hp[0])[[0, 2]])
    if a.mode == "idle":
        # idle: keep the slow sway but tame it
        hp_ip[:, [0, 2]] *= 1.0
    Ls, hp_ip = Ls[:-1], hp_ip[:-1]   # drop the duplicate end frame
    N = len(Ls)

    # Posture: set the mean sagittal angle (deg, + = leaning forward) of the pelvis and each spine
    # segment, keeping the legs' world rotations (so feet are unchanged) and letting the arms ride
    # along with the chest. Natural per-frame motion is preserved; only the mean is shifted.
    def sag(Gw, bone):
        yax = Gw[:, tn.index(bone)][:, :, 1]
        return np.degrees(np.arctan2(yax[:, 2], yax[:, 1]))

    def head_pitch(Gw):
        yax = Gw[:, tn.index("Head")][:, :, 1]
        return np.degrees(np.arctan2(yax[:, 2], yax[:, 1]))

    chain = ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head"]
    Gw, Pw = fk_target(Ls, hp_ip)
    print("posture before (deg fwd):", {b: round(float(sag(Gw, b).mean()), 1) for b in chain})
    if a.posture:
        tgt = dict(zip(chain, [float(x) for x in a.posture.split(",")]))
        tgt = {b: v + a.lean for b, v in tgt.items()}
        Gn = Gw.copy()
        for b in chain:
            th = np.radians(tgt[b] - sag(Gw, b).mean())
            Gn[:, tn.index(b)] = R.from_euler("x", th).as_matrix() @ Gw[:, tn.index(b)]
        # rebuild the locals: chain bones from the new worlds, legs keep their old worlds,
        # everything else keeps its local rotation.
        keep_world = {tn.index(s + n) for s in ("Left", "Right") for n in ("UpperLeg",)}
        Lnew = Ls.copy()
        for t in range(T):
            p = par[t]
            if tn[t] in chain or t in keep_world:
                pg = Gn[:, p] if p >= 0 else np.tile(np.eye(3), (len(Ls), 1, 1))
                Lnew[:, t] = np.einsum("fji,fjk->fik", pg, Gn[:, t])
            if p >= 0 and tn[t] not in chain:
                Gn[:, t] = Gn[:, p] @ Lnew[:, t] if t not in keep_world else Gw[:, t]
        Ls = Lnew
        Gw, Pw = fk_target(Ls, hp_ip)
        print("posture after  (deg fwd):", {b: round(float(sag(Gw, b).mean()), 1) for b in chain})

    # Ground: stance ankle at its rest height (flat foot), from the target FK.
    Gw, Pw = fk_target(Ls, hp_ip)
    feet = [tn.index("LeftFoot"), tn.index("RightFoot")]
    toes = [tn.index("LeftToes"), tn.index("RightToes")]
    low = np.minimum(np.minimum(Pw[:, feet[0], 1], Pw[:, feet[1], 1]),
                     np.minimum(Pw[:, toes[0], 1], Pw[:, toes[1], 1]))
    ankle_rest = tg_org[feet[0], 1]
    lift = ankle_rest - np.percentile(low, 5) + a.ground
    hp_ip[:, 1] += lift

    # Start on a left heel strike: left ankle furthest ahead of the hips.
    shift = 0
    if a.mode == "walk":
        Gw, Pw = fk_target(Ls, hp_ip)
        rel = Pw[:, feet[0], 2] - Pw[:, hips_i, 2]
        shift = int(np.argmax(rel))
    Ls = np.roll(Ls, -shift, axis=0); hp_ip = np.roll(hp_ip, -shift, axis=0)

    # Resample (periodic) to the output fps.
    length = N * ft
    n_out = max(2, int(round(length * a.fps)))
    tt = np.arange(n_out) / n_out * N
    out_rot = {}
    for t in range(T):
        if tn[t] not in MAP:
            continue
        q = R.from_matrix(np.concatenate([Ls[:, t], Ls[:1, t]]))
        sl = Slerp(np.arange(N + 1), q)
        out_rot[tn[t]] = sl(tt).as_quat().tolist()
    hpx = np.concatenate([hp_ip, hp_ip[:1]])
    out_pos = np.stack([np.interp(tt, np.arange(N + 1), hpx[:, k]) for k in range(3)], 1)

    Gw, Pw = fk_target(Ls, hp_ip)
    for k in feet:
        print(f"{tn[k]} range xz cm: {np.ptp(Pw[:, k, 0])*100:.1f} {np.ptp(Pw[:, k, 2])*100:.1f}  y {np.ptp(Pw[:, k, 1])*100:.1f}")
    spd = travel / (P * ft)
    info = {"source": a.bvh.split("/")[-1], "speed_mps": spd, "cycle_s": length,
            "stride_m": travel, "scale_m_per_unit": scale,
            "bob_cm": float(np.ptp(hp_ip[:, 1]) * 100)}
    print(json.dumps(info))
    json.dump({"length": length, "fps": a.fps, "motion_scale": ms, "info": info,
               "rot": out_rot, "hips_pos": ((out_pos - tl_org[root_i]) / ms).tolist()}, open(a.out, "w"))


if __name__ == "__main__":
    main()
