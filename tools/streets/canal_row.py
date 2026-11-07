#!/usr/bin/env python3
"""Canal Row plan: see docs/LEVEL_AUTHORING.md. Writes levels/canal_row.json.

The new idea is a light headwind off the canal: rain slants toward the walker, he tilts into it,
and every gap costs a little more stamina and time than on Main Street. Most tests are one long gap
followed by 10 m or more of cover, because shorter cover gives almost no stamina back.
"""
from street import Street

s = Street("canal_row", "Canal Row",
           "Warehouses and loading docks by the canal. Fewer awnings, and the wind is picking up.",
           aesthetic="industrial", neon=0.0, rain=[[0.0, 0.85], [0.5, 1.1], [1.0, 1.15]],
           wind=[[0.0, 0.0], [0.07, 0.0], [0.14, -0.2], [0.45, -0.28], [1.0, -0.3]])

# 1. The wharf: continuous cover past the cafe and the first loading docks
s.lot("cafe", 6, "shop_lit", "awning", sign="WHARF CAFE", color="red", floors=2, awning_style="waterfall")
s.lot("dock1", 8, "loading_dock", "awning", color="brown", floors=2, awning_style="tin")
s.lot("chandler", 6, "shop_lit", "awning", sign="SHIP CHANDLER", color="green", floors=2)
s.lot("dock2", 8, "loading_dock", "awning", color="orange", floors=2, awning_style="tin")
s.lot("alley1", 2.5, "wall", "none", floors=2)
s.lot("bait", 6, "shop_dark", "awning", sign="BAIT & TACKLE", color="teal", floors=2)
# 2. First breeze: the wind rises under Cold Storage, then one short windy gap and long cover
s.lot("alley2", 3, "wall", "none", floors=2)
s.lot("cold", 8, "warehouse", "awning", sign="COLD STORAGE", color="blue", floors=3, awning_style="tin")
s.lot("yard1", 4, "vacant", "none", floors=0)
s.lot("dock3", 8, "loading_dock", "awning", color="brown", floors=2, awning_style="tin")
s.lot("ice", 5, "shop_dark", "awning", sign="ICE", color="blue", floors=2)
# 3. The grain store downpipe: gutter in a seam, then a puddled yard
s.lot("grain", 6, "warehouse", "awning", sign="GRAIN STORE", color="brown", floors=4, awning_style="tin")
s.lot("pipe", 1.5, "wall", "none", floors=4)
s.lot("mill", 6, "warehouse", "awning", color="red", floors=3, awning_style="tin")
s.lot("yard2", 6, "vacant", "none", floors=0)
s.lot("rope", 5, "shuttered", "awning", sign="ROPE WORKS", color="green", floors=2)
s.lot("marine", 6, "shop_lit", "awning", sign="MARINE SUPPLY", color="blue", floors=2)
# 4. Lock Bridge: the canal crossing into the wind, then the harbour office balconies
s.xing("bridge", 10)
s.lot("harbour", 8, "shop_lit", "balcony", sign="HARBOUR OFFICE", floors=4)
s.lot("customs", 5, "doorway", "balcony", sign="CUSTOMS", floors=4)
# 5. Tin shed row: torn tin awnings keep the umbrella up, a gutter through a tear
s.lot("shed1", 8, "warehouse", "awning", color="brown", floors=2, awning_style="tin", tears=[[1.0, 2.2], [5.0, 6.2]])
s.lot("shed2", 6, "warehouse", "awning", color="orange", floors=2, awning_style="tin", tears=[[2.0, 3.4]])
s.lot("yard3", 4, "vacant", "none", floors=0)
s.lot("shed3", 6, "loading_dock", "awning", color="red", floors=2, awning_style="tin")
s.lot("boatyard", 8, "shop_dark", "awning", sign="BOATYARD", color="blue", floors=2)
s.lot("salvage", 5, "shop_dark", "awning", sign="SALVAGE", color="orange", floors=2)
# 6. The coal yard: the long open quay at full wind, then the truck stop canopy
s.lot("coal", 16, "vacant", "none", floors=0)
s.lot("truckstop", 8, "gas_station", "canopy", sign="TRUCK STOP", floors=0)
s.lot("tires", 5, "shop_dark", "awning", sign="TIRES", color="teal", floors=2)
# 7. The sun wharf: rain, a sun break on the open quay, rain, then the flats
s.lot("alley5", 4, "wall", "none", floors=2)
s.lot("pawn", 5, "shuttered", "awning", sign="PAWN", color="green", floors=2)
s.lot("quay", 14, "vacant", "none", floors=0)
s.lot("flats", 8, "boarded", "balcony", floors=3)
s.lot("bar", 5, "shop_dark", "awning", sign="BAR", color="red", floors=2)
s.lot("mission", 6, "shop_dark", "awning", sign="SEAMEN'S MISSION", color="brown", floors=3)
# 8. Turning Basin bridge: the second crossing, deep puddles at both kerbs
s.lot("lot3", 3, "vacant", "none", floors=0)
s.xing("basin", 9)
s.lot("motel", 8, "shop_lit", "awning", sign="MOTEL", color="teal", floors=3)
s.lot("diner", 5, "shop_dark", "awning", sign="DINER", color="red", floors=2)
# 9. Ferry Lane: the slipway gap, torn canvas and a downpipe in the wind, then the inn
s.lot("alley7", 4, "wall", "none", floors=3)
s.lot("depot", 8, "warehouse", "awning", sign="DEPOT", color="brown", floors=3, awning_style="tin")
s.lot("slip", 7, "vacant", "none", floors=0)
s.lot("laundry", 8, "shop_lit", "awning", sign="LAUNDRY", color="blue", floors=2)
s.lot("alley8", 3, "wall", "none", floors=2)
s.lot("ferry", 8, "shop_lit", "balcony", sign="FERRY OFFICE", floors=3)
s.lot("alley9", 4, "wall", "none", floors=3)
s.lot("hardware", 6, "shop_dark", "awning", sign="HARDWARE", color="green", floors=2, tears=[[1.0, 2.2], [3.6, 4.8]])
s.lot("pipe2", 1.5, "wall", "none", floors=3)
s.lot("inn", 8, "inn", "awning", sign="THE RAINY DAY INN", color="red", floors=3)
s.lot("bakery", 8, "shop_dark", "awning", sign="BAKERY", color="teal", floors=3)
s.door("inn")

