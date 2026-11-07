"""Street plans: write an authored levels/<id>.json from lots placed end to end.

A plan script (tools/streets/<id>.py) lists lots and crossings in walking order, then hangs
features, props and set pieces off named lots, so moving one lot shifts everything after it.

    python3 tools/streets/main_street.py      # rewrites levels/main_street.json, prints the plan
"""
import json
from pathlib import Path

LEVELS = Path(__file__).resolve().parent.parent.parent / "levels"


class Street:
    def __init__(self, id, name, blurb, aesthetic, neon, rain, wind, gusts=False):
        self.head = {"authored": True, "id": id, "name": name, "blurb": blurb, "aesthetic": aesthetic,
                     "neon": neon, "rain": rain, "wind": wind, "gusts": gusts}
        self.x = 0.0
        self.at = {}
        self.lots, self.crossings, self.features, self.props, self.set_pieces = [], [], [], [], []
        self.end_x = None

    def lot(self, tag, w, style, cover, sign=None, color=None, floors=2, tears=None, awning_style=None):
        lot = {"x": self.x, "w": float(w), "style": style, "cover": cover, "floors": floors}
        if sign:
            lot["sign"] = sign
        if cover == "awning":
            lot["awning_color"] = color
            if awning_style:
                lot["awning_style"] = awning_style
        if tears:
            lot["tears"] = tears
        self.lots.append(lot)
        self._place(tag, w)

    def xing(self, tag, w):
        self.crossings.append({"x": self.x, "w": float(w)})
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

    def prop(self, id, x):
        self.props.append({"id": id, "x": round(x, 2)})

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
        level = {**{k: level[k] for k in ["authored", "id", "name", "blurb", "aesthetic", "neon"]},
                 "length": self.x, "end_x": self.end_x,
                 **{k: level[k] for k in ["rain", "wind", "gusts"]}, **rest}
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
