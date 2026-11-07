class_name PolarBear
extends Critter

## A cheerful polar bear with a scarf, the critter of the North Pole.

const _FUR := Color(1.0, 0.985, 0.95)
const _FUR_SHADE := Color(0.86, 0.88, 0.93)
const _CHEEK := Color(1.0, 0.7, 0.75, 0.7)
const _SCARVES := [
    [Color(0.9, 0.25, 0.25), Color(1.0, 0.95, 0.95)],
    [Color(0.2, 0.55, 0.95), Color(1.0, 0.85, 0.3)],
    [Color(0.25, 0.7, 0.4), Color(1, 1, 1)],
]

var _scarf: Array = _SCARVES[randi() % _SCARVES.size()]


func _draw_body(wind_up: bool, throwing: bool) -> void:
    # Body
    draw_colored_polygon(Draw2D.ellipse(Vector2(4, -82), 86, 94), _FUR_SHADE)
    draw_colored_polygon(Draw2D.ellipse(Vector2(0, -86), 82, 90), _FUR)
    draw_colored_polygon(Draw2D.ellipse(Vector2(0, -60), 48, 52), Color.WHITE)

    # Scarf
    draw_colored_polygon(
        PackedVector2Array(
            [Vector2(-58, -140), Vector2(58, -140), Vector2(54, -118), Vector2(-54, -118)]
        ),
        _scarf[0]
    )
    for i in range(-2, 3):
        draw_line(Vector2(i * 22 - 4, -139), Vector2(i * 22 + 4, -119), _scarf[1], 5)
    draw_colored_polygon(
        PackedVector2Array(
            [Vector2(-40, -122), Vector2(-18, -122), Vector2(-24, -70), Vector2(-44, -74)]
        ),
        _scarf[0]
    )

    # Left paw, resting
    draw_circle(Vector2(-68, -92), 22, _FUR_SHADE)
    draw_circle(Vector2(-68, -95), 20, _FUR)

    # Right paw: rests, rises with a snowball during the wind-up, throws forward.
    var paw := Vector2(68, -95)
    if wind_up:
        paw = paw.lerp(Vector2(62, -250), _wind_up_progress())
    elif throwing:
        paw = Vector2(30, -170)
    draw_line(Vector2(52, -120), paw, _FUR, 30)
    draw_circle(paw, 22, _FUR_SHADE)
    draw_circle(paw + Vector2(0, -2), 20, _FUR)
    if wind_up:
        _draw_snowball(paw + Vector2(-2, -26))

    _draw_head(HEAD, wind_up or throwing)


func _draw_head(head: Vector2, determined: bool) -> void:
    for x in [-40, 40]:
        draw_circle(head + Vector2(x, -42), 18, _FUR_SHADE)
        draw_circle(head + Vector2(x, -42), 10, Color(0.95, 0.8, 0.82))
    draw_colored_polygon(Draw2D.ellipse(head + Vector2(3, 3), 58, 54), _FUR_SHADE)
    draw_colored_polygon(Draw2D.ellipse(head, 57, 53), _FUR)
    draw_colored_polygon(Draw2D.ellipse(head + Vector2(0, 18), 28, 21), Color.WHITE)
    draw_colored_polygon(Draw2D.ellipse(head + Vector2(0, 8), 11, 8), INK)
    draw_arc(head + Vector2(-6, 24), 7, 0.2, PI - 0.2, 8, INK, 2.5)
    draw_arc(head + Vector2(6, 24), 7, 0.2, PI - 0.2, 8, INK, 2.5)
    draw_circle(head + Vector2(-34, 12), 9, _CHEEK)
    draw_circle(head + Vector2(34, 12), 9, _CHEEK)

    if state == State.DIZZY:
        draw_colored_polygon(Draw2D.blob(head + Vector2(10, -6), 30, 0.25, 7), Color(1, 1, 1, 0.95))
    _draw_eyes(head, 20, determined)
