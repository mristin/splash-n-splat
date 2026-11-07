class_name LevelTheme
extends RefCounted

## The look of a world: its palette and its projectiles.
##
## The winter world is the first one; a future summer world (water balloons on
## a beach) only needs another theme.

var sky_top: Color
var sky_horizon: Color
var ground_near: Color
var ground_far: Color

## The y-coordinate where the ground meets the hills.
var ground_top: float = 560.0
var ground_bottom: float = 1080.0

var projectile: ProjectileStyle


## The ground color at the given height, exactly as the backdrop draws it.
func ground_at(y: float) -> Color:
    var t := clampf((y - ground_top) / (ground_bottom - ground_top), 0.0, 1.0)
    return ground_far.lerp(ground_near, t)
