#!/usr/bin/env python3
"""Arcade Lane plan: see docs/LEVEL_AUTHORING.md. Writes levels/arcade_lane.json."""
from street import Street

s = Street("arcade_lane", "Arcade Lane",
           "The first neon signs creep in. Watch the side streets: drivers here don't slow for puddles.",
           aesthetic="rundown_neon", neon=0.35, rain=[[0.0, 0.8], [0.5, 1.05], [1.0, 1.1]],
           wind=[[0.0, 0.0], [0.5, 0.1], [1.0, 0.1]])

# 1. The Penny Arcade: a lit colonnade of games, continuous cover
s.lot("soda", 5, "shop_lit", "awning", sign="SODA", color="red", awning_style="classic", floors=2)
# Arcade lots are 4 m so the colonnade columns (every 3.5 m from the lot edge) frame each sign
# instead of standing in front of it.
s.lot("arcade", 4, "shop_lit", "arcade", neon=True, sign="ARCADE", floors=3)
s.lot("pinball", 4, "shop_lit", "arcade", neon=True, sign="PINBALL", floors=3)
s.lot("photos", 4, "doorway", "arcade", sign="PHOTOS", floors=3)
s.lot("skee", 4, "shop_lit", "arcade", neon=True, sign="SKEE-BALL", floors=3)
s.lot("prizes", 4, "shop_dark", "arcade", sign="PRIZES", floors=3)
s.lot("tokens", 4, "shop_lit", "arcade", neon=True, sign="TOKENS", floors=3)
# 2. Malt Shop corner and Bell Street: warm-up gaps, then the first car on a short crossing
s.lot("alley1", 2.5, "wall", "none", floors=2)
s.lot("records", 5, "shop_lit", "awning", sign="RECORDS", color="teal", awning_style="pennant", floors=2)
s.lot("lot1", 3, "vacant", "none", floors=0)
s.lot("barber", 5, "shop_lit", "awning", sign="BARBER", color="blue", floors=2)
s.lot("alley2", 3, "wall", "none", floors=3)
s.lot("malt", 6, "shop_lit", "awning", sign="MALT SHOP", color="red", awning_style="wide_stripe", floors=2)
s.lot("shakes", 5, "shop_dark", "awning", sign="SHAKES", color="red", awning_style="wide_stripe", floors=2)
s.xing("bell", 6, car=True)
# 3. The Rialto: the cinema's bulb marquee is a long breather after the first car
s.lot("rialto", 8, "shop_lit", "awning", neon=True, sign="RIALTO", color="red", awning_style="marquee", floors=4)
s.lot("showing", 4, "doorway", "awning", sign="TONIGHT", color="red", awning_style="marquee", floors=4)
# 4. Bowl-o-Rama: a puddle lot and a gutter seam
s.lot("lot2", 5, "vacant", "none", floors=0)
s.lot("candy", 4, "shop_lit", "awning", sign="CANDY", color="orange", awning_style="dome", floors=3)
s.lot("alley6", 2.5, "wall", "none", floors=3)
s.lot("bowl", 8, "shop_lit", "awning", neon=True, sign="BOWL-O-RAMA", color="teal", awning_style="googie", floors=2)
s.lot("pipe1", 1.5, "wall", "none", floors=3)
s.lot("laundro", 6, "shop_dark", "awning", sign="LAUNDRY", color="blue", floors=2)
s.lot("lot2b", 3, "vacant", "none", floors=0)
s.lot("drugs", 6, "shop_lit", "awning", sign="DRUGS", color="orange", floors=3)
# 5. Hi-Fi Row: torn awnings and a gutter through a tear
s.lot("hifi", 6, "shop_lit", "awning", sign="HI-FI", color="green", floors=3, tears=[[1.4, 2.6], [4.0, 5.0]])
s.lot("alley3", 3, "wall", "none", floors=2)
s.lot("tv", 6, "shuttered", "awning", sign="TV REPAIR", color="brown", floors=2, tears=[[2.2, 3.4]])
s.lot("jukebox", 5, "shop_lit", "awning", neon=True, sign="JUKEBOX", color="teal", awning_style="bubble", floors=2)
s.lot("hobby", 5, "shop_lit", "awning", sign="HOBBIES", color="green", floors=2)
# 6. Orbit Avenue: open kerb, a wide crossing, a deep puddle at the kerb
s.lot("busstop", 4, "vacant", "none", floors=0)
s.xing("orbit", 10, car=True)
s.lot("motel", 8, "shop_lit", "balcony", neon=True, sign="MOTEL", floors=4)
s.lot("rooms", 6, "doorway", "balcony", sign="VACANCY", floors=4)
s.lot("lot3", 5, "vacant", "none", floors=0)
s.lot("pawn", 6, "shop_dark", "awning", sign="PAWN", color="orange", floors=3)
s.lot("carwash", 6, "shop_dark", "awning", sign="CAR WASH", color="blue", floors=1)
# 7. The flatiron: two side streets with a narrow diner between them, a car down each
s.xing("ash", 7, car=True)
s.lot("flatiron", 6, "shop_lit", "awning", neon=True, sign="DINER", color="teal", awning_style="googie", floors=4)
s.lot("cigars", 5, "shop_dark", "awning", sign="CIGARS", color="brown", floors=4)
s.xing("elm", 8, car=True)
s.lot("flats", 8, "boarded", "balcony", floors=3)
s.lot("deli", 6, "shop_lit", "awning", sign="DELI", color="red", floors=2)
# 8. The Starlite drive-in: the open car park, then gaps with puddles
s.lot("drivein", 12, "vacant", "none", floors=0)
s.lot("starlite", 8, "shop_lit", "awning", neon=True, sign="STARLITE", color="blue", awning_style="googie", floors=2)
s.lot("alley4", 4, "wall", "none", floors=2)
s.lot("tobacco", 5, "shop_dark", "awning", sign="TOBACCO", color="brown", floors=2)
s.lot("lot4", 6, "vacant", "none", floors=0)
s.lot("hotel", 8, "shop_lit", "balcony", neon=True, sign="HOTEL", floors=5)
# 9. Neon Row and the Boulevard: torn neon awnings, a gutter at the kerb, the widest crossing
s.lot("tiki", 6, "shop_lit", "awning", neon=True, sign="TIKI", color="orange", awning_style="bubble", floors=2, tears=[[1.0, 2.2]])
s.lot("lot5", 4, "vacant", "none", floors=0)
s.lot("bar", 6, "shop_lit", "awning", sign="COCKTAILS", color="green", awning_style="classic", floors=3)
s.lot("rocket", 6, "shop_lit", "awning", neon=True, sign="ROCKET", color="teal", awning_style="googie", floors=3)
s.lot("lounge", 4, "shop_dark", "awning", sign="LOUNGE", color="blue", awning_style="bubble", floors=3)
s.lot("pipe2", 1.5, "wall", "none", floors=4)
s.xing("blvd", 11, car=True)
s.lot("florist", 5, "shop_lit", "awning", sign="FLORIST", color="green", floors=2)
s.lot("cafe", 6, "shop_lit", "awning", neon=True, sign="CAFE", color="red", awning_style="marquee", floors=2, tears=[[1.4, 2.6]])
s.lot("alley5", 3, "wall", "none", floors=2)
s.lot("watch", 4, "shop_lit", "awning", sign="WATCHES", color="blue", floors=2)
s.lot("inn", 8, "inn", "awning", sign="THE RAINY DAY INN", color="red", floors=3)
s.lot("cleaners", 8, "shop_dark", "awning", sign="CLEANERS", color="teal", floors=4)
s.door("inn")

