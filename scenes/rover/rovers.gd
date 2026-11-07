class_name Rovers
extends Node

## Send the rovers across the screen of a level now and then: the penguins and
## the snowy owls which throw while they move, the kittens which must not be hit,
## and the balloons with the boosters; and keep the boosters which the players
## collected, until their time runs out.
##
## At most one walker (a penguin or a kitten), one owl and one balloon are on
## the screen at a time, so that it never gets too crowded.

## A penguin or an owl threw a snowball from the paw.
signal threw(paw: Vector2, size: float)

## The seconds between two throws of a held fist under rapid fire.
const RAPID_FIRE_INTERVAL := 0.22

const _MARGIN := 220.0
const _SCREEN := Vector2(1920, 1080)

var rules: LevelRules = null
var level: Level = null
var random := RandomNumberGenerator.new()

## Ask whether a thrower may throw (the game limits the snowballs in the air).
var may_throw: Callable = func() -> bool: return true

## The rovers on the screen.
var list: Array[Rover] = []

## The seconds left of the active boosters, by [enum Booster.Kind].
var boosts: Dictionary = {}

var _thrower_timer := 0.0
var _kitten_timer := 0.0
var _booster_timer := 0.0

## The seconds since the last throw of every held fist under rapid fire, by hand id.
var _rapid_fists: Dictionary = {}


## Clear the rovers and the boosters for a new level.
func reset() -> void:
    for rover in list:
        if is_instance_valid(rover):
            rover.queue_free()
    list.clear()
    boosts.clear()
    _rapid_fists.clear()
    _thrower_timer = 5.0
    _kitten_timer = random.randf_range(6.0, 10.0)
    _booster_timer = random.randf_range(rules.min_booster_interval, rules.max_booster_interval)


## Forget the rovers which are gone.
func prune() -> void:
    var rovers: Array[Rover] = []
    for rover in list:
        if is_instance_valid(rover) and rover.state != Rover.State.GONE:
            rovers.append(rover)
    list = rovers


func has_boost(kind: Booster.Kind) -> bool:
    return boosts.has(kind)


## Start the booster (or give back the energy at once for health).
func collect(kind: Booster.Kind) -> void:
    if kind == Booster.Kind.HEALTH:
        rules.heal()
    else:
        boosts[kind] = rules.boost_seconds


## The boosters as shown on the HUD: [kind, the share of the time left].
func shown_boosts() -> Array:
    var shown: Array = []
    for kind in boosts:
        shown.append([kind, boosts[kind] / rules.boost_seconds])
    return shown


## The front-most rover which the point hits, or null.
func hit_test(at: Vector2, tolerance: float) -> Rover:
    var hit: Rover = null
    for rover in list:
        if is_instance_valid(rover) and rover.hit_test(at, tolerance):
            if hit == null or rover.z_index > hit.z_index:
                hit = rover
    return hit


## Count down the boosters, and send new rovers if [param spawn].
func update(delta: float, spawn: bool) -> void:
    prune()
    for kind in boosts.keys():
        boosts[kind] -= delta
        if boosts[kind] <= 0.0:
            boosts.erase(kind)
    if spawn:
        _spawn(delta)


## The hands which throw again under rapid fire now, given the hands of the
## aim ({id: {"gesture"}}): every held fist throws every
## [constant RAPID_FIRE_INTERVAL] seconds.
func rapid_fire(delta: float, hands: Dictionary) -> Array:
    if not boosts.has(Booster.Kind.RAPID_FIRE):
        _rapid_fists.clear()
        return []
    var throwing: Array = []
    var fists: Dictionary = {}
    for id in hands:
        if hands[id]["gesture"] == "fist":
            fists[id] = _rapid_fists.get(id, 0.0) + delta
            if fists[id] >= RAPID_FIRE_INTERVAL:
                fists[id] = 0.0
                throwing.append(id)
    _rapid_fists = fists
    return throwing


func _spawn(delta: float) -> void:
    _thrower_timer -= delta
    if _thrower_timer <= 0.0:
        spawn("penguin" if random.randf() < 0.5 else "owl")
        _thrower_timer = random.randf_range(rules.min_thrower_interval, rules.max_thrower_interval)
    _kitten_timer -= delta
    if _kitten_timer <= 0.0:
        spawn("kitten")
        _kitten_timer = random.randf_range(rules.min_kitten_interval, rules.max_kitten_interval)
    _booster_timer -= delta
    if _booster_timer <= 0.0:
        # NOTE (mristin):
        # Health comes only when the players can use it.
        var kinds := ["rapid", "big"]
        if rules.hits_taken > 0:
            kinds.append("health")
        spawn(kinds[random.randi() % kinds.size()])
        _booster_timer = random.randf_range(rules.min_booster_interval, rules.max_booster_interval)


## Send a rover across the screen: "penguin", "owl", "kitten", or a balloon with
## a booster, "rapid", "big" or "health". Return it, or null if its way is taken.
func spawn(kind: String) -> Rover:
    var rover: Rover
    match kind:
        "penguin":
            rover = Penguin.new()
            rover.travel_seconds = 10.0
        "owl":
            rover = SnowyOwl.new()
            rover.travel_seconds = 8.5
        "kitten":
            rover = Kitten.new()
            rover.size = 1.1
            rover.travel_seconds = 11.0
        "rapid":
            rover = Booster.new(Booster.Kind.RAPID_FIRE)
        "big":
            rover = Booster.new(Booster.Kind.BIG_SNOWBALLS)
        _:
            rover = Booster.new(Booster.Kind.HEALTH)
    if rover is Booster:
        rover.travel_seconds = 9.0

    prune()
    for other in list:
        if _same_way(other, rover):
            rover.free()
            return null

    var left_to_right := random.randf() < 0.5
    var y := level.walk_y
    if rover is SnowyOwl:
        y = random.randf_range(170.0, 300.0)
    elif rover is Booster:
        y = random.randf_range(300.0, 400.0)
    rover.from = Vector2(-_MARGIN if left_to_right else _SCREEN.x + _MARGIN, y)
    rover.to = Vector2(_SCREEN.x + _MARGIN if left_to_right else -_MARGIN, y)
    if rover is Thrower:
        var thrower := rover as Thrower
        thrower.may_throw = may_throw
        thrower.threw.connect(func(t: Thrower, paw: Vector2): threw.emit(paw, t.size))
    level.add_child(rover)
    list.append(rover)
    return rover


## Whether two rovers would share their way: both walk, both are owls, or both
## are balloons.
static func _same_way(a: Rover, b: Rover) -> bool:
    if a.motion == Rover.Motion.WALK and b.motion == Rover.Motion.WALK:
        return true
    return (a is SnowyOwl and b is SnowyOwl) or (a is Booster and b is Booster)
