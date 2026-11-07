extends SceneTree
## Check the bounds of the snow on the screen and the rules of the level.

var _failures: Array[String] = []


func _check(condition: bool, message: String) -> void:
    if condition:
        print("PASS ", message)
    else:
        print("FAIL ", message)
        _failures.append(message)


func _initialize() -> void:
    _test_snow_starts_clear()
    _test_hit_adds_snow_nearest_to_impact()
    _test_snow_never_covers_the_screen()
    _test_lumps_stay_in_bands()
    _test_reset()
    _test_win_and_loss()
    _test_quick_hits_score_more()
    _test_difficulty_rises_but_stays_fair()
    _test_difficulty_adapts_to_the_player()

    if _failures.is_empty():
        print("RESULT: OK")
        quit(0)
    else:
        print("RESULT: FAILED (%d)" % _failures.size())
        quit(1)


func _test_snow_starts_clear() -> void:
    var snow := SnowAccumulation.new()
    _check(snow.visible_width() == 1.0 and snow.visible_height() == 1.0, "the screen starts clear")
    _check(snow.blobs.is_empty(), "there are no lumps at the start")


func _test_hit_adds_snow_nearest_to_impact() -> void:
    var snow := SnowAccumulation.new()
    snow.add_hit(0.05, 0.5)
    _check(
        snow.left > snow.right and snow.left > snow.top, "a hit on the left frosts the left most"
    )
    _check(snow.blobs.size() == 1, "a hit sticks a lump")
    _check(snow.blobs[0].x <= snow.left + 1e-6, "the lump lies in the left band")


func _test_snow_never_covers_the_screen() -> void:
    var snow := SnowAccumulation.new()
    var random := RandomNumberGenerator.new()
    random.seed = 3
    var ok := true
    for i in range(500):
        snow.add_hit(random.randf() * 1.4 - 0.2, random.randf() * 1.4 - 0.2)
        for edge in [snow.left, snow.right, snow.top, snow.bottom]:
            ok = ok and edge >= 0.0 and edge <= snow.max_edge_fraction
        ok = ok and snow.visible_width() >= snow.min_visible_fraction() - 1e-6
        ok = ok and snow.visible_height() >= snow.min_visible_fraction() - 1e-6
        ok = ok and snow.blobs.size() <= snow.max_blobs
    _check(ok, "500 hits never cover more than the edge bands")
    _check(snow.min_visible_fraction() > 0.4, "more than 40% of the screen always stays clear")


func _test_lumps_stay_in_bands() -> void:
    var snow := SnowAccumulation.new(5)
    var random := RandomNumberGenerator.new()
    random.seed = 5
    for i in range(40):
        snow.add_hit(random.randf(), random.randf())
    var ok := true
    var band := snow.max_edge_fraction
    for blob in snow.blobs:
        ok = (
            ok
            and (blob.x <= band or blob.x >= 1.0 - band or blob.y <= band or blob.y >= 1.0 - band)
        )
    _check(ok, "the lumps stay out of the clear center")


func _test_reset() -> void:
    var snow := SnowAccumulation.new()
    snow.add_hit(0.1, 0.1)
    snow.reset()
    _check(snow.hits == 0 and snow.visible_width() == 1.0 and snow.blobs.is_empty(), "reset clears")


func _test_win_and_loss() -> void:
    var rules := LevelRules.new()
    rules.target_bears = 3
    for i in range(3):
        rules.register_bear_hit(1.0, 2.0)
    _check(rules.outcome() == LevelRules.Outcome.WON, "hitting enough bears wins")
    _check(rules.register_bear_hit(0.1, 2.0) == 0, "no points after the end")

    rules = LevelRules.new()
    rules.max_hits = 2
    rules.register_player_hit()
    _check(rules.outcome() == LevelRules.Outcome.PLAYING, "one hit does not lose")
    _check(is_equal_approx(rules.energy(), 0.5), "a snowball costs a share of the energy")
    rules.register_player_hit()
    _check(rules.outcome() == LevelRules.Outcome.LOST, "too many snowballs lose")
    _check(rules.energy() == 0.0, "no energy left at the end")


func _test_quick_hits_score_more() -> void:
    var rules := LevelRules.new()
    var quick := rules.register_bear_hit(0.1, 2.0)
    var slow := rules.register_bear_hit(1.9, 2.0)
    _check(quick > slow, "quick hits score more")
    _check(rules.score == quick + slow, "the score adds up")


func _test_difficulty_rises_but_stays_fair() -> void:
    var rules := LevelRules.new()
    rules.target_bears = 10
    var interval := rules.spawn_interval()
    var exposure := rules.exposure_seconds()
    for i in range(9):
        rules.register_bear_hit(1.0, 2.0)
    _check(rules.spawn_interval() < interval, "the bears come more often")
    _check(rules.exposure_seconds() < exposure, "the bears throw sooner")
    _check(rules.flight_seconds() >= rules.min_flight_seconds, "the snowballs never get too fast")
    _check(rules.may_spawn_bear(0, 0.99), "a bear always comes when none is out")
    _check(not rules.may_spawn_bear(1, 0.5), "mostly no second bear")
    _check(rules.may_spawn_bear(1, 0.01), "seldom a second bear")
    _check(not rules.may_spawn_bear(2, 0.0), "never three bears at once")


## Win a level of the rules with the given throws and snowballs taken.
func _win(rules: LevelRules, throws: int, hits_taken: int) -> void:
    rules.reset()
    for i in range(throws):
        rules.register_throw()
    for i in range(hits_taken):
        rules.register_player_hit()
    for i in range(rules.target_bears):
        rules.register_bear_hit(1.0, 2.0)


func _test_difficulty_adapts_to_the_player() -> void:
    var rules := LevelRules.new()
    rules.target_bears = 20
    _check(rules.challenge == 0, "the game starts at the base difficulty")
    _check(not rules.may_spawn_bear(2, 0.0), "at the base, never three bears at once")

    _win(rules, 8, 4)
    _check(not rules.was_easy(), "a win with snowballs taken is not too easy")
    _check(rules.adapt_challenge() == 0, "a hard win keeps the difficulty")

    _win(rules, 2, 1)
    _check(rules.was_easy(), "a win where nearly no bear could throw is too easy")
    _check(rules.adapt_challenge() == 1, "a too easy win raises the difficulty")
    _check(rules.may_spawn_bear(1, 0.3), "then, a second bear comes out more often")
    _check(not rules.may_spawn_bear(2, 0.0), "but still never three bears at once")

    _win(rules, 6, 0)
    _check(rules.was_easy(), "a win without a snowball taken is too easy")
    rules.adapt_challenge()
    _check(rules.may_spawn_bear(2, 0.1), "at the top, a third bear sometimes comes out")
    _check(not rules.may_spawn_bear(2, 0.9), "but only seldom")
    _check(not rules.may_spawn_bear(3, 0.0), "never four bears at once")

    _win(rules, 0, 0)
    _check(rules.adapt_challenge() == 0, "the difficulty does not rise beyond the top")
    _check(rules.challenge == LevelRules.MAX_CHALLENGE, "the difficulty stays at the top")

    rules.reset()
    for i in range(rules.max_hits):
        rules.register_player_hit()
    _check(rules.adapt_challenge() == -1, "a lost level lowers the difficulty")
