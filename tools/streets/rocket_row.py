#!/usr/bin/env python3
"""Rocket Row plan: see docs/LEVEL_AUTHORING.md. Writes levels/rocket_row.json.

A hotel strip: chrome rocket-fin canopies, revolving doors with doormen beside them, and more neon
than wall, under heavier rain than Atomic Avenue that thickens toward the far end. The walker's
umbrella fires here. Five men wait under the hotel canopies among the doormen and open up as he
comes: soak each one (two clean hits), block his jets with the canopy, or hurry past and take some
water. Downpipes in the seams between hotels refill the shot. Midway a car idles in a side street
with a man in a slicker at the corner; once the walker has dealt with the man before it, the car
pulls out through the puddle at him.
"""
from street import Street

s = Street("rocket_row", "Rocket Row",
           "Hotels with red carpet, and doormen who don't look at you. Some of them aren't doormen.",
           aesthetic="neon", neon=0.9, rain=[[0.0, 0.95], [0.5, 1.15], [1.0, 1.3]],
           wind=[[0.0, 0.05], [0.3, 0.12], [0.55, 0.2], [0.8, 0.14], [1.0, 0.18]],
           gusts=False, par_speed=1.15)


def seam(tag, w, floors=6):
    """A narrow wall seam between hotels; the blank sign keeps the retro kit from naming it."""
    s.lot(tag, w, "wall", "none", sign=" ", floors=floors)


def gap(tag, w):
    s.lot(tag, w, "vacant", "none", floors=0)


def shop(tag, w, sign, color, style="shop_lit", floors=4, **kw):
    """A lounge, bar or travel office under a rocket-fin canopy, its name in tube lettering."""
    s.lot(tag, w, style, "awning", sign=sign, color=color, floors=floors, awning_style="rocket",
          neon=bool(sign and sign.strip()), **kw)


def hotel(tag, w, sign, color, floors=9, **kw):
    """A hotel front: a doorway under a rocket-fin canopy, with a revolving door and a doorman."""
    shop(tag, w, sign, color, style="doorway", floors=floors, **kw)
    s.prop("revolving_door", s.start(tag) + 2.2)
    s.figure(s.start(tag) + 0.7)


# 1. The Starliner: continuous canopies, the first doormen
hotel("starliner", 8, "THE STARLINER", "teal", floors=10)
shop("cocktails", 6, "COCKTAILS", "red")
hotel("vega", 8, "HOTEL VEGA", "blue")
seam("seam1", 1.5)
shop("tours", 5, "SPACE TOURS", "orange")
gap("lot1", 3)
shop("barber", 5, "BARBER", "green")
gap("lot2", 4)
shop("cafe", 6, "CAFE", "red")
# 2. The Orbit: the first man waits under its canopy
gap("lot2b", 3)
shop("grill", 6, "ORBIT GRILL", "red")
hotel("orbit", 8, "HOTEL ORBIT", "teal")
gap("lot3", 4)
shop("records", 5, "RECORDS", "blue")
seam("seam2", 2.5)
shop("lounge", 6, "LUNAR LOUNGE", "orange")
gap("lot4", 4)
shop("drugs", 6, "DRUGS", "green")
hotel("nova", 8, "HOTEL NOVA", "blue")
# 3. Thrust Street, the Comet and the second man
s.xing("thrust", 8, car=True)
shop("travel", 8, "AIR TRAVEL", "blue")
gap("lot5a", 4)
hotel("comet", 8, "THE COMET", "red")
gap("lot5", 6)
shop("bar", 5, "SKY BAR", "teal")
seam("seam3", 2.0)
shop("florist", 5, "FLOWERS", "green")
gap("lot6", 5)
shop("deli", 6, "DELI", "orange")
# 4. The first downpipe, then the Apollo, the third man and a car in Gantry Lane
gap("lot6b", 4)
shop("hats", 5, "HATS", "blue")
seam("pipe1", 1.5)
shop("jewels", 6, "JEWELLERS", "blue")
gap("lot7", 5)
shop("casino", 6, "CASINO", "red")
hotel("apollo", 8, "THE APOLLO", "teal", floors=11)
shop("apollo_bar", 4, "BAR", "teal")
s.xing("gantry", 9)
# 5. Booster Row: wider gaps as the rain thickens, the fourth man
shop("tailor", 8, "TAILOR", "green")
gap("lot8", 6)
shop("radio", 5, "RADIO", "orange")
seam("seam4", 2.5)
shop("motors", 6, "JET MOTORS", "red")
gap("lot8b", 5)
hotel("satellite", 8, "SATELLITE", "blue")
gap("lot9", 6)
shop("diner", 6, "COUNTDOWN DINER", "red")
gap("lot10", 7)
shop("shoes", 5, "SHOES", "teal")
gap("lot10a", 6)
shop("cleaners", 6, "DRY CLEANERS", "green")
hotel("meteor", 8, "THE METEOR", "red")
shop("photo", 5, "CAMERAS", "orange")
# 6. Ignition Street, the second downpipe and the Stratos with the last man
s.xing("ignition", 8, car=True)
shop("bank", 6, "SAVINGS", "blue", style="doorway")
gap("lot11", 3)
shop("pipe_bar", 6, "MARTINIS", "orange")
seam("pipe2", 1.5)
shop("cinema", 6, "ROCKETORAMA", "red")
gap("lot12", 4)
shop("bowling", 6, "BOWL", "green")
gap("lot12b", 5)
hotel("stratos", 8, "THE STRATOS", "teal", floors=12)
gap("lot13", 7)
shop("lunch", 5, "LUNCH", "green")
seam("seam5", 2.0)
shop("gifts", 6, "GIFTS", "blue")
gap("lot14", 6)
shop("nite", 6, "NITE CLUB", "red")
gap("lot15", 6)
shop("pharm", 5, "PHARMACY", "teal")
seam("seam6", 2.5)
shop("cigars", 5, "CIGARS", "green")
gap("lot16", 5)
shop("rooms", 6, "ROOMS", "orange")
shop("inn", 8, "THE LAUNCHPAD INN", "teal", style="inn", floors=9)
shop("tower", 8, "SKYLINE", "blue", style="shop_dark", floors=12)
s.door("inn")

