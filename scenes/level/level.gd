class_name Level
extends Node2D

## A world of the game: its backdrop, the hiding places of its critters, its
## theme and its texts.
##
## The hiding places are the [CoverSpot] nodes under [code]Spots[/code]; move them
## around and change their kind in the Godot editor. They lie at three depths
## (far, middle, near): the scale of a spot gives its depth, and the farther,
## the smaller the critters and the harder to hit.
##
## A new world provides its own scene with a script which extends this class.

var theme: LevelTheme = WinterTheme.new()
var spots: Array[CoverSpot] = []

## The name on the title and the level-finished screens.
var display_name := ""

## What the HUD counts, e.g., "Polar bears".
var critters_name := ""

## The story on the title screen, before the instructions.
var intro := ""

## The message when the level is won, and when it is lost.
var won_message := ""
var lost_title := ""
var lost_message := ""

## Where the feet of the walkers (the penguins, the kittens) touch the snow
## in the very front of the scene.
var walk_y := 1040.0

## The places where the orcas leap, as [from_x, to_x, water_y, size]; empty
## for a world without orcas.
var orca_lanes: Array = []


func _ready() -> void:
    for child in $Spots.get_children():
        if child is CoverSpot:
            child.theme = theme
            spots.append(child)


## Make a new critter for a hiding place.
func make_critter(_random: RandomNumberGenerator) -> Critter:
    return PolarBear.new()
