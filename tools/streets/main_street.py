#!/usr/bin/env python3
"""Main Street plan: see docs/LEVEL_AUTHORING.md. Writes levels/main_street.json."""
from street import Street

s = Street("main_street", "Main Street",
           "The old downtown. Most shops are shuttered, but the awnings still hold.",
           aesthetic="rundown", neon=0.0, rain=[[0.0, 0.8], [0.5, 1.0], [1.0, 1.05]],
           wind=[[0.0, 0.0], [1.0, 0.0]])

# 1. The Bijou arcade: continuous cover, the title-screen stretch
s.lot("diner", 6, "shop_lit", "awning", sign="DINER", color="red", floors=2)
s.lot("bijou", 8, "shop_lit", "arcade", sign="BIJOU", floors=3)
s.lot("showing", 6, "shop_dark", "arcade", sign="NOW SHOWING", floors=3)
s.lot("tickets", 4, "doorway", "arcade", sign="TICKETS", floors=3)
s.lot("candy", 4, "shop_lit", "arcade", sign="CANDY", floors=3)
# 2. First gaps: open the umbrella
s.lot("alley1", 2.5, "wall", "none", floors=2)
s.lot("hats", 5, "shop_dark", "awning", sign="HATS", color="green", floors=2)
s.lot("drugs", 6, "shop_lit", "awning", sign="DRUGS", color="teal", floors=3)
s.lot("lot1", 4, "vacant", "none", floors=0)
s.lot("radio", 6, "shuttered", "awning", sign="RADIO & TV", color="orange", floors=2)
s.lot("shoes", 4, "shop_lit", "awning", sign="SHOES", color="brown", floors=2)
s.lot("alley2", 3, "wall", "none", floors=3)
s.lot("tailor", 5, "shop_dark", "awning", sign="TAILOR", color="blue", floors=2)
s.lot("parking", 5, "vacant", "none", floors=0)
s.lot("dime", 8, "shop_lit", "awning", sign="FIVE & DIME", color="red", floors=2)
s.lot("cafe", 4, "shop_dark", "awning", sign="CAFE", color="brown", floors=2)
# 3. Elm Street and the used-car lot: the long gap, then recover
s.lot("carlot", 3, "vacant", "none", floors=0)
s.xing("elm", 9)
s.lot("hotel", 8, "shop_lit", "balcony", sign="HOTEL AMBASSADOR", floors=5)
s.lot("lounge", 4, "shop_dark", "balcony", sign="LOUNGE", floors=5)
# 4. The drainpipe at the savings bank: gutter, then a puddle gap
s.lot("bank", 8, "shuttered", "awning", sign="SAVINGS & LOAN", color="green", floors=3)
s.lot("pipe", 1.5, "wall", "none", floors=3)
s.lot("barber", 5, "shop_lit", "awning", sign="BARBER", color="red", floors=2)
s.lot("deli", 5, "shop_dark", "awning", sign="DELI", color="teal", floors=2)
s.lot("lot2", 5, "vacant", "none", floors=0)
s.lot("books", 6, "shop_dark", "awning", sign="BOOKS", color="brown", floors=2)
s.lot("photo", 4, "shop_lit", "awning", sign="PHOTO", color="blue", floors=3)
# 5. Oak Street: the puddle crossing, then recover
s.xing("oak", 8)
s.lot("news", 4, "shop_lit", "awning", sign="NEWS", color="teal", floors=3)
s.lot("cleaners", 5, "shuttered", "awning", sign="CLEANERS", color="brown", floors=2)
s.lot("grocery", 6, "shop_lit", "awning", sign="GROCERY", color="orange", floors=2)
# 6. The Palace lot: a sun break where closing pays
s.lot("palace", 12, "vacant", "none", floors=0)
s.lot("laundro", 6, "shop_lit", "awning", sign="LAUNDROMAT", color="blue", floors=2)
s.lot("alley4", 4, "wall", "none", floors=2)
s.lot("flats", 8, "boarded", "balcony", floors=3)
s.lot("loans", 5, "shop_lit", "awning", sign="LOANS", color="green", floors=2)
s.lot("lot3", 7, "vacant", "none", floors=0)
s.lot("liquor", 4, "shop_lit", "awning", sign="LIQUOR", color="red", floors=2)
s.lot("alley5", 4, "wall", "none", floors=2)
s.lot("florist", 4, "shop_lit", "awning", sign="FLORIST", color="green", floors=2)
s.lot("tobacco", 4, "shop_dark", "awning", sign="TOBACCO", color="brown", floors=2)
# 7. Pawn Row: the broken awnings before the inn (final exam)
s.lot("pawn", 6, "shop_lit", "awning", sign="PAWN", color="orange", floors=3, tears=[[1.2, 2.2], [3.8, 4.8]])
s.lot("records", 4, "shuttered", "awning", sign="RECORDS", color="teal", floors=2, tears=[[1.4, 2.4]])
s.lot("toys", 6, "boarded", "awning", color="red", floors=2, tears=[[0.6, 1.6], [3.0, 4.4]])
s.lot("secondhand", 7, "shop_lit", "awning", sign="SECOND HAND", color="green", floors=2)
s.lot("hardware", 6, "shop_dark", "awning", sign="HARDWARE", color="blue", floors=2, tears=[[0.8, 1.8], [2.8, 3.8], [4.6, 5.6]])
s.lot("tvrepair", 4, "shuttered", "awning", sign="TV REPAIR", color="orange", floors=2, tears=[[0.8, 1.8], [2.6, 3.6]])
s.lot("pipe2", 1.0, "wall", "none", floors=3)
s.lot("watch", 3, "shop_lit", "awning", sign="WATCH REPAIR", color="teal", floors=2)
s.lot("inn", 8, "inn", "awning", sign="THE RAINY DAY INN", color="red", floors=3)
s.lot("bakery", 8, "shop_dark", "awning", sign="BAKERY", color="teal", floors=3)
s.door("inn")

