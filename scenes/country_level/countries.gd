class_name Countries
extends Object

## The winter countries on the way from Greenland to Astana (via Kyiv after
## Minsk), in the order of the journey, each with two or three of its national
## animals, and at the end the way back home to Zurich with its city foxes.
##
## A country is a dictionary with its [code]name[/code] (also its place on the
## travel map), the [code]critters_name[/code] for the HUD, the texts, the
## [code]critters[/code] (each a [code]kind[/code], "beast", "bird" or
## "ladybird", with its [code]look[/code]), the six [code]covers[/code] of the
## hiding places (far left to right, then near left to right), the colors of the
## sky and the snow, the [code]terrain[/code] ("volcanic", "fjord", "forest",
## "city", "steppe" or "alps"), whether it is [code]night[/code], and its
## [code]landmark[/code] on the horizon.

const K := CoverSpot.Kind

const _BEAR_BROWN := Color(0.55, 0.36, 0.22)


static func all() -> Array[Dictionary]:
    return [
        {
            "id": "iceland",
            "name": "Iceland",
            "critters_name": "Foxes, falcons and puffins",
            "intro": "Arctic foxes, gyrfalcons and puffins are hiding between the lava rocks!",
            "won": "The foxes, the falcons and the puffins are giggling by the geysers.",
            "lost": "The Icelandic animals won this snowball fight.",
            "critters":
            [
                {
                    "kind": "beast",
                    "look":
                    {
                        "fur": Color(0.97, 0.97, 0.99),
                        "shade": Color(0.82, 0.85, 0.92),
                        "belly": Color(1, 1, 1),
                        "muzzle": Color(1, 1, 1),
                        "ears": "pointy",
                        "snout": "pointy",
                        "features": [],
                    },
                },
                {
                    "kind": "bird",
                    "look":
                    {
                        "body": Color(0.92, 0.93, 0.96),
                        "belly": Color(1, 1, 1),
                        "wing": Color(0.6, 0.64, 0.72),
                        "beak": Color(0.98, 0.8, 0.3),
                        "beak_shape": "hooked",
                        "eye_ring": Color(1.0, 0.85, 0.3),
                    },
                },
                {
                    "kind": "bird",
                    "look":
                    {
                        "body": Color(0.15, 0.16, 0.2),
                        "belly": Color(0.98, 0.98, 1.0),
                        "wing": Color(0.12, 0.13, 0.17),
                        "head": Color(0.15, 0.16, 0.2),
                        "mask": Color(0.96, 0.96, 0.98),
                        "beak_shape": "puffin",
                    },
                },
            ],
            "covers": [K.BOULDER, K.DRIFT, K.BOULDER, K.DRIFT, K.BOULDER, K.SNOWMAN],
            "sky": [Color(0.5, 0.66, 0.86), Color(0.88, 0.92, 0.98)],
            "ground": [Color(0.86, 0.9, 0.96), Color(0.98, 0.99, 1.0)],
            "terrain": "volcanic",
            "landmark": "hallgrimskirkja",
        },
        {
            "id": "norway",
            "name": "Norway",
            "critters_name": "Reindeer and fjord horses",
            "intro": "Reindeer and fjord horses are hiding in the snow by the fjord!",
            "won": "The reindeer and the fjord horses are giggling by the fjord.",
            "lost": "The Norwegian animals won this snowball fight.",
            "critters":
            [
                {
                    "kind": "beast",
                    "look":
                    {
                        "fur": Color(0.56, 0.44, 0.36),
                        "shade": Color(0.44, 0.34, 0.28),
                        "belly": Color(0.9, 0.86, 0.78),
                        "muzzle": Color(0.68, 0.56, 0.46),
                        "antler": Color(0.9, 0.82, 0.66),
                        "ears": "horse",
                        "snout": "long",
                        "features": ["branched_antlers", "ruff"],
                    },
                },
                {
                    "kind": "beast",
                    "look":
                    {
                        "fur": Color(0.86, 0.72, 0.5),
                        "shade": Color(0.72, 0.58, 0.38),
                        "belly": Color(0.95, 0.88, 0.74),
                        "muzzle": Color(0.6, 0.48, 0.36),
                        "ears": "horse",
                        "snout": "long",
                        "features": ["mane_stripe"],
                    },
                },
            ],
            "covers": [K.SPRUCE, K.DRIFT, K.BOULDER, K.DRIFT, K.SNOWMAN, K.SPRUCE],
            "sky": [Color(0.38, 0.55, 0.85), Color(0.84, 0.9, 1.0)],
            "ground": [Color(0.84, 0.89, 0.97), Color(0.98, 0.99, 1.0)],
            "terrain": "fjord",
            "landmark": "stave_church",
        },
        {
            "id": "sweden",
            "name": "Sweden",
            "critters_name": "Moose and blackbirds",
            "intro": "Moose and blackbirds are hiding behind the spruces and the woodpiles!",
            "won": "The moose and the blackbirds are giggling in the forest.",
            "lost": "The Swedish animals won this snowball fight.",
            "critters":
            [
                {
                    "kind": "beast",
                    "look":
                    {
                        "fur": Color(0.45, 0.3, 0.2),
                        "shade": Color(0.35, 0.22, 0.15),
                        "belly": Color(0.6, 0.45, 0.32),
                        "muzzle": Color(0.55, 0.4, 0.3),
                        "ears": "horse",
                        "snout": "long",
                        "features": ["antlers"],
                    },
                },
                {
                    "kind": "bird",
                    "look":
                    {
                        "body": Color(0.14, 0.14, 0.17),
                        "belly": Color(0.22, 0.22, 0.26),
                        "wing": Color(0.1, 0.1, 0.12),
                        "beak": Color(1.0, 0.6, 0.1),
                        "eye_ring": Color(1.0, 0.75, 0.15),
                        "tail": "long",
                    },
                },
            ],
            "covers": [K.SPRUCE, K.WOODPILE, K.SPRUCE, K.WOODPILE, K.SPRUCE, K.DRIFT],
            "sky": [Color(0.45, 0.62, 0.9), Color(0.92, 0.94, 1.0)],
            "ground": [Color(0.85, 0.9, 0.97), Color(0.98, 0.99, 1.0)],
            "terrain": "forest",
            "landmark": "red_cottages",
        },
        {
            "id": "finland",
            "name": "Finland",
            "critters_name": "Bears and swans",
            "intro": "Brown bears and whooper swans are hiding under the northern lights!",
            "won": "The bears and the swans are giggling by the sauna.",
            "lost": "The Finnish animals won this snowball fight.",
            "critters":
            [
                {
                    "kind": "beast",
                    "look":
                    {
                        "fur": _BEAR_BROWN,
                        "shade": _BEAR_BROWN.darkened(0.2),
                        "belly": Color(0.7, 0.52, 0.36),
                        "muzzle": Color(0.82, 0.66, 0.5),
                        "ears": "round",
                        "features": [],
                    },
                },
                {
                    "kind": "bird",
                    "look":
                    {
                        "body": Color(0.98, 0.98, 1.0),
                        "belly": Color(1, 1, 1),
                        "wing": Color(0.88, 0.9, 0.95),
                        "beak": Color(1.0, 0.85, 0.2),
                        "beak_shape": "swan",
                        "long_neck": true,
                    },
                },
            ],
            "covers": [K.SPRUCE, K.DRIFT, K.SPRUCE, K.DRIFT, K.WOODPILE, K.SPRUCE],
            "sky": [Color(0.06, 0.1, 0.24), Color(0.2, 0.3, 0.5)],
            "ground": [Color(0.62, 0.7, 0.86), Color(0.8, 0.86, 0.96)],
            "terrain": "forest",
            "night": true,
            "landmark": "sauna",
        },
        {
            "id": "estonia",
            "name": "Estonia",
            "critters_name": "Wolves and swallows",
            "intro": "Grey wolves and barn swallows are hiding below the towers of Tallinn!",
            "won": "The wolves and the swallows are giggling in the old town.",
            "lost": "The Estonian animals won this snowball fight.",
            "critters":
            [
                {
                    "kind": "beast",
                    "look":
                    {
                        "fur": Color(0.6, 0.62, 0.66),
                        "shade": Color(0.46, 0.48, 0.54),
                        "belly": Color(0.86, 0.86, 0.84),
                        "muzzle": Color(0.92, 0.9, 0.86),
                        "ears": "pointy",
                        "snout": "pointy",
                        "features": [],
                    },
                },
                {
                    "kind": "bird",
                    "look":
                    {
                        "body": Color(0.15, 0.22, 0.45),
                        "belly": Color(0.98, 0.95, 0.9),
                        "wing": Color(0.1, 0.15, 0.32),
                        "head": Color(0.15, 0.22, 0.45),
                        "bib": Color(0.78, 0.3, 0.2),
                        "beak": Color(0.2, 0.2, 0.22),
                        "tail": "fork",
                    },
                },
            ],
            "covers": [K.DRIFT, K.WOODPILE, K.BOULDER, K.SPRUCE, K.DRIFT, K.SNOWMAN],
            "sky": [Color(0.48, 0.6, 0.82), Color(0.9, 0.92, 0.98)],
            "ground": [Color(0.86, 0.9, 0.96), Color(0.98, 0.99, 1.0)],
            "terrain": "city",
            "landmark": "tallinn",
        },
        {
            "id": "latvia",
            "name": "Latvia",
            "critters_name": "Wagtails and ladybirds",
            "intro": "White wagtails and giant ladybirds are hiding in the snow of Riga!",
            "won": "The wagtails and the ladybirds are giggling in Riga.",
            "lost": "The Latvian animals won this snowball fight.",
            "critters":
            [
                {
                    "kind": "bird",
                    "look":
                    {
                        "body": Color(0.62, 0.64, 0.68),
                        "belly": Color(0.98, 0.98, 1.0),
                        "wing": Color(0.3, 0.3, 0.34),
                        "head": Color(0.98, 0.98, 1.0),
                        "cap": Color(0.12, 0.12, 0.14),
                        "bib": Color(0.12, 0.12, 0.14),
                        "beak": Color(0.15, 0.15, 0.17),
                        "tail": "long",
                    },
                },
                {"kind": "ladybird", "look": {}},
            ],
            "covers": [K.SNOWMAN, K.DRIFT, K.WOODPILE, K.DRIFT, K.SNOWMAN, K.DRIFT],
            "sky": [Color(0.5, 0.62, 0.84), Color(0.9, 0.93, 0.99)],
            "ground": [Color(0.86, 0.9, 0.96), Color(0.98, 0.99, 1.0)],
            "terrain": "city",
            "landmark": "riga",
        },
        {
            "id": "lithuania",
            "name": "Lithuania",
            "critters_name": "Storks and iron wolves",
            "intro":
            "White storks and the Iron Wolf of the Vilnius legend are hiding by the castle hill!",
            "won": "The storks and the iron wolves are giggling below Gediminas' Tower.",
            "lost": "The Lithuanian animals won this snowball fight.",
            "critters":
            [
                {
                    "kind": "bird",
                    "look":
                    {
                        "body": Color(0.98, 0.98, 1.0),
                        "belly": Color(1, 1, 1),
                        "wing": Color(0.15, 0.15, 0.17),
                        "beak": Color(0.92, 0.25, 0.15),
                        "beak_shape": "long",
                        "long_neck": true,
                    },
                },
                {
                    "kind": "beast",
                    "look":
                    {
                        "fur": Color(0.68, 0.72, 0.8),
                        "shade": Color(0.5, 0.54, 0.62),
                        "belly": Color(0.82, 0.85, 0.9),
                        "muzzle": Color(0.86, 0.88, 0.92),
                        "ears": "pointy",
                        "snout": "pointy",
                        "features": ["metal"],
                    },
                },
            ],
            "covers": [K.SPRUCE, K.DRIFT, K.SPRUCE, K.WOODPILE, K.BOULDER, K.DRIFT],
            "sky": [Color(0.55, 0.62, 0.82), Color(0.94, 0.9, 0.92)],
            "ground": [Color(0.86, 0.89, 0.96), Color(0.98, 0.99, 1.0)],
            "terrain": "forest",
            "landmark": "gediminas",
        },
        {
            "id": "belarus",
            "name": "Belarus",
            "critters_name": "Bison and beavers",
            "intro": "European bison and beavers are hiding in the snowy forest of Belarus!",
            "won": "The bison and the beavers are giggling by Mir Castle.",
            "lost": "The Belarusian animals won this snowball fight.",
            "critters":
            [
                {
                    "kind": "beast",
                    "look":
                    {
                        "fur": Color(0.42, 0.28, 0.18),
                        "shade": Color(0.3, 0.2, 0.13),
                        "belly": Color(0.5, 0.36, 0.24),
                        "muzzle": Color(0.3, 0.22, 0.17),
                        "nose": Color(0.12, 0.1, 0.1),
                        "ears": "tiny",
                        "features": ["hump", "horns", "beard"],
                    },
                },
                {
                    "kind": "beast",
                    "look":
                    {
                        "fur": Color(0.58, 0.4, 0.26),
                        "shade": Color(0.45, 0.3, 0.2),
                        "belly": Color(0.72, 0.56, 0.4),
                        "muzzle": Color(0.76, 0.6, 0.46),
                        "ears": "tiny",
                        "features": ["teeth"],
                    },
                },
            ],
            "covers": [K.WOODPILE, K.SPRUCE, K.DRIFT, K.SPRUCE, K.WOODPILE, K.SPRUCE],
            "sky": [Color(0.5, 0.6, 0.8), Color(0.9, 0.92, 0.97)],
            "ground": [Color(0.86, 0.9, 0.96), Color(0.98, 0.99, 1.0)],
            "terrain": "forest",
            "landmark": "mir_castle",
        },
        {
            "id": "ukraine",
            "name": "Ukraine",
            "critters_name": "Nightingales and marmots",
            "intro": "Nightingales and steppe marmots are hiding below the golden domes of Kyiv!",
            "won": "The nightingales and the marmots are giggling by the golden domes.",
            "lost": "The Ukrainian animals won this snowball fight.",
            "critters":
            [
                {
                    "kind": "bird",
                    "look":
                    {
                        "body": Color(0.56, 0.42, 0.3),
                        "belly": Color(0.92, 0.86, 0.76),
                        "wing": Color(0.48, 0.34, 0.24),
                        "head": Color(0.58, 0.44, 0.32),
                        "beak": Color(0.45, 0.35, 0.3),
                        "eye_ring": Color(0.96, 0.92, 0.84),
                        "tail": "long",
                    },
                },
                {
                    "kind": "beast",
                    "look":
                    {
                        "fur": Color(0.78, 0.62, 0.4),
                        "shade": Color(0.64, 0.48, 0.3),
                        "belly": Color(0.9, 0.8, 0.62),
                        "muzzle": Color(0.92, 0.84, 0.7),
                        "ears": "tiny",
                        "features": ["teeth"],
                    },
                },
            ],
            "covers": [K.DRIFT, K.WOODPILE, K.SPRUCE, K.SNOWMAN, K.DRIFT, K.WOODPILE],
            "sky": [Color(0.42, 0.6, 0.9), Color(0.9, 0.93, 1.0)],
            "ground": [Color(0.86, 0.9, 0.97), Color(0.98, 0.99, 1.0)],
            "terrain": "city",
            "landmark": "st_michael",
        },
        {
            "id": "russia",
            "name": "Russia",
            "critters_name": "Tigers and eagles",
            "intro": "Amur tigers and the double-headed eagles are hiding below the onion domes!",
            "won": "The tigers and the eagles are giggling on the Red Square.",
            "lost": "The Russian animals won this snowball fight.",
            "critters":
            [
                {
                    "kind": "beast",
                    "look":
                    {
                        "fur": Color(0.96, 0.58, 0.2),
                        "shade": Color(0.84, 0.46, 0.14),
                        "belly": Color(1.0, 0.97, 0.92),
                        "muzzle": Color(1.0, 0.97, 0.92),
                        "marks": Color(0.15, 0.12, 0.12),
                        "ears": "round",
                        "features": ["stripes", "cheeks"],
                    },
                },
                {
                    "kind": "bird",
                    "look":
                    {
                        "body": Color(0.86, 0.66, 0.24),
                        "belly": Color(0.98, 0.86, 0.5),
                        "wing": Color(0.72, 0.5, 0.16),
                        "head": Color(0.9, 0.72, 0.3),
                        "beak": Color(1.0, 0.85, 0.3),
                        "beak_shape": "hooked",
                        "two_heads": true,
                    },
                },
            ],
            "covers": [K.DRIFT, K.SNOWMAN, K.BOULDER, K.SPRUCE, K.DRIFT, K.SNOWMAN],
            "sky": [Color(0.42, 0.5, 0.78), Color(0.98, 0.84, 0.8)],
            "ground": [Color(0.88, 0.88, 0.95), Color(0.99, 0.98, 1.0)],
            "terrain": "city",
            "landmark": "st_basil",
        },
        {
            "id": "kazakhstan",
            "name": "Kazakhstan",
            "critters_name": "Leopards, eagles and horses",
            "intro":
            (
                "Snow leopards, golden eagles and steppe horses are hiding in the snowy "
                + "steppe of Astana!"
            ),
            "won":
            (
                "The snow leopards, the eagles and the horses are giggling below Bayterek. "
                + "You made it to Astana!"
            ),
            "lost": "The animals of Kazakhstan won this snowball fight.",
            "critters":
            [
                {
                    "kind": "beast",
                    "look":
                    {
                        "fur": Color(0.88, 0.88, 0.84),
                        "shade": Color(0.72, 0.72, 0.7),
                        "belly": Color(0.98, 0.98, 0.96),
                        "muzzle": Color(0.98, 0.98, 0.96),
                        "marks": Color(0.3, 0.3, 0.32),
                        "ears": "round",
                        "features": ["rosettes"],
                    },
                },
                {
                    "kind": "bird",
                    "look":
                    {
                        "body": Color(0.4, 0.27, 0.17),
                        "belly": Color(0.52, 0.36, 0.22),
                        "wing": Color(0.3, 0.2, 0.13),
                        "head": Color(0.42, 0.29, 0.18),
                        "nape": Color(0.88, 0.68, 0.3),
                        "beak": Color(0.98, 0.82, 0.3),
                        "beak_shape": "hooked",
                    },
                },
                {
                    "kind": "beast",
                    "look":
                    {
                        "fur": Color(0.62, 0.36, 0.2),
                        "shade": Color(0.5, 0.28, 0.15),
                        "belly": Color(0.76, 0.52, 0.34),
                        "muzzle": Color(0.82, 0.66, 0.54),
                        "ears": "horse",
                        "snout": "long",
                        "features": ["mane_stripe"],
                    },
                },
            ],
            "covers": [K.YURT, K.DRIFT, K.YURT, K.DRIFT, K.SNOWMAN, K.YURT],
            "sky": [Color(0.3, 0.55, 0.92), Color(0.86, 0.93, 1.0)],
            "ground": [Color(0.88, 0.92, 0.98), Color(0.99, 0.995, 1.0)],
            "terrain": "steppe",
            "landmark": "astana",
        },
        {
            "id": "zurich",
            "name": "Zurich",
            "critters_name": "Foxes",
            "intro": "Back home in Zurich, the city foxes are hiding in the snow by the lake!",
            "won": "The foxes of Zurich are giggling by the lake. Welcome home!",
            "lost": "The foxes of Zurich won this snowball fight.",
            "critters":
            [
                {
                    "kind": "beast",
                    "look":
                    {
                        "fur": Color(0.9, 0.45, 0.16),
                        "shade": Color(0.76, 0.34, 0.1),
                        "belly": Color(1.0, 0.96, 0.92),
                        "muzzle": Color(1.0, 0.97, 0.94),
                        "ear_inner": Color(0.25, 0.18, 0.15),
                        "ears": "pointy",
                        "snout": "pointy",
                        "features": [],
                    },
                },
                {
                    "kind": "beast",
                    "look":
                    {
                        "fur": Color(0.82, 0.38, 0.14),
                        "shade": Color(0.66, 0.28, 0.1),
                        "belly": Color(0.98, 0.94, 0.88),
                        "muzzle": Color(0.98, 0.95, 0.9),
                        "ear_inner": Color(0.25, 0.18, 0.15),
                        "ears": "pointy",
                        "snout": "pointy",
                        "features": ["cheeks"],
                    },
                },
            ],
            "covers": [K.SPRUCE, K.DRIFT, K.BOULDER, K.SNOWMAN, K.WOODPILE, K.SPRUCE],
            "sky": [Color(0.4, 0.62, 0.92), Color(0.9, 0.94, 1.0)],
            "ground": [Color(0.86, 0.9, 0.97), Color(0.98, 0.99, 1.0)],
            "terrain": "alps",
            "landmark": "grossmuenster",
        },
    ]


static func by_id(id: String) -> Dictionary:
    for country in all():
        if country["id"] == id:
            return country
    push_error("Unknown country: %s" % id)
    return {}


static func ids() -> Array[String]:
    var result: Array[String] = []
    for country in all():
        result.append(country["id"])
    return result


## Make a critter of the country from its description.
static func make_critter(description: Dictionary) -> Critter:
    match description["kind"]:
        "bird":
            return Bird.new(description["look"])
        "ladybird":
            return Ladybird.new()
    return Beast.new(description["look"])
