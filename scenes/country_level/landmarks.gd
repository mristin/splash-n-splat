class_name Landmarks
extends Object

## Draw the landmarks of the countries on the horizon, as friendly sketches.
##
## The main landmark stands at [constant MAIN_X], between the far hiding
## places, and a smaller one at [constant SIDE_X]; [param base] is the y of the
## horizon, where they stand.

const MAIN_X := 1275.0
const SIDE_X := 640.0

const _WHITE := Color(0.97, 0.97, 0.95)
const _SNOW := Color(0.98, 0.99, 1.0)
const _BRICK := Color(0.72, 0.3, 0.22)
const _BRICK_DARK := Color(0.58, 0.22, 0.17)
const _WINDOW := Color(1.0, 0.88, 0.5)
const _DARK := Color(0.25, 0.22, 0.24)
const _GOLD := Color(1.0, 0.8, 0.25)


static func draw(c: CanvasItem, id: String, base: float) -> void:
    var at := Vector2(MAIN_X, base + 4)
    var side := Vector2(SIDE_X, base + 4)
    match id:
        "hallgrimskirkja":
            hallgrimskirkja(c, at)
            geyser(c, side)
        "stave_church":
            stave_church(c, at)
        "red_cottages":
            red_cottage(c, at + Vector2(-70, 0), 1.0)
            red_cottage(c, at + Vector2(80, 0), 0.8)
            dala_horse(c, side)
        "sauna":
            helsinki_cathedral(c, at)
            sauna(c, side)
        "tallinn":
            tallinn(c, at)
        "riga":
            house_of_blackheads(c, at)
            freedom_monument(c, side)
        "gediminas":
            gediminas_tower(c, at)
        "mir_castle":
            mir_castle(c, at)
        "st_michael":
            st_michael(c, at)
        "st_basil":
            st_basil(c, at)
            kremlin_tower(c, side)
        "astana":
            bayterek(c, at)
            khan_shatyr(c, side)
        "grossmuenster":
            grossmuenster(c, at)


static func _poly(c: CanvasItem, origin: Vector2, points: Array, color: Color) -> void:
    var result := PackedVector2Array()
    for p in points:
        result.append(origin + p)
    c.draw_colored_polygon(result, color)


static func _windows(c: CanvasItem, origin: Vector2, xs: Array, y: float, size: Vector2) -> void:
    for x in xs:
        c.draw_rect(Rect2(origin + Vector2(x - size.x * 0.5, y), size), _WINDOW)


## Hallgrímskirkja in Reykjavik: stepped wings rising to a tall tower.
static func hallgrimskirkja(c: CanvasItem, at: Vector2) -> void:
    var concrete := Color(0.86, 0.87, 0.88)
    var shade := Color(0.74, 0.75, 0.78)
    for k in range(6):
        var h := 60.0 + k * 34
        var x := 30.0 + (5 - k) * 18
        c.draw_rect(Rect2(at + Vector2(-x - 18, -h), Vector2(18, h)), shade if k % 2 else concrete)
        c.draw_rect(Rect2(at + Vector2(x, -h), Vector2(18, h)), shade if k % 2 else concrete)
    _poly(
        c,
        at,
        [Vector2(-30, 0), Vector2(-30, -250), Vector2(0, -320), Vector2(30, -250), Vector2(30, 0)],
        concrete
    )
    c.draw_rect(Rect2(at + Vector2(-8, -230), Vector2(16, 26)), _DARK)
    _poly(c, at, [Vector2(-6, -320), Vector2(0, -350), Vector2(6, -320)], shade)
    c.draw_rect(Rect2(at + Vector2(-110, -50), Vector2(220, 50)), concrete)


## A geyser with its column of steam.
static func geyser(c: CanvasItem, at: Vector2) -> void:
    for k in range(9):
        var y := -20.0 - k * 26
        var r := 14.0 + k * 5
        c.draw_circle(at + Vector2(sin(k * 1.3) * 10, y), r, Color(1, 1, 1, 0.55 - k * 0.04))
    c.draw_colored_polygon(Draw2D.ellipse(at, 60, 10), Color(0.55, 0.75, 0.85))


