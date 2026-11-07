class_name Game
extends Node2D

## Run the snowball shooting gallery: the title, the levels and the end screens.
##
## The critters of a level (the polar bears of the North Pole, the walruses
## and the seals of Greenland) pop up from behind their cover, get ready (a "!"
## bubble) and throw a snowball at the player, unless the player hits them first.
## In Greenland, orcas also leap out of the sea now and then, for bonus points.
##
## When the camera sees the heads of the players, the critters throw at a head
## (its outline shows on the screen), and the snowball only hits if a head is
## still there when it lands: a player who moves away dodges it. The player aims
## with an open hand and throws by making a fist; every hand of every player
## aims and throws on its own. An incoming snowball can be
## intercepted by hitting it; otherwise it splats on the screen and the snow piles
## up along the edges. A level is won after [member LevelRules.target_bears] hit
## critters and lost after [member LevelRules.max_hits] snowballs taken. A won
## level leads to the next one; after the last one, the game-finished screen
## celebrates the whole trip, and then the game starts over. Before
## every new world, a little plane flies there on an old map of the Arctic.
##
## Besides the critters, penguins walk and snowy owls fly across the screen and
## throw while they move; kittens stroll by, which the players must not hit (it
## costs energy); and balloons bring the boosters: rapid fire, big snowballs and
## health. The boosters do not last forever.
##
## The game is played with the hands only; Escape twice quits; --debug shows the debug
## overlay. The tests drive the game with [method fire_at] and inspect it with
## the public methods.

enum State { TITLE, TRAVELING, PLAYING, ENDED, FINISHED, UNPLAYABLE }

const _SCREEN := Vector2(1920, 1080)
const _QUIT_PROMPT_SECONDS := 3.0
## The game-finished screen ignores the fists for so long, so that the
## celebration is not skipped by the throws which the players are still making.
const _FINISHED_SECONDS := 15.0

## The hit area of a head is this much larger than its outline, so that a
## player has to really duck or step aside to dodge.
const _HEAD_HIT_FACTOR := 1.15
## How much farther a big snowball reaches than a normal one, in pixels.
const _BIG_SNOWBALL_REACH := 60.0
const _LEVEL_SCENES: Array[PackedScene] = [
    preload("res://scenes/winter_level/winter_level.tscn"),
    preload("res://scenes/greenland_level/greenland_level.tscn"),
]
## The scene of the winter countries after Greenland (see [Countries]).
const _COUNTRY_SCENE := preload("res://scenes/country_level/country_level.tscn")

## Use the webcam; the tests switch it off and drive the game themselves.
@export var use_camera := true

## Spawn the bears by themselves; the tests may spawn them by hand.
@export var auto_spawn := true

var rules := LevelRules.new()

## The penguins, the owls, the kittens and the balloons with the boosters.
var rovers := Rovers.new()
var state := State.TITLE

## The index of the current level: first the [constant _LEVEL_SCENES], then the
## countries of [Countries].
var level_index := 0

var _countries: Array[Dictionary] = Countries.all()

var _settings := GameSettings.new()
var _random := RandomNumberGenerator.new()
var _bears: Array[Critter] = []
var _orcas: Array[Orca] = []
var _incoming: Array[Snowball] = []
var _spawn_timer := 0.0
var _orca_timer := 0.0
var _won := false

## The totals of the won levels of the trip so far, for the game-finished screen.
var _trip_worlds := 0
var _trip_score := 0
var _trip_critters := 0
var _trip_intercepts := 0

## The index of the level which the plane flies to.
var _travel_to := 0

## The heads of the players in screen pixels; the tests set them by hand.
var _test_heads: Array[Rect2] = []
var _use_test_heads := false
var _state_time := 0.0
var _shake := 0.0
var _last_spot := -1
var _benchmark_time := 0.0
var _benchmark_fps: Array[float] = []
var _events: FileAccess = null
var _quit_prompt_left := 0.0
var _next_aim_log := 0.0

