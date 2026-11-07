class_name Snowball
extends Node2D

## A thrown projectile in a pseudo-3D flight: toward the player (growing) or away
## from the player into the scene (shrinking).
##
## The projectile flies along a gentle arc from [member start] to
## [member target] over [member flight_seconds]. A projectile toward the player
## shows where it will land with a ring which tightens, so that the player sees
## it coming and can intercept it by hitting it. The look comes from
## a [ProjectileStyle], so that a future world can throw water balloons.

signal arrived(snowball: Snowball)

enum Heading { TOWARD_PLAYER, AWAY_FROM_PLAYER }

var heading := Heading.TOWARD_PLAYER
var style: ProjectileStyle = ProjectileStyle.snowball()
var start := Vector2.ZERO
var target := Vector2.ZERO
var flight_seconds := 1.6
var start_radius := 10.0
var end_radius := 150.0

## Height of the arc in pixels.
var arc_height := 120.0

## Progress of the flight in [0, 1].
var progress := 0.0
var radius := 0.0
var is_done := false

var _time := 0.0
var _spin := 0.0
var _seed := randi() % 1000


func _ready() -> void:
    z_index = 500 if heading == Heading.TOWARD_PLAYER else 450
    _update(0.0)


func _process(delta: float) -> void:
    if is_done:
        return

    _time += delta
    _spin += delta * 3.0
    _update(clampf(_time / flight_seconds, 0.0, 1.0))

    if _time >= flight_seconds:
        is_done = true
        arrived.emit(self)
        queue_free()

    queue_redraw()


func _update(t: float) -> void:
    progress = t

    # NOTE (mristin):
    # Toward the player, the ball grows slowly at first and quickly at the end,
    # like a real approaching object; away from the player the other way round.
    var toward := heading == Heading.TOWARD_PLAYER
    var growth := t * t * t if toward else 1.0 - (1.0 - t) * (1.0 - t)
    radius = lerpf(start_radius, end_radius, growth)

    var along := t * t if toward else 1.0 - (1.0 - t) * (1.0 - t)
    var p := start.lerp(target, along)
    p.y -= arc_height * 4.0 * t * (1.0 - t)
    position = p


## Whether a shot at the global point intercepts the projectile.
func hit_test(point: Vector2, tolerance: float = 45.0) -> bool:
    # NOTE (mristin):
    # We are generous: small far-away balls are hard to hit otherwise.
    return not is_done and point.distance_to(position) <= radius * 1.4 + tolerance


## Stop the projectile, e.g., when it was intercepted.
func pop() -> void:
    is_done = true
    queue_free()


func _draw() -> void:
    if heading == Heading.TOWARD_PLAYER and progress < 0.98:
        var ring := target - position
        var alpha := 0.25 + 0.45 * progress
        var ring_radius := lerpf(end_radius * 1.4, end_radius * 0.9, progress)
        draw_arc(ring, ring_radius, 0, TAU, 48, Color(1, 0.55, 0.3, alpha), 5)
        draw_arc(ring, ring_radius * 0.25, 0, TAU, 24, Color(1, 0.55, 0.3, alpha), 3)

    var r := radius
    draw_colored_polygon(
        Draw2D.blob(Vector2(r * 0.08, r * 0.1), r, style.lumpiness, _seed), style.shade
    )
    draw_colored_polygon(
        Draw2D.blob(Vector2.ZERO, r * 0.95, style.lumpiness, _seed + 1), style.body
    )
    var glint := Vector2(cos(_spin), sin(_spin)) * r * 0.1
    draw_circle(Vector2(-r * 0.35, -r * 0.35) + glint, r * 0.22, Color(style.highlight, 0.9))
    draw_circle(Vector2(r * 0.3, r * 0.25), r * 0.12, Color(style.shade, 0.6))