static func volcano_smoke(c: CanvasItem, top: Vector2) -> void:
    for k in range(6):
        c.draw_circle(
            top + Vector2(k * 22, -20 - k * 22), 16 + k * 6, Color(0.9, 0.9, 0.92, 0.5 - k * 0.06)
        )


## A Norwegian stave church: stacked dark roofs with dragon heads.
static func stave_church(c: CanvasItem, at: Vector2) -> void:
    var wood := Color(0.36, 0.22, 0.14)
    var roof := Color(0.24, 0.15, 0.1)
    c.draw_rect(Rect2(at + Vector2(-90, -70), Vector2(180, 70)), wood)
    for k in range(4):
        var w := 120.0 - k * 26
        var y := -70.0 - k * 58
        _poly(c, at, [Vector2(-w, y), Vector2(0, y - 60), Vector2(w, y)], roof)
        _poly(
            c, at, [Vector2(-w * 0.8, y - 10), Vector2(0, y - 52), Vector2(-w * 0.2, y - 18)], _SNOW
        )
        c.draw_rect(Rect2(at + Vector2(-w * 0.6, y - 2), Vector2(w * 1.2, 12)), wood)
        for s in [-1.0, 1.0]:
            # The dragon heads at the ends of the ridges
            c.draw_line(at + Vector2(s * w, y), at + Vector2(s * (w + 18), y - 24), roof, 6)
    _poly(c, at, [Vector2(-6, -300), Vector2(0, -360), Vector2(6, -300)], roof)
    c.draw_rect(Rect2(at + Vector2(-14, -50), Vector2(28, 50)), Color(0.2, 0.12, 0.08))


## A Falu-red cottage with white corners and a snowy roof.
static func red_cottage(c: CanvasItem, at: Vector2, s: float) -> void:
    var red := Color(0.62, 0.15, 0.12)
    c.draw_rect(Rect2(at + Vector2(-70, -90) * s, Vector2(140, 90) * s), red)
    for x in [-70, 62]:
        c.draw_rect(Rect2(at + Vector2(x, -90) * s, Vector2(8, 90) * s), _WHITE)
    _poly(c, at, [Vector2(-86, -88) * s, Vector2(0, -150) * s, Vector2(86, -88) * s], _SNOW)
    _windows(c, at, [-36 * s, 36 * s], -64 * s, Vector2(22, 22) * s)
    c.draw_rect(Rect2(at + Vector2(30, -160) * s, Vector2(16, 40) * s), red)


## A Dala horse, the painted wooden horse of Sweden.
static func dala_horse(c: CanvasItem, at: Vector2) -> void:
    var red := Color(0.85, 0.15, 0.12)
    _poly(
        c,
        at,
        [
            Vector2(-60, 0),
            Vector2(-50, -70),
            Vector2(-56, -120),
            Vector2(30, -120),
            Vector2(44, -170),
            Vector2(90, -150),
            Vector2(70, -110),
            Vector2(56, -70),
            Vector2(60, 0),
            Vector2(30, 0),
            Vector2(26, -40),
            Vector2(-26, -40),
            Vector2(-30, 0)
        ],
        red
    )
    c.draw_arc(at + Vector2(-10, -88), 18, PI, TAU, 12, _GOLD, 4)
    c.draw_circle(at + Vector2(64, -148), 4, _DARK)
    c.draw_rect(Rect2(at + Vector2(-20, -122), Vector2(46, 8)), Color(0.2, 0.45, 0.8))


## Helsinki Cathedral: white with green domes.
static func helsinki_cathedral(c: CanvasItem, at: Vector2) -> void:
    var green := Color(0.4, 0.62, 0.55)
    var white := Color(0.9, 0.92, 0.96)
    c.draw_rect(Rect2(at + Vector2(-110, -130), Vector2(220, 130)), white)
    _poly(c, at, [Vector2(-60, -130), Vector2(0, -170), Vector2(60, -130)], white)
    c.draw_rect(Rect2(at + Vector2(-34, -230), Vector2(68, 80)), white)
    c.draw_colored_polygon(Draw2D.dome(at + Vector2(0, -228), 46, 60), green)
    c.draw_rect(Rect2(at + Vector2(-3, -300), Vector2(6, 16)), _GOLD)
    for x in [-90, 90]:
        c.draw_rect(Rect2(at + Vector2(x - 14, -170), Vector2(28, 40)), white)
        c.draw_colored_polygon(Draw2D.dome(at + Vector2(x, -168), 20, 26), green)
    for x in [-60, -30, 30, 60]:
        c.draw_rect(Rect2(at + Vector2(x - 5, -110), Vector2(10, 80)), Color(0.8, 0.82, 0.88))
    _windows(c, at, [-90, 90], -100, Vector2(14, 26))