@onready var _vision: Node = $HandVisionService
@onready var _camera: Camera2D = $Camera
@onready var _level: Level = $Level
@onready var _projectiles: Node2D = $Projectiles
@onready var _snow: SnowAccumulationOverlay = $SnowOverlay
@onready var _aim: AimController = $AimLayer/Aim
@onready var _head_outlines: HeadOutlines = $AimLayer/HeadOutlines
@onready var _camera_overlay: CameraOverlay = $CameraOverlay
@onready var _hud: Hud = $Hud
@onready var _debug: DebugOverlay = $DebugOverlay
@onready var _sound: SoundBank = $Sound
@onready var _travel_map: TravelMap = $TravelMap


func _enter_tree() -> void:
    # NOTE (mristin):
    # We configure the vision service here, before its _ready runs.
    _settings = GameSettings.from_command_line()
    if _settings.seed_value >= 0:
        _random.seed = _settings.seed_value

    var vision := $HandVisionService
    vision.UseCamera = use_camera and _settings.use_camera
    vision.CameraIndex = _settings.camera_index
    vision.Mirror = _settings.mirror
    vision.VisionConfigPath = _settings.vision_config_path
    vision.RecordDir = _settings.record_play_dir


func _ready() -> void:
    if _settings.windowed:
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
        DisplayServer.window_set_size(Vector2i(1280, 720))

    _camera_overlay.setup(_vision)
    _aim.setup(_vision)
    _aim.fired.connect(_on_fired)
    _travel_map.landed.connect(func(): _load_level(_travel_to))
    _travel_map.arrived.connect(start_level)
    _hud.setup(rules, _vision)
    rovers.name = "Rovers"
    rovers.rules = rules
    rovers.random.seed = _random.randi()
    rovers.may_throw = func() -> bool: return get_incoming_count() < rules.max_incoming
    rovers.threw.connect(_throw_at_player)
    add_child(rovers)
    _debug.setup(_vision, _aim)
    _debug.visible = _settings.debug
    _load_level(clampi(_settings.level - 1, 0, level_count() - 1))
    _show_title()

    var record_path: String = _vision.GetRecordPath()
    if not record_path.is_empty():
        _events = FileAccess.open(record_path.path_join("events.jsonl"), FileAccess.WRITE)


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
        request_quit()


## Quit on the second Escape within a few seconds, so that a single unintended
## press does not end the game.
func request_quit() -> void:
    if _quit_prompt_left > 0.0:
        get_tree().quit()
        return
    _quit_prompt_left = _QUIT_PROMPT_SECONDS
    _hud.show_quit_prompt(true)


func _show_title() -> void:
    state = State.TITLE
    _state_time = 0.0
    _hud.set_playing(false)
    _hud.show_message(
        "Splash 'n' Splat",
        (
            "Polar bears, walruses, reindeer, foxes and many more animals are hiding "
            + "in the snow, from the North Pole to Astana! Hit them with a snowball "
            + "before they throw theirs at you."
            + "\n\nHold up an OPEN hand to aim, make a FIST to throw. When the ring "
            + "around your head glows orange, duck!"
            + "\n\nOpen your hand and make a fist to start!"
        )
    )


func level_count() -> int:
    return _LEVEL_SCENES.size() + _countries.size()


## Switch to the level at the index, unless it is already loaded.
func _load_level(index: int) -> void:
    var changed := index != level_index or _level == null
    level_index = index
    if changed:
        var position_in_tree := _level.get_index()
        remove_child(_level)
        _level.queue_free()
        if index < _LEVEL_SCENES.size():
            _level = _LEVEL_SCENES[index].instantiate()
        else:
            var country_level: CountryLevel = _COUNTRY_SCENE.instantiate()
            country_level.country = _countries[index - _LEVEL_SCENES.size()]
            _level = country_level
        _level.name = "Level"
        add_child(_level)
        move_child(_level, position_in_tree)
    _hud.set_critters_name(_level.critters_name)


func _start_trip() -> void:
    _trip_worlds = 0
    _trip_score = 0
    _trip_critters = 0
    _trip_intercepts = 0


