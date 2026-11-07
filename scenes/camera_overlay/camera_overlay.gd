class_name CameraOverlay
extends CanvasLayer

## Show the webcam dimly over the whole screen, like a mirror, so that the players
## see their hands right under their aims.
##
## We show exactly the region of the camera image which the vision maps to
## the screen (see HandVisionService.GetAimRegion), so the picture and the aim
## line up.

const _SCREEN := Vector2(1920, 1080)

## How strongly the camera shows through.
@export_range(0.0, 1.0) var opacity := 0.2

var vision: Node = null

@onready var _canvas: Node2D = $Canvas


func _ready() -> void:
    _canvas.draw.connect(_draw_camera)


func setup(vision_service: Node) -> void:
    vision = vision_service


func _process(_delta: float) -> void:
    _canvas.queue_redraw()


func _draw_camera() -> void:
    if vision == null:
        return
    var texture: Texture2D = vision.GetCameraTexture()
    if texture == null:
        return

    var size := texture.get_size()
    if size.x <= 0 or size.y <= 0:
        return

    var region: Rect2 = vision.GetAimRegion()
    var source := Rect2(region.position * size, region.size * size)
    if vision.Mirror:
        _canvas.draw_set_transform(Vector2(_SCREEN.x, 0), 0, Vector2(-1, 1))
    _canvas.draw_texture_rect_region(
        texture, Rect2(Vector2.ZERO, _SCREEN), source, Color(1, 1, 1, opacity)
    )
    _canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
