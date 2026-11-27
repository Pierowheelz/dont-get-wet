#!/usr/bin/env python3
"""Long Lane plan: see docs/LEVEL_AUTHORING.md. Writes levels/long_lane.json.

The lane out past the last motel: no pavement, just a verge between the hedges, old oaks over it,
fields and gates, a farm with an open-fronted barn, a church and its lychgate, a bus shelter, and a
country pub at the end. Little real cover. The trees keep most of the rain off but not all of it, and
the sun breaks through often and for long stretches: here the sun is what keeps him going. Against
that, the lane wets him in ways he can't do much about: gusts that shake the trees' water down on
him, their men running up from behind for one quick shot, and Fairweather's black car coming up
behind with its lights off, through every puddle he can find.
"""
from street import Street

s = Street("long_lane", "Long Lane",
           "A lane between the hedges. Old oaks, open fields and the sun breaking through. No pavement, "
           "and nowhere much to hide.",
           aesthetic="country", neon=0.0, rain=[[0.0, 0.95], [0.5, 1.15], [1.0, 1.25]],
           wind=[[0.0, 0.05], [0.4, 0.1], [0.7, 0.14], [1.0, 0.12]],
           gusts=True, dry_falloff=3.0)

# 1. The village: the last shops, under their awnings
s.lot("stores", 8, "shop_lit", "awning", sign="VILLAGE STORES", color="green", floors=1)
s.lot("post", 6, "shop_dark", "awning", sign="POST OFFICE", color="red", floors=1)
s.lot("tea", 8, "shop_lit", "awning", sign="TEA ROOMS", color="teal", floors=1)
s.lot("cott1", 7, "cottage", "porch", floors=1)
s.lot("hedge1", 5, "hedge", "none", floors=0)
# 2. The first oak, the first long sun
s.lot("oak1", 10, "tree", "trees", floors=0)
s.lot("hedge2", 6, "hedge", "none", floors=0)
s.lot("gate1", 5, "field_gate", "none", floors=0)
s.lot("hedge3", 10, "hedge", "none", floors=0)
s.lot("oak2", 9, "tree", "trees", floors=0)
# 3. Under the oaks: the first gust
s.lot("hedge4", 4, "hedge", "none", floors=0)
s.lot("oak3", 10, "tree", "trees", floors=0)
s.lot("oak4", 10, "tree", "trees", floors=0)
s.lot("oak5", 8, "tree", "trees", floors=0)
s.lot("wall1", 16, "stone_wall", "none", floors=0)
s.lot("copse", 10, "tree", "trees", floors=0)
s.lot("hedge4b", 8, "hedge", "none", floors=0)
# 4. Hollow Farm: the barn, and a broken downpipe to fill the umbrella at
s.lot("gate2", 5, "field_gate", "none", floors=0)
s.lot("farm", 7, "cottage", "porch", sign="HOLLOW FARM", floors=1)
s.lot("pipe", 1.5, "stone_wall", "none", floors=0)
s.lot("barn", 8, "barn", "barn", floors=0)
s.lot("yard", 6, "field_gate", "none", floors=0)
# 5. The open lane: the first runner, then the car with no lights
s.lot("hedge5", 8, "hedge", "none", floors=0)
s.lot("hedge6", 10, "hedge", "none", floors=0)
s.lot("hedge6b", 10, "hedge", "none", floors=0)
s.lot("oak6", 9, "tree", "trees", floors=0)
s.lot("hedge7", 12, "hedge", "none", floors=0)
s.lot("gate3", 5, "field_gate", "none", floors=0)
s.lot("hedge8", 8, "hedge", "none", floors=0)
s.lot("wall2", 14, "stone_wall", "none", floors=0)
# 6. St Michael's: the lychgate and the churchyard yews
s.lot("oak7", 8, "tree", "trees", floors=0)
s.lot("lych", 4, "lychgate", "shelter", floors=0)
s.lot("cwall", 6, "stone_wall", "none", floors=0)
s.lot("yew1", 10, "tree", "trees", floors=0)
s.lot("yew2", 8, "tree", "trees", floors=0)
s.xing("churchln", 8, car=True)
# 7. The bus shelter: the second runner and the second car
s.lot("hedge9", 10, "hedge", "none", floors=0)
s.lot("hedge10", 10, "hedge", "none", floors=0)
s.lot("shelter", 4, "bus_shelter", "shelter", floors=0)
s.lot("hedge11", 6, "hedge", "none", floors=0)
s.lot("wall3", 18, "stone_wall", "none", floors=0)
s.lot("oak7b", 9, "tree", "trees", floors=0)
s.lot("hedge11b", 8, "hedge", "none", floors=0)
# 8. The last of the lane: the strongest gust, the last car, and the Plough
s.lot("oak8", 10, "tree", "trees", floors=0)
s.lot("oak9", 10, "tree", "trees", floors=0)
s.lot("hedge12", 8, "hedge", "none", floors=0)
s.lot("hedge12b", 8, "hedge", "none", floors=0)
s.lot("gate4", 5, "field_gate", "none", floors=0)
s.lot("cott2", 7, "cottage", "porch", floors=1)
s.lot("hedge13", 6, "hedge", "none", floors=0)
s.lot("oak10", 9, "tree", "trees", floors=0)
s.lot("inn", 8, "inn", "awning", sign="THE PLOUGH", color="green", floors=1)
s.lot("garden", 8, "hedge", "none", floors=0)
s.door("inn")

