#!/usr/bin/env python3
"""Telstar Parade plan: see docs/LEVEL_AUTHORING.md. Writes levels/telstar_parade.json.

Neon Junction's chrome under an elevated monorail that runs the whole street. A train comes every 12 s
and sheds a sheet of water wherever it is: wait it out under an awning, hurry through, or keep the
umbrella upright, which in open sky means giving up the tilt into the wind. Four glass deck spans are
long cover from the rain, not from the wash. Between them, the usual mix of gaps, gutters and cars.
Every payphone rings as the walker nears it.
"""
from street import Street

s = Street("telstar_parade", "Telstar Parade",
           "Under the monorail, the trains shake the rain loose. Every payphone on the street is ringing.",
           aesthetic="neon", neon=0.9, rain=[[0.0, 0.85], [0.5, 1.1], [1.0, 1.25]],
           wind=[[0.0, 0.08], [0.2, 0.14], [0.45, 0.3], [0.55, 0.38], [0.62, 0.0], [0.68, -0.25], [1.0, -0.32]],
           gusts=True, par_speed=1.4)


def seam(tag, w, floors):
    """A narrow wall seam between shops. The blank sign stops the retro kit painting a filler name on it."""
    s.lot(tag, w, "wall", "none", sign=" ", floors=floors)


def shop(tag, w, style, cover, sign=None, **kw):
    """Every signed shop on this street gets tube lettering, whichever kit era the builder picks."""
    s.lot(tag, w, style, cover, sign=sign, neon=bool(sign), **kw)