## A little sauna cabin with smoke from the chimney, by a frozen lake.
static func sauna(c: CanvasItem, at: Vector2) -> void:
    c.draw_colored_polygon(Draw2D.ellipse(at + Vector2(0, -4), 150, 14), Color(0.55, 0.7, 0.9, 0.7))
    var wood := Color(0.5, 0.32, 0.2)
    c.draw_rect(Rect2(at + Vector2(-60, -70), Vector2(120, 70)), wood)
    for k in range(4):
        c.draw_line(
            at + Vector2(-60, -14 - k * 16), at + Vector2(60, -14 - k * 16), wood.darkened(0.25), 2
        )
    _poly(c, at, [Vector2(-76, -68), Vector2(0, -118), Vector2(76, -68)], _SNOW)
    _windows(c, at, [20], -50, Vector2(22, 18))
    c.draw_rect(Rect2(at + Vector2(-40, -130), Vector2(14, 36)), _DARK)
    for k in range(5):
        c.draw_circle(
            at + Vector2(-34 + k * 8, -146 - k * 18), 10 + k * 3, Color(1, 1, 1, 0.5 - k * 0.08)
        )


## The towers of the old town of Tallinn: red cones and a city wall.
static func tallinn(c: CanvasItem, at: Vector2) -> void:
    var stone := Color(0.82, 0.8, 0.74)
    var red := Color(0.78, 0.3, 0.22)
    c.draw_rect(Rect2(at + Vector2(-200, -70), Vector2(400, 70)), stone)
    for x in [-170, -60, 60, 170]:
        c.draw_rect(Rect2(at + Vector2(x - 26, -150), Vector2(52, 150)), stone)
        _poly(c, at, [Vector2(x - 32, -150), Vector2(x, -240), Vector2(x + 32, -150)], red)
        _poly(c, at, [Vector2(x - 20, -168), Vector2(x, -232), Vector2(x - 4, -170)], _SNOW)
        _windows(c, at, [x], -120, Vector2(10, 18))
    # Tall Hermann with the flag of Estonia
    c.draw_rect(Rect2(at + Vector2(-26, -260), Vector2(52, 260)), stone.darkened(0.05))
    c.draw_line(at + Vector2(0, -260), at + Vector2(0, -320), _DARK, 4)
    for k in range(3):
        var flag: Color = [Color(0.0, 0.45, 0.85), Color(0.08, 0.08, 0.08), Color(1, 1, 1)][k]
        c.draw_rect(Rect2(at + Vector2(2, -320 + k * 10), Vector2(46, 10)), flag)


## The House of the Blackheads in Riga: a stepped, ornate gable.
static func house_of_blackheads(c: CanvasItem, at: Vector2) -> void:
    var white := Color(0.96, 0.95, 0.9)
    _poly(
        c,
        at,
        [
            Vector2(-110, 0),
            Vector2(-110, -150),
            Vector2(-90, -150),
            Vector2(-90, -190),
            Vector2(-60, -190),
            Vector2(-60, -230),
            Vector2(-30, -230),
            Vector2(-30, -270),
            Vector2(30, -270),
            Vector2(30, -230),
            Vector2(60, -230),
            Vector2(60, -190),
            Vector2(90, -190),
            Vector2(90, -150),
            Vector2(110, -150),
            Vector2(110, 0)
        ],
        _BRICK
    )
    for y in [-150, -190, -230]:
        c.draw_rect(Rect2(at + Vector2(-110, y), Vector2(220, 8)), white)
    for row in range(3):
        _windows(c, at, [-70, -30, 30, 70], -130 + row * 40, Vector2(18, 24))
    c.draw_circle(at + Vector2(0, -210), 14, _GOLD)
    _poly(c, at, [Vector2(-6, -270), Vector2(0, -300), Vector2(6, -270)], _DARK)


