#!/usr/bin/env python3
"""Skyway Terminal plan: see docs/LEVEL_AUTHORING.md. Writes levels/skyway_terminal.json.

The downtown air terminal: glass towers, and a glass skyway carried over the pavement at the first
floor, so most of the street is dry underfoot. The rain is no longer the threat. The shuttle
helicopters to the airport come in low over the skyway, and their rotor wash drives the rain in under
it: umbrella up, upright, whatever cover you're under. The camera sits further back so the towers
read at their size.

Fairweather, the man in the yellow slicker, steps out of the travel bureau early on. Tail him under
the skyway (keep him in frame, stay out of his glance, hide your face when he looks round) until he
goes in at the terminal. Then his men are waiting for you under the skyway, a helicopter hangs over
it, cars come up behind you on Airport Road, and his own helicopter passes over as you reach the
hotel. Every car crossing has skyway over its approach (tilting forward for the splash bares the
back), and every downpipe stands well clear of the men (bracing for a jet under a stream soaks you).
"""
from street import Street

s = Street("skyway_terminal", "Skyway Terminal",
           "Glass towers and skyways over the pavement. The airport helicopters come and go from the terminal roof.",
           aesthetic="modern", neon=0.35, rain=[[0.0, 1.0], [0.5, 1.15], [1.0, 1.3]],
           wind=[[0.0, 0.06], [0.4, 0.12], [0.7, 0.18], [1.0, 0.14]],
           gusts=False, par_speed=1.2,
           camera={"distance": 10.5, "height": 3.2, "fov": 52.0, "pitch": 3.0, "lead": 2.8})


def tower(tag, w, sign=None, floors=16, **kw):
    """A glass curtain-wall tower front; under a skyway it takes no cover of its own."""
    s.lot(tag, w, "glass_tower", "none", sign=sign, floors=floors, **kw)


def lobby(tag, w, sign=None, floors=14, **kw):
    """A lit double-height glass lobby: the airline offices, the terminal, hotels."""
    s.lot(tag, w, "lobby", "none", sign=sign, floors=floors, lit=True, **kw)


def shop(tag, w, sign, color, floors=12, awning_style="googie", **kw):
    """A shop or bar with its own canopy, where the skyway doesn't reach."""
    s.lot(tag, w, "shop_lit", "awning", sign=sign, color=color, floors=floors, awning_style=awning_style,
          neon=True, **kw)


def plaza(tag, w, sign=None, **kw):
    """An open plaza with its tower set well back: open sky, and the skyline beyond."""
    s.lot(tag, w, "plaza", "none", sign=sign, floors=5, **kw)


def seam(tag, w, floors=14):
    """A narrow wall seam between towers, where a downpipe comes down between skyways."""
    s.lot(tag, w, "wall", "none", sign=" ", floors=floors)