# 1. The Telstar Arcade: finned kiosks and chrome canopies, continuous cover
shop("telstar", 6, "shop_lit", "awning", sign="TELSTAR", color="teal", floors=5, awning_style="bubble")
shop("automat", 8, "shop_lit", "awning", sign="AUTOMAT", color="red", floors=6, awning_style="googie")
shop("booth1", 5, "shop_dark", "awning", sign="PHONES", color="blue", floors=5, awning_style="googie")
shop("milk", 6, "shop_lit", "awning", sign="MILK BAR", color="orange", floors=4, awning_style="bubble")
# first gaps
seam("seam1", 2.5, 4)
shop("radio", 5, "shop_lit", "awning", sign="RADIO", color="red", floors=3)
shop("lot1", 4, "vacant", "none", floors=0)
shop("cosmo", 5, "shop_dark", "awning", sign="COSMOS", color="green", floors=3)
shop("alley1", 3, "wall", "none", floors=4)
shop("jets", 6, "shop_lit", "awning", sign="JET TRAVEL", color="blue", floors=3)
shop("lot0", 4, "vacant", "none", floors=0)
# Comet Street: the first car, with cover along its approach
shop("drug", 6, "shop_lit", "awning", sign="DRUGS", color="green", floors=4)
shop("tickets", 5, "shop_lit", "awning", sign="TICKETS", color="red", floors=4, awning_style="googie")
s.xing("comet", 7, car=True)
shop("bank", 6, "doorway", "awning", sign="SAVINGS", color="blue", floors=6)
# 2. The Parade Viaduct: the first trains, with awnings under the deck to wait beneath
shop("tv", 6, "shop_lit", "awning", sign="TELEVISIONS", color="teal", floors=4, awning_style="bubble")
shop("vac1", 4, "vacant", "none", floors=0)
shop("diner", 6, "shop_lit", "awning", sign="SATURN DINER", color="red", floors=4, awning_style="googie")
seam("seam2", 3, 5)
shop("records", 6, "shop_lit", "awning", sign="RECORDS", color="orange", floors=4, awning_style="bubble")
shop("vac2", 4, "vacant", "none", floors=0)
shop("cafe", 5, "shop_lit", "awning", sign="ESPRESSO", color="teal", floors=4, awning_style="googie")
# out from under the deck: open sky and a gutter
shop("lot2", 5, "vacant", "none", floors=0)
shop("volt", 6, "shop_lit", "awning", sign="VOLT", color="green", floors=3)
seam("pipe1", 1.5, 5)
shop("atomic", 6, "shop_dark", "awning", sign="ATOMIC", color="teal", floors=3)
shop("lot3", 6, "vacant", "none", floors=0)
shop("rocket", 8, "shop_lit", "awning", sign="ROCKET BURGER", color="orange", floors=3)
shop("alley2", 3, "wall", "none", floors=4)
shop("sat", 5, "shop_lit", "awning", sign="SATELLITE", color="blue", floors=3)
shop("deli", 6, "shop_dark", "awning", sign="DELI", color="red", floors=3)
shop("barber", 4, "shop_lit", "awning", sign="BARBER", color="blue", floors=3)
# Orbit Avenue: a second car, the wind rising
s.xing("orbit", 9, car=True)
shop("credit", 8, "shuttered", "awning", sign="CREDIT", color="green", floors=7)
shop("lot4", 7, "vacant", "none", floors=0)
shop("chrome", 6, "shop_lit", "awning", sign="CHROME DINER", color="red", floors=3, awning_style="bubble")
# 3. The Express Viaduct: trains closer together, longer bare stretches under the deck
shop("laund", 5, "shop_lit", "awning", sign="LAUNDERETTE", color="teal", floors=4, awning_style="googie")
shop("vac3", 6, "vacant", "none", floors=0)
shop("bowl", 5, "shop_lit", "awning", sign="BOWL", color="red", floors=4, awning_style="bubble")
shop("shut1", 7, "shuttered", "none", floors=4)
shop("hifi", 5, "shop_lit", "awning", sign="HI-FI", color="orange", floors=4, awning_style="googie")
shop("vac4", 5, "vacant", "none", floors=0)
shop("nova", 4, "shop_lit", "awning", sign="NOVA", color="blue", floors=4, awning_style="bubble")
# the gutter run: googie awnings split by pouring seams
shop("lot5", 6, "vacant", "none", floors=0)
shop("zap", 5, "shop_lit", "awning", sign="ZAP", color="red", floors=5, awning_style="googie")
seam("seamA", 1.2, 6)
shop("flux", 4, "shop_lit", "awning", sign="FLUX", color="blue", floors=5, awning_style="googie")
seam("seamB", 1.2, 6)
shop("ion", 5, "shop_lit", "awning", sign="ION", color="teal", floors=5, awning_style="googie")
shop("lot6", 8, "vacant", "none", floors=0)
shop("quasar", 6, "shop_lit", "awning", sign="QUASAR", color="orange", floors=4)
# 4. The Junction Viaduct: the wind turns into a headwind under the deck
shop("disco", 5, "shop_lit", "awning", sign="DISCO", color="blue", floors=5, awning_style="bubble")
shop("vac6", 6, "vacant", "none", floors=0)
shop("luna", 5, "shop_lit", "awning", sign="LUNA", color="green", floors=5, awning_style="googie")
seam("seam4", 4, 5)
shop("pulsar", 5, "shop_lit", "awning", sign="PULSAR", color="orange", floors=5, awning_style="bubble")
shop("vac7", 5, "vacant", "none", floors=0)
shop("orb", 4, "shop_lit", "awning", sign="ORB", color="teal", floors=5, awning_style="googie")
# into the headwind: a torn marquee with a gutter in the tear, then Sputnik Street's car
shop("lot7", 4, "vacant", "none", floors=0)
shop("meteor", 6, "shop_dark", "awning", sign="METEOR", color="red", floors=4, awning_style="marquee",
     tears=[[2.4, 3.6]])
