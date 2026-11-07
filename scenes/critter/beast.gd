class_name Beast
extends Critter

## A furry critter, drawn from a [member look]: a fox, a wolf, a lion, a horse,
## a moose, a bear, a bison, a beaver, a tiger or a snow leopard.
##
## The look is a dictionary with the colors ([code]fur[/code], [code]shade[/code],
## [code]belly[/code], [code]muzzle[/code], [code]nose[/code], [code]ear_inner[/code],
## and [code]marks[/code] for the stripes and the spots), the shape of the
## [code]ears[/code] ("pointy", "round", "horse" or "tiny"), the [code]snout[/code]
## ("short", "pointy" or "long") and a list of [code]features[/code]: "mane",
## "antlers" (a moose), "branched_antlers" (a reindeer), "horns", "beard", "ruff",
## "hump", "stripes", "rosettes", "teeth", "cheeks", "mane_stripe" and "metal".

const _SCARVES := [
    [Color(0.9, 0.25, 0.25), Color(1.0, 0.95, 0.95)],
    [Color(0.2, 0.55, 0.95), Color(1.0, 0.85, 0.3)],
    [Color(0.25, 0.7, 0.4), Color(1, 1, 1)],
    [Color(0.6, 0.3, 0.8), Color(1.0, 0.9, 0.4)],
]
const _CHEEK := Color(1.0, 0.6, 0.65, 0.55)

var look: Dictionary = {}

var _scarf: Array = _SCARVES[randi() % _SCARVES.size()]


func _init(look_value: Dictionary = {}) -> void:
    look = look_value


func _color(key: String, fallback: Color) -> Color:
    return look.get(key, fallback)


func _has(feature: String) -> bool:
    return feature in look.get("features", [])


func _draw_body(wind_up: bool, throwing: bool) -> void:
    var fur := _color("fur", Color(0.6, 0.45, 0.3))
    var shade := _color("shade", fur.darkened(0.2))
    var belly := _color("belly", fur.lightened(0.35))

    if _has("mane"):
        # NOTE (mristin):
        # The mane of the lion goes behind the head and the shoulders.
        var mane := _color("mane", fur.darkened(0.35))
        _draw_fluffy(HEAD + Vector2(0, 10), 92, mane.darkened(0.15), 16, 0)
        _draw_fluffy(HEAD + Vector2(0, 6), 84, mane, 16, 1)

    # Body
    if _has("hump"):
        draw_colored_polygon(Draw2D.ellipse(Vector2(0, -130), 100, 56), shade)
    draw_colored_polygon(Draw2D.ellipse(Vector2(4, -82), 86, 94), shade)
    draw_colored_polygon(Draw2D.ellipse(Vector2(0, -86), 82, 90), fur)
    draw_colored_polygon(Draw2D.ellipse(Vector2(0, -60), 46, 52), belly)
    _draw_marks(Vector2(0, -86), 80, 88)
    if _has("metal"):
        _draw_metal()

    # Scarf
    draw_colored_polygon(
        PackedVector2Array(
            [Vector2(-58, -140), Vector2(58, -140), Vector2(54, -118), Vector2(-54, -118)]
        ),
        _scarf[0]
    )
    for i in range(-2, 3):
        draw_line(Vector2(i * 22 - 4, -139), Vector2(i * 22 + 4, -119), _scarf[1], 5)

    # Left paw, resting
    draw_circle(Vector2(-68, -92), 22, shade)
    draw_circle(Vector2(-68, -95), 20, fur)

    # Right paw: rests, rises with a snowball during the wind-up, throws forward.
    var paw := Vector2(68, -95)
    if wind_up:
        paw = paw.lerp(Vector2(62, -250), _wind_up_progress())
    elif throwing:
        paw = Vector2(30, -170)
    draw_line(Vector2(52, -120), paw, fur, 30)
    draw_circle(paw, 22, shade)
    draw_circle(paw + Vector2(0, -2), 20, fur)
    if wind_up:
        _draw_snowball(paw + Vector2(-2, -26))

    _draw_head(HEAD, wind_up or throwing)


