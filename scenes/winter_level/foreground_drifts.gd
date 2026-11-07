class_name ForegroundDrifts
extends Node2D

## Draw the soft snowdrifts in the very front of the scene.


func _ready() -> void:
    z_index = 400


func _draw() -> void:
    var points := PackedVector2Array()
    for x in range(-20, 1941, 30):
        points.append(Vector2(x, 1010 - 26 * sin(x * 0.006 + 0.8) - 14 * sin(x * 0.017)))

    var shadow := PackedVector2Array()
    for point in points:
        shadow.append(point + Vector2(0, -10))
    shadow.append(Vector2(1940, 1090))
    shadow.append(Vector2(-20, 1090))
    draw_colored_polygon(shadow, Color(WinterTheme.SHADOW, 0.55))

    points.append(Vector2(1940, 1090))
    points.append(Vector2(-20, 1090))
    draw_colored_polygon(points, Color(0.99, 0.995, 1.0))

    for lump in [[150, 1000, 30], [700, 1010, 22], [1320, 1004, 26], [1800, 996, 34]]:
        draw_circle(Vector2(lump[0], lump[1]), lump[2], Color.WHITE)
