class_name WinterBackdrop
extends Node2D

## Draw the static winter landscape behind the bears: the sky, the sun, the far
## mountains, the hills with the pine trees and the snowfield.
##
## Everything is drawn once with polygons; Godot caches the draw commands, so
## the backdrop costs nearly nothing per frame.

const _WIDTH := 1920.0

var theme: LevelTheme = WinterTheme.new()


func _draw() -> void:
    _draw_gradient(0, theme.ground_top - 40, theme.sky_top, theme.sky_horizon)
    _draw_sun(Vector2(1560, 170))
    _draw_clouds()

    _draw_mountains(
        [
            0,
            380,
            180,
            300,
            420,
            260,
            700,
            340,
            950,
            230,
            1250,
            330,
            1500,
            210,
            1760,
            320,
            1920,
            260
        ],
        WinterTheme.MOUNTAIN_FAR,
        0.55
    )
    _draw_mountains(
        [0, 440, 260, 330, 520, 420, 820, 300, 1100, 430, 1380, 310, 1650, 420, 1920, 350],
        WinterTheme.MOUNTAIN,
        0.6
    )
    _draw_hills()

    for tree in [
        [90, 560, 0.9],
        [170, 548, 0.7],
        [700, 545, 0.6],
        [1290, 548, 0.65],
        [1360, 556, 0.8],
        [1840, 560, 0.95],
        [1780, 548, 0.7]
    ]:
        draw_pine(Vector2(tree[0], tree[1]), tree[2])

    _draw_gradient(theme.ground_top, theme.ground_bottom, theme.ground_far, theme.ground_near)

    # NOTE (mristin):
    # Soft shadows give the flat snowfield some relief.
    for shadow in [[640, 680, 260, 18], [1300, 820, 340, 22], [420, 1000, 380, 26]]:
        draw_colored_polygon(
            Draw2D.ellipse(Vector2(shadow[0], shadow[1]), shadow[2], shadow[3]),
            Color(WinterTheme.SHADOW, 0.25)
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
        draw_circle(center, 40 + i * 22, Color(1, 0.97, 0.8, 0.06))
    draw_circle(center, 52, Color(1, 0.96, 0.78))


func _draw_clouds() -> void:
    for cloud in [[320, 150, 1.0], [820, 90, 0.7], [1200, 200, 0.85]]:
        var x: float = cloud[0]
        var y: float = cloud[1]
        var s: float = cloud[2]
        var color := Color(1, 1, 1, 0.8)
        draw_circle(Vector2(x, y), 46 * s, color)
        draw_circle(Vector2(x + 50 * s, y + 10 * s), 38 * s, color)
        draw_circle(Vector2(x - 50 * s, y + 12 * s), 34 * s, color)
        draw_circle(Vector2(x + 95 * s, y + 18 * s), 26 * s, color)


func _draw_mountains(ridge: Array, color: Color, cap_fraction: float) -> void:
    var points := PackedVector2Array()
    for i in range(ridge.size() / 2):
        points.append(Vector2(ridge[2 * i], ridge[2 * i + 1]))
    points.append(Vector2(_WIDTH, theme.ground_top))
    points.append(Vector2(0, theme.ground_top))
    draw_colored_polygon(points, color)

    # NOTE (mristin):
    # A snow cap on every peak, a fraction of the way down to the valleys.
    for i in range(1, ridge.size() / 2 - 1):
        var peak := Vector2(ridge[2 * i], ridge[2 * i + 1])
        var left := Vector2(ridge[2 * i - 2], ridge[2 * i - 1])
        var right := Vector2(ridge[2 * i + 2], ridge[2 * i + 3])
        if peak.y > left.y or peak.y > right.y:
            continue

        var depth := minf(left.y, right.y) - peak.y
        var a := peak.lerp(left, cap_fraction * 0.5)
        var b := peak.lerp(right, cap_fraction * 0.5)
        var mid := Vector2(peak.x, peak.y + depth * cap_fraction * 0.6)
        draw_colored_polygon(
            PackedVector2Array(
                [peak, b, (b + mid) * 0.5 + Vector2(0, 8), mid, (a + mid) * 0.5 + Vector2(0, 10), a]
            ),
            Color(0.97, 0.98, 1.0)
        )


func _draw_hills() -> void:
    var points := PackedVector2Array()
    for x in range(0, 1921, 40):
        var y := theme.ground_top - 38 - 22 * sin(x * 0.004) - 12 * sin(x * 0.011 + 1.3)
        points.append(Vector2(x, y))
    points.append(Vector2(_WIDTH, theme.ground_top + 1))
    points.append(Vector2(0, theme.ground_top + 1))

    var colors := PackedColorArray()
    for point in points:
        colors.append(
            Color(0.9, 0.94, 0.99) if point.y < theme.ground_top - 20 else theme.ground_far
        )
    draw_polygon(points, colors)


## Draw a snowy pine tree standing at the given base point.
func draw_pine(base_point: Vector2, scale_factor: float) -> void:
    var s := scale_factor
    draw_rect(Rect2(base_point.x - 8 * s, base_point.y - 30 * s, 16 * s, 30 * s), WinterTheme.BARK)
    for i in range(4):
        var bottom := base_point.y - 20 * s - i * 42 * s
        var half := (70 - i * 14) * s
        var top := bottom - 70 * s
        draw_colored_polygon(
            PackedVector2Array(
                [
                    Vector2(base_point.x - half, bottom),
                    Vector2(base_point.x + half, bottom),
                    Vector2(base_point.x, top)
                ]
            ),
            WinterTheme.PINE if i % 2 == 0 else WinterTheme.PINE_DARK
        )
        draw_colored_polygon(
            PackedVector2Array(
                [
                    Vector2(base_point.x - half * 0.6, bottom - 22 * s),
                    Vector2(base_point.x + half * 0.6, bottom - 22 * s),
                    Vector2(base_point.x + half * 0.3, bottom - 14 * s),
                    Vector2(base_point.x, bottom - 18 * s),
                    Vector2(base_point.x - half * 0.4, bottom - 12 * s)
                ]
            ),
            Color(0.96, 0.98, 1.0)
        )
