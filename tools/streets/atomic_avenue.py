#!/usr/bin/env python3
"""Atomic Avenue plan: see docs/LEVEL_AUTHORING.md. Writes levels/atomic_avenue.json.

Department stores with glass canopies and gaps between them, under lighter rain than Telstar Parade,
so attention stays on the man under the yellow umbrella. He steps out of a doorway a little way in
and walks to the inn ahead of the walker, stopping at the big store windows. Keep him in frame,
don't come within his glance (hold stop to hang back), and hide your face when he looks round.
"""
from street import Street

s = Street("atomic_avenue", "Atomic Avenue",
           "Department stores and mirrored glass. Good for window shopping. Good for watching a man's reflection.",
           aesthetic="neon", neon=0.8, rain=[[0.0, 0.7], [0.5, 0.85], [1.0, 0.95]],
           wind=[[0.0, 0.04], [0.3, 0.1], [0.6, 0.16], [1.0, 0.14]],
           gusts=False, par_speed=1.25)


def seam(tag, w, floors):
    """A narrow wall seam between stores. The blank sign stops the retro kit painting a filler name on it."""
    s.lot(tag, w, "wall", "none", sign=" ", floors=floors)


def shop(tag, w, style, cover, sign=None, **kw):
    """Every signed shop on this street gets tube lettering, whichever kit era the builder picks."""
    s.lot(tag, w, style, cover, sign=sign, neon=bool(sign), **kw)


def store(tag, w, sign, color, floors=6, **kw):
    """A department store: a wide lit front under a glass canopy, the kind he stops to look into."""
    shop(tag, w, "shop_lit", "awning", sign=sign, color=color, floors=floors, awning_style="bubble", **kw)


