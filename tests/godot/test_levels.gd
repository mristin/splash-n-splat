extends SceneTree
## Play every level headless without a camera: every kind of critter of every
## level comes out, gets hit and counts, a critter throws, and every level has
## a place on the travel map.

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


func _run() -> void:
    _game = load("res://scenes/game/game.tscn").instantiate()
    _game.use_camera = false
    _game.auto_spawn = false
    root.add_child(_game)
    await _wait(0.2)

    # NOTE (mristin):
    # The test hits more critters than a level needs to be won.
    _game.rules.target_bears = 1000

    var names: Array[String] = []
    var map: TravelMap = _game.get_node("TravelMap")
    for index in range(_game.level_count()):
        _game.play_level(index)
        await _wait(0.1)
        var level_name := _game.get_level_name()
        names.append(level_name)
        _check(_game.get_spot_count() == 6, "%s has six hiding places" % level_name)
        _check(map.places.has(level_name), "%s is on the travel map" % level_name)

        # NOTE (mristin):
        # Enough critters, one after the other, so that every kind comes out.
        var kinds := {}
        for round in range(4):
            for spot in range(6):
                var critter := _game.spawn_bear(spot)
                if critter == null:
                    continue
                var look = critter.get("look")
                kinds[[critter.get_class(), critter.get_script(), look]] = true
            await _wait(0.5)
            var before := _game.rules.bears_hit
            for spot in range(6):
                _game.fire_at(_game.get_bear_head(spot))
                await _wait(0.25)
            _check(
                _game.rules.bears_hit == before + 6,
                (
                    "%s: all six critters of round %d get hit (%d)"
                    % [level_name, round, _game.rules.bears_hit - before]
                )
            )
            await _wait(1.3)
        # NOTE (mristin):
        # The North Pole has only the polar bears; every other level has more kinds.
        var expected := 1 if index == 0 else 2
        _check(kinds.size() >= expected, "%s has %d kinds of critters" % [level_name, kinds.size()])

        _check(_game.spawn_bear(4) != null, "%s: a critter appears" % level_name)
        var threw := false
        for i in range(600):
            if _game.get_incoming_count() > 0:
                threw = true
                break
            await process_frame
        _check(threw, "%s: an unhit critter throws a snowball" % level_name)
        await _wait(2.5)

    _check(names.size() == 14, "there are 14 levels, got %d" % names.size())
    _check(
        names.find("Ukraine") == names.find("Belarus") + 1,
        "Kyiv comes after Minsk, on the way to Moscow"
    )
    _check(names[0] == "The North Pole" and names[-1] == "Zurich", "from the North Pole to Zurich")
    _check(names.has("Kazakhstan"), "the journey goes through Kazakhstan")

    if _failures.is_empty():
        print("RESULT: OK")
        quit(0)
    else:
        print("RESULT: FAILED (%d)" % _failures.size())
        quit(1)