s.feature("puddle", s.mid("lot2"), w=1.2)
s.feature("gutter", s.mid("pipe1"))
s.feature("puddle", s.start("orbit") + 1.2, w=1.4, deep=True)
s.feature("puddle", s.mid("alley3"), w=1.0)
s.feature("gutter", s.start("tv") + 2.8)
s.feature("puddle", s.mid("lot3"), w=1.0)
s.feature("puddle", s.end("elm") - 1.2, w=1.4, deep=True)
s.feature("fire_barrel", s.mid("flats"), w=1.8)
s.feature("puddle", s.start("drivein") + 1.6, w=1.0)
s.feature("puddle", s.mid("lot4"), w=1.2, deep=True)
s.feature("gutter", s.mid("pipe2"))
s.feature("puddle", s.start("blvd") + 1.2, w=1.6, deep=True)
s.feature("gutter", s.mid("alley5"))

for t in ["soda", "pinball", "records", "malt", "rialto", "candy", "bowl", "laundro", "motel", "hifi", "jukebox",
          "deli", "starlite", "hotel", "rocket", "florist", "watch", "cleaners"]:
    s.prop("lamp_post", s.start(t) + 0.3)
s.prop("vending_machine_b", s.start("arcade") + 1.5)
s.prop("bench", s.mid("prizes"))
s.prop("vending_machine_a", s.start("photos") + 1.0)
s.prop("sandwich_board", s.start("skee") + 1.0)
s.prop("trash_bags", s.mid("alley1"))
s.prop("chainlink_fence_4", s.mid("lot1"))
s.prop("newspaper_box", s.end("barber") - 0.8)
s.prop("bench", s.mid("malt") + 1.0)
s.prop("street_sign", s.start("bell") - 0.6)
s.prop("hydrant", s.end("bell") + 1.3)
s.prop("sandwich_board", s.end("showing") - 1.0)
s.prop("cardboard_boxes", s.start("lot2") + 0.8)
s.prop("downpipe", s.mid("pipe1"))
s.prop("bench", s.mid("busstop"))
s.prop("street_sign", s.start("orbit") - 0.6)
s.prop("hydrant", s.end("orbit") + 1.3)
s.prop("phone_booth", s.end("rooms") - 1.0)
s.prop("trash_can", s.start("alley3") + 0.5)
s.prop("trash_bags", s.start("tv") + 2.0)
s.prop("mailbox", s.end("pawn") - 1.0)
s.prop("trash_can", s.end("carwash") - 1.8)
s.prop("street_sign", s.start("ash") - 0.6)
s.prop("newspaper_box_b", s.end("flatiron") - 0.6)
s.prop("street_sign", s.start("elm") - 0.6)
s.prop("hydrant", s.end("elm") + 1.3)
s.prop("bench", s.mid("drivein") + 3.0)
s.prop("cardboard_boxes", s.start("drivein") + 0.5)
s.prop("trash_bags", s.mid("alley4"))
s.prop("chainlink_fence_4", s.mid("lot4"))
s.prop("bench", s.mid("hotel") + 1.5)
s.prop("trash_can", s.mid("lot5"))
s.prop("downpipe", s.mid("pipe2"))
s.prop("street_sign", s.start("blvd") - 0.6)
s.prop("hydrant", s.end("blvd") + 1.3)
s.prop("downpipe", s.mid("alley5"))
s.prop("bollard", s.start("inn") - 0.5)
s.prop("newspaper_box", s.end("inn") + 2.2)