# 1. Atom Plaza: continuous canopies, his doorway, the first short gaps
store("plaza", 6, "ATOMIC", "teal", floors=5)
shop("automat", 8, "shop_lit", "awning", sign="AUTOMAT", color="red", floors=6, awning_style="googie")
shop("lobby", 6, "doorway", "awning", sign="ATOM HOUSE", color="blue", floors=8, awning_style="marquee")
shop("milk", 5, "shop_lit", "awning", sign="MILK BAR", color="orange", floors=4, awning_style="googie")
seam("seam1", 2.5, 4)
shop("radio", 6, "shop_lit", "awning", sign="RADIO", color="red", floors=4, awning_style="googie")
shop("lot1", 3, "vacant", "none", floors=0)
shop("cosmo", 6, "shop_dark", "awning", sign="COSMOS", color="green", floors=4)
# 2. Halcyon's: the first department store window, then gaps between stores
store("halcyon", 8, "HALCYON'S", "teal", floors=7)
seam("alley1", 3, 6)
shop("jets", 6, "shop_lit", "awning", sign="JET TRAVEL", color="blue", floors=4)
shop("lot2", 4, "vacant", "none", floors=0)
shop("drug", 6, "shop_lit", "awning", sign="DRUGS", color="green", floors=4, awning_style="googie")
store("meridian", 8, "MERIDIAN", "orange", floors=7)
seam("pipe1", 1.5, 6)
shop("tickets", 5, "shop_lit", "awning", sign="TICKETS", color="red", floors=4)
shop("lot2b", 3, "vacant", "none", floors=0)
shop("cafe", 6, "shop_lit", "awning", sign="ESPRESSO", color="teal", floors=4, awning_style="googie")
store("atomstore", 8, "ATOM STORES", "blue", floors=7)
# 3. Fission Street: open road, then the Kelvin & Co. arcade of windows
s.xing("fission", 8)
shop("bank", 6, "doorway", "awning", sign="SAVINGS", color="blue", floors=6, awning_style="marquee")
shop("lot3", 4, "vacant", "none", floors=0)
store("kelvin", 8, "KELVIN & CO", "red", floors=7)
shop("vac1", 4, "vacant", "none", floors=0)
store("kelvin2", 6, "KELVIN & CO", "red", floors=7)
seam("alley2", 3, 5)
shop("tv", 6, "shop_lit", "awning", sign="TELEVISIONS", color="teal", floors=4, awning_style="googie")
shop("lot4", 5, "vacant", "none", floors=0)
shop("records", 6, "shop_lit", "awning", sign="RECORDS", color="orange", floors=4, awning_style="googie")
# 4. Nucleon Square: wider gaps, a gutter, his longest window stop
s.xing("nucleon", 9)
store("nucleon_dept", 8, "NUCLEON", "blue", floors=8)
shop("lot5", 6, "vacant", "none", floors=0)
shop("diner", 6, "shop_lit", "awning", sign="SATURN DINER", color="red", floors=4, awning_style="googie")
seam("pipe2", 1.5, 5)
shop("volt", 5, "shop_lit", "awning", sign="VOLT", color="green", floors=4)
shop("lot6", 5, "vacant", "none", floors=0)
store("orbital", 8, "ORBITAL", "teal", floors=7)
shop("lot7", 4, "vacant", "none", floors=0)
shop("barber", 5, "shop_lit", "awning", sign="BARBER", color="blue", floors=4, awning_style="googie")
# 5. Isotope Row: the wind up, gaps between every store
s.xing("isotope", 8)
store("emporium", 8, "THE EMPORIUM", "orange", floors=8)
shop("lot8", 6, "vacant", "none", floors=0)
shop("hifi", 5, "shop_lit", "awning", sign="HI-FI", color="orange", floors=4, awning_style="googie")
seam("alley3", 3, 5)
shop("nova", 6, "shop_lit", "awning", sign="NOVA", color="blue", floors=4)
shop("lot9", 6, "vacant", "none", floors=0)
store("proton", 8, "PROTON", "green", floors=7)
shop("lot10", 5, "vacant", "none", floors=0)
shop("zap", 5, "shop_lit", "awning", sign="ZAP", color="red", floors=5, awning_style="googie")
seam("pipe3", 1.5, 6)
shop("flux", 5, "shop_lit", "awning", sign="FLUX", color="teal", floors=5, awning_style="googie")
# 6. The Electron Arcade: more windows, the gaps getting no shorter
shop("lot15", 5, "vacant", "none", floors=0)
store("electron", 8, "ELECTRON", "teal", floors=8)
seam("alley5", 3, 6)
shop("chrome", 6, "shop_lit", "awning", sign="CHROME DINER", color="red", floors=4, awning_style="googie")
shop("lot16", 6, "vacant", "none", floors=0)
store("quasar", 8, "QUASAR", "orange", floors=7)
shop("lot17", 6, "vacant", "none", floors=0)
shop("bowl", 6, "shop_lit", "awning", sign="BOWL", color="blue", floors=4, awning_style="googie")
seam("pipe5", 1.5, 5)
shop("ion", 5, "shop_lit", "awning", sign="ION", color="green", floors=5, awning_style="googie")
# 7. Positron Street, then the last stores before the inn
s.xing("positron", 9)
store("baxters", 8, "BAXTER'S", "red", floors=8)
shop("lot11", 6, "vacant", "none", floors=0)
shop("luna", 5, "shop_lit", "awning", sign="LUNA", color="green", floors=5, awning_style="googie")
seam("alley4", 3, 5)
store("isotope_dept", 8, "ISOTOPE", "blue", floors=7)
shop("lot12", 6, "vacant", "none", floors=0)
shop("pulsar", 5, "shop_lit", "awning", sign="PULSAR", color="orange", floors=5, awning_style="googie")
shop("lot13", 4, "vacant", "none", floors=0)
shop("lounge", 6, "shop_lit", "awning", sign="LOUNGE", color="red", floors=5, awning_style="googie")
shop("lot14", 5, "vacant", "none", floors=0)
seam("pipe4", 1.2, 6)
shop("mall", 5, "shop_lit", "awning", sign="GIFTS", color="orange", floors=6, awning_style="bubble")
shop("inn", 8, "inn", "awning", sign="THE ATOMIC INN", color="teal", floors=7, awning_style="bubble")
shop("tower", 8, "shop_dark", "awning", sign="TOWER", color="blue", floors=9, awning_style="bubble")
s.door("inn")

s.courier(appear_x=s.mid("lobby"), door_x=s.end_x, stops=[
    (s.mid("halcyon"), 3.0),
    (s.mid("meridian"), 2.5),
    (s.mid("kelvin"), 3.0),
    (s.mid("nucleon_dept"), 4.0),
    (s.mid("orbital"), 2.5),
    (s.mid("emporium"), 3.5),
    (s.mid("proton"), 3.0),
    (s.mid("electron"), 3.0),
    (s.mid("quasar"), 2.5),
    (s.mid("baxters"), 3.0),
    (s.mid("isotope_dept"), 2.5),
])

