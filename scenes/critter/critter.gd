class_name Critter
extends Node2D

## A cheerful animal which pops up from its cover, gets ready and throws a
## snowball at the player, unless the player hits it first.
##
## The critter lives in the bear slot of its [CoverSpot], in the spot's local
## coordinates: its feet are at the origin when it is fully out. All the critters
## have about the same size (the head at [constant HEAD], the body below it), so
## that every cover hides any of them; the subclasses only draw themselves in
## [method _draw_body].
##
## Before throwing, the critter winds up for [constant WIND_UP_SECONDS] with
## a clearly visible "!" bubble, so that the player always has a fair chance.
## When hit, it only gets dizzy (stars, swirly eyes) and ducks away.

signal threw(critter: Critter, at: Vector2)
signal finished(critter: Critter)

enum State { EMERGING, EXPOSED, WIND_UP, THROWING, RETREATING, DIZZY, GONE }

const EMERGE_SECONDS := 0.35
const WIND_UP_SECONDS := 0.7
const THROW_SECONDS := 0.2
const RETREAT_SECONDS := 0.35
const DIZZY_SECONDS := 0.8

## The center of the head in the critter's own coordinates.
const HEAD := Vector2(0, -178)

const INK := Color(0.15, 0.17, 0.22)

## Seconds from fully out to the throw, including the wind-up.
var exposure_seconds := 2.4

## Ask whether the critter may throw (the game limits the snowballs in the air).
var may_throw: Callable = func() -> bool: return true

var spot: CoverSpot
var state := State.EMERGING

## How far the critter is out of its cover, in [0, 1].
var emergence := 0.0

## Seconds the critter has been fully out.
var exposed_time := 0.0

var _state_time := 0.0
var _slide := 0.0
var _bob := 0.0


func is_targetable() -> bool:
    return (
        state in [State.EMERGING, State.EXPOSED, State.WIND_UP, State.THROWING]
        and emergence >= 0.35
    )


func _process(delta: float) -> void:
    _state_time += delta
    _bob += delta

    match state:
        State.EMERGING:
            emergence = _ease_out_back(clampf(_state_time / EMERGE_SECONDS, 0.0, 1.0))
            if _state_time >= EMERGE_SECONDS:
                emergence = 1.0
                _enter(State.EXPOSED)

        State.EXPOSED:
            exposed_time += delta
            if spot.kind == CoverSpot.Kind.RIDGE:
                _slide = clampf(_slide + delta * 0.1, 0.0, 1.0)
            if exposed_time >= maxf(0.4, exposure_seconds - WIND_UP_SECONDS):
                _enter(State.WIND_UP)

        State.WIND_UP:
            exposed_time += delta
            if _state_time >= WIND_UP_SECONDS:
                if may_throw.call():
                    _enter(State.THROWING)
                    threw.emit(self, spot.to_global(_body_transform() * _throw_point()))
                else:
                    _enter(State.RETREATING)

        State.THROWING:
            exposed_time += delta
            if _state_time >= THROW_SECONDS:
                _enter(State.RETREATING)

        State.RETREATING:
            emergence = 1.0 - clampf(_state_time / RETREAT_SECONDS, 0.0, 1.0)
            if _state_time >= RETREAT_SECONDS:
                _enter(State.GONE)
                finished.emit(self)
                queue_free()

        State.DIZZY:
            if _state_time >= DIZZY_SECONDS:
                _enter(State.RETREATING)

    queue_redraw()


func _enter(new_state: State) -> void:
    state = new_state
    _state_time = 0.0


## Hit the critter: it gets dizzy and ducks away. Return false if it can not be hit.
func hit() -> bool:
    if not is_targetable():
        return false
    _enter(State.DIZZY)
    return true


## Whether a global point hits the visible part of the critter.
##
## The tolerance (in pixels of the screen) is generous, since the hand tracking
## is not precise.
func hit_test(global_point: Vector2, tolerance: float = 45.0) -> bool:
    if not is_targetable():
        return false

    var local := spot.to_local(global_point)
    if spot.occludes(local):
        return false

    var p := _body_transform().affine_inverse() * local
    var t := tolerance / maxf(0.1, spot.scale.x)
    return (
        Draw2D.in_ellipse(p, HEAD, 58 + t, 54 + t)
        or Draw2D.in_ellipse(p, Vector2(0, -85), 84 + t, 92 + t)
    )


## The global position of the head, e.g., for the score.
func head_global_position() -> Vector2:
    return spot.to_global(_body_transform() * HEAD)


