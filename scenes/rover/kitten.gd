class_name Kitten
extends Rover

## A cute kitten with big, shiny eyes which strolls along the snow in the front.
##
## The kitten does not play along: the players must not hit it. When hit, it
## sits down and cries for a moment (the game takes some of the players'
## energy), and then runs off the screen.

const CRY_SECONDS := 1.6

const _CREAM := Color(1.0, 0.95, 0.85)
const _PINK := Color(1.0, 0.62, 0.7)
const _TEAR := Color(0.45, 0.75, 1.0)

var fur := Color(1.0, 0.72, 0.38)
var stripes := Color(0.9, 0.5, 0.2)


func _init() -> void:
    motion = Motion.WALK
    _hit_speed = 0.0


func _update(_delta: float) -> void:
    # NOTE (mristin):
    # The kitten sits and cries first; then it runs off quickly.
    if state == State.HIT and _state_time >= CRY_SECONDS:
        _hit_speed = 3.0


func is_crying() -> bool:
    return state == State.HIT and _state_time < CRY_SECONDS


func center_global_position() -> Vector2:
    if is_crying():
        return from.lerp(to, progress)
    return super.center_global_position()


func _hit_ellipse() -> Rect2:
    return Rect2(Vector2(10, -80), Vector2(80, 76))


func _draw_body() -> void:
    var crying := is_crying()
    var step := sin(_time * 7.0)

    # The tail, curled up
    var tail_tip := Vector2(-110, -120 + 10 * sin(_time * 3.0))
    draw_polyline(
        PackedVector2Array([Vector2(-60, -50), Vector2(-96, -60), tail_tip]), fur, 16, true
    )
    draw_circle(tail_tip, 8, stripes)

    # Legs (tucked in while sitting)
    if not crying:
        for x in [-44.0, -24.0, 28.0, 48.0]:
            var lift: float = maxf(0.0, step * (1.0 if x < 0 else -1.0)) * 8.0
            draw_rect(Rect2(x - 8, -34 - lift, 16, 34), fur)
            draw_circle(Vector2(x, -2 - lift), 9, _CREAM)

    # Body with stripes
    var body_y := -50.0 if not crying else -40.0
    draw_colored_polygon(Draw2D.ellipse(Vector2(0, body_y), 70, 38, 28), fur)
    for x in [-30.0, -8.0, 14.0]:
        draw_line(Vector2(x, body_y - 36), Vector2(x + 6, body_y - 18), stripes, 6)
    draw_colored_polygon(Draw2D.ellipse(Vector2(20, body_y + 14), 36, 18, 20), _CREAM)

    # Head, ears
    var head := Vector2(52, -110 if not crying else -96)
    for side in [-1.0, 1.0]:
        var ear := head + Vector2(side * 34, -34)
        draw_colored_polygon(
            PackedVector2Array(
                [ear + Vector2(-18, 14), ear + Vector2(side * 6, -26), ear + Vector2(18, 14)]
            ),
            fur
        )
        draw_colored_polygon(
            PackedVector2Array(
                [ear + Vector2(-9, 10), ear + Vector2(side * 4, -12), ear + Vector2(9, 10)]
            ),
            _PINK
        )
    draw_colored_polygon(Draw2D.ellipse(head, 56, 48, 32), fur)
    draw_line(head + Vector2(-8, -44), head + Vector2(-4, -30), stripes, 5)
    draw_line(head + Vector2(8, -44), head + Vector2(4, -30), stripes, 5)
    draw_colored_polygon(Draw2D.ellipse(head + Vector2(0, 20), 30, 20, 20), _CREAM)

    # The big eyes, the nose, the mouth and the whiskers
    var left := head + Vector2(-22, -6)
    var right := head + Vector2(22, -6)
    if crying:
        # NOTE (mristin):
        # Squeezed eyes, a wobbly mouth and big tears which roll down.
        for eye in [left, right]:
            draw_arc(eye + Vector2(0, 4), 12, PI * 1.15, PI * 1.85, 10, INK, 4)
            var fall := fmod(_state_time * 1.6, 1.0)
            draw_circle(eye + Vector2(0, 14 + 34 * fall), 6, Color(_TEAR, 1.0 - fall))
            draw_circle(eye + Vector2(0, 12), 5, _TEAR)
        draw_arc(head + Vector2(0, 34), 10, PI * 1.1, PI * 1.9, 10, INK, 3)
    else:
        _draw_eye(left, 15, true)
        _draw_eye(right, 15, true)
        draw_arc(head + Vector2(-7, 22), 7, 0.2, PI - 0.2, 8, INK, 3)
        draw_arc(head + Vector2(7, 22), 7, 0.2, PI - 0.2, 8, INK, 3)
    draw_colored_polygon(
        PackedVector2Array([head + Vector2(-7, 12), head + Vector2(7, 12), head + Vector2(0, 19)]),
        _PINK
    )
    for side in [-1.0, 1.0]:
        for k in [-1.0, 1.0]:
            draw_line(
                head + Vector2(side * 24, 18),
                head + Vector2(side * 62, 14 + k * 8),
                Color(INK, 0.6),
                2
            )