s.feature("gutter", s.mid("pipe"))
s.feature("puddle", s.mid("yard2"), w=1.2)
s.feature("puddle", s.start("bridge") + 1.2, w=1.2)
s.feature("puddle", s.end("bridge") - 1.2, w=1.2)
s.feature("puddle", s.start("shed1") + 5.6, w=1.0)
s.feature("gutter", s.start("shed2") + 2.7)
s.feature("puddle", s.mid("yard3"), w=1.4, deep=True)
s.feature("puddle", s.start("coal") + 5.0, w=1.2)
s.feature("puddle", s.end("coal") - 4.0, w=1.2, deep=True)
s.feature("vent", s.mid("tires"), w=1.6)
s.feature("puddle", s.mid("alley5"), w=1.2)
s.feature("sun", s.start("quay") + 2.0, w=6.0)
s.feature("puddle", s.start("basin") + 1.2, w=1.4, deep=True)
s.feature("puddle", s.end("basin") - 1.2, w=1.4, deep=True)
s.feature("puddle", s.mid("slip"), w=1.2)
s.feature("puddle", s.mid("alley9"), w=1.2)
s.feature("gutter", s.mid("pipe2"))

for t in ["dock1", "dock2", "cold", "ice", "mill", "marine", "harbour", "shed2", "boatyard", "tires", "pawn", "flats", "bar", "motel", "depot", "laundry", "ferry", "hardware"]:
    s.prop("lamp_post", s.start(t) + 0.7)   # at the lot's edge, clear of its sign