func _draw_head(head: Vector2, determined: bool) -> void:
    var fur := _color("fur", Color(0.6, 0.45, 0.3))
    var shade := _color("shade", fur.darkened(0.2))
    var muzzle := _color("muzzle", fur.lightened(0.45))
    var nose := _color("nose", INK)
    var ear_inner := _color("ear_inner", Color(0.95, 0.78, 0.78))

    if _has("antlers"):
        _draw_antlers(head, _color("antler", Color(0.86, 0.76, 0.6)))
    if _has("branched_antlers"):
        _draw_branched_antlers(head, _color("antler", Color(0.9, 0.82, 0.66)))
    _draw_ears(head, fur, shade, ear_inner)
    if _has("horns"):
        for side in [-1.0, 1.0]:
            var root := head + Vector2(side * 48, -30)
            draw_polyline(
                PackedVector2Array(
                    [root, root + Vector2(side * 26, -6), root + Vector2(side * 30, -30)]
                ),
                Color(0.92, 0.88, 0.78),
                12,
                true
            )

    draw_colored_polygon(Draw2D.ellipse(head + Vector2(3, 3), 58, 54), shade)
    draw_colored_polygon(Draw2D.ellipse(head, 57, 53), fur)
    if _has("cheeks"):
        for side in [-1.0, 1.0]:
            _draw_fluffy(head + Vector2(side * 38, 16), 22, Color(0.98, 0.97, 0.94), 7, 3)
    _draw_head_marks(head)
    if _has("ruff"):
        # NOTE (mristin):
        # The light, shaggy collar of a reindeer, under the chin.
        _draw_fluffy(head + Vector2(0, 56), 30, _color("belly", Color.WHITE), 9, 4)
    if _has("beard"):
        _draw_fluffy(head + Vector2(0, 58), 26, shade.darkened(0.25), 8, 2)
    if _has("mane_stripe"):
        draw_line(head + Vector2(0, -54), head + Vector2(0, -20), Color(0.2, 0.16, 0.12), 10)
        draw_line(head + Vector2(-5, -54), head + Vector2(-5, -24), Color(0.96, 0.94, 0.88), 4)

    match look.get("snout", "short"):
        "long":
            draw_colored_polygon(Draw2D.ellipse(head + Vector2(0, 30), 32, 34), muzzle)
            draw_circle(head + Vector2(-12, 40), 5, nose)
            draw_circle(head + Vector2(12, 40), 5, nose)
            draw_arc(head + Vector2(0, 50), 10, 0.3, PI - 0.3, 8, INK, 2.5)
        "pointy":
            draw_colored_polygon(
                PackedVector2Array(
                    [head + Vector2(-26, 4), head + Vector2(26, 4), head + Vector2(0, 40)]
                ),
                muzzle
            )
            draw_colored_polygon(Draw2D.ellipse(head + Vector2(0, 30), 9, 7), nose)
            draw_arc(head + Vector2(-5, 40), 6, 0.2, PI - 0.2, 8, INK, 2.5)
            draw_arc(head + Vector2(5, 40), 6, 0.2, PI - 0.2, 8, INK, 2.5)
        _:
            draw_colored_polygon(Draw2D.ellipse(head + Vector2(0, 18), 28, 21), muzzle)
            draw_colored_polygon(Draw2D.ellipse(head + Vector2(0, 8), 11, 8), nose)
            draw_arc(head + Vector2(-6, 24), 7, 0.2, PI - 0.2, 8, INK, 2.5)
            draw_arc(head + Vector2(6, 24), 7, 0.2, PI - 0.2, 8, INK, 2.5)

    if _has("teeth"):
        draw_rect(Rect2(head + Vector2(-9, 30), Vector2(8, 14)), Color(1.0, 0.7, 0.25))
        draw_rect(Rect2(head + Vector2(1, 30), Vector2(8, 14)), Color(1.0, 0.7, 0.25))
    draw_circle(head + Vector2(-36, 12), 9, _CHEEK)
    draw_circle(head + Vector2(36, 12), 9, _CHEEK)

    if _has("metal") and state != State.DIZZY:
        # NOTE (mristin):
        # The Iron Wolf of the legend of Vilnius has friendly, glowing eyes.
        for x in [-20, 20]:
            draw_circle(head + Vector2(x, -12), 10, Color(1.0, 0.85, 0.3, 0.5))
    _draw_eyes(head, 20, determined)


func _draw_ears(head: Vector2, fur: Color, shade: Color, inner: Color) -> void:
    for side in [-1.0, 1.0]:
        match look.get("ears", "round"):
            "pointy":
                var base := head + Vector2(side * 30, -36)
                var tip := head + Vector2(side * 46, -86)
                draw_colored_polygon(
                    PackedVector2Array([base + Vector2(-20, 0), tip, base + Vector2(20, 0)]), fur
                )
                draw_colored_polygon(
                    PackedVector2Array(
                        [base + Vector2(-10, -4), tip.lerp(base, 0.3), base + Vector2(10, -4)]
                    ),
                    inner
                )
            "horse":
                var base := head + Vector2(side * 32, -42)
                draw_colored_polygon(Draw2D.ellipse(base + Vector2(side * 6, -12), 12, 18), shade)
                draw_colored_polygon(Draw2D.ellipse(base + Vector2(side * 6, -10), 6, 10), inner)
            "tiny":
                draw_circle(head + Vector2(side * 42, -38), 11, shade)
            _:
                draw_circle(head + Vector2(side * 40, -42), 18, shade)
                draw_circle(head + Vector2(side * 40, -42), 10, inner)


