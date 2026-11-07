class_name Thrower
extends Rover

## A cheeky rover which throws snowballs at the player while it moves on.
##
## It throws at most [member throws_left] times on its way, every time after
## a wind-up with the same "!" bubble as the critters, so that the player
## always has a fair chance to hit it or to intercept its snowball. When hit,
## it gets dizzy and hurries off the screen.

signal threw(thrower: Thrower, at: Vector2)

const WIND_UP_SECONDS := 0.7

var throws_left := 2

## Ask whether the thrower may throw (the game limits the snowballs in the air).
var may_throw: Callable = func() -> bool: return true

## The seconds until the next wind-up.
var _next_throw := 1.6
var _wind_up := -1.0
## The seconds since the last throw, for the throwing pose.
var _since_throw := 10.0


func _init() -> void:
    _hit_speed = 2.5


func _update(delta: float) -> void:
    _since_throw += delta
    if state != State.MOVING or throws_left <= 0:
        _wind_up = -1.0
        return
    if _wind_up >= 0.0:
        _wind_up += delta
        if _wind_up >= WIND_UP_SECONDS:
            _wind_up = -1.0
            _next_throw = 2.2
            if may_throw.call() and is_targetable():
                throws_left -= 1
                _since_throw = 0.0
                threw.emit(self, to_screen(_throw_point()))
        return
    _next_throw -= delta
    # NOTE (mristin):
    # It winds up only well inside the screen, so that the player can see it.
    var x := center_global_position().x
    if _next_throw <= 0.0 and x > 200.0 and x < 1720.0:
        _wind_up = 0.0


func is_winding_up() -> bool:
    return _wind_up >= 0.0


## Where the snowball leaves the thrower, in its own coordinates.
func _throw_point() -> Vector2:
    return Vector2(40, -160)


## Where the "!" bubble floats, in its own coordinates.
func _bubble_point() -> Vector2:
    return Vector2(-40, -230)


func _draw_overlay() -> void:
    if state == State.HIT:
        for i in range(4):
            var a := _state_time * 5.0 + i * TAU / 4
            var center := to_screen(_bubble_point() + Vector2(40, 30))
            _draw_star(center + Vector2(cos(a) * 60, sin(a) * 14) * size, 11, Color(1.0, 0.85, 0.2))
        return
    if not is_winding_up():
        return
    var bubble := to_screen(_bubble_point())
    var left := 1.0 - clampf(_wind_up / WIND_UP_SECONDS, 0.0, 1.0)
    draw_circle(bubble, 30, Color(1.0, 0.85, 0.2))
    draw_arc(bubble, 36, -PI / 2, -PI / 2 + TAU * left, 32, Color(0.95, 0.35, 0.2), 6)
    draw_rect(Rect2(bubble + Vector2(-4, -18), Vector2(8, 22)), INK)
    draw_circle(bubble + Vector2(0, 12), 4.5, INK)


## Draw the snowball in the paw or the wing while winding up.
func _draw_held_snowball(center: Vector2) -> void:
    if not is_winding_up():
        return
    draw_circle(center + Vector2(2, 2), 20, Color(0.7, 0.8, 0.92))
    draw_circle(center, 18, Color.WHITE)


## Draw the eyes: dizzy swirls after a hit, frowning brows while winding up.
func _draw_eyes(left: Vector2, right: Vector2, radius: float) -> void:
    if state == State.HIT:
        for eye in [left, right]:
            for i in range(3):
                var start := i + _state_time * 8.0
                draw_arc(eye, 3 + i * 3, start, start + 4, 10, INK, 2)
        return
    _draw_eye(left, radius, false)
    _draw_eye(right, radius, false)
    if is_winding_up():
        var lift := Vector2(0, -radius - 6)
        draw_line(left + lift + Vector2(-10, -4), left + lift + Vector2(8, 2), INK, 3)
        draw_line(right + lift + Vector2(10, -4), right + lift + Vector2(-8, 2), INK, 3)
