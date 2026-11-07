class_name WinterLevel
extends Level

## The first world: the North Pole, with the hiding places of the polar bears.


func _init() -> void:
    theme = WinterTheme.new()
    display_name = "The North Pole"
    critters_name = "Polar bears"
    intro = (
        "Polar bears are hiding behind the snowdrifts at the North Pole! Hit them "
        + "with a snowball before they throw theirs at you."
    )
    won_message = "All the polar bears are giggling in the snow."
    lost_title = "Brrr, snowed in!"
    lost_message = "The polar bears won this snowball fight."


func make_critter(_random: RandomNumberGenerator) -> Critter:
    return PolarBear.new()
