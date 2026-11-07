class_name Orca
extends Node2D

## An orca which leaps slowly out of the sea in a high arc and dives back in.
##
## It never throws; it is a bonus target, which the player may hit while it is
## out of the water. The orca lives in global coordinates, with its water line
## at [member water_y]. Below the water line, the orca paints the sea over
## itself in the exact color of the backdrop, so that only the part out of the
## water shows.

signal finished(orca: Orca)

enum State { LEAPING, SPLASHED, GONE }

const _BLACK := Color(0.12, 0.14, 0.2)
const _WHITE := Color(0.97, 0.98, 1.0)
const _FOAM := Color(1, 1, 1, 0.85)

## The x-coordinates where the orca comes out and where it dives back in.
var from_x := 600.0
var to_x := 1200.0
var water_y := 800.0

## The height of the arc above the water line.
var height := 300.0

## The seconds from coming out to diving back in.
var leap_seconds := 6.5

## The size; 1 is about as long as a near polar bear is tall.
var size := 1.0

var theme: LevelTheme = null
var state := State.LEAPING

## The progress of the leap in [0, 1].
var progress := 0.0

var _state_time := 0.0
var _spin := 0.0


func _ready() -> void:
    z_index = int(water_y / 4.0)


func _process(delta: float) -> void:
    _state_time += delta
    # NOTE (mristin):
    # The orca also finishes its leap when hit, but spins happily.
    progress = clampf(progress + delta / leap_seconds, 0.0, 1.0)
    if state == State.SPLASHED:
        _spin += delta * 6.0
    if progress >= 1.0 and state != State.GONE:
        state = State.GONE
        finished.emit(self)
        queue_free()
    queue_redraw()


## The point of the arc at the progress t in [0, 1]; the arc starts and ends
## a bit below the water, so that the orca comes out and dives in completely.
func _arc(t: float) -> Vector2:
    var x := lerpf(from_x, to_x, t)
    var y := water_y + 80 * size - (height + 80 * size) * 4.0 * t * (1.0 - t)
    return Vector2(x, y)


func _heading() -> float:
    var a := _arc(maxf(0.0, progress - 0.01))
    var b := _arc(minf(1.0, progress + 0.01))
    return (b - a).angle()


func _transform() -> Transform2D:
    var flip := Vector2(1, 1) if to_x >= from_x else Vector2(1, -1)
    return Transform2D(_heading() + _spin, flip * size, 0.0, _arc(progress))


func is_targetable() -> bool:
    return state == State.LEAPING and _arc(progress).y < water_y - 40 * size


## Hit the orca: it spins happily and dives in. Return false if it can not be hit.
func hit() -> bool:
    if not is_targetable():
        return false
    state = State.SPLASHED
    return true


## Whether a global point hits the orca out of the water.
func hit_test(global_point: Vector2, tolerance: float = 45.0) -> bool:
    if not is_targetable() or global_point.y > water_y:
        return false
    var p := _transform().affine_inverse() * global_point
    var t := tolerance / maxf(0.1, size)
    return Draw2D.in_ellipse(p, Vector2(0, 0), 125 + t, 42 + t)


func center_global_position() -> Vector2:
    return _arc(progress)


func _draw() -> void:
    draw_set_transform_matrix(_transform())
    _draw_orca()
    draw_set_transform_matrix(Transform2D.IDENTITY)
    _draw_water()


## Draw the orca along the x axis, the nose at +x, the back up (-y).
func _draw_orca() -> void:
    # Tail flukes
    draw_colored_polygon(
        PackedVector2Array(
            [Vector2(-110, 0), Vector2(-160, -34), Vector2(-146, 0), Vector2(-160, 34)]
        ),
        _BLACK
    )
    # Dorsal fin
    draw_colored_polygon(
        PackedVector2Array([Vector2(-20, -30), Vector2(-4, -100), Vector2(24, -32)]), _BLACK
    )
    # Body, the white belly and the white patches
    draw_colored_polygon(Draw2D.ellipse(Vector2(0, 0), 125, 42, 36), _BLACK)
    draw_colored_polygon(Draw2D.ellipse(Vector2(20, 22), 80, 16, 24), _WHITE)
    draw_colored_polygon(Draw2D.ellipse(Vector2(70, -14), 20, 9, 16), _WHITE)
    draw_colored_polygon(Draw2D.ellipse(Vector2(-30, -26), 22, 7, 16), Color(0.7, 0.74, 0.8))
    # Pectoral fin
    draw_colored_polygon(
        PackedVector2Array([Vector2(30, 20), Vector2(0, 58), Vector2(10, 22)]), _BLACK
    )
    # A happy face
    draw_circle(Vector2(84, -6), 5, _WHITE)
    draw_circle(Vector2(85, -7), 3, _BLACK)
    draw_arc(Vector2(96, 10), 16, 0.3, PI * 0.7, 10, _WHITE, 3)
    if state == State.SPLASHED:
        for i in range(4):
            var a := _state_time * 5.0 + i * TAU / 4
            _draw_star(Vector2(40 + cos(a) * 70, -70 + sin(a) * 18), 11, Color(1.0, 0.85, 0.2))


func _draw_water() -> void:
    if theme == null:
        return

    # NOTE (mristin):
    # Paint the sea below the water line over the part of the orca in the water,
    # with the gradient of the backdrop in global coordinates.
    var left := minf(from_x, to_x) - 200 * size
    var right := maxf(from_x, to_x) + 200 * size
    var depth := 220.0 * size
    var top := theme.ground_at(water_y)
    var bottom := theme.ground_at(water_y + depth)
    draw_polygon(
        PackedVector2Array(
            [
                Vector2(left, water_y),
                Vector2(right, water_y),
                Vector2(right, water_y + depth),
                Vector2(left, water_y + depth)
            ]
        ),
        PackedColorArray([top, top, bottom, bottom])
    )

    # Foam where the orca comes out and dives in, while it does.
    for end in [[from_x, 0.0], [to_x, 1.0]]:
        var near := 1.0 - clampf(absf(progress - end[1]) / 0.18, 0.0, 1.0)
        if near > 0.0:
            var center := Vector2(end[0], water_y)
            draw_colored_polygon(
                Draw2D.ellipse(center, (60 + 70 * near) * size, (10 + 8 * near) * size),
                Color(_FOAM, 0.85 * near)
            )
            for k in range(5):
                var x := (k - 2) * 26 * size
                draw_circle(
                    center + Vector2(x, -near * (30 + 25 * (2 - absf(k - 2))) * size),
                    7 * size,
                    Color(_FOAM, near)
                )


func _draw_star(center: Vector2, radius: float, color: Color) -> void:
    var points := PackedVector2Array()
    for i in range(10):
        var a := -PI / 2 + i * PI / 5
        var r := radius if i % 2 == 0 else radius * 0.45
        points.append(center + Vector2(cos(a) * r, sin(a) * r))
    draw_colored_polygon(points, color)