# 1. Terminal Approach: the first skyway, and the first helicopter overhead
tower("meridian", 8, "MERIDIAN", floors=18)
lobby("bank", 8, "FIRST NATIONAL", floors=20)
tower("tower1", 6, floors=16)
lobby("airline", 8, "PAN-STELLAR AIRWAYS", floors=18)
tower("tower2", 8, floors=22)
tower("tower3", 6, floors=16)
# 2. The concourse: the skyway breaks off for short gaps and a downpipe, then carries on over Jetway Street
plaza("plaza1", 4)
shop("coffee", 6, "COFFEE SHOP", "teal")
seam("pipe1", 1.5)
shop("news", 5, "NEWS", "orange")
plaza("plaza2", 4)
tower("tower4a", 5, floors=16)
tower("tower4", 6, floors=18)
s.xing("jetway", 9, car=True)
# 3. The tail: Fairweather out of the travel bureau, under the long skyway over Concourse Avenue
lobby("bureau", 8, "TRAVEL BUREAU", floors=16)
tower("tower5", 8, floors=20)
lobby("jewels", 6, "JEWELLERS", floors=14)
tower("tower6", 6, floors=18)
s.xing("concourse", 10)
lobby("tickets", 8, "AIR TICKETS", floors=16)
tower("tower7", 8, floors=22)
lobby("lounge", 6, "SKY LOUNGE", floors=14)
tower("tower8", 6, floors=18)
lobby("cameras", 6, "CAMERAS", floors=14)
tower("tower9", 8, floors=20)
plaza("plaza3", 5)
shop("florist", 5, "FLOWERS", "green")
plaza("plaza4", 4)
tower("tower10", 6, floors=18)
lobby("tailor", 6, "TAILOR", floors=14)
tower("tower11", 8, floors=20)
s.xing("runway", 9, car=True)
lobby("cocktail", 6, "COCKTAILS", floors=16)
tower("tower12", 6, floors=18)
lobby("terminal", 12, "SKYWAY TERMINAL", floors=24)
# 4. His men: two posted under the next skyway, downpipes in the seams either side
seam("pipe2", 1.5)
tower("tower13", 8, floors=18)
lobby("bar", 6, "BAR", floors=14)
tower("tower14", 6, floors=20)
lobby("travel", 8, "HOLIDAYS", floors=16)
tower("tower15", 6, floors=18)
seam("pipe3", 1.5)
# 5. The hover: a helicopter overtakes and hangs over the skyway; then a downpipe to refill
lobby("gifts", 6, "GIFTS", floors=14)
tower("tower16", 8, floors=22)
lobby("lounge2", 6, "COCKTAIL LOUNGE", floors=16)
tower("tower16b", 8, floors=18)
seam("pipe4", 1.5)
# 6. Airport Road: plazas open to the sky, and two cars that come up behind
plaza("plaza4b", 7)
shop("luggage", 8, "LUGGAGE", "orange")
plaza("plaza5", 7)
shop("diner", 6, "DINER", "red")
plaza("plaza6", 7)
shop("rentals", 6, "CAR RENTAL", "blue")
tower("tower17", 6, floors=18)
lobby("motors", 6, "MOTORS", floors=14)
s.xing("airportrd", 9, car=True)
tower("tower18", 8, floors=20)
lobby("bags", 6, "TRAVEL GOODS", floors=14)
seam("pipe5", 1.5)
# 7. The hotel: the last of his men at the lobby, his helicopter overhead
tower("tower19", 6, floors=18)
lobby("hotel_lobby", 8, "RESTAURANT", floors=22)
s.lot("inn", 8, "inn", "none", sign="SKYWAY TERMINAL HOTEL", floors=22)
tower("tower20", 8, floors=24)
s.door("inn")

s.skyway("meridian", "tower3")
s.skyway("tower4a", "tower9")
s.skyway("tower10", "terminal")
s.skyway("tower13", "tower15")
s.skyway("gifts", "tower16b")
s.skyway("tower17", "bags")
s.skyway("tower19", "tower20")

# The helicopters: one to learn on under the first skyway; one coming in to land on the terminal as
# Fairweather goes in; one that hangs over the skyway past his men; his own at the hotel.
s.helicopter(s.start("tower1"), dir=-1)
s.helicopter(s.start("terminal"), dir=-1)
s.helicopter(s.start("tower15") + 2.0, dir=1, hover_x=s.mid("tower16"), hover_s=2.0)
s.helicopter(s.start("tower19"), dir=1)

s.courier(appear_x=s.mid("bureau"), door_x=s.mid("terminal"), look="slicker", stops=[
    (s.mid("jewels") - 0.5, 3.5),
    (s.mid("lounge"), 3.0),
    (s.mid("cameras"), 2.5),
    (s.mid("tailor"), 4.0),
])

# His men, each well clear of a downpipe (a stream within a man's reach soaks a walker bracing for him).
s.henchman(s.start("bar") + 3.0)
s.henchman(s.start("travel") + 2.0)
s.henchman(s.start("hotel_lobby") + 2.5)

DRIVE_BY_LEAD = 4.5   # metres short of cover: the splash lands in the open, the shot as he reaches it
for t in ["diner", "rentals"]:
    s.drive_by(s.start(t) - DRIVE_BY_LEAD)

