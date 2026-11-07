class_name WinterTheme
extends LevelTheme

## The palette of the winter world.

const SHADOW := Color(0.72, 0.8, 0.92)
const DEEP_SHADOW := Color(0.6, 0.68, 0.84)
const MOUNTAIN := Color(0.62, 0.7, 0.86)
const MOUNTAIN_FAR := Color(0.74, 0.8, 0.92)
const PINE := Color(0.16, 0.42, 0.38)
const PINE_DARK := Color(0.11, 0.31, 0.3)
const BARK := Color(0.42, 0.3, 0.24)
const ROCK := Color(0.55, 0.6, 0.7)
const ROCK_DARK := Color(0.44, 0.48, 0.58)
const ICE := Color(0.8, 0.9, 1.0)
const SNOW := Color(0.97, 0.985, 1.0)


func _init() -> void:
    sky_top = Color(0.42, 0.68, 0.94)
    sky_horizon = Color(0.84, 0.92, 1.0)
    ground_near = Color(0.985, 0.99, 1.0)
    ground_far = Color(0.86, 0.91, 0.97)
    projectile = ProjectileStyle.snowball()