s.feature("puddle", s.mid("lot1"), w=1.0)
s.feature("puddle", s.mid("lot2"), w=1.2)
s.feature("gutter", s.mid("pipe1"))
s.feature("puddle", s.start("fission") + 1.2, w=1.4)
s.feature("puddle", s.mid("lot4"), w=1.2)
s.feature("puddle", s.start("nucleon") + 1.2, w=1.4)
s.feature("puddle", s.mid("lot5"), w=1.2)
s.feature("gutter", s.mid("pipe2"))
s.feature("puddle", s.mid("lot6"), w=1.2)
s.feature("puddle", s.start("isotope") + 1.2, w=1.4)
s.feature("puddle", s.mid("lot8"), w=1.4, deep=True)
s.feature("puddle", s.mid("lot9"), w=1.2)
s.feature("gutter", s.mid("pipe3"))
s.feature("puddle", s.mid("lot15"), w=1.2)
s.feature("puddle", s.mid("lot16"), w=1.4, deep=True)
s.feature("gutter", s.mid("pipe5"))
s.feature("puddle", s.start("positron") + 1.2, w=1.4)
s.feature("puddle", s.end("positron") - 1.2, w=1.4, deep=True)
s.feature("puddle", s.mid("lot11"), w=1.2)
s.feature("puddle", s.mid("lot12"), w=1.4, deep=True)
s.feature("puddle", s.mid("lot14"), w=1.2)
s.feature("gutter", s.mid("pipe4"))

for store_tag in ["plaza", "halcyon", "kelvin", "nucleon_dept", "emporium", "electron", "baxters"]:
    s.prop("atom_sign", s.start(store_tag) + 1.3)
s.prop("vending_machine_a", s.start("automat") + 1.2)
s.prop("bench", s.mid("automat") + 1.5)
s.prop("trash_bags", s.mid("seam1"))
s.prop("chainlink_fence_4", s.mid("lot1"))
s.prop("newspaper_box_b", s.start("halcyon") + 0.8)
s.prop("crates", s.mid("alley1"))
s.prop("phone_booth", s.mid("jets"))
s.prop("lamp_post", s.mid("lot2"))
s.prop("street_sign", s.start("fission") - 0.6)
s.prop("hydrant", s.end("fission") + 0.8)
s.prop("lamp_post", s.mid("lot3"))
s.prop("chainlink_fence_4", s.mid("vac1"))
s.prop("trash_bags", s.mid("alley2"))
s.prop("parking_meter", s.start("lot4") + 1.0)
s.prop("street_sign", s.start("nucleon") - 0.6)
s.prop("mailbox", s.end("nucleon") + 1.0)
s.prop("lamp_post", s.mid("lot5"))
s.prop("phone_booth", s.mid("diner") + 1.5)
s.prop("cardboard_boxes", s.start("lot6") + 1.0)
s.prop("lamp_post", s.mid("lot7"))
s.prop("street_sign", s.start("isotope") - 0.6)
s.prop("hydrant", s.end("isotope") + 0.8)
s.prop("lamp_post", s.mid("lot8"))
s.prop("trash_bags", s.mid("alley3"))
s.prop("chainlink_fence_4", s.mid("lot9"))
s.prop("trash_can", s.end("lot10") - 1.0)
s.prop("lamp_post", s.mid("lot15"))
s.feature("gutter", s.mid("alley5"))
s.prop("chainlink_fence_4", s.mid("lot16"))
s.prop("lamp_post", s.mid("lot17"))
s.prop("street_sign", s.start("positron") - 0.6)
s.prop("hydrant", s.end("positron") + 0.8)
s.prop("lamp_post", s.mid("lot11"))
s.prop("crates", s.mid("alley4"))
s.prop("parking_meter", s.start("lot12") + 1.0)
s.prop("lamp_post", s.mid("lot13"))
s.prop("sandwich_board", s.start("lounge") + 1.0)
s.prop("trash_can", s.end("lot14") - 1.5)
s.prop("bench", s.mid("mall") + 1.5)
s.prop("newspaper_box", s.end("inn") + 1.0)

s.set_piece("Atom Plaza", 0.0, s.end("cosmo"),
            "continuous canopies, then a man in a doorway steps out under a yellow umbrella: keep him in "
            "frame and hang back. Two short gaps between stores")
s.set_piece("Halcyon's", s.start("halcyon"), s.end("tickets"),
            "his first window stop: the walker has to stop well short of him (hold stop), then gaps "
            "between stores and a gutter, at his pace rather than the walker's")
s.set_piece("Fission Street", s.start("fission"), s.end("records"),
            "open road and the Kelvin & Co. windows: stopping behind him in the open, umbrella up")
s.set_piece("Nucleon Square", s.start("nucleon"), s.end("barber"),
            "his longest window stop, wider gaps and a gutter as the rain and wind rise")
s.set_piece("Isotope Row", s.start("isotope"), s.end("flux"),
            "gaps between every store and a gutter: keeping him in frame while the umbrella stays up")
s.set_piece("The Electron Arcade", s.start("lot15"), s.end("ion"),
            "two more windows between open lots and a gutter, the wind at its strongest")
s.set_piece("Positron Street", s.start("positron"), s.end("inn"),
            "the last stores and windows; he goes into the inn just ahead of the walker")

s.write()
