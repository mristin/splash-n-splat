class_name Booster
extends Rover

## A balloon which carries a little crate with a booster across the sky; the
## players collect the booster by hitting the crate or the balloon.
##
## The boosters do not last forever (see [member LevelRules.boost_seconds]):
## rapid fire throws again and again while a fist is held, big snowballs are
## easier to aim with, and health gives back some energy at once.

enum Kind { RAPID_FIRE, BIG_SNOWBALLS, HEALTH }

const _POP_SECONDS := 0.5
const _STRING := Color(0.4, 0.4, 0.45)
const _CRATE := Color(0.72, 0.5, 0.3)
const _CRATE_DARK := Color(0.55, 0.36, 0.2)

var kind := Kind.HEALTH


func _init(kind_value: Kind = Kind.HEALTH) -> void:
    kind = kind_value
    motion = Motion.FLY
    _hit_speed = 0.0


func _update(_delta: float) -> void:
    if state == State.HIT and _state_time >= _POP_SECONDS:
        _finish()


func _hit_ellipse() -> Rect2:
    return Rect2(Vector2(0, -60), Vector2(70, 110))


## The color of the balloon of the kind.
static func color_of(booster_kind: Kind) -> Color:
    match booster_kind:
        Kind.RAPID_FIRE:
            return Color(1.0, 0.75, 0.15)
        Kind.BIG_SNOWBALLS:
            return Color(0.35, 0.65, 1.0)
    return Color(0.95, 0.3, 0.4)


## The name of the kind, e.g., for the message when collected.
static func name_of(booster_kind: Kind) -> String:
    match booster_kind:
        Kind.RAPID_FIRE:
            return "Rapid fire!"
        Kind.BIG_SNOWBALLS:
            return "Big snowballs!"
    return "Energy!"


## What the booster does, in a few words for the players, or empty if the name
## says it all.
static func hint_of(booster_kind: Kind) -> String:
    match booster_kind:
        Kind.BIG_SNOWBALLS:
            return "Easier to hit!"
    return ""


## Draw the icon of the kind on the canvas: a lightning bolt, a big snowball
## or a heart, in a circle of the given radius.
static func draw_icon(
    canvas: CanvasItem, booster_kind: Kind, center: Vector2, radius: float
) -> void:
    var s := radius / 30.0
    match booster_kind:
        Kind.RAPID_FIRE:
            var bolt := PackedVector2Array(
                [
                    Vector2(6, -26),
                    Vector2(-14, 4),
                    Vector2(0, 4),
                    Vector2(-6, 26),
                    Vector2(14, -6),
                    Vector2(0, -6),
                ]
            )
            for i in range(bolt.size()):
                bolt[i] = center + bolt[i] * s
            canvas.draw_colored_polygon(bolt, Color(1.0, 0.95, 0.4))
            canvas.draw_polyline(bolt + PackedVector2Array([bolt[0]]), Rover.INK, 2.0 * s, true)
        Kind.BIG_SNOWBALLS:
            # NOTE (mristin):
            # A plain white disc did not read as anything to the players, so we
            # draw a small snowball which grows into a big one, outlined in ink
            # so that the snow shows on the white background of the icon.
            var blue := Color(0.25, 0.6, 1.0)
            var small := center + Vector2(-18, 15) * s
            var big := center + Vector2(5, -3) * s
            _draw_icon_snowball(canvas, small, 6 * s, s, 1)
            _draw_icon_snowball(canvas, big, 17 * s, s, 2)
            # Short rays around the big snowball: it has grown.
            for angle in [-2.0, -1.2, -0.4, 0.4]:
                var ray := Vector2.RIGHT.rotated(angle)
                canvas.draw_line(big + ray * 21 * s, big + ray * 28 * s, blue, 3.5 * s)
        _:
            var heart := PackedVector2Array()
            for i in range(32):
                var t := i * TAU / 32
                var x := 16 * pow(sin(t), 3)
                var y := -(13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t))
                heart.append(center + Vector2(x, y) * s * 1.3)
            canvas.draw_colored_polygon(heart, Color(1.0, 0.35, 0.45))
            canvas.draw_circle(center + Vector2(-8, -8) * s, 4 * s, Color(1, 1, 1, 0.7))


## Draw a snowball of the icon: lumpy white snow with a bluish shade, a few
## dents and an ink outline, so that it reads as snow and not as a bubble.
static func _draw_icon_snowball(
    canvas: CanvasItem, at: Vector2, radius: float, s: float, seed_value: int
) -> void:
    var outline := Draw2D.blob(at, radius, 0.06, seed_value, 24)
    canvas.draw_colored_polygon(
        Draw2D.blob(at, radius, 0.06, seed_value, 24), Color(0.8, 0.87, 0.96)
    )
    canvas.draw_colored_polygon(
        Draw2D.blob(at + Vector2(-0.1, -0.1) * radius, radius * 0.82, 0.06, seed_value, 24),
        Color.WHITE
    )
    for dent in [Vector2(0.3, 0.2), Vector2(-0.25, 0.35), Vector2(0.05, -0.4)]:
        canvas.draw_circle(at + dent * radius, radius * 0.12, Color(0.75, 0.83, 0.94))
    outline.append(outline[0])
    canvas.draw_polyline(outline, Rover.INK, 2.0 * s, true)


func _draw_body() -> void:
    if state == State.HIT:
        # NOTE (mristin):
        # The balloon pops into a ring of sparkles.
        var t := clampf(_state_time / _POP_SECONDS, 0.0, 1.0)
        for i in range(10):
            var direction := Vector2.RIGHT.rotated(i * TAU / 10)
            _draw_star(
                Vector2(0, -60) + direction * (30 + 90 * t),
                12 * (1.0 - t) + 2,
                Color(color_of(kind), 1.0 - t)
            )
        return

    var balloon := color_of(kind)
    var sway := sin(_time * 1.7) * 6.0
    # The string, the balloon and its shine
    draw_line(Vector2(0, -30), Vector2(sway, -100), _STRING, 3)
    draw_colored_polygon(Draw2D.ellipse(Vector2(sway, -150), 46, 54, 28), balloon.darkened(0.15))
    draw_colored_polygon(Draw2D.ellipse(Vector2(sway - 3, -153), 43, 51, 28), balloon)
    draw_colored_polygon(Draw2D.ellipse(Vector2(sway - 18, -170), 9, 15, 12), Color(1, 1, 1, 0.55))
    draw_colored_polygon(
        PackedVector2Array([Vector2(sway - 6, -96), Vector2(sway + 6, -96), Vector2(sway, -104)]),
        balloon.darkened(0.15)
    )

    # The crate with the icon
    draw_rect(Rect2(-40, -32, 80, 64), _CRATE_DARK)
    draw_rect(Rect2(-36, -28, 72, 56), _CRATE)
    draw_circle(Vector2.ZERO, 26, Color(1, 1, 1, 0.85))
    draw_icon(self, kind, Vector2.ZERO, 22)
