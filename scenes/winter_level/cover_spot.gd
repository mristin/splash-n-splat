class_name CoverSpot
extends Node2D

## A place where a critter hides, with the cover drawn in front of the critter.
##
## The spot's origin is on the ground, where the bear stands; its scale gives
## the depth (smaller is farther). Place the spots in the level scene in the
## editor. The bear is a child of [member bear_slot], drawn behind the cover.
##
## For the bears which rise from behind the cover, the cover also paints the
## ground below the origin in the exact color of the snowfield, so that the
## hidden bear does not show below the ground.

enum Kind {
    ## A snowdrift; the bear peeks up from behind it.
    DRIFT,
    ## An igloo; the bear peeks up from behind it.
    IGLOO,
    ## A big snowy boulder; the bear leans out sideways.
    BOULDER,
    ## A long snow wall; the bear rises and walks along it.
    RIDGE,
    ## A flat ice floe on the sea; the critter peeks up from behind it.
    FLOE,
    ## A small iceberg on the sea; the critter peeks up from behind it.
    ICEBERG,
    ## A dark rock in the sea; the critter leans out sideways.
    SEA_ROCK,
    ## A big snowy spruce; the critter leans out sideways.
    SPRUCE,
    ## A snowman; the critter leans out sideways.
    SNOWMAN,
    ## A pile of logs with snow on top; the critter peeks up from behind it.
    WOODPILE,
    ## A Kazakh yurt; the critter peeks up from behind it.
    YURT,
}

## The elliptical outlines of the covers (but the ridge), for the occlusion.
const _SHAPES := {
    Kind.DRIFT: [Vector2(0, 30), 170.0, 105.0],
    Kind.IGLOO: [Vector2(0, 20), 150.0, 150.0],
    Kind.BOULDER: [Vector2(0, -120), 135.0, 150.0],
    Kind.FLOE: [Vector2(0, 30), 185.0, 110.0],
    Kind.ICEBERG: [Vector2(0, 20), 150.0, 160.0],
    Kind.SEA_ROCK: [Vector2(0, -120), 135.0, 150.0],
    Kind.SPRUCE: [Vector2(0, -130), 120.0, 170.0],
    Kind.SNOWMAN: [Vector2(0, -130), 115.0, 160.0],
    Kind.WOODPILE: [Vector2(0, 30), 180.0, 105.0],
    Kind.YURT: [Vector2(0, 20), 160.0, 150.0],
}

@export var kind: Kind = Kind.DRIFT

## For the boulder, the side to lean out to (+1 right, -1 left); for the ridge,
## the direction of the walk.
@export var side: int = 1

## For the ridge, its length in local units.
@export var ridge_length: float = 520.0

var bear: Critter = null
var bear_slot: Node2D
var theme: LevelTheme = WinterTheme.new()


func _ready() -> void:
    z_index = int(position.y / 4.0)
    bear_slot = Node2D.new()
    bear_slot.name = "BearSlot"
    add_child(bear_slot)

    var front := CoverFront.new()
    front.name = "Front"
    front.spot = self
    front.z_index = 1
    add_child(front)


func is_free() -> bool:
    return bear == null or not is_instance_valid(bear)


## Whether the critter rises from below (true) or leans out sideways.
func rises() -> bool:
    return not kind in [Kind.BOULDER, Kind.SEA_ROCK, Kind.SPRUCE, Kind.SNOWMAN]


## Whether the local point is hidden behind the cover (or below the ground).
func occludes(local: Vector2) -> bool:
    if rises() and local.y > 0.0:
        return true

    if kind == Kind.RIDGE:
        return absf(local.x) < ridge_length * 0.5 + 40 and local.y > -95

    # NOTE (mristin):
    # The other covers are about elliptical: [center, rx, ry].
    var shape: Array = _SHAPES[kind]
    return Draw2D.in_ellipse(local, shape[0], shape[1], shape[2])