## Where the snowball leaves the critter, in its own coordinates.
func _throw_point() -> Vector2:
    return Vector2(62, -250)


## Map the critter's own coordinates to the spot's.
func _body_transform() -> Transform2D:
    var offset: Vector2
    var rotation_angle := 0.0
    if not spot.rises():
        offset = Vector2(spot.side * (-10 + emergence * 120), 0)
        rotation_angle = spot.side * 0.18 * emergence
    else:
        var x := 0.0
        if spot.kind == CoverSpot.Kind.RIDGE:
            var half := spot.ridge_length * 0.5 - 80
            x = lerpf(-half, half, _slide if spot.side > 0 else 1.0 - _slide)
        offset = Vector2(x, (1.0 - emergence) * 290)

    var bob := sin(_bob * 4.0) * 1.5 if state == State.EXPOSED else 0.0
    var body_scale := Vector2.ONE
    if state == State.DIZZY:
        var wobble := sin(_state_time * 18.0) * 0.05
        body_scale = Vector2(1.06 + wobble, 0.94 - wobble)
        rotation_angle += sin(_state_time * 10.0) * 0.08

    return Transform2D(rotation_angle, body_scale, 0.0, offset + Vector2(0, bob))


func _draw() -> void:
    var body := _body_transform()
    draw_set_transform_matrix(body)
    _draw_body(state == State.WIND_UP, state == State.THROWING)
    draw_set_transform_matrix(Transform2D.IDENTITY)

    if state == State.WIND_UP:
        # NOTE (mristin):
        # The warning bubble with a ring which closes when the throw comes.
        var bubble := body * Vector2(-70, -275)
        var left := 1.0 - clampf(_state_time / WIND_UP_SECONDS, 0.0, 1.0)
        draw_circle(bubble, 30, Color(1.0, 0.85, 0.2))
        draw_arc(bubble, 36, -PI / 2, -PI / 2 + TAU * left, 32, Color(0.95, 0.35, 0.2), 6)
        draw_rect(Rect2(bubble + Vector2(-4, -18), Vector2(8, 22)), INK)
        draw_circle(bubble + Vector2(0, 12), 4.5, INK)


## Draw the critter in its own coordinates (the feet at the origin).
func _draw_body(_wind_up: bool, _throwing: bool) -> void:
    pass


## How far the wind-up has come, in [0, 1].
func _wind_up_progress() -> float:
    return clampf(_state_time / (WIND_UP_SECONDS * 0.5), 0.0, 1.0)


## Draw the snowball which the critter is about to throw.
func _draw_snowball(center: Vector2) -> void:
    var style := spot.theme.projectile
    draw_circle(center + Vector2(2, 2), 20, style.shade)
    draw_circle(center, 18, style.body)


## Draw the eyes: open, swirly when dizzy, with frowning brows when about to throw.
func _draw_eyes(head: Vector2, spacing: float, determined: bool) -> void:
    if state == State.DIZZY:
        # NOTE (mristin):
        # Swirly eyes and circling stars: the critter is only dizzy, never hurt.
        for x in [-spacing, spacing]:
            for i in range(3):
                var start := i + _state_time * 8.0
                draw_arc(head + Vector2(x, -12), 3 + i * 3, start, start + 4, 10, INK, 2)
        for i in range(4):
            var a := _state_time * 5.0 + i * TAU / 4
            draw_star(head + Vector2(cos(a) * 60, -70 + sin(a) * 14), 10, Color(1.0, 0.85, 0.2))
        return

    for x in [-spacing, spacing]:
        draw_circle(head + Vector2(x, -12), 7, INK)
        draw_circle(head + Vector2(x + 2, -15), 2.5, Color.WHITE)

    if determined:
        draw_line(head + Vector2(-spacing - 10, -26), head + Vector2(-spacing + 8, -22), INK, 3)
        draw_line(head + Vector2(spacing + 10, -26), head + Vector2(spacing - 8, -22), INK, 3)


func draw_star(center: Vector2, radius: float, color: Color) -> void:
    var points := PackedVector2Array()
    for i in range(10):
        var a := -PI / 2 + i * PI / 5
        var r := radius if i % 2 == 0 else radius * 0.45
        points.append(center + Vector2(cos(a) * r, sin(a) * r))
    draw_colored_polygon(points, color)


static func _ease_out_back(t: float) -> float:
    var c1 := 1.4
    var c3 := c1 + 1.0
    return 1.0 + c3 * pow(t - 1.0, 3) + c1 * pow(t - 1.0, 2)
