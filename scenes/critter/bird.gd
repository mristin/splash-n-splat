class_name Bird
extends Critter

## A round, fluffed-up winter bird, drawn from a [member look]: a gyrfalcon, a
## puffin, a blackbird, a swan, a swallow, a wagtail, a stork or an eagle.
##
## The look is a dictionary with the colors ([code]body[/code], [code]belly[/code],
## [code]wing[/code], [code]head[/code], [code]beak[/code], and optionally
## [code]cap[/code], [code]mask[/code], [code]bib[/code], [code]eye_ring[/code]
## and [code]nape[/code]), the [code]beak_shape[/code] ("short", "hooked",
## "puffin", "long" or "swan"), the [code]tail[/code] ("short", "fork" or
## "long"), and the flags [code]long_neck[/code] and [code]two_heads[/code].
## It throws with its wing.

var look: Dictionary = {}


func _init(look_value: Dictionary = {}) -> void:
    look = look_value


func _color(key: String, fallback: Color) -> Color:
    return look.get(key, fallback)


func _draw_body(wind_up: bool, throwing: bool) -> void:
    var body := _color("body", Color(0.5, 0.5, 0.55))
    var belly := _color("belly", body.lightened(0.5))
    var wing := _color("wing", body.darkened(0.2))

    # The tail, behind the body
    match look.get("tail", "short"):
        "fork":
            for side in [-1.0, 1.0]:
                draw_colored_polygon(
                    PackedVector2Array(
                        [Vector2(side * 10, -30), Vector2(side * 70, 20), Vector2(side * 30, -10)]
                    ),
                    wing
                )
        "long":
            draw_colored_polygon(
                PackedVector2Array(
                    [Vector2(-18, -30), Vector2(18, -30), Vector2(10, 30), Vector2(-10, 30)]
                ),
                wing
            )
        _:
            draw_colored_polygon(
                PackedVector2Array([Vector2(-30, -20), Vector2(30, -20), Vector2(0, 10)]), wing
            )

    # Body
    draw_colored_polygon(Draw2D.ellipse(Vector2(4, -78), 76, 90), body.darkened(0.15))
    draw_colored_polygon(Draw2D.ellipse(Vector2(0, -82), 72, 86), body)
    draw_colored_polygon(Draw2D.ellipse(Vector2(0, -66), 44, 58), belly)
    if look.has("bib"):
        draw_colored_polygon(Draw2D.ellipse(Vector2(0, -132), 40, 22), _color("bib", INK))

    # Left wing, folded
    draw_colored_polygon(Draw2D.ellipse(Vector2(-62, -84), 22, 52), wing)

    # Right wing: rises with a snowball during the wind-up, swings forward at the throw.
    var tip := Vector2(70, -60)
    if wind_up:
        tip = tip.lerp(Vector2(62, -250), _wind_up_progress())
    elif throwing:
        tip = Vector2(30, -170)
    var root := Vector2(56, -110)
    var along := (tip - root).normalized()
    var across := along.orthogonal() * 20.0
    draw_colored_polygon(PackedVector2Array([root + across, tip + along * 10, root - across]), wing)
    draw_circle(tip, 16, wing)
    if wind_up:
        _draw_snowball(tip + Vector2(-2, -24))

    # The neck and the head(s)
    if look.get("long_neck", false):
        draw_line(Vector2(0, -150), HEAD + Vector2(0, 20), body, 34)
    if look.get("two_heads", false):
        for side in [-1.0, 1.0]:
            var head := HEAD + Vector2(side * 42, -6)
            draw_line(Vector2(side * 16, -150), head, body, 26)
            _draw_head(head, 40.0, side, wind_up or throwing)
            _draw_crown(head + Vector2(0, -44))
    else:
        _draw_head(HEAD, 50.0, 1.0, wind_up or throwing)


