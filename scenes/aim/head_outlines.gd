class_name HeadOutlines
extends Node2D

## Draw a soft, glowing ellipse around the head of every player, so that the
## players see where the opponents aim; an outline turns orange and pulses while
## a snowball flies at it. The glow is a shader (head_outline.gdshader) on a
## quad per head.

## The quad around the ellipse, as a factor of its radii; see the shader.
const _MARGIN := 1.4

## The heads in screen pixels.
var heads: Array[Rect2] = []

## The targets of the snowballs which fly at the heads, in screen pixels.
var threats: Array[Vector2] = []

var _time := 0.0
var _white: Texture2D


func _ready() -> void:
    var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
    image.fill(Color.WHITE)
    _white = ImageTexture.create_from_image(image)
    var shader_material := ShaderMaterial.new()
    shader_material.shader = preload("res://scenes/aim/head_outline.gdshader")
    shader_material.set_shader_parameter("margin", _MARGIN)
    material = shader_material


func _process(delta: float) -> void:
    _time += delta
    queue_redraw()


## Whether the head contains the point, with some tolerance in pixels, and
## the ellipse scaled by the factor.
static func head_contains(
    head: Rect2, point: Vector2, tolerance: float, factor: float = 1.0
) -> bool:
    var radii := (head.size * 0.5 * 1.1 + Vector2(tolerance, tolerance)) * factor
    return Draw2D.in_ellipse(point, head.get_center(), radii.x, radii.y)


func _draw() -> void:
    for head in heads:
        var threatened := false
        for threat in threats:
            if head_contains(head, threat, 40.0):
                threatened = true
        var radii := head.size * 0.5 * 1.1
        var color := Color(1, 1, 1, 0.7)
        if threatened:
            var pulse := 0.5 + 0.5 * sin(_time * 12.0)
            color = Color(1.0, 0.55, 0.2, 0.75 + 0.25 * pulse)
            radii *= 1.0 + 0.05 * pulse
        var quad := radii * _MARGIN
        draw_texture_rect(_white, Rect2(head.get_center() - quad, quad * 2.0), false, color)
