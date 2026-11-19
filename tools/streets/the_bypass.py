#!/usr/bin/env python3
"""The Bypass plan: see docs/LEVEL_AUTHORING.md. Writes levels/the_bypass.json.

The road out of town: a truck stop, car yards and open forecourts, a shut diner, the last petrol
station, a billboard over an empty paddock and a motel at the end. Heavy rain on a tailwind and one
short sun break early. Cars come up the near lane from behind: a splash as each passes (tilt back),
then a shot from its back window once it is ahead (tilt forward). A man comes up behind on foot, and
another waits under the petrol canopy beside the street's only drainpipe, the one place to refill.
"""
from street import Street

DRIVE_BY_LEAD = 4.5   # metres short of cover: the splash lands in the open, the shot as he reaches the cover

s = Street("the_bypass", "The Bypass",
           "The bypass. A petrol station, a motel, and a lot of open road.",
           aesthetic="outskirts", neon=0.0, rain=[[0.0, 1.15], [0.5, 1.35], [1.0, 1.5]],
           wind=[[0.0, 0.04], [0.3, 0.08], [0.6, 0.12], [1.0, 0.15]],
           gusts=True)

# 1. The truck stop: covered start, the first short gaps
s.lot("cafe", 8, "shop_lit", "awning", sign="TRUCKERS CAFE", color="red", floors=1, awning_style="wide_stripe")
s.lot("tyres", 6, "shuttered", "awning", sign="TYRES", color="brown", floors=1, awning_style="tin")
s.lot("wash", 6, "shop_dark", "awning", sign="CAR WASH", color="blue", floors=1, awning_style="waterfall")
s.lot("gap1", 4, "vacant", "none", floors=0)
s.lot("parts", 6, "shop_dark", "awning", sign="AUTO PARTS", color="green", floors=1, awning_style="pennant")
s.lot("gap2", 5, "vacant", "none", floors=0)
# 2. The car yards: open forecourts, the only sun break
s.lot("yard1", 10, "forecourt", "none", sign="USED CARS", floors=0, lit=True)
s.lot("sales", 5, "doorway", "awning", color="orange", floors=1, awning_style="tin")
s.lot("yard2", 12, "forecourt", "none", sign="BYPASS MOTORS", floors=0, lit=True)
s.lot("spares", 6, "shop_lit", "awning", sign="SPARES", color="red", floors=1, awning_style="wide_stripe")
s.lot("gap3", 6, "vacant", "none", floors=0)
s.lot("hire", 6, "shuttered", "awning", sign="TRUCK HIRE", color="brown", floors=1, awning_style="tin")
# 3. The first man on foot, from behind
s.lot("gap4", 7, "vacant", "none", floors=0)
s.lot("freight", 6, "shop_dark", "awning", sign="FREIGHT", color="green", floors=1, awning_style="tin")
s.lot("gap5", 8, "vacant", "none", floors=0)
s.lot("store", 8, "shop_lit", "awning", sign="GENERAL STORE", color="blue", floors=2, awning_style="wide_stripe")
s.xing("depotrd", 9)
s.lot("feed", 6, "shuttered", "awning", sign="STOCK FEED", color="brown", floors=1, awning_style="tin")
# 4. The shut diner's car park: the first car from behind
s.lot("dlot", 12, "forecourt", "none", sign="DINER", floors=0, note="CLOSED")
s.lot("dlot2", 8, "forecourt", "none", floors=0)
s.lot("bait", 6, "doorway", "awning", sign="BAIT", color="teal", floors=1, awning_style="tin")
s.lot("gap6", 5, "vacant", "none", floors=0)
# 5. The petrol station: the only drainpipe, and a man waiting under the canopy beside it
s.lot("kiosk", 6, "shop_lit", "awning", sign="SERVICE", color="red", floors=1, awning_style="wide_stripe")
s.lot("pipe", 1.5, "wall", "none", floors=1)
s.lot("petrol1", 8, "gas_station", "canopy", sign="BYPASS FUEL", floors=0)
s.lot("petrol2", 8, "gas_station", "canopy", floors=0)
s.lot("air", 6, "vacant", "none", floors=0)
# 6. The paddock under the billboard, the machinery yards
s.lot("field1", 14, "vacant", "none", floors=0)
s.lot("shed", 6, "shuttered", "awning", color="brown", floors=1, awning_style="tin")
s.lot("gap9", 6, "vacant", "none", floors=0)
s.lot("tractor", 8, "shop_dark", "awning", sign="TRACTOR PARTS", color="red", floors=1, awning_style="tin", tears=[[3.0, 4.2]])
s.lot("gap10", 7, "vacant", "none", floors=0)
s.lot("weigh", 6, "shuttered", "awning", sign="WEIGHBRIDGE", color="brown", floors=1, awning_style="tin")
# 7. The stock agent's yard: the second car
s.lot("ylot", 12, "forecourt", "none", sign="STOCK & STATION", floors=0)
s.lot("panel", 8, "shop_dark", "awning", sign="PANEL BEATER", color="green", floors=1, awning_style="tin")
s.lot("seed", 9, "shuttered", "awning", sign="SEED & GRAIN", color="green", floors=1, awning_style="waterfall")
s.xing("millln", 9, car=True)
# The last of the strip
s.lot("grain", 8, "warehouse", "awning", sign="GRAIN", color="brown", floors=1, awning_style="tin")
s.lot("gap7", 6, "vacant", "none", floors=0)
s.lot("laundry", 6, "shop_dark", "awning", sign="LAUNDROMAT", color="blue", floors=1, awning_style="waterfall")
# 8. The truckies' rest
s.lot("gap8", 8, "vacant", "none", floors=0)
s.lot("motor", 6, "shop_dark", "awning", sign="MOTOR REPAIRS", color="green", floors=1, awning_style="tin")
s.lot("clear1", 8, "vacant", "none", floors=0)
s.lot("bottle", 8, "shop_lit", "awning", sign="BOTTLE SHOP", color="red", floors=1, awning_style="wide_stripe")
s.lot("gap11", 4, "vacant", "none", floors=0)
s.lot("phone", 7, "doorway", "awning", color="brown", floors=1, awning_style="tin")
s.lot("mlot", 12, "forecourt", "none", sign="VACANCY", floors=0, lit=True)
# 9. The Bypass Motor Inn: the walkway along the rooms, the office at the end
s.lot("rooms1", 11, "motel", "walkway", floors=1)
s.lot("pool", 12, "forecourt", "none", floors=0)
s.lot("rooms2", 10, "motel", "walkway", floors=1)
s.lot("inn", 8, "inn", "awning", sign="BYPASS MOTOR INN", color="teal", floors=1, awning_style="wide_stripe")
s.lot("rooms3", 11, "motel", "walkway", floors=1)
s.door("inn")

