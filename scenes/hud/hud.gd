class_name Hud
extends CanvasLayer

## Show the score, the critters to go, the energy left, and the messages of
## the title, the level-finished and the game-finished screens.

var rules: LevelRules = null
var vision: Node = null

## The energy as drawn; it follows the real one smoothly.
var _shown_energy := 1.0
## Flashes the bar when the player takes a snowball; falls from 1 to 0.
var _flash := 0.0

var _critters_name := "Polar bears"

## The active boosters as [kind, the share of the time left].
var _boosts: Array = []

## The stars of the level-finished screen, and the seconds it has been shown.
var _stars := 0
var _panel_time := 0.0
## Whether the panel celebrates the end of the whole trip with confetti.
var _celebrating := false

@onready var _score: Label = $Score
@onready var _bears: Label = $Bears
@onready var _title: Label = $Title
@onready var _message: Label = $Message
@onready var _status: Label = $Status
@onready var _icons: Node2D = $Icons
@onready var _quit_prompt: Label = $QuitPrompt
@onready var _panel: Node2D = $Panel


func _ready() -> void:
    _icons.draw.connect(_draw_icons)
    _panel.draw.connect(_draw_panel)


func setup(level_rules: LevelRules, vision_service: Node) -> void:
    rules = level_rules
    vision = vision_service


## Show a big title and a message in the middle; hide them with empty strings.
func show_message(title: String, message: String) -> void:
    _set_text_layout(150, 46, Rect2(160, 430, 1600, 360))
    _title.text = title
    _message.text = message
    _panel.visible = false
    _celebrating = false


## Show the level-finished screen: a panel with the title, the message and
## the stars (none for a lost level), which pop in one after the other.
func show_level_finished(title: String, message: String, stars: int) -> void:
    show_message(title, message)
    _stars = stars
    _celebrating = false
    _panel_time = 0.0
    _panel.visible = true


## Show the game-finished screen: the panel with all the three stars, and
## colorful confetti which rains down over it.
func show_game_finished(title: String, message: String) -> void:
    show_level_finished(title, message, 3)
    _celebrating = true
    # NOTE (mristin):
    # The celebration has more to say, so its texts are a bit smaller.
    _set_text_layout(112, 40, Rect2(280, 410, 1360, 560))


func _set_text_layout(title_size: int, message_size: int, message_box: Rect2) -> void:
    _title.add_theme_font_size_override("font_size", title_size)
    _message.add_theme_font_size_override("font_size", message_size)
    _message.offset_left = message_box.position.x
    _message.offset_top = message_box.position.y
    _message.offset_right = message_box.end.x
    _message.offset_bottom = message_box.end.y


func is_game_finished_shown() -> bool:
    return _panel.visible and _celebrating


func is_level_finished_shown() -> bool:
    return _panel.visible


## Show the active boosters under the energy bar, as [kind, share of the time left].
func set_boosts(boosts: Array) -> void:
    _boosts = boosts


func set_critters_name(critters_name: String) -> void:
    _critters_name = critters_name


func show_quit_prompt(shown: bool) -> void:
    _quit_prompt.visible = shown


func set_status(status: String) -> void:
    _status.text = status


func set_playing(playing: bool) -> void:
    _score.visible = playing
    _bears.visible = playing
    _icons.visible = playing


func _process(delta: float) -> void:
    if rules != null:
        _score.text = "Score %d" % rules.score
        _bears.text = "%s: %d / %d" % [_critters_name, rules.bears_hit, rules.target_bears]
        var energy := rules.energy()
        if energy < _shown_energy - 0.001:
            _flash = 1.0
        _shown_energy = move_toward(_shown_energy, energy, delta * 0.6)
        if energy > _shown_energy:
            # NOTE: a new level refills the energy at once.
            _shown_energy = energy
    _flash = maxf(0.0, _flash - delta * 2.0)
    _icons.queue_redraw()
    if _panel.visible:
        _panel_time += delta
        _panel.queue_redraw()