## Celebrate the end of the trip after the last world, with the totals of all
## the won worlds.
func _show_game_finished() -> void:
    state = State.FINISHED
    _state_time = 0.0
    _sound.play(SoundBank.Sound.WIN)
    var worlds := "%d worlds" % _trip_worlds if _trip_worlds != 1 else "one world"
    _hud.set_playing(false)
    _hud.show_game_finished(
        "Our snowball trip is over!",
        (
            (
                (
                    "What a journey: from the North Pole across %s, all the way home to Zurich!"
                    + "\nYou hit %d critters, knocked %d snowballs out of the air "
                    + "and scored %d points."
                )
                % [worlds, _trip_critters, _trip_intercepts, _trip_score]
            )
            + "\n\nYou were quick, brave and a great team. Thank you for playing!"
            + "\n\nMake a fist to fly again!"
        )
    )


## Fly from a place on the map to the level at the index, then start it.
##
## NOTE (mristin):
## We switch to the level only when the plane has landed, while the map covers
## the screen, so that the next world does not show through the map before.
func _travel(from_place: String, to_index: int) -> void:
    state = State.TRAVELING
    _state_time = 0.0
    _travel_to = to_index
    _hud.set_playing(false)
    _hud.show_message("", "")
    var info := _level_info(to_index)
    _travel_map.fly(from_place, info[0], info[1])
    _sound.play(SoundBank.Sound.PLANE, -6.0)


## The name of the level after the current one, or "" after the last one.
func _next_level_name() -> String:
    if level_index + 1 >= level_count():
        return ""
    return _level_name(level_index + 1)


func _level_name(index: int) -> String:
    return _level_info(index)[0]


## The name and the intro of the level at the index.
func _level_info(index: int) -> Array[String]:
    if index == level_index:
        return [_level.display_name, _level.intro]
    if index >= _LEVEL_SCENES.size():
        var country: Dictionary = _countries[index - _LEVEL_SCENES.size()]
        return [country["name"], country["intro"]]
    var level: Level = _LEVEL_SCENES[index].instantiate()
    var info: Array[String] = [level.display_name, level.intro]
    level.free()
    return info


## Start (or restart) the level.
func start_level() -> void:
    for bear in _bears:
        if is_instance_valid(bear):
            bear.queue_free()
    for orca in _orcas:
        if is_instance_valid(orca):
            orca.queue_free()
    for child in _projectiles.get_children():
        child.queue_free()
    _bears.clear()
    _orcas.clear()
    _incoming.clear()
    for spot in _level.spots:
        spot.bear = null

    rules.reset()
    _snow.reset()
    _sound.stop(SoundBank.Sound.PLANE)
    state = State.PLAYING
    _state_time = 0.0
    _spawn_timer = 1.2
    _orca_timer = _next_orca_interval()
    rovers.level = _level
    rovers.reset()
    _hud.set_playing(true)
    _hud.show_message("", "")
    _sound.play(SoundBank.Sound.START)


func _process(delta: float) -> void:
    _state_time += delta
    if _settings.benchmark_seconds > 0:
        _run_benchmark(delta)
    _update_shake(delta)
    _log_aims()
    if _quit_prompt_left > 0.0:
        _quit_prompt_left -= delta
        if _quit_prompt_left <= 0.0:
            _hud.show_quit_prompt(false)
    _update_status()
    _update_heads()

    if state == State.TITLE and use_camera and _settings.use_camera and _vision.IsUnusable():
        state = State.UNPLAYABLE
        _hud.show_message(
            "Splash 'n' Splat", _vision.GetStatusMessage() + "\n\nPress Escape twice to quit."
        )

    _aim.big = state == State.PLAYING and rovers.has_boost(Booster.Kind.BIG_SNOWBALLS)
    if state != State.PLAYING:
        return

    _prune()
    rovers.update(delta, auto_spawn)
    _hud.set_boosts(rovers.shown_boosts())
    for hand_id in rovers.rapid_fire(delta, _aim.hands):
        _aim.fire(hand_id)

    if auto_spawn:
        _spawn_timer -= delta
        if _spawn_timer <= 0:
            if rules.may_spawn_bear(_bears.size(), _random.randf()):
                spawn_bear(-1)
            _spawn_timer = rules.spawn_interval() * (0.8 + 0.4 * _random.randf())

        if not _level.orca_lanes.is_empty():
            _orca_timer -= delta
            if _orca_timer <= 0 and _orcas.is_empty():
                spawn_orca(-1)
                _orca_timer = _next_orca_interval()

    if rules.outcome() != LevelRules.Outcome.PLAYING:
        _end_level(rules.outcome() == LevelRules.Outcome.WON)


