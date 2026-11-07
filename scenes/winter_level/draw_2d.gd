class_name Draw2D
extends Object

## The small drawing helpers which Godot lacks.


static func ellipse(
    center: Vector2, rx: float, ry: float, segments: int = 28
) -> PackedVector2Array:
    var points := PackedVector2Array()
    for i in range(segments):
        var a := i * TAU / segments
        points.append(center + Vector2(cos(a) * rx, sin(a) * ry))
    return points


## Make a lumpy blob around the center, deterministic for the seed.
static func blob(
    center: Vector2, radius: float, lumpiness: float, seed_value: int, segments: int = 20
) -> PackedVector2Array:
    var points := PackedVector2Array()
    for i in range(segments):
        var a := i * TAU / segments
        var noise := sin(a * 3 + seed_value * 1.7) * 0.5 + sin(a * 5 + seed_value * 0.9) * 0.5
        var r := radius * (1.0 + lumpiness * noise)
        points.append(center + Vector2(cos(a) * r, sin(a) * r))
    return points


## Make a dome: the upper half of an ellipse, closed along its base.
static func dome(
    base_center: Vector2, rx: float, ry: float, segments: int = 20
) -> PackedVector2Array:
    var points := PackedVector2Array()
    for i in range(segments + 1):
        var a := PI + i * PI / segments
        points.append(base_center + Vector2(cos(a) * rx, sin(a) * ry))
    return points


static func in_ellipse(point: Vector2, center: Vector2, rx: float, ry: float) -> bool:
    var d := point - center
    return d.x * d.x / (rx * rx) + d.y * d.y / (ry * ry) <= 1.0