## The Freedom Monument in Riga: a column with a figure holding up three stars.
static func freedom_monument(c: CanvasItem, at: Vector2) -> void:
    var stone := Color(0.85, 0.82, 0.76)
    c.draw_rect(Rect2(at + Vector2(-40, -50), Vector2(80, 50)), stone)
    c.draw_rect(Rect2(at + Vector2(-16, -230), Vector2(32, 180)), stone)
    var copper := Color(0.4, 0.62, 0.56)
    c.draw_colored_polygon(Draw2D.ellipse(at + Vector2(0, -262), 12, 32), copper)
    c.draw_line(at + Vector2(0, -280), at + Vector2(0, -330), copper, 8)
    for k in range(3):
        var star := at + Vector2(-24 + k * 24, -340)
        c.draw_circle(star, 9, _GOLD)


## Gediminas' Tower on its castle hill in Vilnius, with the flag of Lithuania.
static func gediminas_tower(c: CanvasItem, at: Vector2) -> void:
    c.draw_colored_polygon(Draw2D.dome(at, 190, 110), Color(0.9, 0.94, 0.99))
    var top := at + Vector2(0, -110)
    c.draw_rect(Rect2(top + Vector2(-50, -150), Vector2(100, 150)), _BRICK)
    c.draw_rect(Rect2(top + Vector2(-16, -150), Vector2(32, 150)), _BRICK_DARK)
    for k in range(5):
        c.draw_rect(Rect2(top + Vector2(-50 + k * 22, -166), Vector2(12, 16)), _BRICK)
    _windows(c, top, [-28, 28], -110, Vector2(12, 22))
    c.draw_line(top + Vector2(0, -166), top + Vector2(0, -230), _DARK, 4)
    var colors := [Color(0.99, 0.73, 0.07), Color(0.0, 0.42, 0.27), Color(0.76, 0.15, 0.18)]
    for k in range(3):
        c.draw_rect(Rect2(top + Vector2(2, -230 + k * 10), Vector2(46, 10)), colors[k])


## Mir Castle in Belarus: red brick towers with white ornaments.
static func mir_castle(c: CanvasItem, at: Vector2) -> void:
    c.draw_rect(Rect2(at + Vector2(-190, -110), Vector2(380, 110)), _BRICK)
    for x in [-170, -60, 60, 170]:
        var h := 220.0 if absf(x) < 100 else 180.0
        c.draw_rect(Rect2(at + Vector2(x - 30, -h), Vector2(60, h)), _BRICK)
        for k in range(3):
            c.draw_rect(Rect2(at + Vector2(x - 30, -h + 30 + k * 50), Vector2(60, 6)), _WHITE)
        _poly(
            c,
            at,
            [Vector2(x - 36, -h), Vector2(x, -h - 70), Vector2(x + 36, -h)],
            Color(0.36, 0.42, 0.38)
        )
        _poly(
            c, at, [Vector2(x - 22, -h - 18), Vector2(x, -h - 64), Vector2(x - 4, -h - 18)], _SNOW
        )
        _windows(c, at, [x], -h + 50, Vector2(12, 20))
    _poly(c, at, [Vector2(-130, -110), Vector2(0, -150), Vector2(130, -110)], _SNOW)


## St. Basil's Cathedral in Moscow: colorful onion domes.
static func st_basil(c: CanvasItem, at: Vector2) -> void:
    c.draw_rect(Rect2(at + Vector2(-150, -90), Vector2(300, 90)), _BRICK)
    var domes := [
        [Vector2(0, -250), 48.0, Color(0.95, 0.8, 0.2), Color(0.85, 0.25, 0.2)],
        [Vector2(-90, -170), 36.0, Color(0.25, 0.6, 0.35), Color(0.95, 0.85, 0.3)],
        [Vector2(90, -170), 36.0, Color(0.2, 0.45, 0.8), Color(0.98, 0.98, 0.95)],
        [Vector2(-140, -130), 26.0, Color(0.9, 0.3, 0.25), Color(0.25, 0.6, 0.35)],
        [Vector2(140, -130), 26.0, Color(0.3, 0.7, 0.7), Color(0.95, 0.8, 0.2)],
    ]
    for dome in domes:
        var center: Vector2 = at + dome[0]
        var r: float = dome[1]
        c.draw_rect(
            Rect2(center + Vector2(-r * 0.7, 0), Vector2(r * 1.4, at.y - center.y - 80)),
            _BRICK.lightened(0.1)
        )
        _onion(c, center, r, dome[2], dome[3])


