class_name ProjectileStyle
extends RefCounted

## How a thrown projectile looks and splashes.
##
## The winter world throws snowballs; a future summer world can throw water
## balloons by giving its theme another style.

var name: String
var body: Color
var shade: Color
var highlight: Color
var splat: Color

## How lumpy the outline is: 0 for a perfect circle.
var lumpiness: float


func _init(
    style_name: String,
    body_color: Color,
    shade_color: Color,
    highlight_color: Color,
    splat_color: Color,
    lumpiness_value: float
) -> void:
    name = style_name
    body = body_color
    shade = shade_color
    highlight = highlight_color
    splat = splat_color
    lumpiness = lumpiness_value


static func snowball() -> ProjectileStyle:
    return ProjectileStyle.new(
        "snowball",
        Color(0.98, 0.99, 1.0),
        Color(0.72, 0.82, 0.95),
        Color(1, 1, 1),
        Color(0.97, 0.99, 1.0, 0.95),
        0.08
    )


## Not used yet: the projectile of the summer world.
static func water_balloon() -> ProjectileStyle:
    return ProjectileStyle.new(
        "water balloon",
        Color(0.35, 0.7, 1.0),
        Color(0.2, 0.45, 0.85),
        Color(0.85, 0.95, 1.0),
        Color(0.55, 0.8, 1.0, 0.7),
        0.0
    )