## Play by itself, sample the render rate every second and report at the end.
func _run_benchmark(delta: float) -> void:
    var before := _benchmark_time
    _benchmark_time += delta
    if state != State.PLAYING:
        start_level()
    if int(_benchmark_time) > int(before) and _benchmark_time > 3.0:
        _benchmark_fps.append(Engine.get_frames_per_second())
        print(
            (
                "BENCHMARK t=%.0f s: %s"
                % [_benchmark_time, _vision.GetDebugText().replace("\n", " | ")]
            )
        )
    if _benchmark_time < _settings.benchmark_seconds:
        return

    var sorted := _benchmark_fps.duplicate()
    sorted.sort()
    if sorted.is_empty():
        sorted.append(0.0)
    print(
        (
            "BENCHMARK render fps: median %.1f, min %.1f over %d samples"
            % [sorted[sorted.size() / 2], sorted[0], sorted.size()]
        )
    )
    print("BENCHMARK vision: " + _vision.GetDebugText().replace("\n", " | "))
    get_tree().quit()


## Log an event of the gameplay for the automatic labeling of the recording.
func _log_event(event: Dictionary) -> void:
    if _events == null:
        return
    event["t"] = _vision.GetNow()
    event["state"] = State.keys()[state]
    _events.store_line(JSON.stringify(event))
    _events.flush()


## Log where every hand aims, and whether over a bear, ten times a second.
func _log_aims() -> void:
    if _events == null or _vision.GetNow() < _next_aim_log:
        return
    _next_aim_log = _vision.GetNow() + 0.1

    var hands := []
    for id in _aim.hands:
        var at: Vector2 = _aim.hands[id]["position"]
        var over_bear := false
        for bear in _bears:
            if is_instance_valid(bear) and bear.hit_test(at):
                over_bear = true
        hands.append({"hand_id": id, "x": at.x, "y": at.y, "over_bear": over_bear})
    _log_event({"type": "aims", "hands": hands})


## Forget the bears and the snowballs which are gone.
func _prune() -> void:
    var bears: Array[Critter] = []
    for bear in _bears:
        if is_instance_valid(bear) and bear.state != Critter.State.GONE:
            bears.append(bear)
    _bears = bears

    var orcas: Array[Orca] = []
    for orca in _orcas:
        if is_instance_valid(orca) and orca.state != Orca.State.GONE:
            orcas.append(orca)
    _orcas = orcas

    var incoming: Array[Snowball] = []
    for snowball in _incoming:
        if is_instance_valid(snowball) and not snowball.is_done:
            incoming.append(snowball)
    _incoming = incoming


func _update_status() -> void:
    var status := ""
    if not _vision.IsRunning():
        status = _vision.GetStatusMessage()
    elif not _aim.has_hands():
        status = "Show me your hands!"
    _hud.set_status(status)


