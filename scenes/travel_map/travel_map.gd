class_name TravelMap
extends CanvasLayer

## Show the journey to the next world on an old map of the Arctic: a little
## propeller plane flies from one place to the other and leaves a dashed red
## line behind it, then the destination is welcomed.
##
## The map shows the real coastlines of Natural Earth (public domain), projected
## and simplified by dev/maps/make_travel_map.py into [constant _MAP_PATH], in the
## screen coordinates (1920x1080): the North Pole on the top, with the circles
## of latitude around it, Greenland on the left, and Zurich, the home of the
## players, on the bottom right.

## The plane has landed; the map still covers the screen for the welcome.
signal landed

## The map is gone.
signal arrived

const _MAP_PATH := "res://scenes/travel_map/arctic_map.json"

const _FADE_IN := 0.6
const _MAX_ZOOM := 10.0
## The length of a route on the screen, in pixels, unless the map is too small.
const _ROUTE_ON_SCREEN := 800.0
const _FLIGHT := 5.0
## Long enough to read who hides in the new world.
const _WELCOME := 3.0
const _FADE_OUT := 0.5

const _PAPER := Color(0.94, 0.87, 0.71)
const _PAPER_DARK := Color(0.62, 0.48, 0.3)
const _SEA := Color(0.9, 0.85, 0.7)
const _LAND := Color(0.8, 0.65, 0.43)
const _COAST := Color(0.48, 0.34, 0.2)
const _ICE := Color(0.97, 0.96, 0.92)
const _INK := Color(0.3, 0.2, 0.12)
const _ROUTE := Color(0.82, 0.12, 0.1)

## The places of the game in screen coordinates, by their names (e.g., "Zurich").
var places: Dictionary = {}

## The view on the map for the flight: the route fills a good part of the screen,
## so that a short hop (e.g., Minsk to Kyiv) takes as long to watch as a long flight.
var _view_center := Vector2(960, 540)
var _view_zoom := 1.0

var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _to_name := ""
var _from_name := ""
var _intro := ""
var _time := 0.0
var _flying := false
var _landed := false
var _lands: Array[PackedVector2Array] = []
var _coasts: Array[PackedVector2Array] = []
var _graticule: Array[PackedVector2Array] = []
var _borders: Array[PackedVector2Array] = []

# NOTE (mristin):
# The sea, the paper (zoomed by its transform) and the marks are separate canvas
# items, so that only the marks are drawn anew in every frame.
var _sea := Node2D.new()
var _paper := Node2D.new()
var _marks := Node2D.new()

@onready var _map: Node2D = $Map


func _ready() -> void:
    visible = false
    for node in [_sea, _paper, _marks]:
        _map.add_child(node)
    _sea.draw.connect(func(): _sea.draw_rect(Rect2(0, 0, 1920, 1080), _SEA))
    _paper.draw.connect(_draw_paper_once)
    _marks.draw.connect(_draw_marks)
    _load_map()


func _load_map() -> void:
    var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_MAP_PATH))
    var screen := PackedVector2Array(
        [Vector2(-10, -10), Vector2(1930, -10), Vector2(1930, 1090), Vector2(-10, 1090)]
    )
    for polygon in data["land"]:
        var points := _points_of(polygon)
        var coast := points.duplicate()
        coast.append(points[0])
        _coasts.append(coast)
        if not Geometry2D.triangulate_polygon(points).is_empty():
            _lands.append(points)
            continue
        # NOTE (mristin):
        # Where a big land (Eurasia) leaves the screen and comes back, the clipped
        # outline runs back and forth along the edge and can not be triangulated.
        # Clipping it again with Clipper splits it into proper pieces.
        for piece in Geometry2D.intersect_polygons(points, screen):
            if not Geometry2D.is_polygon_clockwise(piece):
                _lands.append(piece)
    for line in data["graticule"]:
        _graticule.append(_points_of(line))
    for line in data.get("borders", []):
        _borders.append(_points_of(line))
    for place_name in data["places"]:
        var at: Array = data["places"][place_name]
        places[place_name] = Vector2(at[0], at[1])


static func _points_of(values: Array) -> PackedVector2Array:
    var points := PackedVector2Array()
    for i in range(0, values.size(), 2):
        points.append(Vector2(values[i], values[i + 1]))
    return points


