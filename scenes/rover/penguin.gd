class_name Penguin
extends Thrower

## A cheeky penguin in a red bobble hat, which waddles along the snow in the
## front and throws snowballs with its flipper.

const _BLACK := Color(0.16, 0.19, 0.27)
const _WHITE := Color(0.98, 0.98, 1.0)
const _ORANGE := Color(1.0, 0.6, 0.15)
const _HAT := Color(0.88, 0.2, 0.22)


func _init() -> void:
    super._init()
    motion = Motion.WALK


func _hit_ellipse() -> Rect2:
    return Rect2(Vector2(0, -110), Vector2(66, 112))


func _throw_point() -> Vector2:
    return Vector2(78, -170)


func _bubble_point() -> Vector2:
    return Vector2(-60, -280)


func _draw_body() -> void:
    var step := sin(_time * 7.0)
    # Feet
    for side in [-1.0, 1.0]:
        var lift: float = maxf(0.0, step * side) * 8.0
        draw_colored_polygon(
            Draw2D.ellipse(Vector2(side * 22 + 10, -6 - lift), 26, 10, 16), _ORANGE
        )

    # Body, belly
    draw_colored_polygon(Draw2D.ellipse(Vector2(0, -100), 64, 100, 32), _BLACK)
    draw_colored_polygon(Draw2D.ellipse(Vector2(14, -88), 44, 78, 28), _WHITE)

    # The back flipper, and the front flipper which is raised to throw
    draw_colored_polygon(
        PackedVector2Array([Vector2(-50, -130), Vector2(-86, -60), Vector2(-56, -70)]), _BLACK
    )
    if is_winding_up() or _since_throw < 0.25:
        draw_colored_polygon(
            PackedVector2Array([Vector2(36, -130), Vector2(80, -178), Vector2(52, -112)]), _BLACK
        )
        _draw_held_snowball(_throw_point())
    else:
        draw_colored_polygon(
            PackedVector2Array([Vector2(40, -130), Vector2(70, -62), Vector2(48, -76)]), _BLACK
        )

    # Head: the beak and the eyes, with rosy cheeks
    draw_colored_polygon(
        PackedVector2Array([Vector2(48, -168), Vector2(86, -156), Vector2(48, -146)]), _ORANGE
    )
    draw_circle(Vector2(44, -146), 9, Color(1.0, 0.6, 0.65, 0.7))
    _draw_eyes(Vector2(6, -172), Vector2(34, -172), 9)

    # The bobble hat
    draw_colored_polygon(Draw2D.dome(Vector2(4, -190), 54, 40), _HAT)
    draw_rect(Rect2(-52, -198, 112, 18), _WHITE)
    draw_circle(Vector2(-10, -238), 16, _WHITE)
