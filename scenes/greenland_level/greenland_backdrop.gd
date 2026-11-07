class_name GreenlandBackdrop
extends Node2D

## Draw the static fjord behind the critters: the sky, the cliffs with their
## snow caps, a colorful village on the shore, the icebergs on the horizon and
## the sea.
##
## The sea below the horizon band is a plain gradient: the covers and the orcas
## paint it over themselves in its exact colors (see [method LevelTheme.ground_at]).

const _WIDTH := 1920.0

var theme: LevelTheme = GreenlandTheme.new()


func _draw() -> void:
    var horizon := theme.ground_top
    _draw_gradient(0, horizon, theme.sky_top, theme.sky_horizon)
    _draw_sun(Vector2(1380, 200))
    _draw_clouds()

    _draw_cliffs(
        [
            0,
            300,
            160,
            250,
            380,
            330,
            560,
            230,
            760,
            320,
            980,
            260,
            1180,
            340,
            1420,
            240,
            1700,
            310,
            1920,
            270
        ],
        GreenlandTheme.CLIFF_FAR,
        0.5
    )
    _draw_cliffs(
        [1000, horizon, 1180, 420, 1320, 360, 1480, 430, 1640, 350, 1800, 400, 1920, 380],
        GreenlandTheme.CLIFF,
        0.45
    )
    _draw_village()

    _draw_gradient(horizon, theme.ground_bottom, theme.ground_far, theme.ground_near)

    for berg in [[640, 0.55], [880, 0.35], [1560, 0.45]]:
        _draw_far_iceberg(Vector2(berg[0], horizon + 6), berg[1])

    # NOTE (mristin):
    # Glints of light only in the band near the horizon, which nothing paints over.
    for glint in [
        [120, 606, 60],
        [420, 600, 40],
        [760, 612, 70],
        [1080, 604, 50],
        [1300, 616, 60],
        [1720, 608, 70]
    ]:
        draw_line(
            Vector2(glint[0] - glint[2] * 0.5, glint[1]),
            Vector2(glint[0] + glint[2] * 0.5, glint[1]),
            Color(1, 1, 1, 0.45),
            3
        )


func _draw_gradient(top: float, bottom: float, top_color: Color, bottom_color: Color) -> void:
    draw_polygon(
        PackedVector2Array(
            [Vector2(0, top), Vector2(_WIDTH, top), Vector2(_WIDTH, bottom), Vector2(0, bottom)]
        ),
        PackedColorArray([top_color, top_color, bottom_color, bottom_color])
    )


func _draw_sun(center: Vector2) -> void:
    for i in range(5, 0, -1):
        draw_circle(center, 40 + i * 22, Color(1, 0.97, 0.85, 0.06))
    draw_circle(center, 48, Color(1, 0.97, 0.84))


func _draw_clouds() -> void:
    for cloud in [[260, 120, 0.9], [900, 160, 0.75], [1700, 110, 0.8]]:
        var x: float = cloud[0]
        var y: float = cloud[1]
        var s: float = cloud[2]
        var color := Color(1, 1, 1, 0.8)
        draw_circle(Vector2(x, y), 46 * s, color)
        draw_circle(Vector2(x + 50 * s, y + 10 * s), 38 * s, color)
        draw_circle(Vector2(x - 50 * s, y + 12 * s), 34 * s, color)
        draw_circle(Vector2(x + 95 * s, y + 18 * s), 26 * s, color)