func _end_level(won: bool) -> void:
    state = State.ENDED
    _state_time = 0.0
    _won = won
    for snowball in _incoming:
        if is_instance_valid(snowball):
            snowball.pop()
    _incoming.clear()
    var challenge_change := rules.adapt_challenge()
    if won:
        _trip_worlds += 1
        _trip_score += rules.score
        _trip_critters += rules.bears_hit
        _trip_intercepts += rules.intercepts

    _sound.play(SoundBank.Sound.WIN if won else SoundBank.Sound.LOSE)
    if not won:
        _hud.show_level_finished(
            _level.lost_title,
            (
                (
                    "%s\n\nScore %d  ·  %s hit: %d"
                    % [_level.lost_message, rules.score, _level.critters_name, rules.bears_hit]
                )
                + "\n\nOpen your hand and make a fist to try again!"
            ),
            0
        )
        return

    var stats := (
        "Score %d  ·  Energy left %d%%  ·  Snowballs knocked out: %d"
        % [rules.score, roundi(rules.energy() * 100), rules.intercepts]
    )
    if rules.dodges > 0:
        stats += "  ·  Dodged: %d" % rules.dodges
    if not _level.orca_lanes.is_empty():
        stats += "  ·  Orcas: %d" % rules.orcas_hit
    if challenge_change > 0:
        stats += "\n\nThat was too easy! More critters come out at once in the next world."
    var next_name := _next_level_name()
    var next := (
        "Next: %s!\nOpen your hand and make a fist to go on!" % next_name
        if not next_name.is_empty()
        else "That was the last world!\nOpen your hand and make a fist!"
    )
    _hud.show_level_finished(
        "Well done!", _level.won_message + "\n\n" + stats + "\n\n" + next, rules.stars()
    )


## Spawn a critter of the level at the given spot, or at a random free one for -1.
## Return the critter, or null if the spot is taken.
func spawn_bear(spot_index: int) -> Critter:
    var free: Array[int] = []
    for i in range(_level.spots.size()):
        if _level.spots[i].is_free():
            free.append(i)

    if spot_index < 0:
        if free.is_empty():
            return null
        var candidates: Array[int] = []
        for i in free:
            if i != _last_spot:
                candidates.append(i)
        if candidates.is_empty():
            candidates = free
        spot_index = candidates[_random.randi() % candidates.size()]
    elif not spot_index in free:
        return null

    _last_spot = spot_index
    var spot: CoverSpot = _level.spots[spot_index]
    var bear := _level.make_critter(_random)
    bear.spot = spot
    bear.exposure_seconds = rules.exposure_seconds() * (0.85 + 0.3 * _random.randf())
    bear.may_throw = func() -> bool: return get_incoming_count() < rules.max_incoming
    bear.threw.connect(_on_bear_threw)
    bear.finished.connect(func(_b: Critter): spot.bear = null)
    spot.bear = bear
    spot.bear_slot.add_child(bear)
    _bears.append(bear)
    return bear


func _next_orca_interval() -> float:
    return _random.randf_range(rules.min_orca_interval, rules.max_orca_interval)


## Let an orca leap in the lane of the level, or in a random one for -1.
## Return the orca, or null if the level has no orcas.
func spawn_orca(lane_index: int) -> Orca:
    var lanes := _level.orca_lanes
    if lanes.is_empty():
        return null
    if lane_index < 0:
        lane_index = _random.randi() % lanes.size()
    var lane: Array = lanes[lane_index]

    var orca := Orca.new()
    orca.from_x = lane[0]
    orca.to_x = lane[1]
    orca.water_y = lane[2]
    orca.size = lane[3]
    orca.height = 330.0 * orca.size
    orca.theme = _level.theme
    _level.add_child(orca)
    _orcas.append(orca)
    return orca


func _on_bear_threw(bear: Critter, paw: Vector2) -> void:
    _throw_at_player(paw, bear.spot.scale.x)