s.set_piece("The Penny Arcade", 0.0, s.end("tokens"),
            "walking under continuous cover: a lit colonnade of pinball and skee-ball")
s.set_piece("Bell Street", s.start("alley1"), s.end("candy"),
            "first car: short gaps to warm up, then headlights at a 6 m crossing reached under the malt-shop awning; "
            "tilt forward, then 18 m of Rialto marquee to recover")
s.set_piece("Orbit Avenue", s.start("hobby"), s.end("rooms"),
            "harder car: an open bus-stop kerb, then a 10 m crossing with a deep puddle at the kerb, then motel balconies")
s.set_piece("The Flatiron Diner", s.start("carwash"), s.end("deli"),
            "double crossing: a car down each of two side streets, 11 m of diner awning between them to retilt, then a fire barrel under the flats")
s.set_piece("The Boulevard", s.start("tiki"), s.end("inn"),
            "final exam: torn neon awnings, a gutter right at the kerb, the widest crossing with a deep puddle, a last gutter at the inn")


def check_car_approaches():
    """The bot tilts forward from 10.5 m before a car crossing until the wave lands about 5.5 m
    before it, and a forward tilt in open rain soaks the walker's back. Keep that stretch under
    intact cover so the test is the splash, not the rain."""
    for c in s.crossings:
        if not c.get("car"):
            continue
        x = c["x"] - 10.6
        while x < c["x"] - 5.0:
            ok = any(l["cover"] != "none" and l["x"] <= x < l["x"] + l["w"]
                     and not any(l["x"] + a - 0.3 <= x <= l["x"] + b + 0.3 for a, b in l.get("tears", []))
                     for l in s.lots)
            assert ok, f"car crossing at {c['x']}: open sky at {x:.1f} in the tilt-forward window"
            x += 0.2


check_car_approaches()
s.write()
