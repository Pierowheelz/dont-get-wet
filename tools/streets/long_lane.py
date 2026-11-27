#!/usr/bin/env python3
"""Long Lane plan: see docs/LEVEL_AUTHORING.md. Writes levels/long_lane.json.

The edge of town past the Bypass, on a grey late afternoon: a suburb that has been left behind, and the
bridge between the town's dark streets and the country. It thins out toward the end.
Brick-veneer houses behind overgrown gardens, some lit, more of them empty, a shut shopping strip, a
railway overbridge, a church hall, a bus shelter with cracked glass, and the Royal Hotel at the end.
Little real cover. The street trees keep most of the rain off but not all of it, and a low sun breaks
through often and for long stretches: here the sun is what keeps him going. Against that, the street
wets him in ways he can't do much about: gusts that shake the trees' water down on him, their men
running up from behind for one quick shot, and Fairweather's black car coming up behind with its
lights off, through every puddle he can find.
"""
from street import Street

s = Street("long_lane", "Long Lane",
           "The last of the suburbs. Overgrown gardens, empty houses, big old street trees and a low sun "
           "breaking through. Not much to shelter under.",
           aesthetic="suburban", neon=0.0, rain=[[0.0, 0.95], [0.5, 1.15], [1.0, 1.25]],
           wind=[[0.0, 0.05], [0.4, 0.1], [0.7, 0.14], [1.0, 0.12]],
           gusts=True, dry_falloff=3.0)

# 1. The shops: a shut strip of shops, under their verandas
s.lot("milkbar", 8, "shop_dark", "awning", sign="MILK BAR", color="red", floors=1)
s.lot("chemist", 6, "shuttered", "awning", sign="CHEMIST", color="green", floors=1)
s.lot("news", 8, "shop_lit", "awning", sign="NEWSAGENCY", color="blue", floors=1)
s.lot("laundro", 6, "boarded", "awning", sign="LAUNDRETTE", color="teal", floors=1)
s.lot("house1", 8, "house", "none", state="empty", sign="FOR SALE", floors=1)
# 2. The first street tree, the first long sun
s.lot("tree1", 10, "house", "trees", floors=1)
s.lot("house2", 8, "house", "none", state="lived", floors=1)
s.lot("vacant1", 12, "vacant_block", "none", floors=0)
s.lot("tree2", 9, "house", "trees", floors=1)
# 3. The railway overbridge, and a broken downpipe off it to fill the umbrella at
s.lot("house5", 5, "house", "none", floors=1)
s.lot("pipe", 1.5, "wall", "none", floors=1)
s.lot("bridge", 10, "overbridge", "bridge", floors=0)
s.lot("house6", 7, "house", "none", state="boarded", floors=1)
# 4. Under the plane trees: the first gust
s.lot("house3", 4, "house", "none", state="boarded", floors=1)
s.lot("tree3", 10, "house", "trees", floors=1)
s.lot("tree4", 10, "house", "trees", floors=1)
s.lot("tree5", 8, "flats", "trees", floors=2)
s.lot("flats", 16, "flats", "none", sign="BELLEVUE FLATS", floors=2)
s.lot("tree6", 10, "house", "trees", floors=1)
s.lot("house4", 8, "house", "none", state="empty", car="wreck", drive="left", floors=1)
# 5. The open street: the first runner, then the car with no lights
s.lot("house7", 8, "house", "trees", state="lived", drive="right", car="sedan", floors=1)
s.lot("park", 20, "park", "none", sign="MEMORIAL RESERVE", floors=0)
s.lot("tree7", 9, "house", "trees", floors=1)
s.lot("house8", 12, "house", "none", state="empty", sign="SOLD", floors=1)
s.lot("vacant2", 5, "vacant_block", "none", floors=0)
s.lot("house9", 8, "house", "none", floors=1)
s.lot("house10", 14, "house", "none", state="boarded", floors=1)
# 6. St Michael's hall: its porch and the gums
s.lot("tree8", 8, "house", "trees", floors=1)
s.lot("hall", 8, "church_hall", "porch", sign="ST MICHAEL'S HALL", floors=1, porch=[0.0, 8.0])
s.lot("house11", 6, "house", "none", state="lived", floors=1)
s.lot("gum1", 10, "house", "trees", floors=1)
s.lot("gum2", 8, "house", "trees", floors=1)
s.xing("churchst", 8)
# 7. The bus shelter: the second runner and the second car
s.lot("house12", 10, "house", "none", state="empty", floors=1)
s.lot("house13", 10, "house", "none", state="boarded", fence="none", floors=1)
s.lot("shelter", 7, "bus_shelter", "shelter", floors=0)
s.lot("house14", 3, "house", "none", floors=1)
s.lot("vacant3", 18, "vacant_block", "none", floors=0)
s.lot("tree9", 9, "house", "trees", floors=1)
s.lot("house15", 8, "house", "none", state="empty", sign="FOR SALE", floors=1)
# 8. The last of the street: the strongest gust, the last car, and the Royal
s.lot("tree10", 10, "house", "trees", floors=1, thin=0.2)
s.lot("tree11", 10, "house", "trees", floors=1, thin=0.3)
s.lot("house16", 8, "house", "none", floors=1, thin=0.4)
s.lot("house17", 8, "house", "none", floors=1, thin=0.5)
s.lot("house18", 5, "house", "none", floors=1, thin=0.6)
s.lot("flats2", 7, "flats", "none", floors=2, thin=0.5)
s.lot("house19", 6, "house", "none", floors=1, thin=0.7)
s.lot("tree12", 9, "house", "trees", floors=1, thin=0.7)
s.lot("inn", 8, "inn", "awning", sign="ROYAL HOTEL", color="green", floors=2, thin=0.6)
s.lot("carpark", 8, "vacant_block", "none", floors=0, thin=0.8)
s.door("inn")