## Fly from one place of [member places] to another; emit [signal landed] when
## the plane lands and [signal arrived] when the map is gone.
func fly(from_name: String, to_name: String, intro: String = "") -> void:
    _intro = intro
    _from = places.get(from_name, places["Zurich"])
    _to = places.get(to_name, places["The North Pole"])
    _to_name = to_name
    _from_name = from_name
    _time = 0.0
    _flying = true
    _landed = false
    _frame_route()
    visible = true
    _map.modulate.a = 0.0
    _paper.queue_redraw()
    _update_view()


func is_flying() -> bool:
    return _flying


## End the flight at once.
func skip() -> void:
    if not _flying:
        return
    _flying = false
    visible = false
    _land()
    arrived.emit()


func _land() -> void:
    if not _landed:
        _landed = true
        landed.emit()


func _process(delta: float) -> void:
    if not _flying:
        return
    _time += delta
    var total := _FADE_IN + _FLIGHT + _WELCOME + _FADE_OUT
    if _time < _FADE_IN:
        _map.modulate.a = _time / _FADE_IN
    elif _time > total - _FADE_OUT:
        _map.modulate.a = clampf((total - _time) / _FADE_OUT, 0.0, 1.0)
    else:
        _map.modulate.a = 1.0
    if _time >= _FADE_IN + _FLIGHT:
        _land()
    if _time >= total:
        skip()
        return
    _update_view()
    _marks.queue_redraw()


func _update_view() -> void:
    var camera := _camera()
    var zoom: float = camera[1]
    _paper.scale = Vector2(zoom, zoom)
    _paper.position = Vector2(960, 540) - camera[0] * zoom


## Zoom the view on the route, but never beyond the edges of the map.
func _frame_route() -> void:
    # NOTE (mristin):
    # Every route is about the same length on the screen, so that the plane
    # flies a good stretch in its few seconds, but the whole route stays in
    # the view, and the map never zooms out beyond its edges.
    var box := Rect2(_from, Vector2.ZERO)
    for i in range(11):
        box = box.expand(_route(i / 10.0))
    box = box.grow(20.0)
    var length := maxf(1.0, _from.distance_to(_to))
    var fit := minf(1920.0 * 0.75 / box.size.x, 1080.0 * 0.6 / box.size.y)
    _view_zoom = clampf(minf(_ROUTE_ON_SCREEN / length, fit), 1.0, _MAX_ZOOM)
    # NOTE (mristin):
    # The route stays above the banner and the title at the bottom: we center
    # the view a bit below it, so that the route shows higher on the screen.
    _view_center = _clamp_center(box.get_center() + Vector2(0, 130) / _view_zoom, _view_zoom)


static func _clamp_center(center: Vector2, zoom: float) -> Vector2:
    var half := Vector2(960, 540) / zoom
    return Vector2(
        clampf(center.x, half.x, 1920.0 - half.x), clampf(center.y, half.y, 1080.0 - half.y)
    )


## The current zoom and center: from the whole map into the view on the route.
func _camera() -> Array:
    var k := smoothstep(0.0, 1.0, clampf(_time / (_FADE_IN + 1.0), 0.0, 1.0))
    var zoom := exp(lerpf(0.0, log(_view_zoom), k))
    var center := _clamp_center(Vector2(960, 540).lerp(_view_center, k), zoom)
    return [center, zoom]


## Map a point of the map to the screen through the current view.
func _to_screen(point: Vector2) -> Vector2:
    var camera := _camera()
    return (point - camera[0]) * camera[1] + Vector2(960, 540)


## The progress of the flight in [0, 1], eased in and out.
func _progress() -> float:
    return smoothstep(0.0, 1.0, clampf((_time - _FADE_IN) / _FLIGHT, 0.0, 1.0))


## The point of the route at t in [0, 1]: a gentle arc to the left of the
## straight line.
func _route(t: float) -> Vector2:
    var middle := (_from + _to) * 0.5
    var normal := (_to - _from).orthogonal().normalized()
    var control := middle + normal * _from.distance_to(_to) * 0.25
    return _from.lerp(control, t).lerp(control.lerp(_to, t), t)