func _draw_head(head: Vector2, radius: float, facing: float, determined: bool) -> void:
    var color := _color("head", _color("body", Color(0.5, 0.5, 0.55)))
    draw_circle(head + Vector2(2, 2), radius + 2, color.darkened(0.15))
    draw_circle(head, radius, color)
    if look.has("nape"):
        draw_colored_polygon(
            Draw2D.dome(head + Vector2(0, -radius * 0.3), radius, radius * 0.7),
            _color("nape", color)
        )
    if look.has("cap"):
        draw_colored_polygon(
            Draw2D.dome(head + Vector2(0, -radius * 0.25), radius * 0.96, radius * 0.75),
            _color("cap", INK)
        )
    if look.has("mask"):
        draw_colored_polygon(
            Draw2D.ellipse(head + Vector2(0, -6), radius * 0.85, radius * 0.4), _color("mask", INK)
        )

    var scale_factor := radius / 50.0
    if look.has("eye_ring") and state != State.DIZZY:
        for x in [-18, 18]:
            draw_circle(
                head + Vector2(x, -12) * scale_factor,
                11 * scale_factor,
                _color("eye_ring", Color.YELLOW)
            )
    _draw_eyes_scaled(head, scale_factor, determined)
    _draw_beak(head + Vector2(0, 6) * scale_factor, scale_factor, facing)


func _draw_eyes_scaled(head: Vector2, s: float, determined: bool) -> void:
    if s >= 0.99:
        _draw_eyes(head, 18, determined)
        return
    for x in [-14.0, 14.0]:
        draw_circle(head + Vector2(x, -10), 6, INK)
        draw_circle(head + Vector2(x + 2, -12), 2, Color.WHITE)


func _draw_beak(at: Vector2, s: float, facing: float) -> void:
    var beak := _color("beak", Color(1.0, 0.75, 0.2))
    match look.get("beak_shape", "short"):
        "hooked":
            draw_colored_polygon(
                PackedVector2Array(
                    [
                        at + Vector2(-12, 0) * s,
                        at + Vector2(12, 0) * s,
                        at + Vector2(4, 26) * s,
                        at + Vector2(-2, 30) * s
                    ]
                ),
                beak
            )
            draw_circle(at + Vector2(0, 4) * s, 4 * s, beak.darkened(0.3))
        "puffin":
            var stripes := [Color(0.35, 0.38, 0.45), Color(1.0, 0.85, 0.2), Color(0.95, 0.4, 0.15)]
            for i in range(3):
                var w := (26 - i * 6) * s
                draw_colored_polygon(
                    PackedVector2Array(
                        [
                            at + Vector2(-w, i * 9 * s),
                            at + Vector2(w, i * 9 * s),
                            at + Vector2(0, (40 - i * 4) * s)
                        ]
                    ),
                    stripes[i]
                )
        "long":
            # NOTE (mristin):
            # The long beak of the stork points down and to the side.
            draw_colored_polygon(
                PackedVector2Array(
                    [
                        at + Vector2(-8, -2) * s,
                        at + Vector2(8, -2) * s,
                        at + Vector2(facing * 70, 70) * s
                    ]
                ),
                beak
            )
        "swan":
            draw_colored_polygon(
                PackedVector2Array(
                    [
                        at + Vector2(-14, -4) * s,
                        at + Vector2(14, -4) * s,
                        at + Vector2(8, 34) * s,
                        at + Vector2(-8, 34) * s
                    ]
                ),
                beak
            )
            draw_colored_polygon(
                PackedVector2Array(
                    [at + Vector2(-14, -4) * s, at + Vector2(14, -4) * s, at + Vector2(0, 12) * s]
                ),
                INK
            )
        _:
            draw_colored_polygon(
                PackedVector2Array(
                    [at + Vector2(-10, 0) * s, at + Vector2(10, 0) * s, at + Vector2(0, 20) * s]
                ),
                beak
            )


func _draw_crown(at: Vector2) -> void:
    var gold := Color(1.0, 0.8, 0.25)
    draw_colored_polygon(
        PackedVector2Array(
            [
                at + Vector2(-16, 6),
                at + Vector2(-16, -10),
                at + Vector2(-8, -2),
                at + Vector2(0, -14),
                at + Vector2(8, -2),
                at + Vector2(16, -10),
                at + Vector2(16, 6)
            ]
        ),
        gold
    )
    draw_circle(at + Vector2(0, -16), 3.5, Color(0.9, 0.2, 0.25))