s.prop("sandwich_board", s.start("cafe") + 1.2)
s.prop("crates", s.start("dock1") + 1.5)
s.prop("cardboard_boxes", s.end("dock1") - 1.5)
s.prop("newspaper_box", s.end("chandler") - 1.0)
s.prop("crates", s.mid("dock2") + 1.5)
s.prop("trash_bags", s.mid("alley1"))
s.prop("trash_can", s.end("bait") - 0.8)
s.prop("crates", s.start("cold") + 1.0)
s.prop("chainlink_fence_4", s.mid("yard1"))
s.prop("cardboard_boxes", s.start("dock3") + 1.5)
s.prop("crates", s.end("dock3") - 1.5)
s.prop("downpipe_tall", s.mid("pipe"))
s.prop("crates", s.start("mill") + 0.8)
s.prop("chainlink_fence_4", s.mid("yard2"))
s.prop("trash_bags", s.end("rope") - 0.8)
s.prop("street_sign", s.start("bridge") - 0.6)
s.prop("bollard", s.start("bridge") - 1.6)
s.prop("bollard", s.end("bridge") + 0.6)
s.prop("hydrant", s.end("bridge") + 1.6)
s.prop("bench", s.mid("harbour") + 1.5)
s.prop("mailbox", s.end("customs") - 1.0)
s.prop("crates", s.start("shed1") + 3.5)
s.prop("trash_bags", s.start("shed2") + 1.0)
s.prop("cardboard_boxes", s.end("shed3") - 1.5)
s.prop("crates", s.start("shed3") + 1.5)
s.prop("trash_can", s.end("boatyard") - 0.8)
s.prop("bollard", s.start("coal") + 1.5)
s.prop("lamp_post", s.start("coal") + 4.5)
s.prop("crates", s.start("coal") + 6.5)
s.prop("cardboard_boxes", s.start("coal") + 9.0)
s.prop("bollard", s.start("coal") + 8.0)
s.prop("trash_bags", s.end("coal") - 5.0)
s.prop("lamp_post", s.end("coal") - 4.0)
s.prop("bollard", s.end("coal") - 1.5)
s.prop("gas_pump", s.start("truckstop") + 2.5)
s.prop("gas_pump", s.end("truckstop") - 2.5)
s.prop("vending_machine_a", s.end("tires") - 1.0)
s.prop("trash_bags", s.mid("alley5"))
s.prop("bench", s.mid("quay"))
s.prop("bollard", s.start("quay") + 1.5)
s.prop("bollard", s.end("quay") - 1.5)
s.prop("crates", s.end("flats") - 1.0)
s.prop("phone_booth", s.end("bar") - 1.0)
s.prop("street_sign", s.start("basin") - 0.6)
s.prop("parking_meter", s.mid("lot3"))
s.prop("hydrant", s.end("basin") + 1.0)
s.prop("newspaper_box_b", s.end("motel") - 1.0)
s.prop("trash_can", s.end("diner") - 0.8)
s.prop("crates", s.mid("alley7"))
s.prop("cardboard_boxes", s.start("depot") + 1.5)
s.prop("bollard", s.start("slip") + 1.5)
s.prop("bollard", s.end("slip") - 1.5)
s.prop("trash_bags", s.mid("alley8"))
s.prop("bench", s.mid("ferry") + 1.5)
s.prop("sandwich_board", s.start("hardware") + 1.0)
s.prop("downpipe", s.mid("pipe2"))
s.prop("bollard", s.start("inn") - 0.5)
s.prop("newspaper_box", s.end("inn") + 1.0)

s.set_piece("First breeze at Cold Storage", s.start("alley2"), s.end("ice"),
            "the wind picks up under Cold Storage (hint: tilt into it), then one 4 m yard in a light headwind "
            "with 13 m of dock cover after it")
s.set_piece("Lock Bridge", s.start("marine"), s.end("customs"),
            "after the grain store downpipe, a 10 m crossing over the canal into the headwind (~45 stamina, "
            "slowed), puddles at both kerbs, then 13 m of harbour office balconies to close up")
s.set_piece("Tin shed row", s.start("shed1"), s.end("salvage"),
            "torn tin awnings keep the umbrella up for ~22 m (stamina), a gutter through a tear in the second "
            "shed, a deep puddle in the yard, then 19 m of intact cover before the coal yard")
s.set_piece("The coal wharf", s.start("coal"), s.end("flats"),
            "the longest gap: 16 m of open quay at full wind (~70 stamina), the truck stop canopy and the vent at "
            "TIRES to recover, then rain, a 6 m sun break, rain on the next quay, and the flats")
s.set_piece("Turning Basin and Ferry Lane", s.start("lot3"), s.start("inn"),
            "final exam: a 12 m crossing with deep puddles at both kerbs, the 7 m slipway, torn canvas at "
            "HARDWARE and a downpipe at the inn door")

s.write()
