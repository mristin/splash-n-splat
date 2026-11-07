class_name DebugOverlay
extends CanvasLayer

## Show the performance and the state of the hand vision: the camera and render
## rates, the inference latencies, the hands with their gesture probabilities,
## the aims and the last shot. Shown only with the command-line argument --debug.

var vision: Node = null
var aim: AimController = null

var _refresh := 0.0

@onready var _label: Label = $Label
@onready var _preview: Control = $Preview


func setup(vision_service: Node, aim_controller: AimController) -> void:
    vision = vision_service
    aim = aim_controller
    _preview.set("Service", vision)


func _process(delta: float) -> void:
    _refresh -= delta
    if not visible or _refresh > 0:
        return
    _refresh = 0.1

    var text := "render %.0f fps\n" % Engine.get_frames_per_second()
    text += vision.GetDebugText() if vision != null else "no vision\n"
    if aim != null:
        for id in aim.hands:
            var at: Vector2 = aim.hands[id]["position"]
            text += "aim of hand #%d at (%.0f, %.0f)\n" % [id, at.x, at.y]
        text += "last shot: %s\n" % aim.last_shot
    _label.text = text
