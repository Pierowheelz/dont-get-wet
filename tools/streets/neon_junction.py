#!/usr/bin/env python3
"""Neon Junction plan: see docs/LEVEL_AUTHORING.md. Writes levels/neon_junction.json.

The city centre and the final street. No new mechanic: wind with gusts, side-street cars and heavy
gutters together. The tailwind builds to a gale at Junction Square, then turns into a headwind for
the Neon Mile, the finale before the inn.
"""
from street import Street

s = Street("neon_junction", "Neon Junction",
           "Chrome, neon and gale-force gusts between the towers. Past the junction the wind turns in your face.",
           aesthetic="neon", neon=0.9, rain=[[0.0, 0.85], [0.5, 1.1], [1.0, 1.25]],
           wind=[[0.0, 0.08], [0.15, 0.12], [0.45, 0.35], [0.55, 0.5], [0.6, 0.35], [0.63, 0.0], [0.67, -0.3], [1.0, -0.35]],
           gusts=True)


def seam(tag, w, floors):
    """A narrow wall seam between shops. The blank sign stops the retro kit painting a filler name on it."""
    s.lot(tag, w, "wall", "none", sign=" ", floors=floors)


def shop(tag, w, style, cover, sign=None, **kw):
    """Every signed shop on this street gets tube lettering, whichever kit era the builder picks."""
    s.lot(tag, w, style, cover, sign=sign, neon=bool(sign), **kw)


# 1. The Automat Concourse: chrome canopies and a colonnade, continuous cover
shop("orbit", 6, "shop_lit", "awning", sign="ORBIT CAFE", color="teal", floors=4, awning_style="bubble")
shop("automat", 8, "shop_lit", "arcade", sign="AUTOMAT", floors=6)
shop("holo", 6, "shop_dark", "arcade", sign="HOLO", floors=6)
shop("robots", 6, "shop_lit", "awning", sign="ROBOTS", color="blue", floors=4, awning_style="bubble")
# first gaps, light tailwind
seam("seam1", 2.5, 4)
shop("zenith", 5, "shop_lit", "awning", sign="ZENITH TV", color="orange", floors=3)
shop("lot1", 4, "vacant", "none", floors=0)
shop("cosmo", 5, "shop_dark", "awning", sign="COSMO", color="green", floors=3)
shop("alley1", 3, "wall", "none", floors=4)
shop("synth", 6, "shop_lit", "awning", sign="SYNTH", color="blue", floors=3)
# 2. Tube Street: the first car, in a calm wind, then the subway balcony
shop("kiosk", 5, "shop_lit", "awning", sign="TICKETS", color="red", floors=3)
s.xing("tube", 7, car=True)
shop("subway", 8, "doorway", "balcony", sign="SUBWAY", floors=6)
shop("jetset", 6, "shop_lit", "balcony", sign="JET-SET TRAVEL", floors=6)
# the first gutter, alone in a seam
shop("laser", 6, "shop_lit", "awning", sign="LASER LANES", color="red", floors=3)
seam("pipe1", 1.5, 5)
shop("atomic", 6, "shop_dark", "awning", sign="ATOMIC", color="teal", floors=3)
shop("lot2", 6, "vacant", "none", floors=0)
shop("rocket", 8, "shop_lit", "awning", sign="ROCKET BURGER", color="orange", floors=3)
shop("alley2", 3, "wall", "none", floors=4)
shop("sat", 5, "shop_lit", "awning", sign="SATELLITE", color="blue", floors=3)
shop("raygun", 8, "shop_dark", "awning", sign="RAYGUN RECORDS", color="red", floors=3)
# Fifth Avenue: a second car, the wind rising
s.xing("fifth", 9, car=True)
shop("credit", 8, "shuttered", "balcony", sign="CREDIT", floors=7)
shop("radar", 4, "shop_lit", "balcony", sign="RADAR", floors=7)
shop("lot3", 8, "vacant", "none", floors=0)
shop("volt", 6, "shop_lit", "awning", sign="VOLT", color="green", floors=3)
shop("mono", 5, "shop_dark", "awning", sign="MONORAIL", color="brown", floors=3)
shop("alley3", 4, "wall", "none", floors=5)
shop("chrome", 8, "shop_lit", "awning", sign="CHROME DINER", color="red", floors=3, awning_style="bubble")
shop("lot4", 8, "vacant", "none", floors=0)
shop("tube_tv", 8, "shop_lit", "awning", sign="TELEVISORS", color="teal", floors=3)
# 3. The Gutter Gauntlet: neon googie awnings split by four pouring seams
shop("zap", 5, "shop_lit", "awning", sign="ZAP", color="red", floors=5, awning_style="googie")
seam("seamA", 1.2, 6)
shop("flux", 4, "shop_lit", "awning", sign="FLUX", color="blue", floors=5, awning_style="googie")
seam("seamB", 1.2, 6)
shop("nova", 5, "shop_lit", "awning", sign="NOVA", color="orange", floors=5, awning_style="googie")
seam("seamC", 1.2, 6)
shop("ion", 4, "shop_lit", "awning", sign="ION", color="teal", floors=5, awning_style="googie")
seam("seamD", 1.2, 6)
shop("quark", 4, "shop_lit", "awning", sign="QUARK", color="green", floors=5, awning_style="googie")
shop("pulsar", 8, "shop_lit", "awning", sign="PULSAR", color="green", floors=4)
shop("dyna", 5, "shop_dark", "awning", sign="DYNAMO", color="blue", floors=4)
shop("coil", 4, "shop_lit", "awning", sign="COIL", color="orange", floors=8)
# 4. Junction Square: the wide crossing at the gust peak, then the Hotel Orbit
s.xing("junction", 14, car=True)
shop("hotel", 8, "shop_lit", "balcony", sign="HOTEL ORBIT", floors=9)
shop("lobby", 8, "doorway", "balcony", sign="LOBBY", floors=9)
shop("skybar", 4, "shop_lit", "awning", sign="SKY BAR", color="blue", floors=4, awning_style="marquee")
# the wind turns: a headwind from here to the inn
shop("lot6", 8, "vacant", "none", floors=0)
shop("quasar", 5, "shop_lit", "awning", sign="QUASAR", color="orange", floors=4)
shop("alley4", 3, "wall", "none", floors=5)
shop("meteor", 6, "shop_dark", "awning", sign="METEOR", color="red", floors=4, awning_style="marquee",
     tears=[[2.4, 3.6]])