## Draw the marks of every frame over the paper: the edges of the old paper, the
## compass, the route, the places, the plane and the title; they keep their size.
func _draw_marks() -> void:
    _draw_paper()
    _draw_compass(Vector2(220, 880))

    var progress := _progress()
    _draw_route(progress)
    for place_name in places:
        _draw_place(place_name, _to_screen(places[place_name]))
    _draw_plane(progress)

    var font := ThemeDB.fallback_font
    var place := _to_name.replace("The ", "the ")
    var title := ("Welcome to %s!" if progress >= 1.0 else "Off to %s!") % place
    if progress >= 1.0 and not _intro.is_empty():
        # NOTE (mristin):
        # After the landing, a banner tells who hides in the new world.
        var banner := Rect2(160, 790, 1600, 170)
        var style := StyleBoxFlat.new()
        style.bg_color = Color(_PAPER, 0.92)
        style.set_corner_radius_all(24)
        style.set_border_width_all(4)
        style.border_color = _COAST
        _marks.draw_style_box(style, banner)
        _marks.draw_multiline_string(
            font,
            banner.position + Vector2(40, 66),
            _intro,
            HORIZONTAL_ALIGNMENT_CENTER,
            banner.size.x - 80,
            44,
            3,
            _INK
        )
    _marks.draw_string_outline(
        font, Vector2(0, 1040), title, HORIZONTAL_ALIGNMENT_CENTER, 1920, 84, 18, _PAPER
    )
    _marks.draw_string(font, Vector2(0, 1040), title, HORIZONTAL_ALIGNMENT_CENTER, 1920, 84, _ROUTE)


func _draw_paper() -> void:
    # NOTE (mristin):
    # The edges of the old paper get darker: a gradient from each edge inwards.
    var outer := [Vector2(0, 0), Vector2(1920, 0), Vector2(1920, 1080), Vector2(0, 1080)]
    var w := 170.0
    var inner := [
        Vector2(w, w), Vector2(1920 - w, w), Vector2(1920 - w, 1080 - w), Vector2(w, 1080 - w)
    ]
    var dark := Color(_PAPER_DARK, 0.55)
    var clear := Color(_PAPER_DARK, 0.0)
    for i in range(4):
        var j := (i + 1) % 4
        _marks.draw_polygon(
            PackedVector2Array([outer[i], outer[j], inner[j], inner[i]]),
            PackedColorArray([dark, dark, clear, clear])
        )


## Draw the static paper once per flight: the graticule and the lands, in the
## coordinates of the map; the view zooms it by its transform, so that a frame
## of the flight costs nearly nothing.
func _draw_paper_once() -> void:
    # NOTE (mristin):
    # The lines keep about their width on the screen at the zoom of the flight.
    var zoom := _view_zoom
    for line in _graticule:
        _paper.draw_polyline(line, Color(_PAPER_DARK, 0.4), 2.0 / zoom, true)
    _draw_lands(zoom)


func _draw_lands(zoom: float) -> void:
    for land in _lands:
        _paper.draw_colored_polygon(land, _LAND)
    for border in _borders:
        _paper.draw_polyline(border, Color(_COAST, 0.55), 1.6 / zoom, true)
    for coast in _coasts:
        _paper.draw_polyline(coast, _COAST, 2.0 / zoom, true)
    # NOTE (mristin):
    # A soft glow of the sea ice around the pole.
    var pole: Vector2 = places["The North Pole"]
    for i in range(6, 0, -1):
        _paper.draw_circle(pole, 30.0 * i, Color(_ICE, 0.12))


func _draw_compass(center: Vector2) -> void:
    for i in range(8):
        var direction := Vector2.UP.rotated(i * TAU / 8)
        var length := 80.0 if i % 2 == 0 else 46.0
        var side := direction.orthogonal() * 14.0
        _marks.draw_colored_polygon(
            PackedVector2Array([center + side, center + direction * length, center - side]),
            _INK if i % 2 == 0 else _PAPER_DARK
        )
    _marks.draw_circle(center, 12, _PAPER)
    var font := ThemeDB.fallback_font
    _marks.draw_string(
        font, center + Vector2(-14, -92), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 36, _INK
    )