## Draw the stripes or the rosettes on the body.
func _draw_marks(center: Vector2, rx: float, ry: float) -> void:
    var marks := _color("marks", INK)
    if _has("stripes"):
        for i in range(-2, 3):
            var y := center.y + i * ry * 0.32
            for side in [-1.0, 1.0]:
                var edge: float = (
                    center.x + side * rx * sqrt(maxf(0.0, 1.0 - pow((y - center.y) / ry, 2)))
                )
                draw_colored_polygon(
                    PackedVector2Array(
                        [Vector2(edge, y - 8), Vector2(edge - side * 34, y), Vector2(edge, y + 8)]
                    ),
                    marks
                )
    if _has("rosettes"):
        for at in [
            Vector2(-46, -120),
            Vector2(40, -130),
            Vector2(-56, -64),
            Vector2(52, -70),
            Vector2(-30, -30)
        ]:
            draw_arc(at, 9, 0, TAU, 12, marks, 4)
    if _has("speckles"):
        for at in [Vector2(-46, -120), Vector2(40, -110), Vector2(-56, -64), Vector2(52, -60)]:
            draw_circle(at, 5, marks)


func _draw_head_marks(head: Vector2) -> void:
    var marks := _color("marks", INK)
    if _has("stripes"):
        for side in [-1.0, 1.0]:
            for k in range(2):
                var root := head + Vector2(side * 56, -4 + k * 16)
                draw_line(root, root + Vector2(-side * 20, -4), marks, 6)
        draw_line(head + Vector2(-8, -48), head + Vector2(0, -36), marks, 5)
        draw_line(head + Vector2(8, -48), head + Vector2(0, -36), marks, 5)
    if _has("rosettes"):
        for at in [Vector2(-34, -30), Vector2(30, -34), Vector2(0, -44)]:
            draw_circle(head + at, 5, marks)


## The palmate antlers of a moose, on both sides of the head.
func _draw_antlers(head: Vector2, color: Color) -> void:
    for side in [-1.0, 1.0]:
        # NOTE (mristin):
        # A short beam from the head into a broad, flat palm with tines on top.
        var root := head + Vector2(side * 32, -42)
        var palm := root + Vector2(side * 58, -26)
        draw_line(root, palm, color, 16)
        draw_colored_polygon(Draw2D.ellipse(palm + Vector2(side * 6, 0), 52, 20), color)
        for k in range(5):
            var tip := palm + Vector2(side * (k * 22 - 34), -14)
            draw_line(tip, tip + Vector2(side * 6, -20), color, 9)


## The branched antlers of a reindeer: a curved beam with tines on both sides.
func _draw_branched_antlers(head: Vector2, color: Color) -> void:
    for side in [-1.0, 1.0]:
        var beam := PackedVector2Array()
        for k in range(7):
            var t := k / 6.0
            beam.append(head + Vector2(side * (24 + 46 * sin(t * 1.6)), -40 - 110 * t))
        draw_polyline(beam, color, 10, true)
        for k in [2, 4, 6]:
            var root := beam[k]
            draw_line(root, root + Vector2(side * 26, -14), color, 7)
            draw_line(root, root + Vector2(-side * 14, -22), color, 6)
        # The brow tine, forward over the face
        draw_line(beam[1], beam[1] + Vector2(-side * 20, 6), color, 7)


## The rivets and the shine of the Iron Wolf.
func _draw_metal() -> void:
    for at in [Vector2(-50, -110), Vector2(50, -110), Vector2(-60, -60), Vector2(60, -60)]:
        draw_circle(at, 5, Color(0.42, 0.46, 0.54))
        draw_circle(at + Vector2(-1, -1), 2, Color(1, 1, 1, 0.8))
    draw_line(Vector2(-40, -150), Vector2(-62, -90), Color(1, 1, 1, 0.5), 6)


## A fluffy ring of circles, e.g., a mane or a cheek ruff.
func _draw_fluffy(
    center: Vector2, radius: float, color: Color, lumps: int, seed_value: int
) -> void:
    draw_colored_polygon(Draw2D.blob(center, radius * 0.85, 0.12, seed_value, 24), color)
    for i in range(lumps):
        var a := i * TAU / lumps
        draw_circle(center + Vector2(cos(a), sin(a)) * radius * 0.8, radius * 0.28, color)