for t in ["pipe1", "pipe2", "pipe3", "pipe4", "pipe5"]:
    s.feature("gutter", s.mid(t))
s.feature("puddle", s.mid("plaza1"), w=1.0)
s.feature("puddle", s.mid("plaza2"), w=1.2)
s.feature("puddle", s.start("jetway") + 1.2, w=1.4, deep=True)
s.feature("puddle", s.start("runway") + 1.2, w=1.4, deep=True)
s.feature("puddle", s.mid("plaza4b"), w=1.2)
s.feature("puddle", s.mid("plaza5"), w=1.4)
s.feature("puddle", s.mid("plaza6"), w=1.2, deep=True)
s.feature("puddle", s.start("airportrd") + 1.2, w=1.4, deep=True)

s.hint(s.mid("terminal") + 3.0, "He's gone in. They'll have seen you come.", 4.0)
s.hint(s.start("tower19") + 2.0, "That's his helicopter.", 3.5)

s.prop("revolving_door", s.start("bank") + 2.2)
s.prop("revolving_door", s.start("terminal") + 3.0)
s.prop("revolving_door", s.start("hotel_lobby") + 5.5)
s.prop("bench", s.mid("tower2"))
s.prop("newspaper_box_b", s.start("news") + 0.8)
s.prop("phone_booth", s.mid("tower5"))
s.prop("street_sign", s.start("jetway") - 0.6)
s.prop("hydrant", s.end("jetway") + 0.8)
s.prop("street_sign", s.start("concourse") - 0.6)
s.prop("trash_can", s.mid("tower8"))
s.prop("mailbox", s.mid("tower11"))
s.prop("street_sign", s.start("runway") - 0.6)
s.prop("hydrant", s.end("runway") + 0.8)
s.prop("bench", s.mid("tower14"))
s.prop("lamp_post", s.mid("plaza4b"))
s.prop("lamp_post", s.mid("plaza5"))
s.prop("lamp_post", s.mid("plaza6"))
s.prop("street_sign", s.start("airportrd") - 0.6)
s.prop("hydrant", s.end("airportrd") + 0.8)
s.prop("newspaper_box", s.end("inn") + 1.0)
for tag in ["meridian", "tower3", "tickets", "tower16"]:
    s.figure(s.mid(tag) + 1.0)

s.set_piece("Terminal Approach", 0.0, s.end("tower3"),
            "the first skyway, dry underfoot with the wider camera; the first helicopter comes in low "
            "from ahead and its rotor wash drives the rain in under the skyway: umbrella up, upright")
s.set_piece("The Concourse", s.start("plaza1"), s.end("jetway"),
            "the skyway breaks off for short gaps and a downpipe, then carries on over Jetway Street, "
            "whose car comes at a walker under cover")
s.set_piece("Tailing Fairweather", s.start("bureau"), s.end("terminal"),
            "the man in the yellow slicker steps out of the travel bureau and walks to the terminal "
            "under the skyway, stopping at four windows: keep him in frame, out of his glance, hide your "
            "face when he looks round; two plazas in the rain, and a car at Runway Street")
s.set_piece("At the terminal door", s.start("tower12"), s.end("pipe2"),
            "a helicopter coming in to land on the terminal roof as he goes in: umbrella up for the wash")
s.set_piece("His Men", s.start("tower13"), s.end("pipe3"),
            "two men posted under the skyway, downpipes before and after them to refill the shot")
s.set_piece("The Hover", s.start("gifts"), s.end("pipe4"),
            "a helicopter overtakes and hangs over the skyway: hold the canopy up through the wash "
            "(stopping is free) until it flies on")
s.set_piece("Airport Road", s.start("plaza4b"), s.end("airportrd"),
            "plazas open to the sky in heavier rain, and two cars that come up behind: splash from behind, "
            "a shot from ahead; skyway again over the approach to Airport Road")
s.set_piece("Skyway Terminal Hotel", s.start("pipe5"), s.end("inn"),
            "a last downpipe, the last of his men at the hotel lobby, and Fairweather's helicopter "
            "passing overhead as the walker reaches the door")

s.write()
