class_name Rover
extends Node2D

## Something which crosses the screen on its own: it walks along the snow in
## the very front of the scene, or flies across the sky.
##
## The rover lives in global coordinates. It moves from [member from] to
## [member to] in [member travel_seconds]; a walker hops a little on its way,
## a flyer floats up and down. The subclasses draw it in their own coordinates
## (facing +x, a walker with its feet and a flyer with its middle at the origin)
## in [method _draw_body], and give its hit area in [method _hit_ellipse].

signal finished(rover: Rover)

enum Motion { WALK, FLY }
enum State { MOVING, HIT, GONE }

const INK := Color(0.15, 0.17, 0.22)

var motion := Motion.WALK
var from := Vector2.ZERO
var to := Vector2.ZERO
var travel_seconds := 9.0

## The size; 1 is the size in the subclass' own coordinates.
var size := 1.0

var state := State.MOVING

## The progress of the crossing in [0, 1].
var progress := 0.0

var _time := 0.0
var _state_time := 0.0

## How much faster the rover moves on after a hit (e.g., runs away).
var _hit_speed := 1.0


func _ready() -> void:
    # NOTE (mristin):
    # The walkers walk in front of the covers and the foreground drifts, the
    # flyers fly in front of the backdrop, but behind the snowballs.
    z_index = 410 if motion == Motion.WALK else 300


func _process(delta: float) -> void:
    _time += delta
    _state_time += delta
    var speed := _hit_speed if state == State.HIT else 1.0
    progress = minf(1.0, progress + delta * speed / travel_seconds)
    _update(delta)
    if progress >= 1.0 and state != State.GONE:
        _finish()
    queue_redraw()


func _finish() -> void:
    state = State.GONE
    finished.emit(self)
    queue_free()


## Update the subclass in every frame (e.g., the throws).
func _update(_delta: float) -> void:
    pass


## The facing: 1 to the right, -1 to the left.
func facing() -> float:
    return 1.0 if to.x >= from.x else -1.0


## The position of the rover's origin on the screen now.
func center_global_position() -> Vector2:
    var at := from.lerp(to, progress)
    if motion == Motion.WALK:
        return at + Vector2(0, -absf(sin(_time * 7.0)) * 10.0 * size)
    return at + Vector2(0, sin(_time * 2.2) * 30.0 * size)


func _transform() -> Transform2D:
    return Transform2D(0.0, Vector2(facing() * size, size), 0.0, center_global_position())


## Whether the rover is on the screen and may be hit.
func is_targetable() -> bool:
    var x := center_global_position().x
    return state == State.MOVING and x > 40.0 and x < 1880.0


## Hit the rover. Return false if it can not be hit.
func hit() -> bool:
    if not is_targetable():
        return false
    state = State.HIT
    _state_time = 0.0
    _on_hit()
    return true


func _on_hit() -> void:
    pass


## Whether a global point hits the rover; the tolerance is in screen pixels.
func hit_test(global_point: Vector2, tolerance: float = 45.0) -> bool:
    if not is_targetable():
        return false
    var p := _transform().affine_inverse() * global_point
    var ellipse := _hit_ellipse()
    var t := tolerance / maxf(0.1, size)
    return Draw2D.in_ellipse(p, ellipse.position, ellipse.size.x + t, ellipse.size.y + t)


## The hit area in the rover's own coordinates: the center and the radii.
func _hit_ellipse() -> Rect2:
    return Rect2(Vector2(0, -80), Vector2(70, 80))


## The middle of the hit area on the screen, e.g., to aim at in the tests.
func aim_point() -> Vector2:
    return to_screen(_hit_ellipse().position)


## A point of the rover's own coordinates on the screen.
func to_screen(local: Vector2) -> Vector2:
    return _transform() * local


func _draw() -> void:
    draw_set_transform_matrix(_transform())
    _draw_body()
    draw_set_transform_matrix(Transform2D.IDENTITY)
    _draw_overlay()


## Draw the rover in its own coordinates.
func _draw_body() -> void:
    pass


## Draw over the rover in global coordinates (e.g., a warning bubble).
func _draw_overlay() -> void:
    pass


## Draw the eyes; [param big] for the big, shiny eyes of a kitten.
func _draw_eye(center: Vector2, radius: float, big: bool) -> void:
    draw_circle(center, radius, INK)
    draw_circle(center + Vector2(radius * 0.3, -radius * 0.35), radius * 0.38, Color.WHITE)
    if big:
        draw_circle(center + Vector2(-radius * 0.35, radius * 0.35), radius * 0.16, Color.WHITE)


func _draw_star(center: Vector2, radius: float, color: Color) -> void:
    var points := PackedVector2Array()
    for i in range(10):
        var a := -PI / 2 + i * PI / 5
        var r := radius if i % 2 == 0 else radius * 0.45
        points.append(center + Vector2(cos(a) * r, sin(a) * r))
    draw_colored_polygon(points, color)