static func _onion(c: CanvasItem, center: Vector2, r: float, color: Color, stripe: Color) -> void:
    c.draw_colored_polygon(Draw2D.ellipse(center + Vector2(0, -r * 0.2), r, r * 0.9), color)
    _poly(
        c,
        center,
        [Vector2(-r * 0.6, -r * 0.8), Vector2(0, -r * 1.9), Vector2(r * 0.6, -r * 0.8)],
        color
    )
    for k in [-1, 0, 1]:
        c.draw_line(
            center + Vector2(k * r * 0.5, r * 0.6), center + Vector2(0, -r * 1.7), stripe, 4
        )
    c.draw_line(center + Vector2(0, -r * 1.9), center + Vector2(0, -r * 2.4), _GOLD, 3)
    c.draw_line(center + Vector2(-8, -r * 2.2), center + Vector2(8, -r * 2.2), _GOLD, 3)


## A tower of the Kremlin with its red star.
static func kremlin_tower(c: CanvasItem, at: Vector2) -> void:
    c.draw_rect(Rect2(at + Vector2(-120, -60), Vector2(240, 60)), _BRICK)
    for k in range(10):
        c.draw_rect(Rect2(at + Vector2(-118 + k * 24, -76), Vector2(14, 16)), _BRICK)
    c.draw_rect(Rect2(at + Vector2(-34, -200), Vector2(68, 200)), _BRICK)
    c.draw_rect(Rect2(at + Vector2(-24, -250), Vector2(48, 50)), _BRICK_DARK)
    _poly(c, at, [Vector2(-28, -250), Vector2(0, -330), Vector2(28, -250)], Color(0.25, 0.42, 0.32))
    c.draw_circle(at + Vector2(0, -170), 14, _WHITE)
    var star := PackedVector2Array()
    for i in range(10):
        var a := -PI / 2 + i * PI / 5
        var r := 16.0 if i % 2 == 0 else 7.0
        star.append(at + Vector2(0, -346) + Vector2(cos(a), sin(a)) * r)
    c.draw_colored_polygon(star, Color(0.9, 0.12, 0.15))


## Bayterek in Astana: a white tree of steel holding a golden egg.
static func bayterek(c: CanvasItem, at: Vector2) -> void:
    var white := Color(0.96, 0.97, 0.99)
    c.draw_rect(Rect2(at + Vector2(-60, -20), Vector2(120, 20)), Color(0.8, 0.82, 0.86))
    _poly(
        c, at, [Vector2(-22, -20), Vector2(-12, -250), Vector2(12, -250), Vector2(22, -20)], white
    )
    for s in [-1.0, 1.0]:
        for k in range(4):
            var root := at + Vector2(s * 8, -200 - k * 10)
            var tip := root + Vector2(s * (50 - k * 6), -60 - k * 8)
            c.draw_line(root, tip, white, 5)
    c.draw_circle(at + Vector2(0, -300), 48, Color(0.9, 0.62, 0.18))
    c.draw_circle(at + Vector2(-10, -312), 38, _GOLD)
    c.draw_circle(at + Vector2(-20, -326), 12, Color(1, 0.95, 0.7))


## Khan Shatyr in Astana: a huge, tilted tent of glass.
static func khan_shatyr(c: CanvasItem, at: Vector2) -> void:
    _poly(
        c,
        at,
        [Vector2(-130, 0), Vector2(-20, -260), Vector2(10, -262), Vector2(120, 0)],
        Color(0.78, 0.86, 0.9)
    )
    for k in range(5):
        c.draw_line(
            at + Vector2(-130 + k * 62, 0),
            at + Vector2(-20 + k * 7, -260),
            Color(0.6, 0.7, 0.78),
            3
        )
    c.draw_line(at + Vector2(-20, -260), at + Vector2(0, -300), Color(0.6, 0.66, 0.72), 5)


