class_name GreenlandLevel
extends Level

## The second world, after a flight from the North Pole: a fjord in Greenland,
## where walruses and seals hide behind the ice floes, the icebergs and the
## rocks, and orcas leap out of the sea.


func _init() -> void:
    theme = GreenlandTheme.new()
    display_name = "Greenland"
    critters_name = "Walruses and seals"
    intro = (
        "Walruses and seals are hiding behind the ice floes! Hit them with a snowball "
        + "before they throw theirs at you, and watch out for the orcas!"
    )
    won_message = "The walruses and the seals are giggling on the ice."
    lost_title = "Brrr, snowed in!"
    lost_message = "The walruses and the seals won this snowball fight."
    orca_lanes = [
        [420.0, 1300.0, 830.0, 1.6],
        [1500.0, 620.0, 840.0, 1.6],
        [620.0, 1320.0, 640.0, 1.0],
    ]


func make_critter(random: RandomNumberGenerator) -> Critter:
    if random.randf() < 0.5:
        return Walrus.new()
    return Seal.new()
