class_name Seal
extends Critter

## A spotted seal with big eyes, one of the critters of Greenland. It balances
## its snowball on the nose before it flicks it at the player.

const _FUR := Color(0.7, 0.74, 0.8)
const _FUR_SHADE := Color(0.55, 0.6, 0.68)
const _BELLY := Color(0.88, 0.9, 0.94)
const _SPOT := Color(0.48, 0.52, 0.6)
const _CHEEK := Color(1.0, 0.7, 0.75, 0.6)

const _NOSE_TIP := Vector2(0, -238)


func _throw_point() -> Vector2:
    return _NOSE_TIP + Vector2(0, -22)


func _draw_body(wind_up: bool, throwing: bool) -> void:
    # A slim, tall body, which leans back a little when it balances the snowball.
    draw_colored_polygon(Draw2D.ellipse(Vector2(4, -84), 74, 94), _FUR_SHADE)
    draw_colored_polygon(Draw2D.ellipse(Vector2(0, -88), 70, 90), _FUR)
    draw_colored_polygon(Draw2D.ellipse(Vector2(0, -66), 40, 58), _BELLY)
    for spot_point in [Vector2(-46, -110), Vector2(48, -70), Vector2(-40, -40), Vector2(36, -130)]:
        draw_colored_polygon(Draw2D.blob(spot_point, 7, 0.3, int(spot_point.x)), _SPOT)

    # Front flippers; they clap during the throw.
    var lift := 18.0 if throwing else 0.0
    for side in [-1.0, 1.0]:
        var root := Vector2(side * 56, -100)
        var tip := Vector2(side * 76, -46 - lift)
        draw_line(root, tip, _FUR_SHADE, 22)
        draw_circle(tip, 12, _FUR_SHADE)

    _draw_head(HEAD, wind_up or throwing)

    if wind_up:
        # NOTE (mristin):
        # The snowball rolls up from the belly onto the nose.
        var at := Vector2(0, -70).lerp(_throw_point(), _wind_up_progress())
        _draw_snowball(at)


func _draw_head(head: Vector2, determined: bool) -> void:
    draw_colored_polygon(Draw2D.ellipse(head + Vector2(3, 3), 56, 54), _FUR_SHADE)
    draw_colored_polygon(Draw2D.ellipse(head, 54, 52), _FUR)
    draw_colored_polygon(Draw2D.ellipse(head + Vector2(0, 20), 26, 18), _BELLY)
    draw_colored_polygon(Draw2D.ellipse(head + Vector2(0, 10), 9, 6), INK)
    draw_arc(head + Vector2(-6, 24), 6, 0.2, PI - 0.2, 8, INK, 2.5)
    draw_arc(head + Vector2(6, 24), 6, 0.2, PI - 0.2, 8, INK, 2.5)
    for side in [-1.0, 1.0]:
        for k in range(3):
            var root := head + Vector2(side * 18, 18 + k * 5)
            draw_line(root, root + Vector2(side * 34, -6 + k * 7), Color(0.3, 0.32, 0.38), 1.6)
    draw_circle(head + Vector2(-36, 10), 8, _CHEEK)
    draw_circle(head + Vector2(36, 10), 8, _CHEEK)

    if state == State.DIZZY:
        _draw_eyes(head, 20, determined)
        return

    # Big, shiny eyes
    for x in [-20, 20]:
        draw_circle(head + Vector2(x, -10), 12, INK)
        draw_circle(head + Vector2(x + 4, -15), 4.5, Color.WHITE)
        draw_circle(head + Vector2(x - 3, -5), 2, Color.WHITE)
    if determined:
        draw_line(head + Vector2(-32, -30), head + Vector2(-12, -25), INK, 3)
        draw_line(head + Vector2(32, -30), head + Vector2(12, -25), INK, 3)
