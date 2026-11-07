class_name Splat
extends Node2D

## A soft puff of snow which bursts out and fades away.

var style: ProjectileStyle = ProjectileStyle.snowball()
var size := 60.0
var lifetime := 0.6

var _time := 0.0
var _directions: Array[Vector2] = []
var _sizes: Array[float] = []


func _ready() -> void:
    z_index = 600
    for i in range(12):
        var a := i * TAU / 12 + randf() * 0.4
        _directions.append(Vector2(cos(a), sin(a)) * (0.6 + randf() * 0.8))
        _sizes.append(0.12 + randf() * 0.14)


func _process(delta: float) -> void:
    _time += delta
    if _time >= lifetime:
        queue_free()
        return
    queue_redraw()


func _draw() -> void:
    var t := _time / lifetime
    var ease_out := 1.0 - (1.0 - t) * (1.0 - t)
    var alpha := 1.0 - t * t
    draw_circle(Vector2.ZERO, size * (0.35 + 0.25 * ease_out), Color(style.splat, alpha * 0.9))
    for i in range(_directions.size()):
        var p := _directions[i] * size * ease_out + Vector2(0, 30 * t * t)
        draw_circle(p, size * _sizes[i] * (1.0 - 0.5 * t), Color(style.splat, alpha))
