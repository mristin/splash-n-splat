extends SceneTree
## Play a level headless with the rovers: a penguin and an owl throw while they
## move and can be hit for bonus points, a hit kitten cries and costs energy,
## and the boosters (rapid fire, big snowballs, health) are collected by a hit
## and do not last forever.

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


## Wait until the rover is well on the screen, then hit it.
func _hit(rover: Rover) -> void:
    await _wait_until(func(): return rover.aim_point().x > 500 and rover.aim_point().x < 1420, 6.0)
    _game.fire_at(rover.aim_point())
    await _wait(0.3)


func _run() -> void:
    _game = load("res://scenes/game/game.tscn").instantiate() as Game
    _game.use_camera = false
    _game.auto_spawn = false
    root.add_child(_game)
    await _wait(0.2)
    _game.play_level(0)
    _game.rules.target_bears = 1000
    await _wait(0.2)

    var rovers := _game.rovers
    var penguin := rovers.spawn("penguin")
    _check(penguin is Penguin, "a penguin walks in")
    _check(rovers.spawn("kitten") == null, "only one walker at a time")
    var threw: bool = await _wait_until(func(): return _game.get_incoming_count() > 0, 8.0)
    _check(threw, "the penguin throws a snowball while it walks")
    var at := penguin.center_global_position()
    await _wait(0.5)
    _check(penguin.center_global_position().x != at.x, "the penguin keeps walking after the throw")
    var score := _game.rules.score
    await _hit(penguin)
    _check(_game.rules.score == score + _game.rules.points_per_thrower, "a hit penguin scores")
    _check(_game.rules.bears_hit == 0, "a penguin is a bonus, not a critter to go")
    await _wait_until(func(): return rovers.list.is_empty(), 8.0)

    var owl := rovers.spawn("owl")
    _check(owl is SnowyOwl, "a snowy owl flies in")
    _check(owl.center_global_position().y < 400, "the owl flies in the sky")
    # NOTE (mristin):
    # The owl must not throw here: our shot would intercept its snowball first.
    (owl as Thrower).throws_left = 0
    await _hit(owl)
    _check(owl.state == Rover.State.HIT, "the owl can be hit")

    var kitten := rovers.spawn("kitten")
    _check(kitten is Kitten, "a kitten strolls in while the owl flies")
    var hits_taken := _game.rules.hits_taken
    await _hit(kitten)
    _check((kitten as Kitten).is_crying(), "a hit kitten cries")
    _check(_game.rules.hits_taken == hits_taken + 1, "a hit kitten costs energy")
    var crying_at := kitten.center_global_position()
    await _wait(0.5)
    _check(kitten.center_global_position().x == crying_at.x, "the kitten sits while it cries")
    await _wait_until(func(): return rovers.list.is_empty(), 8.0)

    var big := rovers.spawn("big")
    _check(big is Booster, "a balloon brings a booster")
    await _hit(big)
    _check(rovers.has_boost(Booster.Kind.BIG_SNOWBALLS), "a hit balloon gives the booster")
    _check(_game.get_hud().visible, "the HUD shows")

    # NOTE (mristin):
    # A big snowball reaches farther: a shot beside the bear hits it.
    _check(_game.spawn_bear(5) != null, "a bear appears")
    await _wait(0.5)
    var bears_hit := _game.rules.bears_hit
    _game.fire_at(_game.get_bear_head(5) + Vector2(150, 0))
    await _wait(0.4)
    _check(_game.rules.bears_hit == bears_hit + 1, "a big snowball hits more easily")

    await _wait(_game.rules.boost_seconds)
    _check(not rovers.has_boost(Booster.Kind.BIG_SNOWBALLS), "the booster does not last forever")
    await _wait_until(func(): return rovers.list.is_empty(), 8.0)

    _game.take_hits(4)
    hits_taken = _game.rules.hits_taken
    var health := rovers.spawn("health")
    await _hit(health)
    _check(
        _game.rules.hits_taken == hits_taken - _game.rules.heal_hits,
        "the health booster gives energy back"
    )
    await _wait_until(func(): return rovers.list.is_empty(), 8.0)

    var rapid := rovers.spawn("rapid")
    await _hit(rapid)
    _check(rovers.has_boost(Booster.Kind.RAPID_FIRE), "a balloon gives rapid fire")
    var hands := {7: {"gesture": "fist"}}
    var throws := 0
    for i in range(60):
        throws += rovers.rapid_fire(1.0 / 60.0, hands).size()
    _check(throws >= 4, "a held fist throws again and again under rapid fire, got %d" % throws)
    _check(
        rovers.rapid_fire(1.0, {7: {"gesture": "open"}}).is_empty(), "an open hand does not throw"
    )

    if _failures.is_empty():
        print("RESULT: OK")
        quit(0)
    else:
        print("RESULT: FAILED (%d)" % _failures.size())
        quit(1)