s.feature("gutter", s.mid("pipe"))
s.feature("puddle", s.mid("lot2"), w=1.2)
s.feature("fire_barrel", s.start("hotel") + 2.0, w=1.8)
s.feature("puddle", s.start("oak") + 1.2, w=1.4, deep=True)
s.feature("puddle", s.end("oak") - 1.2, w=1.4, deep=True)
s.feature("puddle", s.start("palace") + 1.6, w=1.0)
s.feature("sun", s.start("palace") + 3.0, w=6.0)
s.feature("puddle", s.mid("alley4"), w=1.4, deep=True)
s.feature("puddle", s.start("records") + 1.9, w=1.0)
s.feature("gutter", s.start("toys") + 3.7)
s.feature("gutter", s.mid("pipe2"))

for t in ["diner", "showing", "drugs", "radio", "dime", "hotel", "bank", "deli", "photo", "laundro", "loans", "news", "records", "secondhand", "tvrepair", "bakery"]:
    s.prop("lamp_post", s.mid(t))
s.prop("newspaper_box", s.start("bijou") + 1.0)
s.prop("bench", s.mid("bijou") + 1.5)
s.prop("sandwich_board", s.start("candy") + 1.0)
s.prop("trash_bags", s.start("alley1") + 0.6)
s.prop("mailbox", s.end("drugs") - 1.0)
s.prop("chainlink_fence_4", s.mid("lot1"))
s.prop("trash_can", s.end("shoes") - 0.8)
s.prop("crates", s.mid("alley2"))
s.prop("parking_meter", s.start("carlot") + 1.0)
s.prop("parking_meter", s.end("carlot") - 1.5)
s.prop("street_sign", s.start("elm") - 0.6)
s.prop("hydrant", s.end("elm") + 0.8)
s.prop("bench", s.mid("hotel") + 1.5)
s.prop("downpipe", s.mid("pipe"))
s.prop("phone_booth", s.end("barber") - 1.0)
s.prop("trash_bags", s.mid("alley5"))
s.prop("cardboard_boxes", s.start("palace") + 2.0)
s.prop("bench", s.mid("palace") + 1.0)
s.prop("trash_can", s.end("laundro") - 0.8)
s.prop("crates", s.start("alley4") + 0.5)
s.prop("newspaper_box_b", s.end("photo") - 0.8)
s.prop("street_sign", s.start("oak") - 0.6)
s.prop("mailbox", s.end("news") - 1.0)
s.prop("hydrant", s.end("oak") + 1.0)
s.prop("trash_bags", s.start("toys") + 3.0)
s.prop("downpipe", s.mid("pipe2"))
s.prop("sandwich_board", s.start("hardware") + 1.0)
s.prop("bollard", s.start("inn") - 0.5)
s.prop("newspaper_box", s.end("inn") + 1.0)

s.set_piece("The Bijou arcade", 0.0, s.end("candy"),
            "walking under continuous cover (diner awning, then the cinema colonnade)")
s.set_piece("First gaps", s.start("alley1"), s.end("parking"),
            "open the umbrella for a short gap: 2.5, 4, 3 and 5 m, each followed by cover")
s.set_piece("Elm Street and the Hotel Ambassador", s.start("carlot"), s.end("lounge"),
            "a 12 m gap (used-car lot + Elm St) that costs ~40 stamina, then 12 m of balconies and a fire barrel to close up and recover")
s.set_piece("The drainpipe at the Savings & Loan", s.start("bank"), s.end("photo"),
            "a gutter in a 1.5 m seam between awnings (keep the umbrella upright), then a puddle in the next lot (walk, don't run)")
s.set_piece("Oak Street", s.start("oak"), s.end("grocery"),
            "re-test: deep puddles at both kerbs, then 15 m of cover to recover")
s.set_piece("The Palace lot", s.start("palace"), s.end("flats"),
            "sun break mid-lot (rain, 6 m sun, rain): close it in the sun to recover, reopen in time")
s.set_piece("Pawn Row", s.start("pawn"), s.start("inn"),
            "final exam: torn awnings keep the umbrella up (stamina), a gutter through the toy shop's torn awning, a breather under SECOND HAND, a last gutter at the inn")

s.write()