# The men wait under the hotel canopies, clear of the revolving doors.
H = ["orbit", "comet", "apollo", "satellite", "stratos"]
for tag in H:
    s.henchman(s.start(tag) + 5.4)
s.pickup("gantry", after=2)
# Each resume starts clear of the men: no one in range for the first few metres.
s.checkpoints = [s.start("travel") + 1.1, s.start("tailor") + 1.5, s.start("pipe_bar") + 1.2]

s.feature("puddle", s.mid("lot1"), w=1.0)
s.feature("puddle", s.mid("lot2"), w=1.2)
s.feature("puddle", s.mid("lot3"), w=1.2)
s.feature("puddle", s.mid("lot4"), w=1.4)
s.feature("puddle", s.start("thrust") + 1.2, w=1.4, deep=True)
s.feature("puddle", s.mid("lot5"), w=1.2)
s.feature("puddle", s.mid("lot6"), w=1.2)
s.feature("gutter", s.mid("pipe1"))
s.feature("puddle", s.mid("lot7"), w=1.2)
s.feature("puddle", s.start("gantry") + 1.2, w=1.6, deep=True)
s.feature("puddle", s.mid("lot8"), w=1.2)
s.feature("puddle", s.mid("lot9"), w=1.4)
s.feature("puddle", s.mid("lot10"), w=1.2)
s.feature("puddle", s.start("ignition") + 1.2, w=1.4, deep=True)
s.feature("puddle", s.mid("lot11"), w=1.2)
s.feature("gutter", s.mid("pipe2"))
s.feature("puddle", s.mid("lot12"), w=1.4)
s.feature("puddle", s.mid("lot13"), w=1.4, deep=True)
s.feature("puddle", s.mid("lot14"), w=1.2)
s.feature("puddle", s.mid("lot10a"), w=1.2)
s.feature("puddle", s.mid("lot15"), w=1.2)
s.feature("puddle", s.mid("lot16"), w=1.2)

s.hint(s.mid("pipe1") - 0.6, "Low on water? Stop under the downpipe with the umbrella open ({stop}).", 5.0)

s.prop("bench", s.mid("cocktails") + 1.5)
s.prop("newspaper_box_b", s.start("tours") + 0.8)
s.prop("lamp_post", s.mid("lot1"))
s.prop("sandwich_board", s.start("barber") + 1.0)
s.prop("lamp_post", s.mid("lot2"))
s.prop("lamp_post", s.mid("lot3"))
s.prop("phone_booth", s.mid("records"))
s.prop("trash_can", s.end("lounge") - 0.8)
s.prop("street_sign", s.start("thrust") - 0.6)
s.prop("hydrant", s.end("thrust") + 0.8)
s.prop("lamp_post", s.mid("lot5"))
s.prop("vending_machine_a", s.start("bar") + 1.0)
s.prop("lamp_post", s.mid("lot6"))
s.prop("mailbox", s.end("deli") - 1.0)
s.prop("lamp_post", s.mid("lot6b"))
s.prop("lamp_post", s.mid("lot7"))
s.prop("sandwich_board", s.start("casino") + 1.0)
s.prop("hydrant", s.end("gantry") + 0.8)
s.prop("lamp_post", s.mid("lot8"))
s.prop("trash_bags", s.mid("seam4"))
s.prop("lamp_post", s.mid("lot9"))
s.prop("parking_meter", s.start("lot10") + 1.0)
s.prop("lamp_post", s.mid("lot10a"))
s.prop("lamp_post", s.mid("lot15"))
s.prop("trash_can", s.mid("lot16"))
s.prop("street_sign", s.start("ignition") - 0.6)
s.prop("hydrant", s.end("ignition") + 0.8)
s.prop("lamp_post", s.mid("lot11"))
s.prop("newspaper_box", s.end("pipe_bar") - 1.0)
s.prop("lamp_post", s.mid("lot12"))
s.prop("lamp_post", s.mid("lot13"))
s.prop("bench", s.mid("gifts") + 1.5)
s.prop("lamp_post", s.mid("lot14"))
s.prop("newspaper_box", s.end("inn") + 1.0)

s.set_piece("The Starliner", 0.0, s.end("lot2"),
            "continuous rocket-fin canopies past the first hotels and their doormen, then short gaps; the "
            "umbrella's shot is introduced")
s.set_piece("Hotel Orbit", s.start("grill"), s.end("lot4"),
            "the first man under a hotel canopy opens up as the walker comes: soak him, block his jets "
            "tilted forward then back, or hurry past")
s.set_piece("The Comet", s.start("thrust"), s.end("lot6"),
            "a car crossing, then the second man between gaps; the shot runs low")
s.set_piece("The Apollo and Gantry Lane", s.start("deli"), s.end("gantry"),
            "the first downpipe refills the shot just before the third man; a car idles dark in Gantry "
            "Lane with a man in a yellow slicker at the corner, who gets in once the third man is dealt "
            "with, and the car pulls out through the puddle at the walker")
s.set_piece("Booster Row", s.start("tailor"), s.end("shoes"),
            "wider gaps as the rain thickens, the fourth man at the Satellite")
s.set_piece("The Stratos", s.start("ignition"), s.end("inn"),
            "a car crossing, the second downpipe, the last man at the Stratos, then gaps to the inn")

s.write()
