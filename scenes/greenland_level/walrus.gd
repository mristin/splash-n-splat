class_name Walrus
extends Critter

## A round, friendly walrus with a bobble hat, one of the critters of Greenland.

const _SKIN := Color(0.7, 0.5, 0.4)
const _SKIN_SHADE := Color(0.56, 0.38, 0.3)
const _MUZZLE := Color(0.86, 0.68, 0.56)
const _TUSK := Color(1.0, 0.98, 0.9)
const _CHEEK := Color(1.0, 0.6, 0.6, 0.6)
const _HATS := [
    [Color(0.85, 0.2, 0.25), Color(1, 1, 1)],
    [Color(0.2, 0.45, 0.85), Color(1.0, 0.85, 0.3)],
    [Color(0.95, 0.6, 0.15), Color(1, 1, 1)],
]

var _hat: Array = _HATS[randi() % _HATS.size()]


func _draw_body(wind_up: bool, throwing: bool) -> void:
    # Body
    draw_colored_polygon(Draw2D.ellipse(Vector2(4, -80), 90, 92), _SKIN_SHADE)
    draw_colored_polygon(Draw2D.ellipse(Vector2(0, -84), 86, 88), _SKIN)
    for wrinkle in [-60, -40]:
        draw_arc(Vector2(0, wrinkle), 50, 0.5, PI - 0.5, 12, _SKIN_SHADE, 3)

    # Left flipper, resting
    draw_colored_polygon(Draw2D.ellipse(Vector2(-74, -60), 18, 34), _SKIN_SHADE)

    # Right flipper: rests, rises with a snowball during the wind-up, throws forward.
    var flipper := Vector2(74, -60)
    if wind_up:
        flipper = flipper.lerp(Vector2(64, -250), _wind_up_progress())
    elif throwing:
        flipper = Vector2(34, -170)
    draw_line(Vector2(56, -100), flipper, _SKIN, 30)
    draw_colored_polygon(Draw2D.ellipse(flipper, 20, 26), _SKIN_SHADE)
    if wind_up:
        _draw_snowball(flipper + Vector2(-2, -32))

    _draw_head(HEAD, wind_up or throwing)


func _draw_head(head: Vector2, determined: bool) -> void:
    draw_colored_polygon(Draw2D.ellipse(head + Vector2(3, 3), 60, 54), _SKIN_SHADE)
    draw_colored_polygon(Draw2D.ellipse(head, 58, 52), _SKIN)

    # The bobble hat
    draw_colored_polygon(Draw2D.dome(head + Vector2(0, -30), 50, 40), _hat[0])
    draw_rect(Rect2(head + Vector2(-52, -36), Vector2(104, 14)), _hat[1])
    for i in range(-2, 3):
        draw_circle(head + Vector2(i * 18, -50), 4, _hat[1])
    draw_circle(head + Vector2(0, -74), 13, _hat[1])

    # Tusks, then the whiskery muzzle over their roots
    for x in [-14, 14]:
        draw_colored_polygon(
            PackedVector2Array(
                [head + Vector2(x - 6, 22), head + Vector2(x + 6, 22), head + Vector2(x * 1.1, 72)]
            ),
            _TUSK
        )
    for x in [-17, 17]:
        draw_circle(head + Vector2(x, 16), 21, _MUZZLE)
        for k in range(5):
            draw_circle(head + Vector2(x + (k % 3 - 1) * 8, 10 + (k / 3) * 9), 1.8, _SKIN_SHADE)
    draw_colored_polygon(Draw2D.ellipse(head + Vector2(0, 0), 10, 7), INK)
    draw_circle(head + Vector2(-42, 8), 9, _CHEEK)
    draw_circle(head + Vector2(42, 8), 9, _CHEEK)

    _draw_eyes(head, 22, determined)
