#!/usr/bin/env python3
"""Viaduct Road plan: see docs/LEVEL_AUTHORING.md. Writes levels/viaduct_road.json.

Kiln Street's brick outskirts under a railway viaduct that stands over the pavement the whole way.
Its brick arches are deep cover from the rain and from the trains' sheet of water; between them the
line crosses on open iron girder spans that let both through, over the usual gaps, gutters and cars.
Three men come up from behind, one at a time, each announced by footsteps and a long shadow thrown
ahead from a lamp behind him. Each fires a few telegraphed jets: tilt back to block them, or get under
an arch, where he holds his fire while his time runs out.
"""
from street import Street

s = Street("viaduct_road", "Viaduct Road",
           "Under the railway arches. The trains still run, though nobody gets on.",
           aesthetic="outskirts", neon=0.0, rain=[[0.0, 1.1], [0.5, 1.3], [1.0, 1.4]],
           wind=[[0.0, 0.05], [0.3, 0.2], [0.5, 0.25], [0.62, 0.0], [0.75, -0.1], [0.85, -0.22], [1.0, -0.3]],
           gusts=True)


def arch(tag, w, style, sign=None, floors=2):
    """A lot under the viaduct's arches: the arch is its cover, so it has none of its own."""
    s.lot(tag, w, style, "none", sign=sign, floors=floors)


# 1. The arches at the station end, and a black sedan idling in Yard Lane
arch("yard", 6, "shuttered", floors=2)
arch("arch1", 5, "boarded", floors=2)
arch("arch2", 6, "shop_dark", sign="COAL", floors=2)
arch("arch3", 5, "doorway", floors=2)
arch("arch4", 6, "shuttered", floors=2)
# 2. The first girder span: short gaps and the only sun break
s.xing("yardln", 7)
s.lot("terr1", 6, "shop_dark", "awning", color="brown", floors=2, awning_style="tin")
s.lot("gap2", 4, "vacant", "none", floors=0)
s.lot("terr2", 5, "doorway", "awning", color="green", floors=2, awning_style="waterfall")
s.lot("clear1", 10, "vacant", "none", floors=0)
s.lot("terr3", 6, "shop_lit", "awning", sign="TEA ROOM", color="red", floors=2, awning_style="wide_stripe")
s.lot("pipe1", 1.5, "wall", "none", floors=2)
s.lot("terr4", 6, "shuttered", "awning", color="brown", floors=2, awning_style="tin")
# 3. Coal arches, then Station Lane's car
arch("arch5", 6, "shop_dark", sign="CYCLES")
arch("arch6", 6, "shuttered")
arch("arch7", 6, "doorway")
s.xing("stnln", 9, car=True)
# 4. The first man from behind, along the open girders
s.lot("terr5", 8, "boarded", "awning", color="brown", floors=2, awning_style="tin")
s.lot("gap3", 6, "vacant", "none", floors=0)
s.lot("terr6", 6, "shop_dark", "awning", sign="TAILOR", color="blue", floors=2, awning_style="pennant")
s.lot("gap4", 5, "vacant", "none", floors=0)
s.lot("terr7", 5, "shuttered", "awning", color="green", floors=2, awning_style="waterfall")
arch("arch8", 6, "boarded")
arch("arch9", 6, "shop_dark", sign="SCRAP")
arch("arch10", 6, "shuttered")
# 5. The sidings: longer gaps, torn tin, gutters
s.lot("gap5", 8, "vacant", "none", floors=0)
s.lot("terr8", 6, "boarded", "awning", color="brown", floors=2, awning_style="tin")
s.lot("pipe2", 1.5, "wall", "none", floors=2)
s.lot("terr9", 6, "shop_dark", "awning", sign="BOOTS", color="red", floors=2, awning_style="wide_stripe")
s.lot("clear2", 12, "vacant", "none", floors=0)
s.lot("terr10", 6, "shuttered", "awning", color="teal", floors=2, awning_style="waterfall")
s.lot("gap6", 7, "vacant", "none", floors=0)
s.lot("terr11", 6, "doorway", "awning", color="brown", floors=2, awning_style="tin", tears=[[0.6, 1.8]])
arch("arch11", 6, "shuttered")
arch("arch12", 6, "doorway")
s.lot("gap13", 5, "vacant", "none", floors=0)
# 6. The second man, then the long arches before Market Street
s.lot("terr12", 6, "shop_dark", "awning", color="green", floors=2, awning_style="tin")
s.lot("gap7", 5, "vacant", "none", floors=0)
s.lot("terr13", 6, "boarded", "awning", color="brown", floors=2, awning_style="tin", tears=[[1.8, 3.0]])
s.lot("gap8", 7, "vacant", "none", floors=0)
s.lot("terr14", 5, "shuttered", "awning", color="red", floors=2, awning_style="pennant")
arch("arch14", 6, "boarded")
arch("arch15", 6, "shop_dark", sign="SALVAGE")
s.xing("mktst", 9, car=True)
# 7. Past the goods yard: the headwind comes round, gutters at the seams
s.lot("terr15", 6, "shop_lit", "awning", sign="DINING ROOMS", color="red", floors=2, awning_style="wide_stripe")
s.lot("gap9", 6, "vacant", "none", floors=0)
s.lot("terr16", 6, "boarded", "awning", color="brown", floors=2, awning_style="tin", tears=[[2.4, 3.6]])
s.lot("pipe3", 1.5, "wall", "none", floors=2)
s.lot("terr17", 7, "shuttered", "awning", color="blue", floors=2, awning_style="waterfall")
s.lot("clear3", 10, "vacant", "none", floors=0)
s.lot("terr18", 6, "shop_dark", "awning", color="green", floors=2, awning_style="tin")
arch("arch16", 6, "shuttered")
arch("arch17", 6, "doorway")
s.lot("gap14", 5, "vacant", "none", floors=0)
# 8. The third man
s.lot("terr19", 6, "boarded", "awning", color="brown", floors=2, awning_style="tin")
s.lot("gap10", 6, "vacant", "none", floors=0)
s.lot("terr20", 5, "shop_dark", "awning", sign="CHANDLER", color="teal", floors=2, awning_style="pennant")
s.lot("gap11", 7, "vacant", "none", floors=0)
s.lot("terr21", 6, "shuttered", "awning", color="red", floors=2, awning_style="tin")
arch("arch19", 6, "shop_dark", sign="TIMBER")
arch("arch20", 6, "shuttered")
arch("arch21", 6, "doorway")
# 9. The last stretch: long gaps into the headwind, Mill Lane's car, the Railway Arms
s.lot("clear4", 10, "vacant", "none", floors=0)
s.lot("terr22", 6, "boarded", "awning", color="brown", floors=2, awning_style="tin", tears=[[1.5, 2.7]])
s.lot("pipe4", 1.5, "wall", "none", floors=2)
s.lot("terr23", 8, "shop_dark", "awning", color="green", floors=2, awning_style="waterfall")
s.lot("clear5", 9, "vacant", "none", floors=0)
s.lot("terr24", 6, "shuttered", "awning", color="blue", floors=2, awning_style="pennant")
s.lot("terr25", 5, "doorway", "awning", color="red", floors=2, awning_style="tin")
s.xing("millln", 9, car=True)
s.lot("terr26", 6, "shuttered", "awning", color="brown", floors=2, awning_style="tin")
s.lot("post", 6, "shop_lit", "awning", sign="POST OFFICE", color="red", floors=2, awning_style="wide_stripe")
s.lot("inn", 8, "inn", "awning", sign="RAILWAY ARMS", color="green", floors=2, awning_style="wide_stripe")
s.lot("barn", 8, "warehouse", "awning", color="brown", floors=1, awning_style="tin")
s.door("inn")

