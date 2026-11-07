class_name SnowyOwl
extends Thrower

## A round, cheeky snowy owl which flaps across the sky and drops snowballs at
## the player from its talons.

const _WHITE := Color(0.98, 0.98, 1.0)
const _SHADE := Color(0.82, 0.86, 0.94)
const _SPECKLE := Color(0.35, 0.38, 0.45)
const _YELLOW := Color(1.0, 0.82, 0.2)
const _BEAK := Color(0.3, 0.3, 0.35)


func _init() -> void:
    super._init()
    motion = Motion.FLY


func _hit_ellipse() -> Rect2:
    return Rect2(Vector2(0, 0), Vector2(110, 70))


func _throw_point() -> Vector2:
    return Vector2(10, 70)


func _bubble_point() -> Vector2:
    return Vector2(-70, -90)


func _draw_body() -> void:
    # NOTE (mristin):
    # The wings flap fast, and slower and lower while winding up.
    var flap := sin(_time * (8.0 if not is_winding_up() else 5.0))
    for side in [-1.0, 1.0]:
        var tip := Vector2(side * 130, -40 - 50 * flap)
        var wing := PackedVector2Array(
            [
                Vector2(side * 30, -20),
                tip,
                Vector2(side * 120, -10 - 30 * flap),
                Vector2(side * 96, 4 - 18 * flap),
                Vector2(side * 40, 20),
            ]
        )
        draw_colored_polygon(wing, _SHADE)
        for k in range(3):
            draw_circle(Vector2(side * (60 + k * 18), -14 - (12 + k * 10) * flap), 4, _SPECKLE)

    # Body and speckles
    draw_colored_polygon(Draw2D.ellipse(Vector2(0, 6), 62, 56, 28), _SHADE)
    draw_colored_polygon(Draw2D.ellipse(Vector2(0, 2), 58, 52, 28), _WHITE)
    for speckle in [
        Vector2(-24, 30), Vector2(0, 40), Vector2(24, 30), Vector2(-12, 18), Vector2(12, 18)
    ]:
        draw_colored_polygon(Draw2D.ellipse(speckle, 6, 3, 10), _SPECKLE)

    # Talons, with the snowball while winding up
    for x in [-14.0, 18.0]:
        draw_line(Vector2(x, 52), Vector2(x, 64), _BEAK, 4)
    _draw_held_snowball(_throw_point())

    # Face: the yellow eyes in their discs, and the beak
    for x in [-20.0, 20.0]:
        draw_circle(Vector2(x, -14), 17, _SHADE)
        draw_circle(Vector2(x, -14), 13, _YELLOW)
    _draw_eyes(Vector2(-20, -14), Vector2(20, -14), 8)
    draw_colored_polygon(
        PackedVector2Array([Vector2(-6, -2), Vector2(6, -2), Vector2(0, 10)]), _BEAK
    )
    # Ear tufts
    for side in [-1.0, 1.0]:
        draw_colored_polygon(
            PackedVector2Array(
                [Vector2(side * 30, -40), Vector2(side * 44, -62), Vector2(side * 46, -34)]
            ),
            _WHITE
        )