# Sun: often, and for a long way
s.feature("sun", s.start("gate1"), w=14.0)
s.feature("sun", s.start("wall1") + 1.0, w=15.0)
s.feature("sun", s.start("hedge8"), w=20.0)
s.feature("sun", s.start("hedge11") + 1.0, w=20.0)
s.feature("sun", s.start("hedge12"), w=12.0)

s.feature("gutter", s.mid("pipe"))
s.feature("puddle", s.mid("hedge2"), w=1.2)
s.feature("puddle", s.mid("gate2"), w=1.4, deep=True)
s.feature("puddle", s.mid("yard"), w=1.4)
s.feature("puddle", s.mid("hedge6"), w=1.2)
s.feature("puddle", s.mid("gate3"), w=1.6, deep=True)
s.feature("puddle", s.start("churchln") + 1.2, w=1.4, deep=True)
s.feature("puddle", s.mid("hedge10"), w=1.4)
s.feature("puddle", s.mid("gate4"), w=1.4, deep=True)
s.feature("puddle", s.mid("hedge13"), w=1.2)

s.hint(s.start("oak1") + 2.0, "The trees keep most of it off. Not all of it.", 4.0)

# Gusts: under the oaks, under the yews, and the strongest under the last oaks.
s.squall(s.start("oak3") + 4.0, dur=3.0)
s.squall(s.start("yew1") + 2.0, dur=3.0)
s.squall(s.start("oak8") + 5.0, dur=4.0)

# Their men, running up from behind for one shot each.
s.runner(s.start("hedge5") + 2.0, hit=8)
s.runner(s.start("hedge9") + 2.0, hit=8)

# Fairweather's car: up from behind with its lights off, through the puddles.
s.drive_by(s.start("gate3") - 6.0, quiet=True, shot=False, driver="slicker")
s.drive_by(s.mid("hedge10") - 6.0, quiet=True, shot=False, driver="slicker")
s.drive_by(s.start("hedge13") - 6.0, quiet=True, shot=False, driver="slicker")
s.hint(s.end("gate3") + 4.0, "Yellow slicker. Behind the wheel.", 4.0)

for x in [s.start("hedge2"), s.start("hedge5"), s.mid("hedge7"), s.start("hedge9"), s.mid("wall3"),
          s.start("hedge12")]:
    s.prop("telegraph_pole", x + 0.5)
s.prop("milestone", s.start("hedge1") + 1.0)
s.prop("mailbox", s.end("post") - 1.0)
s.prop("bench", s.start("tea") + 2.0)
s.prop("milk_churn_stand", s.start("yard") + 1.0)
s.prop("hay_bales", s.mid("gate2"))
s.prop("signpost", s.start("churchln") - 0.6)
s.prop("phone_booth", s.start("cwall") + 1.2)
s.prop("signpost", s.start("hedge13") + 1.0)

s.set_piece("The village", 0.0, s.end("hedge1"),
            "a covered start under the village shops' awnings, then the first hedges")
s.set_piece("The first oak", s.start("oak1"), s.end("oak2"),
            "trees keep off most of the rain but not all, then a 14 m sun break to dry in")
s.set_piece("Under the oaks", s.start("hedge4"), s.end("wall1"),
            "28 m of oaks and the first gust, which shakes their water down (umbrella up, upright), "
            "then 15 m of sun")
s.set_piece("Hollow Farm", s.start("gate2"), s.end("yard"),
            "the open-fronted barn, and a broken downpipe beside it to fill the umbrella at")
s.set_piece("The open lane", s.start("hedge5"), s.end("wall2"),
            "a man running up from behind for one shot, then Fairweather's car with no lights through "
            "the gateway's puddle, then 20 m of sun")
s.set_piece("St Michael's", s.start("oak7"), s.end("churchln"),
            "the lychgate, a gust under the churchyard yews, and Church Lane's car")
s.set_piece("The bus shelter", s.start("hedge9"), s.end("wall3"),
            "the second runner and the second car across open verge, the shelter, then 20 m of sun")
s.set_piece("The Plough", s.start("oak8"), s.end("inn"),
            "the strongest gust under the last oaks, the last car, and the pub door")

s.write()
