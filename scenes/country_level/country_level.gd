class_name CountryLevel
extends Level

## A winter country on the way from Greenland to Astana, described in [Countries]:
## its national animals hide behind its covers, in front of its landmark.
##
## Set [member country] before adding the level to the tree.

var country: Dictionary = {}


func _ready() -> void:
    theme = CountryTheme.new(country)
    display_name = country["name"]
    critters_name = country["critters_name"]
    intro = country["intro"] + " Hit them with a snowball before they throw theirs at you."
    won_message = country["won"]
    lost_title = "Brrr, snowed in!"
    lost_message = country["lost"]

    var backdrop: CountryBackdrop = $Backdrop
    backdrop.theme = theme
    backdrop.country = country

    # NOTE (mristin):
    # The hiding places are the same in every country; only their covers differ.
    var covers: Array = country["covers"]
    var i := 0
    for child in $Spots.get_children():
        if child is CoverSpot:
            child.kind = covers[i]
            child.side = -1 if i == 2 else 1
            i += 1
    super._ready()


func make_critter(random: RandomNumberGenerator) -> Critter:
    var critters: Array = country["critters"]
    return Countries.make_critter(critters[random.randi() % critters.size()])
