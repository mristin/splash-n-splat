class_name LevelRules
extends RefCounted

## Keep the score and decide the difficulty and the end of a level.
##
## The difficulty rises with the progress: the bears come more often, stay out
## for a shorter time before they throw, and their snowballs fly faster. It never
## becomes unfair: a snowball always flies for at least [member min_flight_seconds],
## and at most [member max_incoming] fly at once. Mostly one bear is out at a time,
## seldom two ([member second_bear_chance]).
##
## The difficulty also adapts from level to level: after a too easy win (see
## [method was_easy]), the [member challenge] rises, and more bears come out at
## once (often two, at most three); after a lost level, it falls again.
##
## The player has the energy for [member max_hits] snowballs; every snowball
## taken costs the same share of it, and so does every hit kitten.
##
## Besides the critters, penguins and snowy owls cross the screen and throw
## while they move (bonus points, they do not count towards the target),
## kittens stroll by (do not hit them!), and balloons bring boosters, which
## last [member boost_seconds] (health gives back [member heal_hits] at once).

enum Outcome { PLAYING, WON, LOST }

const MAX_CHALLENGE := 2

## The chances of a second and a third bear, by the [member challenge].
const _SECOND_BEAR_CHANCES: Array[float] = [0.1, 0.4, 0.5]
const _THIRD_BEAR_CHANCES: Array[float] = [0.0, 0.0, 0.25]

## A won level was too easy when at most this share of the bears could throw.
const _EASY_THROW_SHARE := 0.1

var target_bears := 20
var max_hits := 10
var max_incoming := 2

var max_spawn_interval := 2.2
var min_spawn_interval := 0.9
var max_exposure_seconds := 5.1
var min_exposure_seconds := 3.0
var max_flight_seconds := 1.9
var min_flight_seconds := 1.3

## The chance that a second bear comes out while one is already out, per try
## (one try per spawn interval).
var second_bear_chance := 0.1

## How much harder than the base the level is, in [0, [constant MAX_CHALLENGE]]:
## it carries over from level to level (see [method adapt_challenge]).
var challenge := 0

var points_per_bear := 100
var max_quick_bonus := 50
var points_per_intercept := 25
var points_per_orca := 150
var points_per_dodge := 10
var points_per_thrower := 150

## How long a booster (rapid fire, big snowballs) lasts.
var boost_seconds := 15.0
## How many snowballs taken a health booster takes back.
var heal_hits := 3

## The seconds between the throwers, the kittens and the boosters.
var min_thrower_interval := 9.0
var max_thrower_interval := 14.0
var min_kitten_interval := 12.0
var max_kitten_interval := 20.0
var min_booster_interval := 14.0
var max_booster_interval := 22.0

## The seconds between two orcas (in a world with orcas).
var min_orca_interval := 8.0
var max_orca_interval := 14.0

var score := 0
var bears_hit := 0
var hits_taken := 0
var intercepts := 0
var orcas_hit := 0
var dodges := 0
## The bears which threw a snowball (hit the player or not).
var throws := 0
var kittens_hit := 0


func outcome() -> Outcome:
    if hits_taken >= max_hits:
        return Outcome.LOST
    if bears_hit >= target_bears:
        return Outcome.WON
    return Outcome.PLAYING


## Progress of the level in [0, 1].
func progress() -> float:
    return clampf(float(bears_hit) / maxi(1, target_bears), 0.0, 1.0)


func spawn_interval() -> float:
    return lerpf(max_spawn_interval, min_spawn_interval, progress())


## How long a bear stays out before it throws.
func exposure_seconds() -> float:
    return lerpf(max_exposure_seconds, min_exposure_seconds, progress())


func flight_seconds() -> float:
    return lerpf(max_flight_seconds, min_flight_seconds, progress())


## Decide whether a new bear may come out while [param visible] bears are out;
## [param roll] is a random number in [0, 1).
func may_spawn_bear(visible: int, roll: float) -> bool:
    if visible == 0:
        return true
    if visible == 1:
        return roll < maxf(second_bear_chance, _SECOND_BEAR_CHANCES[challenge])
    if visible == 2:
        return roll < _THIRD_BEAR_CHANCES[challenge]
    return false


## Whether the won level was too easy: the player took no snowball, or hit
## nearly every bear before it could throw.
func was_easy() -> bool:
    if outcome() != Outcome.WON:
        return false
    return hits_taken == 0 or throws <= floori(bears_hit * _EASY_THROW_SHARE)


## Adapt the [member challenge] for the next level at the end of this one:
## harder after a too easy win, easier after a lost level. Return the change.
func adapt_challenge() -> int:
    var before := challenge
    if was_easy():
        challenge = mini(challenge + 1, MAX_CHALLENGE)
    elif outcome() == Outcome.LOST:
        challenge = maxi(challenge - 1, 0)
    return challenge - before


## The energy left in [0, 1].
func energy() -> float:
    return clampf(1.0 - float(hits_taken) / maxi(1, max_hits), 0.0, 1.0)


func reset() -> void:
    score = 0
    bears_hit = 0
    hits_taken = 0
    intercepts = 0
    orcas_hit = 0
    dodges = 0
    throws = 0
    kittens_hit = 0


## Count a hit bear; the quicker the hit, the higher the bonus. Return the points.
func register_bear_hit(seconds_exposed: float, exposure: float) -> int:
    if outcome() != Outcome.PLAYING:
        return 0
    var remaining := clampf(1.0 - seconds_exposed / maxf(0.01, exposure), 0.0, 1.0)
    var points := points_per_bear + roundi(max_quick_bonus * remaining)
    bears_hit += 1
    score += points
    return points


func register_intercept() -> int:
    if outcome() != Outcome.PLAYING:
        return 0
    intercepts += 1
    score += points_per_intercept
    return points_per_intercept


## Count a hit penguin or owl, a bonus which does not count towards the target.
## Return the points.
func register_thrower_hit() -> int:
    if outcome() != Outcome.PLAYING:
        return 0
    score += points_per_thrower
    return points_per_thrower


## Count a hit kitten: it costs the same energy as a snowball taken.
func register_kitten_hit() -> void:
    if outcome() != Outcome.PLAYING:
        return
    kittens_hit += 1
    hits_taken += 1


## Give back the energy of [member heal_hits] snowballs taken. Return how many.
func heal() -> int:
    if outcome() != Outcome.PLAYING:
        return 0
    var healed := mini(heal_hits, hits_taken)
    hits_taken -= healed
    return healed


## Count a hit orca, a bonus which does not count towards the target. Return the points.
func register_orca_hit() -> int:
    if outcome() != Outcome.PLAYING:
        return 0
    orcas_hit += 1
    score += points_per_orca
    return points_per_orca


## Count a snowball which the player dodged by moving the head away. Return the points.
func register_dodge() -> int:
    if outcome() != Outcome.PLAYING:
        return 0
    dodges += 1
    score += points_per_dodge
    return points_per_dodge


## The stars for a won level, by the energy left: 3, 2 or 1.
func stars() -> int:
    if energy() >= 0.7:
        return 3
    if energy() >= 0.4:
        return 2
    return 1


func register_throw() -> void:
    if outcome() != Outcome.PLAYING:
        return
    throws += 1


func register_player_hit() -> void:
    if outcome() != Outcome.PLAYING:
        return
    hits_taken += 1