shop("alley4", 3, "wall", "none", floors=5)
shop("lido", 8, "shop_lit", "awning", sign="LIDO", color="orange", floors=7, awning_style="bubble")
shop("cyber", 6, "shop_lit", "awning", sign="CYBER", color="teal", floors=4)
shop("tube", 6, "shop_lit", "awning", sign="TUBES", color="blue", floors=4)
s.xing("sputnik", 9, car=True)
shop("vision", 8, "shop_lit", "awning", sign="VISION", color="teal", floors=7, awning_style="googie")
shop("lot8", 6, "vacant", "none", floors=0)
shop("plasma", 5, "shop_lit", "awning", sign="PLASMA", color="green", floors=4)
seam("alley5", 3, 5)
# 5. Telstar Station: the last span, the station stairs and the phone beneath them
shop("kiosk", 5, "shop_lit", "awning", sign="KIOSK", color="blue", floors=5, awning_style="bubble")
shop("vac8", 5, "vacant", "none", floors=0)
shop("station", 8, "doorway", "awning", sign="TELSTAR STATION", color="teal", floors=6, awning_style="marquee")
shop("stairs", 6, "wall", "none", sign=" ", floors=6)
shop("lounge", 5, "shop_lit", "awning", sign="LOUNGE", color="red", floors=5, awning_style="googie")
shop("vac9", 5, "vacant", "none", floors=0)
shop("hotel", 4, "shop_lit", "awning", sign="ROOMS", color="orange", floors=6, awning_style="bubble")
# the last open lot, then the inn
shop("lot9", 6, "vacant", "none", floors=0)
seam("pipe2", 1.2, 6)
shop("mall", 5, "shop_lit", "awning", sign="GIFTS", color="orange", floors=6, awning_style="bubble")
shop("inn", 8, "inn", "awning", sign="THE RAINY DAY INN", color="red", floors=6, awning_style="bubble")
shop("tower", 8, "shop_dark", "awning", sign="TOWER", color="teal", floors=8, awning_style="bubble")
s.door("inn")

s.track(period=12.0, phase=9.0)
s.viaduct("tv", "cafe")
s.viaduct("laund", "nova")
s.viaduct("disco", "orb")
s.viaduct("kiosk", "hotel")

s.feature("puddle", s.mid("lot1"), w=1.0)
s.feature("puddle", s.start("comet") + 1.2, w=1.4)
s.feature("puddle", s.mid("vac1"), w=1.0)
s.feature("puddle", s.mid("vac2"), w=1.2)
s.feature("puddle", s.mid("lot2"), w=1.2)
s.feature("gutter", s.mid("pipe1"))
s.feature("puddle", s.mid("lot3"), w=1.2)
s.feature("puddle", s.start("orbit") + 1.2, w=1.4)
s.feature("puddle", s.mid("lot4"), w=1.2, deep=True)
s.feature("puddle", s.mid("lot5"), w=1.2)
s.feature("gutter", s.mid("seamA"))
s.feature("gutter", s.mid("seamB"))
s.feature("puddle", s.mid("lot6"), w=1.4)
s.feature("puddle", s.mid("vac6"), w=1.2)
s.feature("puddle", s.mid("seam4"), w=1.0)
s.feature("puddle", s.mid("vac7"), w=1.2)
s.feature("puddle", s.mid("lot7"), w=1.4, deep=True)
s.feature("gutter", s.mid("pipe2"))
s.feature("gutter", s.start("meteor") + 3.0)
s.feature("puddle", s.start("sputnik") + 1.2, w=1.4)
s.feature("puddle", s.end("sputnik") - 1.2, w=1.4, deep=True)
s.feature("puddle", s.mid("lot8"), w=1.2)
s.feature("puddle", s.mid("lot9"), w=1.4, deep=True)

