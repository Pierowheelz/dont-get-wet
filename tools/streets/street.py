"""Street plans: write an authored levels/<id>.json from lots placed end to end.

A plan script (tools/streets/<id>.py) lists lots and crossings in walking order, then hangs
features, props and set pieces off named lots, so moving one lot shifts everything after it.

    python3 tools/streets/main_street.py      # rewrites levels/main_street.json, prints the plan
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import level_preview

LEVELS = Path(__file__).resolve().parent.parent.parent / "levels"
TRACK_PAST = 40.0   # a default track runs this far past both ends of the street, so no end shows


class Street:
    def __init__(self, id, name, blurb, aesthetic, neon, rain, wind, gusts=False, par_speed=None):
        self.head = {"authored": True, "id": id, "name": name, "blurb": blurb, "aesthetic": aesthetic,
                     "neon": neon, "rain": rain, "wind": wind, "gusts": gusts}
        self.par_speed = par_speed   # None: the global tunable
        self.x = 0.0
        self.at = {}
        self.lots, self.crossings, self.features, self.props, self.set_pieces = [], [], [], [], []
        self.figures = []
        self.hints = []
        self.follower_appear = []
        self.attackers = []
        self.henchmen = []
        self.pickup_rec = None
        self.drive_bys = []
        self.slickers = []
        self.courier_rec = None
        self.track_rec = None
        self.viaducts = []
        self.end_x = None
        self.checkpoints = None   # set by hand to override the solver

    def lot(self, tag, w, style, cover, sign=None, color=None, floors=2, tears=None, awning_style=None,
            neon=False, **extra):
        """extra: style-specific fields, e.g. a forecourt's note="CLOSED" or lit=True."""
        lot = {"x": self.x, "w": float(w), "style": style, "cover": cover, "floors": floors, **extra}
        if sign:
            lot["sign"] = sign
        if cover == "awning" and color:
            lot["awning_color"] = color
            if awning_style:
                lot["awning_style"] = awning_style
        if tears:
            lot["tears"] = tears
        if neon:
            lot["neon"] = True
        self.lots.append(lot)
        self._place(tag, w)

    def xing(self, tag, w, car=False):
        c = {"x": self.x, "w": float(w)}
        if car:
            c["car"] = True
        self.crossings.append(c)
        self._place(tag, w)

    def _place(self, tag, w):
        assert tag not in self.at, f"duplicate tag {tag}"
        self.at[tag] = (self.x, float(w))
        self.x += w

    def start(self, tag): return self.at[tag][0]
    def end(self, tag): return self.at[tag][0] + self.at[tag][1]
    def mid(self, tag): return self.at[tag][0] + self.at[tag][1] / 2

    def feature(self, type, x, **kw):
        self.features.append({"type": type, "x": x, **kw})

    def prop(self, id, x, **kw):
        self.props.append({"id": id, "x": round(x, 2), **kw})

    def figure(self, x, facing="street"):
        """A man in the walker's own suit, standing in a doorway facing up the street (or, with
        facing="away", toward the building with his back to the camera). Scenery only."""
        f = {"x": round(x, 2)}
        if facing != "street":
            f["facing"] = facing
        self.figures.append(f)

    def hint(self, x, text, dur=4.0):
        """A HUD line shown once per attempt as the walker passes x. Takes the {stop}/{hurry}/... tokens."""
        self.hints.append({"x": round(x, 2), "text": text, "dur": dur})

    def follower(self, x, hold):
        """The follower walks in from the left edge when the walker passes x and holds there for hold s."""
        self.follower_appear.append({"x": round(x, 2), "hold": hold})

    def attacker(self, x, shots=5, gap=None, wait=None, hint=None, hit=None):
        """A pursuer who enters from the left once the walker passes x, closes in behind him and fires
        `shots` telegraphed jets, then drops back. One at a time: a later one waits for the last to go.
        gap: how far behind he holds (default 5.8 m). wait: he stands posted at that x under cover from
        the start and fires from there once the walker reaches x, then follows. hint: shown as he comes.
        hit: wetness of one of his shots landing in full (default wet_jet_hit)."""
        a = {"x": round(x, 2), "shots": int(shots)}
        if gap is not None:
            a["gap"] = float(gap)
        if wait is not None:
            a["wait"] = round(wait, 2)
        if hint is not None:
            a["hint"] = hint
        if hit is not None:
            a["hit"] = float(hit)
        self.attackers.append(a)

    def drive_by(self, x):
        """A car that comes up the near lane from behind once the walker passes x, splashes him as it
        passes, then a passenger fires one telegraphed shot from ahead."""
        self.drive_bys.append({"x": round(x, 2)})

    def slicker(self, x, z=0.8, facing=1, pose="stand", smoking=False):
        """A man in a yellow slicker standing at x on lane z (scenery). facing 1 or -1;
        pose "stand", "watch" (turned toward the street) or "walk"."""
        f = {"x": round(x, 2), "z": z, "facing": facing, "pose": pose}
        if smoking:
            f["smoking"] = True
        self.slickers.append(f)

    def henchman(self, x):
        """A man waiting under cover at x who fires telegraphed jets at the walker on a timer while he
        is in range: from ahead as he comes, then from behind once he has passed."""
        self.henchmen.append({"x": round(x, 2)})

    def pickup(self, xing_tag, after):
        """A car idling in the side street xing_tag (a crossing without `car`) and a man in a slicker
        waiting at its corner. Once henchman number `after` (0-based, in x order) is soaked or passed,
        he gets in and the car pulls out through the puddle at the walker."""
        self.pickup_rec = {"x": self.start(xing_tag), "after": int(after)}

    def courier(self, appear_x, door_x, stops=()):
        """A scripted pedestrian the walker must keep in frame: he steps out of a doorway at appear_x,
        walks ahead to the door at door_x and stops at each (x, dur) in stops to look in a window."""
        self.courier_rec = {"appear_x": round(appear_x, 2), "door_x": round(door_x, 2),
                            "stops": [{"x": round(x, 2), "dur": float(d)} for x, d in sorted(stops)]}

    def track(self, gap, style="monorail", x0=None, x1=None):
        """An elevated railway (style "monorail" or "railway") from x0 to x1 (default: the whole street and TRACK_PAST beyond it). Trains
        set off from x1 a random gap = (min, max) s apart, rolled afresh each attempt, run right to left
        and shed a sheet of water behind them wherever they are."""
        self.track_rec = {"x0": x0, "x1": x1, "style": style, "gap": [float(gap[0]), float(gap[1])]}

    def viaduct(self, from_tag, to_tag, style="monorail"):
        """A deck span under the track (a railway's: a run of brick arches) from the start of from_tag
        to the end of to_tag: cover."""
        self.viaducts.append({"x0": self.start(from_tag), "x1": self.end(to_tag), "style": style})

    def set_piece(self, name, x0, x1, teaches):
        self.set_pieces.append({"name": name, "x0": x0, "x1": x1, "teaches": teaches})

    def door(self, inn_tag, local_x=4.0):
        """The inn kit's door sits local_x into its lot; the level ends there."""
        self.end_x = self.start(inn_tag) + local_x

    def write(self):
        assert self.end_x is not None, "call door() on the inn lot"
        level = dict(self.head)
        rest = {"set_pieces": self.set_pieces, "lots": self.lots, "crossings": self.crossings,
                "features": sorted(self.features, key=lambda f: f["x"]),
                "props": sorted(self.props, key=lambda p: p["x"])}
        if self.figures:
            rest["figures"] = self.figures
        if self.hints:
            rest["hints"] = sorted(self.hints, key=lambda h: h["x"])
        if self.follower_appear:
            rest["follower"] = {"appear": sorted(self.follower_appear, key=lambda a: a["x"])}
        if self.attackers:
            rest["attackers"] = sorted(self.attackers, key=lambda a: a["x"])
        if self.drive_bys:
            rest["drive_bys"] = sorted(self.drive_bys, key=lambda a: a["x"])
        if self.slickers:
            rest["slickers"] = self.slickers
        if self.courier_rec:
            rest["courier"] = self.courier_rec
        if self.henchmen:
            rest["henchmen"] = sorted(self.henchmen, key=lambda h: h["x"])
        if self.pickup_rec:
            rest["pickup"] = self.pickup_rec
        assert self.track_rec or not self.viaducts, "deck spans need s.track()"
        if self.track_rec:
            t = dict(self.track_rec)
            t["x0"] = -TRACK_PAST if t["x0"] is None else t["x0"]
            t["x1"] = round(self.x + TRACK_PAST, 2) if t["x1"] is None else t["x1"]
            rest["track"] = t
        if self.viaducts:
            rest["viaducts"] = self.viaducts
        level = {**{k: level[k] for k in ["authored", "id", "name", "blurb", "aesthetic", "neon"]},
                 "length": self.x, "end_x": self.end_x, "checkpoints": [],
                 **{k: level[k] for k in ["rain", "wind", "gusts"]}, **rest}
        if self.par_speed is not None:
            level["par_speed"] = self.par_speed
        level["checkpoints"] = self.checkpoints or level_preview.solve_checkpoints(level_preview.Street(level))
        path = LEVELS / f"{level['id']}.json"
        path.write_text(_dump(level))
        tags = list(self.at.items())
        for i, (t, (a, w)) in enumerate(tags):
            print(f"{t:>12} {a:6.1f}-{a + w:6.1f}", end="\n" if i % 4 == 3 else "   ")
        print(f"\n{path.name}: length {self.x} end_x {self.end_x}")


def _dump(v):
    """One lot / feature / prop per line, so the file reads like a street plan and diffs cleanly."""
    lines = ["{"]
    items = list(v.items())
    for i, (k, val) in enumerate(items):
        comma = "," if i < len(items) - 1 else ""
        if isinstance(val, list) and val and isinstance(val[0], dict):
            lines.append(f' "{k}": [')
            lines.append(",\n".join("  " + json.dumps(r) for r in val))
            lines.append(f" ]{comma}")
        else:
            lines.append(f' "{k}": {json.dumps(val)}{comma}')
    lines.append("}")
    return "\n".join(lines) + "\n"
