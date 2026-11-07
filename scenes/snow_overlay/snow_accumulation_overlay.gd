class_name SnowAccumulationOverlay
extends CanvasLayer

## Show the snow which sticks to the screen when the player is hit: a big splat at
## the impact, which slides off, and translucent frost which piles up along the
## edges and never covers the center (see [SnowAccumulation]).

const _SCREEN := Vector2(1920, 1080)
const _IMPACT_SECONDS := 1.4

var snow := SnowAccumulation.new()
var style: ProjectileStyle = ProjectileStyle.snowball()

var _shown := Vector4.ZERO

## The fading impacts as [position, seed, age].
var _impacts: Array = []

@onready var _frost: ColorRect = $Frost
@onready var _lumps: Node2D = $Lumps


func _ready() -> void:
    _lumps.draw.connect(_draw_lumps)


func reset() -> void:
    snow.reset()
    _impacts.clear()


## Add the snow of a hit at the screen position (in pixels).
func add_hit(at: Vector2) -> void:
    snow.add_hit(at.x / _SCREEN.x, at.y / _SCREEN.y)
    _impacts.append([at, randi() % 1000, 0.0])


func _process(delta: float) -> void:
    # NOTE (mristin):
    # The frost grows smoothly toward its new extent.
    var target := Vector4(snow.left, snow.top, snow.right, snow.bottom)
    _shown = _shown.lerp(target, minf(1.0, delta * 3.0))
    (_frost.material as ShaderMaterial).set_shader_parameter("edges", _shown)

    for impact in _impacts:
        impact[2] += delta
    _impacts = _impacts.filter(func(impact): return impact[2] <= _IMPACT_SECONDS)
    _lumps.queue_redraw()


func _draw_lumps() -> void:
    var index := 0
    for blob in snow.blobs:
        var center := Vector2(blob.x * _SCREEN.x, blob.y * _SCREEN.y)
        var r: float = blob.z * _SCREEN.y
        # NOTE (mristin):
        # Concentric, increasingly opaque layers make a soft lump.
        for layer in range(4):
            var color := style.shade if layer == 0 else style.body
            _lumps.draw_colored_polygon(
                Draw2D.blob(center, r * (1.0 - layer * 0.2), 0.12, index + layer, 36),
                Color(color, 0.16 + layer * 0.06)
            )
        index += 1

    for impact in _impacts:
        # The splat hits hard, then slowly slides down and fades out.
        var t: float = impact[2] / _IMPACT_SECONDS
        var alpha := 0.85 * (1.0 - t * t)
        var center: Vector2 = impact[0] + Vector2(0, 90 * t * t)
        var r := 170.0 * (0.9 + 0.15 * minf(1.0, t * 6.0))
        _lumps.draw_colored_polygon(
            Draw2D.blob(center, r, 0.3, impact[1], 48), Color(style.body, alpha)
        )
        for i in range(6):
            var a: float = impact[1] + i * 1.1
            var drop := center + Vector2(cos(a), sin(a)) * r * 1.2
            _lumps.draw_circle(
                drop + Vector2(0, 140 * t), 22.0 * (1.0 - 0.5 * t), Color(style.body, alpha)
            )