s.track(gap=(10, 25), style="railway")
s.viaduct("yard", "arch4", style="railway")
s.viaduct("arch5", "arch7", style="railway")
s.viaduct("arch8", "arch10", style="railway")
s.viaduct("arch11", "arch12", style="railway")
s.viaduct("arch14", "arch15", style="railway")
s.viaduct("arch16", "arch17", style="railway")
s.viaduct("arch19", "arch21", style="railway")

s.feature("sun", s.start("clear1") + 2.0, w=6.0)
s.feature("gutter", s.mid("pipe1"))
s.feature("puddle", s.start("stnln") + 1.2, w=1.4, deep=True)
s.feature("puddle", s.mid("gap3"), w=1.2)
s.feature("puddle", s.mid("gap5"), w=1.2)
s.feature("gutter", s.start("terr11") + 1.2)
s.feature("gutter", s.mid("pipe2"))
s.feature("puddle", s.mid("clear2"), w=1.4)
s.feature("puddle", s.mid("gap6"), w=1.0)
s.feature("puddle", s.mid("gap13"), w=1.0)
s.feature("gutter", s.start("terr13") + 2.4)
s.feature("puddle", s.start("mktst") + 1.2, w=1.4)
s.feature("gutter", s.start("terr16") + 3.0)
s.feature("gutter", s.mid("pipe3"))
s.feature("puddle", s.mid("clear3"), w=1.4)
s.feature("puddle", s.mid("gap10"), w=1.2)
s.feature("puddle", s.mid("gap11"), w=1.2)
s.feature("puddle", s.start("clear4") + 4.0, w=1.2)
s.feature("gutter", s.start("terr22") + 2.1)
s.feature("gutter", s.mid("pipe4"))
s.feature("puddle", s.mid("clear5"), w=1.4)
s.feature("puddle", s.start("millln") + 1.2, w=1.4, deep=True)