s.feature("sun", s.start("yard2") + 3.0, w=6.0)
s.feature("puddle", s.mid("gap1"), w=1.0)
s.feature("puddle", s.mid("gap3"), w=1.2)
s.feature("puddle", s.mid("gap5"), w=1.2)
s.feature("puddle", s.start("depotrd") + 1.2, w=1.4, deep=True)
s.feature("puddle", s.mid("dlot"), w=1.4)
s.feature("gutter", s.mid("pipe"))
s.feature("puddle", s.mid("field1"), w=1.4)
s.feature("puddle", s.mid("ylot"), w=1.2)
s.feature("puddle", s.start("millln") + 1.2, w=1.4, deep=True)
s.feature("puddle", s.mid("gap7"), w=1.0)
s.feature("puddle", s.mid("mlot"), w=1.4)
s.feature("puddle", s.mid("gap9"), w=1.0)
s.feature("puddle", s.mid("clear1"), w=1.2)
s.feature("puddle", s.mid("pool"), w=1.0)

# The first man comes up behind as the yards end: tilt back to put the shot behind you.
s.attacker(s.start("gap3") + 2.0, shots=4, gap=3.6, hint="Tilt back to aim behind you.")
# The second waits under the petrol canopy beside the drainpipe: he fires as the walker comes up.
s.attacker(s.mid("pipe") - 9.0, shots=4, gap=3.6, wait=s.start("petrol1") + 1.6)
# Cars from behind across the diner's car park, the stock agent's yard and the motel's: each splashes
# him out in the open and fires from ahead just as he comes in under cover.
for t in ["bait", "panel", "rooms1"]:
    s.drive_by(s.start(t) - DRIVE_BY_LEAD)