shop("lot7", 8, "vacant", "none", floors=0)
shop("galaxy", 8, "shop_lit", "arcade", sign="GALAXY", floors=6)
shop("cyber", 5, "shop_lit", "awning", sign="CYBER", color="teal", floors=4)
# Ninth Street: a car into the headwind, then the balconies
s.xing("ninth", 9, car=True)
shop("vision", 6, "shop_lit", "balcony", sign="VISION", floors=7)
shop("helix", 6, "shuttered", "balcony", sign="HELIX", floors=7)
shop("lot8", 6, "vacant", "none", floors=0)
shop("plasma", 6, "shop_lit", "awning", sign="PLASMA", color="green", floors=4)
shop("alley5", 3, "wall", "none", floors=5)
# 5. The Neon Mile: torn marquees with gutters in the tears, into the wind, then Last Avenue's car
shop("comet", 6, "shop_lit", "awning", sign="COMET", color="blue", floors=4)
shop("bijou", 6, "shop_lit", "awning", sign="STARLIGHT", color="red", floors=5, awning_style="marquee",
     tears=[[1.0, 2.2], [3.8, 5.0]])
shop("lounge", 5, "shop_lit", "awning", sign="LOUNGE", color="teal", floors=5, awning_style="googie",
     tears=[[1.6, 2.8]])
seam("pipe2", 1.2, 6)
shop("disco", 6, "shop_lit", "awning", sign="DISCO", color="orange", floors=5, awning_style="marquee",
     tears=[[0.8, 2.0], [3.6, 4.8]])
shop("rocketeer", 6, "shop_dark", "awning", sign="ROCKETEER", color="blue", floors=5, awning_style="marquee")
shop("neonbar", 6, "shop_lit", "awning", sign="NEON BAR", color="red", floors=5, awning_style="googie")
shop("jukebox", 4, "shop_lit", "awning", sign="JUKEBOX", color="orange", floors=5, awning_style="marquee")
s.xing("last", 10, car=True)
# the Bubble Mall: chrome canopies, the last breather before the inn
shop("mall1", 5, "shop_lit", "awning", sign="BUBBLE MALL", color="teal", floors=6, awning_style="bubble")
shop("mall2", 4, "shop_lit", "awning", sign="GIFTS", color="blue", floors=6, awning_style="bubble")
shop("inn", 8, "inn", "awning", sign="THE RAINY DAY INN", color="red", floors=6, awning_style="bubble")
shop("tower", 8, "shop_dark", "awning", sign="TOWER", color="teal", floors=8, awning_style="bubble")
s.figure(s.mid("mall2"))
s.door("inn")