# Three men from behind, one at a time, each with a lamp behind where he comes in.
# Each comes in about 15 m short of a run of arches: a few shots in the open, then shelter.
for tag, shots in [("terr6", 4), ("terr13", 4), ("terr20", 5)]:
    s.attacker(s.start(tag) + 1.0, shots)
    s.prop("bracket_lamp", s.start(tag) - 9.0)

s.prop("idling_sedan", s.mid("yardln") + 1.4)
s.prop("trash_bags", s.start("arch1") + 1.0)
s.prop("crates", s.end("arch2") - 1.0)
s.prop("cardboard_boxes", s.start("arch4") + 0.8)
s.prop("trash_can", s.end("terr1") - 0.8)
s.prop("bench", s.mid("clear1") + 2.0)
s.prop("mailbox", s.end("terr3") - 1.4)
s.prop("crates", s.start("arch6") + 1.2)
s.prop("street_sign", s.start("stnln") - 0.6)
s.prop("hydrant", s.end("stnln") + 0.8)
s.prop("trash_bags", s.mid("gap3") + 2.0)
s.prop("cardboard_boxes", s.end("terr6") - 0.8)
s.prop("crates", s.start("arch9") + 1.0)
s.prop("chainlink_fence_4", s.start("gap5") + 4.0)
s.prop("crates", s.start("terr8") + 0.8)
s.prop("trash_bags", s.mid("clear2") - 3.0)
s.prop("chainlink_fence_4", s.start("clear2") + 8.0)
s.prop("phone_booth", s.mid("arch12"), ring=True)
s.prop("trash_can", s.end("terr12") - 0.8)
s.prop("crates", s.start("arch15") + 1.0)
s.prop("street_sign", s.start("mktst") - 0.6)
s.prop("hydrant", s.end("mktst") + 0.8)
s.prop("sandwich_board", s.start("terr15") + 1.0)
s.prop("trash_bags", s.mid("gap9"))
s.prop("chainlink_fence_4", s.start("clear3") + 7.0)
s.prop("cardboard_boxes", s.start("arch17") + 1.0)
s.prop("crates", s.mid("gap10") + 1.5)
s.prop("trash_bags", s.start("arch20") + 1.0)
s.prop("chainlink_fence_4", s.start("clear4") + 6.0)
s.prop("trash_bags", s.mid("clear5") - 3.0)
s.prop("mailbox", s.end("terr25") - 1.0)
s.prop("street_sign", s.start("millln") - 0.6)
s.prop("hydrant", s.end("millln") + 0.8)
s.prop("mailbox", s.end("post") - 1.4)

s.set_piece("The station arches", 0.0, s.end("arch4"),
            "walk dry under the first run of arches, then across Yard Lane in front of a black sedan idling there, wipers going")
s.set_piece("The first girders", s.start("yardln"), s.end("stnln"),
            "the first open girder span: short gaps that rain and the train's sheet fall through, the only "
            "sun break, a gutter seam, then more arches and Station Lane's car")
s.set_piece("The first man", s.start("terr5"), s.end("arch10"),
            "footsteps and a long shadow from behind, then a man in the walker's own suit who closes in and "
            "fires: tilt back to block his jets, or reach the arches, where he holds his fire")
s.set_piece("The sidings", s.start("gap5"), s.end("gap13"),
            "longer gaps into the tailwind, a gutter seam, torn tin with a gutter through the tear, then arches")
s.set_piece("The second man", s.start("terr12"), s.end("mktst"),
            "the second man along gaps and torn tin, then two arches before Market Street's car")
s.set_piece("The goods yard", s.start("terr15"), s.end("gap14"),
            "the wind turns into a headwind: gaps, torn tin with a gutter, a gutter seam and a 12 m clearing")
s.set_piece("The third man", s.start("terr19"), s.end("arch21"),
            "the third man in the headwind, where tilting back to block him lets the rain in front")
s.set_piece("The Railway Arms", s.start("clear4"), s.end("inn"),
            "long gaps into the headwind with gutters, Mill Lane's car and the inn")

s.write()
