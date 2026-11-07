class_name CountryBackdrop
extends WinterBackdrop

## Draw the winter landscape of a country behind the critters: its sky (by day,
## or by night with the northern lights), its terrain, and its landmark on the
## horizon (see [Landmarks]).

var country: Dictionary = {}


func _draw() -> void:
    var night: bool = country.get("night", false)
    _draw_gradient(0, theme.ground_top - 40, theme.sky_top, theme.sky_horizon)
    if night:
        _draw_night_sky()
    else:
        _draw_sun(Vector2(1560, 170))
        _draw_clouds()

    match country.get("terrain", "forest"):
        "volcanic":
            _draw_mountains(
                [
                    0,
                    400,
                    220,
                    320,
                    420,
                    380,
                    640,
                    250,
                    760,
                    270,
                    900,
                    400,
                    1200,
                    330,
                    1500,
                    260,
                    1920,
                    380
                ],
                Color(0.42, 0.44, 0.5),
                0.7
            )
            Landmarks.volcano_smoke(self, Vector2(700, 250))
        "fjord":
            _draw_mountains(
                [0, 220, 200, 180, 380, 420, 520, 520, 1400, 520, 1560, 380, 1720, 160, 1920, 200],
                Color(0.46, 0.5, 0.6),
                0.4
            )
        "alps":
            _draw_mountains(
                [
                    0,
                    300,
                    160,
                    200,
                    300,
                    330,
                    460,
                    150,
                    640,
                    300,
                    820,
                    190,
                    980,
                    320,
                    1180,
                    170,
                    1400,
                    310,
                    1600,
                    160,
                    1920,
                    280
                ],
                Color(0.6, 0.66, 0.8),
                0.75
            )
        "steppe":
            _draw_mountains(
                [0, 500, 400, 470, 800, 490, 1200, 460, 1600, 485, 1920, 470],
                Color(0.78, 0.84, 0.94),
                0.2
            )
        _:
            _draw_mountains(
                [0, 470, 300, 430, 700, 460, 1100, 420, 1500, 455, 1920, 430],
                Color(0.7, 0.76, 0.9) if not night else Color(0.25, 0.32, 0.5),
                0.6
            )
    _draw_hills()

    if country.get("terrain", "") in ["forest", "city", "fjord", "volcanic", "alps"]:
        for tree in [
            [60, 562, 0.8], [140, 556, 0.65], [210, 560, 0.75], [1780, 556, 0.7], [1860, 562, 0.85]
        ]:
            draw_pine(Vector2(tree[0], tree[1]), tree[2])

    Landmarks.draw(self, country.get("landmark", ""), theme.ground_top)

    _draw_gradient(theme.ground_top, theme.ground_bottom, theme.ground_far, theme.ground_near)
    for shadow in [[640, 680, 260, 18], [1300, 820, 340, 22], [420, 1000, 380, 26]]:
        draw_colored_polygon(
            Draw2D.ellipse(Vector2(shadow[0], shadow[1]), shadow[2], shadow[3]),
            Color(WinterTheme.SHADOW, 0.25)
        )


func _draw_night_sky() -> void:
    var random := RandomNumberGenerator.new()
    random.seed = 11
    for i in range(90):
        var at := Vector2(random.randf_range(0, 1920), random.randf_range(0, 460))
        draw_circle(
            at, random.randf_range(1.0, 2.6), Color(1, 1, 0.9, random.randf_range(0.4, 0.9))
        )
    draw_circle(Vector2(1580, 150), 46, Color(0.98, 0.97, 0.88))
    draw_circle(Vector2(1600, 140), 40, theme.sky_top)

    # NOTE (mristin):
    # The northern lights: soft, wavy ribbons of green and violet.
    for ribbon in [[180.0, Color(0.3, 1.0, 0.6), 0.0], [260.0, Color(0.6, 0.4, 1.0), 1.7]]:
        var points := PackedVector2Array()
        var colors := PackedColorArray()
        for x in range(-40, 1961, 40):
            var y: float = ribbon[0] + 50 * sin(x * 0.004 + ribbon[2]) + 20 * sin(x * 0.011)
            points.append(Vector2(x, y))
            colors.append(Color(ribbon[1], 0.0))
        for x in range(1960, -41, -40):
            var y: float = ribbon[0] + 50 * sin(x * 0.004 + ribbon[2]) + 20 * sin(x * 0.011) - 130
            points.append(Vector2(x, y))
            colors.append(Color(ribbon[1], 0.32))
        draw_polygon(points, colors)