## Draw the energy bar with a snowflake: green when full, red when nearly empty,
## with a notch per snowball the player can take.
func _draw_icons() -> void:
    if rules == null:
        return

    var frame := Rect2(1440, 32, 440, 52)
    var inner := frame.grow(-7)
    var back := StyleBoxFlat.new()
    back.bg_color = Color(0.12, 0.22, 0.42, 0.7)
    back.set_corner_radius_all(26)
    back.set_border_width_all(4)
    back.border_color = Color(1, 1, 1).lerp(Color(1, 0.4, 0.3), _flash)
    _icons.draw_style_box(back, frame)

    if _shown_energy > 0.0:
        var fill := StyleBoxFlat.new()
        var low := Color(1.0, 0.35, 0.3)
        var middle := Color(1.0, 0.85, 0.3)
        var high := Color(0.45, 0.9, 0.45)
        fill.bg_color = (
            low.lerp(middle, _shown_energy * 2.0)
            if _shown_energy < 0.5
            else middle.lerp(high, (_shown_energy - 0.5) * 2.0)
        )
        fill.set_corner_radius_all(19)
        _icons.draw_style_box(
            fill,
            Rect2(inner.position, Vector2(maxf(38.0, inner.size.x * _shown_energy), inner.size.y))
        )

    for i in range(1, rules.max_hits):
        var x := inner.position.x + inner.size.x * i / rules.max_hits
        _icons.draw_line(
            Vector2(x, inner.position.y + 8),
            Vector2(x, inner.end.y - 8),
            Color(0.12, 0.22, 0.42, 0.5),
            2
        )

    # NOTE (mristin):
    # The active boosters under the bar, with a ring which runs out with their time.
    for i in range(_boosts.size()):
        var kind: Booster.Kind = _boosts[i][0]
        var left: float = _boosts[i][1]
        var at := Vector2(frame.end.x - 40 - i * 96, frame.end.y + 52)
        _icons.draw_circle(at, 38, Color(0.12, 0.22, 0.42, 0.7))
        _icons.draw_arc(at, 38, -PI / 2, -PI / 2 + TAU * left, 32, Booster.color_of(kind), 7)
        Booster.draw_icon(_icons, kind, at, 22)

    # A snowflake at the start of the bar.
    var center := Vector2(frame.position.x - 40, frame.get_center().y)
    var color := Color(0.75, 0.92, 1.0)
    _icons.draw_circle(center, 30, Color(0.12, 0.22, 0.42, 0.6))
    for k in range(3):
        var direction := Vector2.RIGHT.rotated(k * PI / 3)
        _icons.draw_line(center - direction * 22, center + direction * 22, color, 5)
        for side in [-1.0, 1.0]:
            var tip: Vector2 = center + direction * 22 * side
            var branch: Vector2 = center + direction * 13 * side
            _icons.draw_line(branch, branch + (tip - branch).rotated(0.9) * 0.8, color, 3)
            _icons.draw_line(branch, branch + (tip - branch).rotated(-0.9) * 0.8, color, 3)


## Draw the panel of the level-finished screen behind the texts, and its stars.
func _draw_panel() -> void:
    var panel := StyleBoxFlat.new()
    panel.bg_color = Color(0.12, 0.22, 0.42, 0.72)
    panel.set_corner_radius_all(48)
    panel.set_border_width_all(6)
    panel.border_color = Color(1, 1, 1, 0.85)
    var top := 70.0 if _stars > 0 else 190.0
    var bottom := 1000.0 if _celebrating else 900.0
    _panel.draw_style_box(panel, Rect2(220, top, 1480, bottom - top))

    if _stars <= 0:
        return

    # NOTE (mristin):
    # Three star places; the won ones pop in one after the other with a bounce.
    for i in range(3):
        var center := Vector2(960 + (i - 1) * 150, 165 - (14 if i == 1 else 0))
        var radius := 62.0 if i == 1 else 52.0
        _draw_star(center, radius + 6, Color(0.12, 0.22, 0.42, 0.9))
        _draw_star(center, radius, Color(1, 1, 1, 0.25))
        if i < _stars:
            var t := clampf((_panel_time - 0.4 - i * 0.35) / 0.3, 0.0, 1.0)
            # NOTE (mristin):
            # A tiny star would fail the triangulation, so it pops in from a pixel.
            if radius * t * 0.35 > 1.0:
                var pop := 1.0 + 0.35 * sin(t * PI)
                _draw_star(center, radius * t * pop, Color(1.0, 0.85, 0.25))
                _draw_star(
                    center + Vector2(-radius * 0.15, -radius * 0.2) * t,
                    radius * 0.35 * t,
                    Color(1, 0.97, 0.75)
                )

    if _celebrating:
        _draw_confetti()


## Draw the confetti of the game-finished screen: little colorful flakes which
## flutter down in a loop, the same ones every time.
func _draw_confetti() -> void:
    var colors: Array[Color] = [
        Color(1.0, 0.85, 0.25),
        Color(1.0, 0.45, 0.4),
        Color(0.45, 0.9, 0.45),
        Color(0.45, 0.75, 1.0),
        Color(0.9, 0.55, 1.0),
    ]
    for i in range(70):
        # NOTE (mristin):
        # A cheap hash gives every flake its own place, speed and phase.
        var seed_x := fposmod(sin(i * 12.9898) * 43758.5453, 1.0)
        var seed_v := fposmod(sin(i * 78.233) * 12345.678, 1.0)
        var speed := 90.0 + 120.0 * seed_v
        var y := fposmod(_panel_time * speed + seed_x * 1200.0, 1200.0) - 60.0
        var x := seed_x * 1920.0 + sin(_panel_time * 2.0 + i) * 30.0
        var angle := _panel_time * (2.0 + 3.0 * seed_v) + i
        var half := Vector2(9, 5).rotated(angle)
        var across := Vector2(-half.y, half.x)
        var at := Vector2(x, y)
        _panel.draw_colored_polygon(
            PackedVector2Array(
                [at - half - across, at + half - across, at + half + across, at - half + across]
            ),
            colors[i % colors.size()]
        )


func _draw_star(center: Vector2, radius: float, color: Color) -> void:
    var points := PackedVector2Array()
    for i in range(10):
        var a := -PI / 2 + i * PI / 5
        var r := radius if i % 2 == 0 else radius * 0.45
        points.append(center + Vector2(cos(a) * r, sin(a) * r))
    _panel.draw_colored_polygon(points, color)