s.feature("puddle", s.mid("lot1"), w=1.0)
s.feature("puddle", s.start("tube") + 1.2, w=1.4)
s.feature("gutter", s.mid("pipe1"))
s.feature("puddle", s.start("fifth") + 1.2, w=1.4)
s.feature("puddle", s.mid("lot3"), w=1.2)
s.feature("puddle", s.mid("lot4"), w=1.2)
s.feature("gutter", s.mid("seamA"))
s.feature("gutter", s.mid("seamB"))
s.feature("gutter", s.mid("seamC"))
s.feature("gutter", s.mid("seamD"))
s.feature("puddle", s.start("junction") + 1.2, w=1.4, deep=True)
s.feature("puddle", s.end("junction") - 1.2, w=1.4, deep=True)
s.feature("vent", s.mid("lobby"), w=1.6)
s.feature("puddle", s.mid("lot6"), w=1.2)
s.feature("gutter", s.mid("alley4"))
s.feature("puddle", s.mid("lot7"), w=1.4, deep=True)
s.feature("puddle", s.start("ninth") + 1.2, w=1.4)
s.feature("puddle", s.end("last") - 1.2, w=1.4, deep=True)
s.feature("gutter", s.start("bijou") + 4.4)
s.feature("gutter", s.mid("pipe2"))
s.feature("puddle", s.start("disco") + 4.2, w=1.0)

for t in ["orbit", "holo", "zenith", "synth", "jetset", "atomic", "sat", "radar", "mono", "tube_tv",
          "pulsar", "hotel", "quasar", "galaxy", "vision", "plasma", "lounge", "tower"]:
    s.prop("lamp_post", s.end(t) - 0.5)   # at the lot edge, between two signs
s.prop("vending_machine_a", s.start("automat") + 1.2)
s.prop("bench", s.mid("automat") + 1.5)
s.prop("vending_machine_b", s.end("holo") - 2.0)
s.prop("trash_bags", s.mid("seam1"))
s.prop("chainlink_fence_4", s.mid("lot1"))
s.prop("crates", s.mid("alley1"))
s.prop("newspaper_box_b", s.start("kiosk") + 0.8)
s.prop("street_sign", s.start("tube") - 0.6)
s.prop("hydrant", s.end("tube") + 0.8)
s.prop("bench", s.mid("subway") + 1.5)
s.prop("cardboard_boxes", s.start("lot2") + 1.0)
s.prop("trash_can", s.end("rocket") - 0.8)
s.prop("trash_bags", s.mid("alley2"))
s.prop("street_sign", s.start("fifth") - 0.6)
s.prop("mailbox", s.end("fifth") + 1.0)
s.prop("parking_meter", s.start("lot3") + 1.0)
s.prop("phone_booth", s.mid("mono"), ring=True)
s.prop("crates", s.mid("alley3"))
s.prop("sandwich_board", s.start("chrome") + 1.0)
s.prop("parking_meter", s.mid("lot4") + 2.0)
s.prop("vending_machine_a", s.mid("dyna"))
s.prop("street_sign", s.start("junction") - 0.6)
s.prop("lamp_post", s.start("junction") - 1.5)
s.prop("lamp_post", s.end("junction") + 1.8)
s.prop("hydrant", s.end("junction") + 0.8)
s.prop("bench", s.mid("hotel") + 1.5)
s.prop("newspaper_box", s.end("skybar") - 0.8)
s.prop("vending_machine_a", s.mid("lot6"))
s.prop("vending_machine_b", s.start("lot7") + 1.5)
s.prop("trash_can", s.end("lot7") - 1.5)
s.prop("vending_machine_b", s.start("galaxy") + 1.0)
s.prop("street_sign", s.start("ninth") - 0.6)
s.prop("hydrant", s.end("ninth") + 0.8)
s.prop("cardboard_boxes", s.start("lot8") + 1.0)
s.prop("crates", s.mid("alley5"))
s.prop("sandwich_board", s.start("jukebox") + 1.0)
s.prop("street_sign", s.start("last") - 0.6)
s.prop("lamp_post", s.start("last") - 1.5)
s.prop("lamp_post", s.end("last") + 1.8)
s.prop("hydrant", s.end("last") + 0.8)
s.prop("bench", s.mid("mall1") + 1.5)
s.prop("newspaper_box", s.end("inn") + 1.0)

s.set_piece("The Automat Concourse", 0.0, s.end("robots"),
            "walking under continuous cover: chrome bubble canopies and the Automat colonnade")
s.set_piece("Tube Street", s.start("kiosk"), s.end("jetset"),
            "the first car, in a calm wind: tilt the umbrella forward at the kerb, cross 7 m, recover under the subway balcony")
s.set_piece("The Gutter Gauntlet", s.start("zap"), s.end("quark"),
            "four gutters in 1.2 m seams between neon googie awnings: the umbrella stays up and upright (not tilted into the rising tailwind) for 20 m")
s.set_piece("Junction Square", s.start("junction"), s.end("skybar"),
            "a 14 m crossing with a car at the gust peak (deep puddles at both kerbs), then 16 m of Hotel Orbit balconies and a vent")
s.set_piece("The Neon Mile and the Bubble Mall", s.start("bijou"), s.end("inn"),
            "finale into the headwind: 18 m of torn marquees with gutters in the tears, a breath under the Rocketeer, Last Avenue's car with a deep puddle at the far kerb, then chrome bubble canopies before the inn")

s.write()