## Draw a ridge of cliffs down to the horizon, with a snow cap on every peak.
func _draw_cliffs(ridge: Array, color: Color, cap_fraction: float) -> void:
    var points := PackedVector2Array()
    for i in range(ridge.size() / 2):
        points.append(Vector2(ridge[2 * i], ridge[2 * i + 1]))
    points.append(Vector2(ridge[ridge.size() - 2], theme.ground_top))
    points.append(Vector2(ridge[0], theme.ground_top))
    draw_colored_polygon(points, color)

    for i in range(1, ridge.size() / 2 - 1):
        var peak := Vector2(ridge[2 * i], ridge[2 * i + 1])
        var left := Vector2(ridge[2 * i - 2], ridge[2 * i - 1])
        var right := Vector2(ridge[2 * i + 2], ridge[2 * i + 3])
        if peak.y > left.y or peak.y > right.y:
            continue
        var a := peak.lerp(left, cap_fraction * 0.5)
        var b := peak.lerp(right, cap_fraction * 0.5)
        var mid := Vector2(peak.x, peak.y + (minf(left.y, right.y) - peak.y) * cap_fraction * 0.6)
        draw_colored_polygon(
            PackedVector2Array(
                [peak, b, (b + mid) * 0.5 + Vector2(0, 8), mid, (a + mid) * 0.5 + Vector2(0, 10), a]
            ),
            Color(0.97, 0.98, 1.0)
        )


## Draw the snowy shore on the left with its colorful wooden houses.
func _draw_village() -> void:
    var horizon := theme.ground_top
    var shore := PackedVector2Array()
    for x in range(0, 601, 30):
        shore.append(Vector2(x, horizon - 70 + 40 * pow(x / 600.0, 2) - 12 * sin(x * 0.02)))
    shore.append(Vector2(640, horizon))
    shore.append(Vector2(0, horizon))
    draw_colored_polygon(shore, Color(0.95, 0.97, 1.0))

    var i := 0
    for house in [[60, 0.9], [150, 1.0], [250, 0.85], [345, 0.95], [450, 0.8]]:
        var x: float = house[0]
        var s: float = house[1]
        var base := Vector2(x, horizon - 58 + 40 * pow(x / 600.0, 2) - 12 * sin(x * 0.02) + 6)
        var wall: Color = GreenlandTheme.HOUSES[i % GreenlandTheme.HOUSES.size()]
        var w := 56.0 * s
        var h := 38.0 * s
        draw_rect(Rect2(base + Vector2(-w * 0.5, -h), Vector2(w, h)), wall)
        draw_colored_polygon(
            PackedVector2Array(
                [
                    base + Vector2(-w * 0.6, -h),
                    base + Vector2(0, -h - 26 * s),
                    base + Vector2(w * 0.6, -h)
                ]
            ),
            Color(0.25, 0.27, 0.33)
        )
        draw_colored_polygon(
            PackedVector2Array(
                [
                    base + Vector2(-w * 0.6, -h),
                    base + Vector2(0, -h - 26 * s),
                    base + Vector2(-w * 0.1, -h - 21 * s),
                    base + Vector2(-w * 0.5, -h + 2)
                ]
            ),
            Color(0.97, 0.98, 1.0)
        )
        for k in [-1, 1]:
            draw_rect(
                Rect2(base + Vector2(k * w * 0.22 - 6 * s, -h * 0.7), Vector2(12 * s, 12 * s)),
                Color(1.0, 0.95, 0.75)
            )
        i += 1


func _draw_far_iceberg(base: Vector2, s: float) -> void:
    var outline := PackedVector2Array(
        [
            base + Vector2(-120, 0) * s,
            base + Vector2(-90, -70) * s,
            base + Vector2(-30, -60) * s,
            base + Vector2(10, -120) * s,
            base + Vector2(60, -60) * s,
            base + Vector2(110, -40) * s,
            base + Vector2(130, 0) * s
        ]
    )
    draw_colored_polygon(outline, GreenlandTheme.ICE_TOP)
    draw_colored_polygon(
        PackedVector2Array(
            [
                base + Vector2(10, -120) * s,
                base + Vector2(60, -60) * s,
                base + Vector2(110, -40) * s,
                base + Vector2(130, 0) * s,
                base + Vector2(30, 0) * s
            ]
        ),
        GreenlandTheme.ICE_SIDE
    )
    draw_colored_polygon(
        Draw2D.ellipse(base + Vector2(5, 4) * s, 130 * s, 9 * s),
        Color(GreenlandTheme.ICE_DEEP, 0.5)
    )