# Sun: often, and for a long way
s.feature("sun", s.start("vacant1"), w=14.0)
s.feature("sun", s.start("flats") + 1.0, w=15.0)
s.feature("sun", s.start("house9"), w=16.0)
s.feature("sun", s.start("park") + 4.0, w=12.0)
s.feature("sun", s.start("house11"), w=6.0)
s.feature("sun", s.start("house12") + 1.0, w=8.0)
s.feature("sun", s.start("house14") + 1.0, w=20.0)
s.feature("sun", s.start("house16"), w=18.0)
s.feature("sun", s.start("house15"), w=8.0)

s.feature("gutter", s.mid("pipe"))
s.feature("puddle", s.mid("house2"), w=1.2)
s.feature("puddle", s.mid("house5"), w=1.4, deep=True)
s.feature("puddle", s.mid("house6"), w=1.4)
s.feature("puddle", s.mid("park"), w=1.2)
s.feature("puddle", s.mid("vacant2"), w=1.6, deep=True)
s.feature("puddle", s.start("churchst") + 1.2, w=1.4, deep=True)
s.feature("puddle", s.mid("house13"), w=1.4)
s.feature("puddle", s.mid("house17"), w=1.4, deep=True)
s.feature("puddle", s.mid("house19"), w=1.2)

s.hint(s.start("tree1") + 2.0, "The trees keep most of it off. Not all of it.", 4.0)

# Gusts: under the trees past the flats, under the gums, and the strongest under the last trees.
s.squall(s.start("tree6") + 2.0, dur=3.0)
s.squall(s.start("gum1") + 2.0, dur=3.0)
s.squall(s.start("tree10") + 5.0, dur=4.0)

# Their men, running up from behind for one shot each.
s.runner(s.start("park") + 5.0, hit=8)   # his shot comes in the park's sun
s.runner(s.start("house9") + 2.0, hit=8)   # his shot comes in the sun

# Fairweather's car: up from behind with its lights off, through the puddles.
s.drive_by(s.start("vacant2") - 6.0, quiet=True, shot=False, driver="slicker")
s.drive_by(s.mid("house13") - 6.0, quiet=True, shot=False, driver="slicker")
s.drive_by(s.start("house19") - 6.0, quiet=True, shot=False, driver="slicker")
s.hint(s.end("vacant2") + 4.0, "Yellow slicker. Behind the wheel.", 4.0)

for t in ["house1", "vacant1", "house4", "house7", "house8", "house10", "house12", "vacant3", "house16", "flats2"]:
    s.prop("lamp_post", s.start(t) + 0.6, **({"lamp": "out"} if t in ("house8", "vacant3") else
                                            {"lamp": "flicker"} if t == "house12" else {}))
s.prop("mailbox", s.end("news") - 1.0)
s.prop("bench", s.start("park") + 3.0)
s.prop("trash_bags", s.end("laundro") - 0.8)
s.prop("street_sign", s.start("churchst") - 0.6)
s.prop("phone_booth", s.start("house11") + 1.2)
s.prop("cardboard_boxes", s.mid("vacant3"))

s.set_piece("The shops", 0.0, s.end("house1"),
            "a covered start under the shut shops' verandas, then the first front gardens")
s.set_piece("The first street tree", s.start("tree1"), s.end("tree2"),
            "trees keep off most of the rain but not all, then a 14 m sun break to dry in")
s.set_piece("The overbridge", s.start("house5"), s.end("house6"),
            "the railway bridge over the street, and a broken downpipe off it to fill the umbrella at")
s.set_piece("Under the plane trees", s.start("house3"), s.end("house4"),
            "28 m of street trees to rest under with the umbrella shut, 15 m of sun by the flats, then the "
            "first gust, which shakes the trees' water down (umbrella up, upright)")
s.set_piece("The open street", s.start("house7"), s.end("house10"),
            "a man running up from behind for one shot in the park's sun, Fairweather's car with no lights "
            "through the deep puddle, then a second runner as the sun comes out")
s.set_piece("St Michael's hall", s.start("tree8"), s.end("churchst"),
            "the hall's porch along its front, a short sun break, and a gust under the gums")
s.set_piece("The bus shelter", s.start("house12"), s.end("house15"),
            "a sun break, Fairweather's second pass across open footpath, the shelter, then 20 m of sun")
s.set_piece("The Royal", s.start("tree10"), s.end("inn"),
            "the strongest gust under the last trees, the suburb thinning toward the country, his last pass, "
            "and the pub door")

s.write()
