class_name Ladybird
extends Critter

## A giant, friendly two-spot ladybird, the national insect of Latvia, with a
## woolly hat against the cold. It throws with one of its front legs.

const _RED := Color(0.9, 0.16, 0.14)
const _RED_SHADE := Color(0.7, 0.1, 0.1)
const _HAT := Color(0.95, 0.95, 0.98)


func _draw_body(wind_up: bool, throwing: bool) -> void:
    # The legs behind the shell
    for side in [-1.0, 1.0]:
        for k in range(3):
            var root := Vector2(side * 50, -40 - k * 34)
            draw_line(root, root + Vector2(side * 40, 14 - k * 4), INK, 7)

    # The shell, split in the middle, with one big spot on each half
    draw_colored_polygon(Draw2D.ellipse(Vector2(4, -84), 84, 92), _RED_SHADE)
    draw_colored_polygon(Draw2D.ellipse(Vector2(0, -88), 80, 88), _RED)
    draw_line(Vector2(0, -170), Vector2(0, -2), INK, 5)
    for side in [-1.0, 1.0]:
        draw_circle(Vector2(side * 40, -86), 20, INK)
    draw_colored_polygon(Draw2D.ellipse(Vector2(-34, -140), 18, 10), Color(1, 1, 1, 0.45))

    # The throwing leg
    var foot := Vector2(70, -110)
    if wind_up:
        foot = foot.lerp(Vector2(62, -250), _wind_up_progress())
    elif throwing:
        foot = Vector2(30, -170)
    draw_line(Vector2(46, -140), foot, INK, 9)
    draw_circle(foot, 9, INK)
    if wind_up:
        _draw_snowball(foot + Vector2(-2, -24))

    # The head with its antennae and a hat
    var head := HEAD + Vector2(0, 6)
    for side in [-1.0, 1.0]:
        var root := head + Vector2(side * 18, -40)
        var tip := root + Vector2(side * 26, -44)
        draw_line(root, tip, INK, 5)
        draw_circle(tip, 8, INK)
    draw_colored_polygon(Draw2D.ellipse(head, 52, 46), INK)
    for side in [-1.0, 1.0]:
        draw_circle(head + Vector2(side * 34, 4), 11, Color(0.98, 0.98, 0.95))
    draw_colored_polygon(Draw2D.dome(head + Vector2(0, -26), 40, 30), _HAT)
    draw_circle(head + Vector2(0, -58), 11, _RED)
    draw_arc(head + Vector2(0, 22), 12, 0.3, PI - 0.3, 10, Color(0.98, 0.98, 0.95), 3)

    # NOTE (mristin):
    # The eyes are light on the black head.
    if state == State.DIZZY:
        _draw_eyes(head, 18, false)
        return
    for x in [-18, 18]:
        draw_circle(head + Vector2(x, -8), 10, Color.WHITE)
        draw_circle(head + Vector2(x + 2, -6), 5, INK)
    if wind_up or throwing:
        draw_line(head + Vector2(-30, -22), head + Vector2(-10, -18), Color.WHITE, 3)
        draw_line(head + Vector2(30, -22), head + Vector2(10, -18), Color.WHITE, 3)