## Throw a snowball from the paw at a head of a player (or at a random spot).
func _throw_at_player(paw: Vector2, start_scale: float) -> void:
    if state != State.PLAYING:
        return
    rules.register_throw()

    var snowball := Snowball.new()
    snowball.heading = Snowball.Heading.TOWARD_PLAYER
    snowball.style = _level.theme.projectile
    snowball.start = paw
    var heads := get_heads()
    var at_head := not heads.is_empty()
    if at_head:
        # NOTE (mristin):
        # Every player gets their turn: the critter picks a random head.
        snowball.target = heads[_random.randi() % heads.size()].get_center()
    else:
        snowball.target = Vector2(
            _SCREEN.x * (0.25 + 0.5 * _random.randf()), _SCREEN.y * (0.3 + 0.4 * _random.randf())
        )
    snowball.flight_seconds = rules.flight_seconds()
    snowball.start_radius = 18.0 * start_scale
    snowball.end_radius = 170.0
    snowball.arc_height = 140.0
    snowball.set_meta("at_head", at_head)
    snowball.arrived.connect(_on_snowball_arrived)
    _projectiles.add_child(snowball)
    _incoming.append(snowball)
    _sound.play(SoundBank.Sound.THROW, -4.0)


## Hit the player, unless the snowball flew at a head which has moved away.
func _on_snowball_arrived(snowball: Snowball) -> void:
    if state != State.PLAYING:
        return
    if not snowball.get_meta("at_head", false):
        _on_player_hit(snowball.target)
        return

    # NOTE (mristin):
    # A head which the camera lost (e.g., the player ducked out of the picture)
    # dodged, too.
    for head in get_heads():
        if HeadOutlines.head_contains(head, snowball.target, 30.0, _HEAD_HIT_FACTOR):
            _on_player_hit(snowball.target)
            return

    var points := rules.register_dodge()
    _add_splat(snowball.target, 60.0)
    _show_points(snowball.target + Vector2(0, -40), points, "Dodged! +%d")
    _sound.play(SoundBank.Sound.THROW, -2.0)
    _log_event({"type": "dodge", "x": snowball.target.x, "y": snowball.target.y})


func _update_heads() -> void:
    _head_outlines.heads = get_heads()
    var threats: Array[Vector2] = []
    for snowball in _incoming:
        if (
            is_instance_valid(snowball)
            and not snowball.is_done
            and snowball.get_meta("at_head", false)
        ):
            threats.append(snowball.target)
    _head_outlines.threats = threats
    _head_outlines.visible = state == State.PLAYING


## The heads of the players in screen pixels.
func get_heads() -> Array[Rect2]:
    if _use_test_heads:
        return _test_heads
    var heads: Array[Rect2] = []
    if not (use_camera and _settings.use_camera):
        return heads
    for head: Rect2 in _vision.GetHeads():
        heads.append(Rect2(head.position * _SCREEN, head.size * _SCREEN))
    return heads


## Put the heads of the players at the given screen rectangles (for the tests).
func set_test_heads(heads: Array[Rect2]) -> void:
    _use_test_heads = true
    _test_heads = heads


func _on_player_hit(at: Vector2) -> void:
    if state != State.PLAYING:
        return
    rules.register_player_hit()
    _snow.add_hit(at)
    _shake = 1.0
    _sound.play(SoundBank.Sound.PLAYER_HIT)


func _on_fired(at: Vector2, hand_id: int) -> void:
    match state:
        State.TITLE:
            _start_trip()
            _travel("Zurich", level_index)
        # NOTE (mristin):
        # The fists do not skip the flight: the players keep throwing from the
        # level before, and the flight would end after a second or two.
        State.ENDED:
            if _state_time > 1.5:
                if not _won:
                    start_level()
                elif level_index + 1 >= level_count():
                    _show_game_finished()
                else:
                    _travel(_level.display_name, level_index + 1)
        State.FINISHED:
            if _state_time > _FINISHED_SECONDS:
                _start_trip()
                _travel(_level.display_name, 0)
        State.PLAYING:
            _log_event({"type": "shot", "hand_id": hand_id, "x": at.x, "y": at.y})
            _throw_at(at, hand_id)