# On the walkway at the motel, in a yellow slicker, smoking. He doesn't move.
s.slicker(s.start("rooms2") + 5.0, z=0.8, facing=-1, pose="watch", smoking=True)
s.hint(s.start("rooms2") + 3.0, "He came dressed for it.", 4.0)

for t in ["cafe", "wash", "spares", "hire", "freight", "store", "feed", "bait", "kiosk", "shed", "panel", "grain", "laundry"]:
    s.prop("lamp_post", s.end(t) - 0.4)
s.prop("sandwich_board", s.start("cafe") + 1.2)
s.prop("trash_can", s.end("tyres") - 0.8)
s.prop("crates", s.start("parts") + 0.8)
s.prop("cardboard_boxes", s.end("parts") - 1.0)
s.prop("chainlink_fence_4", s.start("gap3") + 1.0)
s.prop("trash_bags", s.start("hire") + 0.8)
s.prop("chainlink_fence_4", s.start("gap5") + 2.0)
s.prop("street_sign", s.start("depotrd") - 0.6)
s.prop("hydrant", s.end("depotrd") + 0.8)
s.prop("newspaper_box", s.end("feed") - 1.0)
s.prop("trash_bags", s.end("bait") - 0.8)
s.prop("vending_machine_a", s.start("kiosk") + 1.0)
s.prop("gas_pump", s.start("petrol1") + 3.5)
s.prop("gas_pump", s.start("petrol2") + 2.5)
s.prop("gas_pump", s.start("petrol2") + 5.5)
s.prop("pylon_sign", s.mid("air"), text="LAST FUEL\nBEFORE\nCITY LIMITS")
s.prop("billboard", s.mid("field1"), text="THE OFFICE.\nWE NEVER CLOSE.")
s.prop("crates", s.start("shed") + 0.8)
s.prop("street_sign", s.start("millln") - 0.6)
s.prop("hydrant", s.end("millln") + 0.8)
s.prop("crates", s.start("grain") + 1.2)
s.prop("trash_bags", s.mid("gap7"))
s.prop("mailbox", s.end("laundry") - 1.0)
s.prop("vending_machine_b", s.start("rooms1") + 0.6)
s.prop("chainlink_fence_4", s.start("pool") + 0.5)

s.set_piece("The truck stop", 0.0, s.end("gap2"),
            "a covered start under the truck stop's awnings, then the first short gaps in heavy rain")
s.set_piece("The car yards", s.start("yard1"), s.end("hire"),
            "open forecourts with the only sun break, and the umbrella's water shot")
s.set_piece("The first man", s.start("gap3"), s.end("feed"),
            "a man on foot comes up behind across short gaps: tilt back to block his jets or to shoot back")
s.set_piece("The shut diner", s.start("dlot"), s.end("gap6"),
            "headlights behind across the diner's car park: a car splashes him as it passes (tilt back), then "
            "fires from its back window once ahead (tilt forward)")
s.set_piece("The petrol station", s.start("kiosk"), s.end("air"),
            "the street's only drainpipe, guarded by a man under the petrol canopy: soak him or block him, then refill")
s.set_piece("The paddock", s.start("field1"), s.end("millln"),
            "a 14 m paddock under the billboard, then the second car across a stock agent's yard, and Mill Lane's car")
s.set_piece("The Bypass Motor Inn", s.start("grain"), s.end("inn"),
            "the third car across the motel's car park, the walkway along the rooms and the office door")

s.write()
