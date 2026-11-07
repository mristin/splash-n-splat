extends SceneTree
## Play the game headless without a camera: start, hit bears, miss, intercept
## a snowball, take hits until snowed in, restart, win, go on to Greenland, hit
## a walrus or a seal and an orca, win again and start over; the flights on the
## travel map in between.

var _failures: Array[String] = []
var _game: Game


func _check(condition: bool, message: String) -> void:
    if condition:
        print("PASS ", message)
    else:
        print("FAIL ", message)
        _failures.append(message)


func _initialize() -> void:
    _run.call_deferred()


func _wait(seconds: float) -> void:
    await create_timer(seconds).timeout


func _wait_until(condition: Callable, timeout: float) -> bool:
    var waited := 0.0
    while waited < timeout:
        if condition.call():
            return true
        await process_frame
        waited += 1.0 / 60.0
    return condition.call()


func _game_seconds() -> float:
    return Engine.get_process_frames() / 60.0


func _hit_bear(spot: int) -> void:
    _check(_game.spawn_bear(spot) != null, "a bear appears at spot %d" % spot)
    await _wait(0.5)
    _game.fire_at(_game.get_bear_head(spot))
    await _wait(0.4)


func _run() -> void:
    var wall_start := Time.get_ticks_msec()
    var game_start := _game_seconds()
    _game = load("res://scenes/game/game.tscn").instantiate() as Game
    _game.use_camera = false
    _game.auto_spawn = false
    root.add_child(_game)
    await _wait(0.2)

    _check(_game.state == Game.State.TITLE, "the game starts with the title")

    _game.request_quit()
    _check(_game.is_quit_prompt_shown(), "the first Escape only asks to press it again")
    await _wait(3.5)
    _check(not _game.is_quit_prompt_shown(), "the quit prompt goes away by itself")

    _game.fire_at(Vector2(960, 540))
    await _wait(0.1)
    _check(_game.state == Game.State.TRAVELING, "a shot on the title starts the flight")
    _check(_game.get_node("TravelMap").is_flying(), "the travel map shows the flight")
    for i in range(8):
        await _wait(1.0)
        _game.fire_at(Vector2(960, 540))
    await _wait(0.1)
    _check(_game.state == Game.State.TRAVELING, "the shots do not skip the flight")
    var started: bool = await _wait_until(func(): return _game.state == Game.State.PLAYING, 5.0)
    _check(started, "the plane lands and the level starts")
    _check(not _game.get_node("TravelMap").is_flying(), "the travel map is gone")
    _check(_game.rules.score == 0, "the score starts at zero")

    await _hit_bear(5)
    _check(_game.rules.bears_hit == 1, "hitting a bear counts")
    var score: int = _game.rules.score
    _check(score >= 100, "hitting a bear scores at least 100, got %d" % score)

    _game.fire_at(Vector2(960, 120))
    await _wait(0.4)
    _check(_game.rules.bears_hit == 1, "a shot into the sky hits nothing")

    _check(_game.spawn_bear(1) != null, "a far bear appears")
    var threw: bool = await _wait_until(func(): return _game.get_incoming_count() > 0, 9.0)
    _check(threw, "an unhit bear throws a snowball")
    await _wait(0.4)
    _game.fire_at(_game.get_incoming_position())
    await _wait(0.4)
    _check(_game.get_incoming_count() == 0, "the snowball is intercepted")
    _check(_game.rules.score == score + 25, "intercepting scores 25")
    _check(_game.rules.hits_taken == 0, "an intercepted snowball does not hit")

    _check(_game.spawn_bear(2) != null, "another bear appears")
    await _wait_until(func(): return _game.get_incoming_count() > 0, 9.0)
    var hit: bool = await _wait_until(func(): return _game.rules.hits_taken == 1, 4.0)
    _check(hit, "a snowball which is not intercepted hits the player")
    _check(_game.get_snow().visible_width() < 1.0, "the hit leaves snow on the screen")

    # NOTE (mristin):
    # With a head in the picture, the critters throw at it, and a head which
    # moves away dodges.
    var head := Rect2(860, 300, 200, 240)
    _game.set_test_heads([head])
    _check(_game.spawn_bear(0) != null, "a bear appears to throw at the head")
    var aimed: bool = await _wait_until(func(): return _game.get_incoming_count() > 0, 9.0)
    _check(aimed, "the bear throws at the head")
    _check(
        _game.get_incoming_target().distance_to(head.get_center()) < 1.0,
        "the snowball flies at the center of the head"
    )
    _game.set_test_heads([Rect2(200, 300, 200, 240)])
    var hits: int = _game.rules.hits_taken
    var dodged: bool = await _wait_until(func(): return _game.rules.dodges == 1, 4.0)
    _check(dodged, "a head which moves away dodges the snowball")
    _check(_game.rules.hits_taken == hits, "a dodged snowball does not hit")

    _game.set_test_heads([head])
    _check(_game.spawn_bear(2) != null, "another bear appears to throw at the head")
    await _wait_until(func(): return _game.get_incoming_count() > 0, 9.0)
    # NOTE (mristin):
    # The hit area is 15% larger than the outline: moving a little is not enough.
    _game.set_test_heads([Rect2(head.position + Vector2(150, 0), head.size)])
    var stayed: bool = await _wait_until(func(): return _game.rules.hits_taken == hits + 1, 4.0)
    _check(stayed, "a head which moves only a little is still hit")
    var empty: Array[Rect2] = []
    _game.set_test_heads(empty)

    _game.take_hits(_game.rules.max_hits)
    await _wait(0.2)
    _check(_game.state == Game.State.ENDED, "running out of energy ends the level")
    _check(
        _game.get_snow().visible_width() >= _game.get_snow().min_visible_fraction() - 0.001,
        "the snow never covers the whole width"
    )
    _check(
        _game.get_snow().visible_height() >= _game.get_snow().min_visible_fraction() - 0.001,
        "the snow never covers the whole height"
    )

    _game.fire_at(Vector2(960, 540))
    await _wait(0.2)
    _check(_game.state == Game.State.ENDED, "the end screen ignores a too early shot")
    await _wait(1.5)
    _game.fire_at(Vector2(960, 540))
    await _wait(0.2)
    _check(_game.state == Game.State.PLAYING, "a shot on the end screen restarts")
    _check(_game.rules.hits_taken == 0 and _game.rules.score == 0, "the restart resets the score")
    _check(_game.get_snow().visible_width() == 1.0, "the restart clears the snow")

    _game.rules.target_bears = 2
    await _hit_bear(5)
    await _hit_bear(4)
    await _wait(0.2)
    _check(_game.state == Game.State.ENDED, "hitting enough bears wins")
    _check(_game.get_hud().is_level_finished_shown(), "a won level shows the level-finished screen")

    await _wait(1.5)
    _game.fire_at(Vector2(960, 540))
    await _wait(0.2)
    _check(_game.state == Game.State.TRAVELING, "a shot on the level-finished screen flies on")
    await _wait(3.0)
    _check(
        _game.get_level_name() == "The North Pole",
        "the next world does not show through the map before the plane lands"
    )
    var landed: bool = await _wait_until(func(): return _game.state == Game.State.PLAYING, 10.0)
    _check(landed, "the plane lands by itself and the next level starts")
    _check(_game.level_index == 1, "the next level comes after a won level")
    _check(_game.get_level_name() == "Greenland", "the second level is Greenland")
    _check(_game.get_spot_count() == 6, "Greenland has six hiding places")
    _check(_game.rules.score == 0, "the next level starts with a new score")

    await _hit_bear(3)
    _check(_game.rules.bears_hit == 1, "hitting a walrus or a seal counts")

    _check(_game.spawn_orca(0) != null, "an orca leaps")
    var out: bool = await _wait_until(func(): return _game.get_orca_position().x >= 0, 3.0)
    _check(out, "the orca comes out of the water")
    await _wait(0.3)
    _game.fire_at(_game.get_orca_position())
    await _wait(0.3)
    _check(_game.rules.orcas_hit == 1, "hitting an orca counts")
    _check(_game.rules.bears_hit == 1, "an orca is a bonus, not a critter to go")

    _game.rules.target_bears = 2
    await _hit_bear(4)
    await _wait(0.2)
    _check(_game.state == Game.State.ENDED, "hitting enough critters wins Greenland")
    await _wait(1.5)
    _game.fire_at(Vector2(960, 540))
    await _wait_until(func(): return _game.state == Game.State.PLAYING, 12.0)
    _check(_game.level_index == 2, "Iceland comes after Greenland")
    _check(_game.get_level_name() == "Iceland", "the third level is Iceland")

    _game.play_level(_game.level_count() - 1)
    _check(_game.get_level_name() == "Zurich", "the last level is Zurich")
    _game.rules.target_bears = 1
    await _hit_bear(0)
    await _wait(0.2)
    _check(_game.state == Game.State.ENDED, "hitting enough foxes wins Zurich")
    await _wait(1.5)
    _game.fire_at(Vector2(960, 540))
    await _wait(0.2)
    _check(_game.state == Game.State.FINISHED, "after the last world, the trip is over")
    _check(_game.get_hud().is_game_finished_shown(), "the game-finished screen shows")
    _game.fire_at(Vector2(960, 540))
    await _wait(0.2)
    _check(_game.state == Game.State.FINISHED, "the game-finished screen ignores a too early shot")
    await _wait(10.0)
    _game.fire_at(Vector2(960, 540))
    await _wait(0.2)
    _check(_game.state == Game.State.FINISHED, "the game-finished screen stays for a while")
    await _wait(5.0)
    _game.fire_at(Vector2(960, 540))
    await _wait(0.2)
    _check(_game.state == Game.State.TRAVELING, "the plane flies back to the North Pole")
    await _wait_until(func(): return _game.state == Game.State.PLAYING, 12.0)
    _check(_game.level_index == 0, "after the last level, the game starts over")

    var wall := (Time.get_ticks_msec() - wall_start) / 1000.0
    var simulated := _game_seconds() - game_start
    print(
        (
            "Simulated %.1f s of play in %.1f s (%.0fx real time)"
            % [simulated, wall, simulated / maxf(wall, 0.001)]
        )
    )

    if _failures.is_empty():
        print("RESULT: OK")
        quit(0)
    else:
        print("RESULT: FAILED (%d)" % _failures.size())
        quit(1)
