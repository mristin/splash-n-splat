class_name AimController
extends Node2D

## Show where every hand in front of the webcam aims (as the outline of
## a snowball), and fire when a hand closes into a fist.
##
## The game is played with the hands only, by any number of players: every hand
## aims and throws on its own (see HandVisionService.cs, which tracks the hands,
## maps them to the screen and smooths them). The tests drive a scripted
## aim with [method aim_at] and [method fire].

## Fired at a viewport position, with the id of the hand (-1 if scripted).
signal fired(at: Vector2, hand_id: int)

const _SCREEN := Vector2(1920, 1080)

## A color per hand, so that the players can tell their aims apart.
const _HAND_COLORS := [
    Color(1.0, 0.85, 0.3),
    Color(0.45, 0.85, 1.0),
    Color(1.0, 0.55, 0.75),
    Color(0.6, 1.0, 0.5),
    Color(0.8, 0.6, 1.0),
]

var vision: Node = null

## The aims by hand id: {"position", "gesture", "armed"}.
var hands: Dictionary = {}

var last_shot := "none"

## The scripted aim of the tests.
var scripted_position := _SCREEN * 0.5

## Whether the big snowballs are on, so that the outlines are drawn bigger.
var big := false

var _time := 0.0

## The flashes of the recent shots by hand id: the remaining seconds.
var _flashes: Dictionary = {}


func _ready() -> void:
    z_index = 1000


## Follow the hands of the vision service and fire on their throws.
func setup(vision_service: Node) -> void:
    vision = vision_service
    vision.ShotFired.connect(func(hand_id: int): fire(hand_id))


func has_hands() -> bool:
    return not hands.is_empty()


## Put the scripted aim at a viewport position (for the tests).
func aim_at(at: Vector2) -> void:
    scripted_position = at


## Fire with the hand at its aim; -1 fires the scripted aim.
func fire(hand_id: int) -> void:
    var at := scripted_position
    if hand_id >= 0:
        if not hands.has(hand_id):
            return
        at = hands[hand_id]["position"]

    _flashes[hand_id] = 0.15
    var by := "hand #%d" % hand_id if hand_id >= 0 else "scripted"
    last_shot = "%s at (%.0f, %.0f), t=%.2f" % [by, at.x, at.y, _time]
    fired.emit(at, hand_id)


func _process(delta: float) -> void:
    _time += delta
    for id in _flashes.keys():
        _flashes[id] -= delta
        if _flashes[id] <= 0:
            _flashes.erase(id)

    if vision != null:
        var updated := {}
        for aim in vision.GetAims():
            updated[aim["hand_id"]] = {
                "position": aim["position"] * _SCREEN,
                "gesture": aim["gesture"],
                "armed": aim["armed"],
            }
        hands = updated

    queue_redraw()


func _draw() -> void:
    for id in hands:
        var hand: Dictionary = hands[id]
        var color: Color = _HAND_COLORS[int(id) % _HAND_COLORS.size()]
        _draw_snowball(
            hand["position"], color, _flashes.get(id, 0.0), hand["gesture"], hand["armed"], int(id)
        )

    if _flashes.has(-1):
        _draw_snowball(scripted_position, Color.WHITE, _flashes[-1], "fist", false, 0)


## Draw where a hand aims as the outline of a snowball (no weapon sight: this is
## a game for children). Open hands show the outline, armed hands pulse gently,
## and a fist fills the snowball, as if holding it.
func _draw_snowball(
    at: Vector2, color: Color, flash: float, gesture: String, armed: bool, seed_value: int
) -> void:
    # NOTE (mristin):
    # With the big snowballs, the outline grows by about half of the extra reach
    # of the throw, so that the players see that they now hit more easily.
    var radius := 66.0 if big else 36.0
    if armed:
        radius += 3.0 * sin(_time * 6.0)

    var outline := Draw2D.blob(at, radius, 0.035, seed_value, 32)
    outline.append(outline[0])
    var fill_alpha := 0.9 if gesture == "fist" else 0.15
    var fill := Color(1, 1, 1, fill_alpha)

    draw_colored_polygon(Draw2D.blob(at, radius, 0.035, seed_value, 32), fill)
    draw_polyline(outline, Color(0.1, 0.18, 0.35, 0.7), 8.0, true)
    draw_polyline(outline, color if gesture != "unknown" else Color(color, 0.6), 5.0, true)

    # A little shine, so that it reads as a snowball.
    draw_arc(
        at + Vector2(-8, -8), radius * 0.55, PI * 1.05, PI * 1.45, 10, Color(1, 1, 1, 0.9), 4.0
    )

    if flash > 0.0:
        # A sparkle ring when the snowball flies.
        var t := 1.0 - flash / 0.15
        var sparkle := radius + 40.0 * t
        for i in range(8):
            var direction := Vector2.RIGHT.rotated(i * TAU / 8 + 0.2)
            draw_circle(at + direction * sparkle, 6.0 * (1.0 - t), Color(color, 1.0 - t))