s.prop("phone_booth", s.mid("booth1"), ring=True)
s.prop("vending_machine_a", s.start("automat") + 1.2)
s.prop("bench", s.mid("automat") + 1.5)
s.prop("trash_bags", s.mid("seam1"))
s.prop("chainlink_fence_4", s.mid("lot1"))
s.prop("crates", s.mid("alley1"))
s.prop("street_sign", s.start("comet") - 0.6)
s.prop("hydrant", s.end("comet") + 0.8)
s.prop("newspaper_box_b", s.start("tv") + 0.8)
s.prop("phone_booth", s.mid("diner") + 1.5, ring=True)
s.prop("trash_bags", s.mid("seam2"))
s.prop("vending_machine_b", s.start("records") + 1.0)
s.prop("cardboard_boxes", s.mid("vac2"))
s.prop("cardboard_boxes", s.start("lot3") + 1.0)
s.prop("trash_can", s.end("rocket") - 0.8)
s.prop("trash_bags", s.mid("alley2"))
s.prop("street_sign", s.start("orbit") - 0.6)
s.prop("mailbox", s.end("orbit") + 1.0)
s.prop("parking_meter", s.start("lot4") + 1.0)
s.prop("phone_booth", s.mid("chrome"), ring=True)
s.prop("chainlink_fence_4", s.mid("vac3"))
s.prop("vending_machine_a", s.mid("bowl"))
s.prop("phone_booth", s.mid("hifi"), ring=True)
s.prop("crates", s.mid("vac4"))
s.prop("vending_machine_b", s.start("ion") + 1.0)
s.prop("trash_can", s.end("lot6") - 1.5)
s.prop("chainlink_fence_4", s.mid("vac6"))
s.prop("phone_booth", s.mid("luna"), ring=True)
s.prop("crates", s.mid("seam4"))
s.prop("cardboard_boxes", s.start("lot7") + 1.0)
s.prop("trash_bags", s.mid("alley4"))
s.prop("street_sign", s.start("sputnik") - 0.6)
s.prop("hydrant", s.end("sputnik") + 0.8)
s.prop("bench", s.mid("vision") + 1.5)
s.prop("parking_meter", s.start("lot8") + 1.0)
s.prop("newspaper_box", s.start("kiosk") + 0.8)
s.prop("chainlink_fence_4", s.mid("vac8"))
s.prop("station_stairs", s.start("stairs"))
s.prop("phone_booth", s.start("stairs") + 1.4, ring=True, keep=True,
       line="'Grey suit. Black umbrella. You'll know him.' The line goes dead.")
s.prop("sandwich_board", s.start("lounge") + 1.0)
s.prop("trash_can", s.end("lot9") - 1.5)
s.prop("bench", s.mid("mall") + 1.5)
s.prop("newspaper_box", s.end("inn") + 1.0)

s.figure(s.mid("milk"))
s.figure(s.mid("records"))
s.figure(s.mid("station") + 1.5)
s.figure(s.mid("mall"))

s.set_piece("The Telstar Arcade", 0.0, s.end("milk"),
            "walking under continuous awnings past finned kiosks and the first ringing payphone while the "
            "first trains pass overhead: the awnings keep their sheet off")
s.set_piece("The Parade Viaduct", s.start("tv"), s.end("vac2"),
            "the first deck: cover from the rain, but each train sheds its sheet onto the bare stretches "
            "beneath it. Wait under an awning, hurry through, or hold the umbrella upright")
s.set_piece("Orbit Avenue", s.start("lot2"), s.end("chrome"),
            "open lots, a gutter and a car crossing as the tailwind rises, with trains washing the open sky "
            "and the side street too: tilting into the wind and straightening up for the train pull against "
            "each other")
s.set_piece("The Express Viaduct", s.start("laund"), s.end("quasar"),
            "a second deck over longer bare stretches, then two gutters in googie seams under the track")
s.set_piece("The Junction Viaduct", s.start("disco"), s.end("plasma"),
            "the wind turns into a headwind under the deck; then a torn marquee, a gutter and Sputnik "
            "Street's car, with the sheet crossing the side street")
s.set_piece("Telstar Station", s.start("kiosk"), s.end("inn"),
            "the last span: the station stairs with a phone that keeps ringing beneath them, a deep puddle, the inn")

s.write()
