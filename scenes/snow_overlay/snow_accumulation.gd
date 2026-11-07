class_name SnowAccumulation
extends RefCounted

## How much snow has piled up around the edges of the screen after the player has
## been hit.
##
## Each hit thickens the frost on all edges a little and on the edges nearest to
## the impact a bit more, and sticks a lump of snow there. The frost of an edge
## never exceeds [member max_edge_fraction], so that at least
## [code]1 - 2 * max_edge_fraction[/code] of the screen width and height stays
## clear. The centers of the lumps lie within the frost bands. All positions are
## normalized to [0, 1] of the screen.

## The frost of a single edge is at most this fraction of the screen.
var max_edge_fraction := 0.27

## Frost added to every edge per hit.
var base_growth := 0.035

## Additional frost on the edges nearest to the impact.
var impact_growth := 0.05

## Keep at most this many lumps.
var max_blobs := 48

var left := 0.0
var top := 0.0
var right := 0.0
var bottom := 0.0
var hits := 0

## The lumps as Vector3(x, y, radius), the radius as a fraction of the height.
var blobs: Array[Vector3] = []

var _random := RandomNumberGenerator.new()


func _init(seed_value: int = 1) -> void:
    _random.seed = seed_value


## Fraction of the screen width not covered by the frost bands.
func visible_width() -> float:
    return 1.0 - left - right


## Fraction of the screen height not covered by the frost bands.
func visible_height() -> float:
    return 1.0 - top - bottom


## The guaranteed minimum of the visible width and height.
func min_visible_fraction() -> float:
    return 1.0 - 2.0 * max_edge_fraction


func reset() -> void:
    left = 0.0
    top = 0.0
    right = 0.0
    bottom = 0.0
    hits = 0
    blobs.clear()


## Add the snow of a hit at the normalized screen position.
func add_hit(x: float, y: float) -> void:
    x = clampf(x, 0.0, 1.0)
    y = clampf(y, 0.0, 1.0)
    hits += 1

    var horizontal := absf(x - 0.5) * 2.0
    var vertical := absf(y - 0.5) * 2.0
    left = _grow(left, horizontal if x < 0.5 else 0.0)
    right = _grow(right, horizontal if x >= 0.5 else 0.0)
    top = _grow(top, vertical if y < 0.5 else 0.0)
    bottom = _grow(bottom, vertical if y >= 0.5 else 0.0)

    _add_blob(x, y)


func _grow(edge: float, closeness: float) -> float:
    return minf(max_edge_fraction, edge + base_growth + impact_growth * closeness)


func _add_blob(x: float, y: float) -> void:
    # NOTE (mristin):
    # We slide the lump from the impact to the nearest edge, and keep it inside
    # that edge's frost band.
    var nearest := minf(minf(x, 1.0 - x), minf(y, 1.0 - y))
    var depth := _random.randf()
    var band: float
    var bx := x
    var by := y
    if nearest == x:
        band = left
        bx = band * depth
    elif nearest == 1.0 - x:
        band = right
        bx = 1.0 - band * depth
    elif nearest == y:
        band = top
        by = band * depth
    else:
        band = bottom
        by = 1.0 - band * depth

    var radius := maxf(0.02, band * (0.35 + 0.3 * _random.randf()))
    blobs.append(Vector3(bx, by, radius))
    if blobs.size() > max_blobs:
        blobs.remove_at(0)