## The Grossmünster in Zurich: twin towers with domed tops, by the frozen lake.
static func grossmuenster(c: CanvasItem, at: Vector2) -> void:
    c.draw_colored_polygon(
        Draw2D.ellipse(at + Vector2(-500, 0), 420, 16), Color(0.6, 0.75, 0.9, 0.8)
    )
    var stone := Color(0.86, 0.83, 0.76)
    var shade := Color(0.74, 0.71, 0.64)
    c.draw_rect(Rect2(at + Vector2(-120, -110), Vector2(240, 110)), stone)
    _poly(
        c, at, [Vector2(-130, -108), Vector2(0, -160), Vector2(130, -108)], Color(0.52, 0.3, 0.22)
    )
    _poly(c, at, [Vector2(-110, -112), Vector2(0, -156), Vector2(-20, -118)], _SNOW)
    for x in [-60, 60]:
        c.draw_rect(Rect2(at + Vector2(x - 32, -270), Vector2(64, 270)), stone)
        c.draw_rect(Rect2(at + Vector2(x + 14, -270), Vector2(18, 270)), shade)
        c.draw_rect(Rect2(at + Vector2(x - 38, -280), Vector2(76, 14)), shade)
        c.draw_rect(Rect2(at + Vector2(x - 26, -318), Vector2(52, 40)), stone)
        c.draw_colored_polygon(Draw2D.dome(at + Vector2(x, -316), 30, 34), Color(0.36, 0.38, 0.4))
        _poly(c, at, [Vector2(x - 4, -350), Vector2(x, -372), Vector2(x + 4, -350)], _GOLD)
        for row in range(3):
            c.draw_rect(Rect2(at + Vector2(x - 8, -250 + row * 60), Vector2(16, 30)), _DARK)
        c.draw_circle(at + Vector2(x, -300), 9, Color(0.3, 0.5, 0.75))


## St. Michael's Golden-Domed Monastery in Kyiv: sky-blue walls, golden domes.
static func st_michael(c: CanvasItem, at: Vector2) -> void:
    var blue := Color(0.45, 0.7, 0.92)
    var white := Color(0.97, 0.97, 0.95)
    c.draw_rect(Rect2(at + Vector2(-160, -120), Vector2(320, 120)), blue)
    c.draw_rect(Rect2(at + Vector2(-160, -126), Vector2(320, 10)), white)
    for x in [-120, -60, 60, 120]:
        c.draw_rect(Rect2(at + Vector2(x - 8, -100), Vector2(16, 36)), white)
    c.draw_rect(Rect2(at + Vector2(-24, -60), Vector2(48, 60)), white)
    var domes := [[Vector2(0, -230), 40.0], [Vector2(-110, -170), 26.0], [Vector2(110, -170), 26.0]]
    for dome in domes:
        var center: Vector2 = at + dome[0]
        var r: float = dome[1]
        c.draw_rect(
            Rect2(
                center + Vector2(-r * 0.8, r * 0.4),
                Vector2(r * 1.6, at.y - center.y - 120 - r * 0.4)
            ),
            blue
        )
        c.draw_rect(Rect2(center + Vector2(-r * 0.8, r * 0.4), Vector2(r * 1.6, 6)), white)
        c.draw_colored_polygon(Draw2D.ellipse(center, r, r * 0.85), _GOLD)
        _poly(
            c,
            center,
            [Vector2(-r * 0.5, -r * 0.6), Vector2(0, -r * 1.6), Vector2(r * 0.5, -r * 0.6)],
            _GOLD
        )
        c.draw_circle(center + Vector2(-r * 0.3, -r * 0.2), r * 0.25, Color(1, 0.95, 0.7))
        c.draw_line(center + Vector2(0, -r * 1.6), center + Vector2(0, -r * 2.2), _GOLD, 3)
        c.draw_line(center + Vector2(-7, -r * 2.0), center + Vector2(7, -r * 2.0), _GOLD, 3)
