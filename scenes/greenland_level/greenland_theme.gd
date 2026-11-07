class_name GreenlandTheme
extends LevelTheme

## The palette of Greenland: a fjord with icebergs and a colorful village.
## The "ground" of this world is the sea.

const CLIFF := Color(0.42, 0.46, 0.54)
const CLIFF_FAR := Color(0.62, 0.68, 0.78)
const ICE_TOP := Color(0.96, 0.99, 1.0)
const ICE_SIDE := Color(0.74, 0.9, 0.97)
const ICE_DEEP := Color(0.42, 0.72, 0.88)
const SEA_SHADOW := Color(0.16, 0.36, 0.55)
const SEA_ROCK := Color(0.4, 0.42, 0.48)
const SEA_ROCK_DARK := Color(0.3, 0.32, 0.38)
const HOUSES := [
    Color(0.86, 0.2, 0.2),
    Color(0.98, 0.78, 0.25),
    Color(0.22, 0.48, 0.82),
    Color(0.25, 0.62, 0.45),
    Color(0.86, 0.2, 0.2),
]


func _init() -> void:
    sky_top = Color(0.46, 0.66, 0.9)
    sky_horizon = Color(0.9, 0.94, 0.99)
    ground_top = 590.0
    ground_far = Color(0.52, 0.72, 0.86)
    ground_near = Color(0.24, 0.5, 0.72)
    projectile = ProjectileStyle.snowball()