func _throw_at(at: Vector2, hand_id: int) -> void:
    var snowball := Snowball.new()
    snowball.heading = Snowball.Heading.AWAY_FROM_PLAYER
    snowball.style = _level.theme.projectile
    snowball.start = Vector2(_SCREEN.x * 0.5 + (at.x - _SCREEN.x * 0.5) * 0.3, _SCREEN.y + 60)
    snowball.target = at
    snowball.flight_seconds = 0.2
    var big := rovers.has_boost(Booster.Kind.BIG_SNOWBALLS)
    snowball.start_radius = 80.0 if big else 48.0
    snowball.end_radius = 30.0 if big else 14.0
    snowball.arc_height = 60.0
    snowball.arrived.connect(func(s: Snowball): _resolve(s.target, hand_id))
    _projectiles.add_child(snowball)
    _sound.play(SoundBank.Sound.THROW, -8.0)


## Find out what the player's snowball hit at the position.
func _resolve(at: Vector2, hand_id: int = -1) -> void:
    if state != State.PLAYING:
        return

    var reach := (
        45.0 + (_BIG_SNOWBALL_REACH if rovers.has_boost(Booster.Kind.BIG_SNOWBALLS) else 0.0)
    )
    for snowball in _incoming:
        if is_instance_valid(snowball) and snowball.hit_test(at, reach):
            rules.register_intercept()
            _add_splat(snowball.position, snowball.radius * 1.3)
            _show_points(snowball.position, rules.points_per_intercept)
            snowball.pop()
            _incoming.erase(snowball)
            _sound.play(SoundBank.Sound.POP)
            _log_event({"type": "result", "hand_id": hand_id, "what": "snowball"})
            return

    # NOTE (mristin):
    # The walkers walk in front of everything, so they take the hit first.
    var hit_rover := rovers.hit_test(at, reach)
    if hit_rover != null and hit_rover.hit():
        _on_rover_hit(hit_rover, at, hand_id)
        return

    # NOTE (mristin):
    # The nearest bears are in front, so they take the hit first.
    var hit_bear: Critter = null
    for bear in _bears:
        if is_instance_valid(bear) and bear.hit_test(at, reach):
            if hit_bear == null or bear.spot.z_index > hit_bear.spot.z_index:
                hit_bear = bear

    if hit_bear != null and hit_bear.hit():
        var points := rules.register_bear_hit(hit_bear.exposed_time, hit_bear.exposure_seconds)
        _add_splat(at, 70.0 * hit_bear.spot.scale.x)
        _show_points(
            hit_bear.head_global_position() + Vector2(0, -90 * hit_bear.spot.scale.y), points
        )
        _sound.play(SoundBank.Sound.BOING)
        _log_event({"type": "result", "hand_id": hand_id, "what": "bear"})
        _sound.play(SoundBank.Sound.SPLAT, -6.0)
        return

    for orca in _orcas:
        if is_instance_valid(orca) and orca.hit_test(at, reach) and orca.hit():
            var points := rules.register_orca_hit()
            _add_splat(at, 70.0 * orca.size)
            _show_points(orca.center_global_position() + Vector2(0, -90 * orca.size), points)
            _sound.play(SoundBank.Sound.BOING)
            _sound.play(SoundBank.Sound.SPLAT, -6.0)
            _log_event({"type": "result", "hand_id": hand_id, "what": "orca"})
            return

    _log_event({"type": "result", "hand_id": hand_id, "what": "miss"})
    _add_splat(at, 64.0 if rovers.has_boost(Booster.Kind.BIG_SNOWBALLS) else 32.0)
    _sound.play(SoundBank.Sound.SPLAT, -10.0)


## Score, punish or collect what the player's snowball hit at the position.
func _on_rover_hit(rover: Rover, at: Vector2, hand_id: int) -> void:
    _add_splat(at, 60.0 * rover.size)
    var above := rover.center_global_position() + Vector2(0, -260 * rover.size)
    if rover is Kitten:
        # NOTE (mristin):
        # The kitten is no target: it cries, and the players lose energy.
        rules.register_kitten_hit()
        _shake = 0.6
        _sound.play(SoundBank.Sound.MEOW)
        _show_points(above, 0, "Oh no, a kitten!")
        _log_event({"type": "result", "hand_id": hand_id, "what": "kitten"})
    elif rover is Booster:
        var kind: Booster.Kind = (rover as Booster).kind
        rovers.collect(kind)
        _sound.play(SoundBank.Sound.POWER_UP)
        var message := Booster.name_of(kind)
        if Booster.hint_of(kind) != "":
            message += "\n" + Booster.hint_of(kind)
        _show_points(rover.center_global_position() + Vector2(0, -230), 0, message)
        _log_event({"type": "result", "hand_id": hand_id, "what": "booster"})
    else:
        var points := rules.register_thrower_hit()
        _show_points(above, points)
        _sound.play(SoundBank.Sound.BOING)
        _sound.play(SoundBank.Sound.SPLAT, -6.0)
        _log_event({"type": "result", "hand_id": hand_id, "what": "thrower"})