func _draw_route(progress: float) -> void:
    if progress <= 0.0:
        return
    # NOTE (mristin):
    # Dashes of equal length along the arc, up to the plane.
    var steps := 90
    var last := int(steps * progress)
    for i in range(0, last, 2):
        var a := _to_screen(_route(float(i) / steps))
        var b := _to_screen(_route(minf(float(i + 1) / steps, progress)))
        _marks.draw_line(a, b, _ROUTE, 8.0, true)


func _draw_place(place_name: String, at: Vector2) -> void:
    var font := ThemeDB.fallback_font
    var target := place_name == _to_name
    if target:
        var pulse := 0.5 + 0.5 * sin(_time * 6.0)
        _marks.draw_arc(at, 26 + 10 * pulse, 0, TAU, 32, Color(_ROUTE, 0.8), 5.0, true)
    if not target and place_name != _from_name:
        # NOTE (mristin):
        # The other places are small dots without names; the Baltic capitals lie
        # too close together on the map for their names.
        _marks.draw_circle(at, 7, Color(_INK, 0.7))
        return
    _marks.draw_circle(at, 14, _ROUTE if target else _INK)
    _marks.draw_circle(at, 6, _PAPER)

    # NOTE (mristin):
    # The names keep away from the marker, so that the landed plane does not hide them.
    # The start and the destination get their names on the sides away from each
    # other, so that they do not overlap when the places are near.
    var other := _to_screen(_from if target else _to)
    var on_left := at.x < other.x if not is_equal_approx(at.x, other.x) else not target
    var offset := Vector2(90, 14)
    var alignment := HORIZONTAL_ALIGNMENT_LEFT
    if on_left:
        offset = Vector2(-590, 14)
        alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _marks.draw_string_outline(font, at + offset, place_name, alignment, 500, 46, 12, _PAPER)
    _marks.draw_string(font, at + offset, place_name, alignment, 500, 46, _INK)


## Draw a little red propeller plane, seen from above, at the head of the route.
func _draw_plane(progress: float) -> void:
    var at := _to_screen(_route(progress))
    var ahead := _to_screen(_route(minf(1.0, progress + 0.01)))
    var behind := _to_screen(_route(maxf(0.0, progress - 0.01)))
    var heading := (ahead - behind).angle()
    # NOTE (mristin):
    # The plane climbs (bigger) in the middle of the flight and lands at the end.
    var size := 1.3 + 0.5 * sin(progress * PI)
    var bob := sin(_time * 5.0) * 4.0

    _marks.draw_set_transform(at + Vector2(18, 26) * size, heading, Vector2(size, size))
    _draw_plane_shape(Color(0.2, 0.12, 0.05, 0.25), Color(0.2, 0.12, 0.05, 0.25), false)
    _marks.draw_set_transform(at + Vector2(0, bob), heading, Vector2(size, size))
    _draw_plane_shape(Color(0.86, 0.22, 0.18), Color(0.98, 0.93, 0.8), true)
    _marks.draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_plane_shape(body: Color, wings: Color, details: bool) -> void:
    # Wings and the tail
    _marks.draw_colored_polygon(
        PackedVector2Array([Vector2(8, -58), Vector2(22, -58), Vector2(16, 58), Vector2(2, 58)]),
        wings
    )
    _marks.draw_colored_polygon(
        PackedVector2Array(
            [Vector2(-36, -22), Vector2(-28, -22), Vector2(-30, 22), Vector2(-38, 22)]
        ),
        wings
    )
    # The body
    _marks.draw_colored_polygon(Draw2D.ellipse(Vector2(0, 0), 46, 11, 24), body)
    if not details:
        return
    _marks.draw_circle(Vector2(14, 0), 7, Color(0.35, 0.55, 0.75))
    _marks.draw_line(Vector2(-44, 0), Vector2(-30, 0), Color(0.6, 0.12, 0.1), 4)
    # The spinning propeller
    var blade := Vector2(0, 22).rotated(_time * 40.0)
    _marks.draw_line(
        Vector2(50, 0) + blade * Vector2(0.15, 1),
        Vector2(50, 0) - blade * Vector2(0.15, 1),
        _INK,
        4
    )
    _marks.draw_circle(Vector2(50, 0), 5, _INK)