func _add_splat(at: Vector2, size: float) -> void:
    var splat := Splat.new()
    splat.position = at
    splat.size = size
    splat.style = _level.theme.projectile
    _projectiles.add_child(splat)


func _show_points(at: Vector2, points: int, text: String = "+%d") -> void:
    var label := Label.new()
    label.text = text % points if "%" in text else text
    var lines := label.text.count("\n") + 1
    label.position = at - Vector2(200, 30 * lines)
    label.size = Vector2(400, 60 * lines)
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.z_index = 700
    label.add_theme_font_size_override("font_size", 44)
    label.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
    label.add_theme_color_override("font_outline_color", Color(0.15, 0.25, 0.5))
    label.add_theme_constant_override("outline_size", 12)
    _projectiles.add_child(label)

    var tween := label.create_tween()
    tween.tween_property(label, "position", label.position + Vector2(0, -70), 0.8)
    tween.parallel().tween_property(label, "modulate:a", 0.0, 0.8)
    tween.tween_callback(label.queue_free)


func _update_shake(delta: float) -> void:
    _shake = maxf(0.0, _shake - delta * 2.5)
    var amount := 16.0 * _shake * _shake
    _camera.offset = Vector2(_random.randf_range(-1, 1), _random.randf_range(-1, 1)) * amount


# NOTE (mristin):
# The methods below drive and inspect the game in the automatic tests (tests/godot/).


## Aim at the viewport position and throw.
func fire_at(at: Vector2) -> void:
    _aim.aim_at(at)
    _aim.fire(-1)


func is_quit_prompt_shown() -> bool:
    return _quit_prompt_left > 0.0


func get_incoming_count() -> int:
    var count := 0
    for snowball in _incoming:
        if is_instance_valid(snowball) and not snowball.is_done:
            count += 1
    return count


func get_spot_count() -> int:
    return _level.spots.size()


func get_snow() -> SnowAccumulation:
    return _snow.snow


## The head of the bear at the spot, or (-1, -1) if there is none.
func get_bear_head(spot_index: int) -> Vector2:
    var bear: Critter = _level.spots[spot_index].bear
    return (
        bear.head_global_position() if bear != null and is_instance_valid(bear) else Vector2(-1, -1)
    )


## The position of the first incoming snowball, or (-1, -1).
func get_incoming_position() -> Vector2:
    for snowball in _incoming:
        if is_instance_valid(snowball) and not snowball.is_done:
            return snowball.position
    return Vector2(-1, -1)


func take_hits(count: int) -> void:
    for i in range(count):
        _on_player_hit(Vector2(200 + 300 * i, 300))


## The center of the first orca out of the water, or (-1, -1).
func get_orca_position() -> Vector2:
    for orca in _orcas:
        if is_instance_valid(orca) and orca.is_targetable():
            return orca.center_global_position()
    return Vector2(-1, -1)


func get_level_name() -> String:
    return _level.display_name


func get_hud() -> Hud:
    return _hud


## Switch to the level at the index and start it at once, without a flight.
func play_level(index: int) -> void:
    _load_level(index)
    start_level()


## The target of the first incoming snowball, or (-1, -1).
func get_incoming_target() -> Vector2:
    for snowball in _incoming:
        if is_instance_valid(snowball) and not snowball.is_done:
            return snowball.target
    return Vector2(-1, -1)
