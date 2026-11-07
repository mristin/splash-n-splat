class_name CoverFront
extends Node2D

## Draw the cover of a [CoverSpot] in front of its bear.

var spot: CoverSpot


func _draw() -> void:
    if spot.rises():
        # NOTE (mristin):
        # Paint the ground below the origin, with the gradient of the snowfield
        # in global coordinates.
        var half := spot.ridge_length * 0.5 + 120 if spot.kind == CoverSpot.Kind.RIDGE else 140.0
        var depth := 300.0
        var top := spot.theme.ground_at(spot.global_position.y)
        var bottom := spot.theme.ground_at(spot.global_position.y + depth * spot.scale.y)
        draw_polygon(
            PackedVector2Array(
                [Vector2(-half, 0), Vector2(half, 0), Vector2(half, depth), Vector2(-half, depth)]
            ),
            PackedColorArray([top, top, bottom, bottom])
        )

    match spot.kind:
        CoverSpot.Kind.DRIFT:
            _draw_drift()
        CoverSpot.Kind.IGLOO:
            _draw_igloo()
        CoverSpot.Kind.BOULDER:
            _draw_boulder()
        CoverSpot.Kind.RIDGE:
            _draw_ridge()
        CoverSpot.Kind.FLOE:
            _draw_floe()
        CoverSpot.Kind.ICEBERG:
            _draw_iceberg()
        CoverSpot.Kind.SEA_ROCK:
            _draw_sea_rock()
        CoverSpot.Kind.SPRUCE:
            _draw_spruce()
        CoverSpot.Kind.SNOWMAN:
            _draw_snowman()
        CoverSpot.Kind.WOODPILE:
            _draw_woodpile()
        CoverSpot.Kind.YURT:
            _draw_yurt()


func _draw_drift() -> void:
    draw_colored_polygon(Draw2D.ellipse(Vector2(10, 42), 190, 26), Color(WinterTheme.SHADOW, 0.5))
    draw_colored_polygon(Draw2D.dome(Vector2(0, 40), 175, 115), WinterTheme.SNOW)
    draw_colored_polygon(Draw2D.dome(Vector2(-40, 40), 110, 85), Color.WHITE)
    # NOTE (mristin):
    # A soft outline along the top of the drift.
    var outline := Draw2D.dome(Vector2(0, 40), 175, 115, 24)
    outline.remove_at(outline.size() - 1)
    draw_polyline(outline.slice(2, outline.size() - 2), Color(WinterTheme.SHADOW, 0.7), 4, true)


func _draw_igloo() -> void:
    draw_colored_polygon(Draw2D.dome(Vector2(0, 30), 160, 165), Color(0.93, 0.97, 1.0))
    for row in range(1, 4):
        var y := 30.0 - row * 40
        var half := 160 * sqrt(maxf(0.0, 1 - pow((30 - y) / 165.0, 2)))
        draw_line(Vector2(-half, y), Vector2(half, y), WinterTheme.ICE.darkened(0.12), 3)
    draw_colored_polygon(Draw2D.dome(Vector2(0, 30), 52, 70), WinterTheme.DEEP_SHADOW)
    draw_colored_polygon(Draw2D.ellipse(Vector2(0, 36), 190, 22), Color(0.98, 0.99, 1.0))


func _draw_boulder() -> void:
    draw_colored_polygon(Draw2D.blob(Vector2(0, -115), 145, 0.06, 3), WinterTheme.ROCK_DARK)
    draw_colored_polygon(Draw2D.blob(Vector2(-12, -125), 128, 0.07, 5), WinterTheme.ROCK)
    draw_colored_polygon(Draw2D.dome(Vector2(-10, -170), 120, 85), WinterTheme.SNOW)
    draw_colored_polygon(Draw2D.ellipse(Vector2(0, 8), 200, 30), Color(0.98, 0.99, 1.0))


func _draw_ridge() -> void:
    var l := spot.ridge_length * 0.5
    draw_colored_polygon(
        PackedVector2Array(
            [Vector2(-l - 60, 40), Vector2(-l, -90), Vector2(l, -90), Vector2(l + 60, 40)]
        ),
        Color(0.95, 0.975, 1.0)
    )
    for i in range(9):
        draw_circle(Vector2(-l + i * (2 * l / 8.0), -88), 26, Color(0.99, 0.995, 1.0))
    draw_line(Vector2(-l - 50, 20), Vector2(l + 50, 20), Color(WinterTheme.SHADOW, 0.6), 6)


## Draw the ripple of the sea around the base of a cover.
func _draw_ripple(center: Vector2, rx: float) -> void:
    draw_colored_polygon(Draw2D.ellipse(center, rx, 24), Color(GreenlandTheme.SEA_SHADOW, 0.55))
    # NOTE (mristin):
    # A glint along the near half of the ripple (draw_arc only draws circles).
    var glint := PackedVector2Array()
    for i in range(1, 12):
        var angle := i * PI / 12
        glint.append(center + Vector2(cos(angle) * rx * 0.92, sin(angle) * 20 - 4))
    draw_polyline(glint, Color(1, 1, 1, 0.55), 4, true)


func _draw_floe() -> void:
    _draw_ripple(Vector2(0, 44), 205)
    # The front face of the slab, then its top, lit from above.
    draw_colored_polygon(
        PackedVector2Array(
            [
                Vector2(-185, -40),
                Vector2(185, -46),
                Vector2(178, 36),
                Vector2(60, 46),
                Vector2(-90, 42),
                Vector2(-180, 32)
            ]
        ),
        GreenlandTheme.ICE_SIDE
    )
    draw_colored_polygon(
        PackedVector2Array(
            [
                Vector2(-185, -40),
                Vector2(-120, -96),
                Vector2(40, -104),
                Vector2(150, -88),
                Vector2(185, -46),
                Vector2(20, -30)
            ]
        ),
        GreenlandTheme.ICE_TOP
    )
    draw_line(Vector2(-150, 6), Vector2(150, 0), Color(GreenlandTheme.ICE_DEEP, 0.5), 4)


func _draw_iceberg() -> void:
    _draw_ripple(Vector2(0, 36), 185)
    draw_colored_polygon(
        PackedVector2Array(
            [
                Vector2(-170, 34),
                Vector2(-150, -40),
                Vector2(-96, -120),
                Vector2(-40, -110),
                Vector2(6, -172),
                Vector2(70, -96),
                Vector2(120, -110),
                Vector2(170, 34)
            ]
        ),
        GreenlandTheme.ICE_TOP
    )
    # The shady side with its blue crevices
    draw_colored_polygon(
        PackedVector2Array(
            [
                Vector2(6, -172),
                Vector2(70, -96),
                Vector2(120, -110),
                Vector2(170, 34),
                Vector2(30, 34)
            ]
        ),
        GreenlandTheme.ICE_SIDE
    )
    for crevice in [[Vector2(-70, -60), Vector2(-56, 10)], [Vector2(90, -50), Vector2(80, 20)]]:
        draw_line(crevice[0], crevice[1], GreenlandTheme.ICE_DEEP, 5)


func _draw_sea_rock() -> void:
    draw_colored_polygon(Draw2D.blob(Vector2(0, -110), 145, 0.08, 4), GreenlandTheme.SEA_ROCK_DARK)
    draw_colored_polygon(Draw2D.blob(Vector2(-12, -120), 128, 0.09, 6), GreenlandTheme.SEA_ROCK)
    draw_colored_polygon(Draw2D.dome(Vector2(-18, -175), 100, 60), WinterTheme.SNOW)
    # Seaweed near the water line, then the sea around the foot of the rock
    for x in [-90, -40, 30, 90]:
        draw_circle(Vector2(x, -4), 12, Color(0.3, 0.42, 0.34))
    draw_colored_polygon(
        Draw2D.ellipse(Vector2(0, 22), 210, 30), spot.theme.ground_at(spot.global_position.y)
    )
    _draw_ripple(Vector2(0, 14), 190)


func _draw_spruce() -> void:
    draw_colored_polygon(Draw2D.ellipse(Vector2(0, 8), 170, 26), Color(WinterTheme.SHADOW, 0.6))
    draw_rect(Rect2(-18, -60, 36, 64), WinterTheme.BARK)
    # NOTE (mristin):
    # A chunky spruce, so that it hides a critter which is about to lean out.
    for i in range(5):
        var bottom := 6.0 - i * 50
        var half := 160.0 - i * 20
        draw_colored_polygon(
            PackedVector2Array(
                [Vector2(-half, bottom), Vector2(half, bottom), Vector2(0, bottom - 120)]
            ),
            WinterTheme.PINE if i % 2 == 0 else WinterTheme.PINE_DARK
        )
        draw_colored_polygon(
            PackedVector2Array(
                [
                    Vector2(-half * 0.7, bottom - 26),
                    Vector2(half * 0.7, bottom - 26),
                    Vector2(half * 0.35, bottom - 12),
                    Vector2(0, bottom - 20),
                    Vector2(-half * 0.45, bottom - 10)
                ]
            ),
            WinterTheme.SNOW
        )
    draw_colored_polygon(Draw2D.ellipse(Vector2(0, 10), 180, 26), Color(0.98, 0.99, 1.0))


func _draw_snowman() -> void:
    draw_colored_polygon(Draw2D.ellipse(Vector2(10, 10), 150, 24), Color(WinterTheme.SHADOW, 0.5))
    draw_circle(Vector2(4, -88), 108, WinterTheme.SHADOW)
    draw_circle(Vector2(0, -92), 104, WinterTheme.SNOW)
    draw_circle(Vector2(4, -238), 72, WinterTheme.SHADOW)
    draw_circle(Vector2(0, -242), 68, WinterTheme.SNOW)
    # Buttons, the face, the carrot and the hat
    for k in range(3):
        draw_circle(Vector2(0, -150 + k * 36), 9, Critter.INK)
    for x in [-22, 22]:
        draw_circle(Vector2(x, -258), 8, Critter.INK)
    draw_colored_polygon(
        PackedVector2Array([Vector2(-4, -246), Vector2(-4, -230), Vector2(56, -236)]),
        Color(1.0, 0.55, 0.15)
    )
    for k in range(5):
        draw_circle(Vector2(-26 + k * 13, -212 + absf(k - 2) * -5), 4, Critter.INK)
    draw_rect(Rect2(-60, -318, 120, 12), Critter.INK)
    draw_rect(Rect2(-40, -380, 80, 64), Critter.INK)
    draw_rect(Rect2(-40, -336, 80, 12), Color(0.85, 0.2, 0.2))
    draw_colored_polygon(Draw2D.ellipse(Vector2(0, 8), 170, 26), Color(0.98, 0.99, 1.0))


func _draw_woodpile() -> void:
    draw_colored_polygon(Draw2D.ellipse(Vector2(10, 42), 200, 26), Color(WinterTheme.SHADOW, 0.5))
    var wood := Color(0.62, 0.42, 0.26)
    var rings := Color(0.86, 0.7, 0.5)
    for row in range(3):
        var count := 5 - row
        for k in range(count):
            var center := Vector2((k - (count - 1) * 0.5) * 66, 6 - row * 52)
            draw_circle(center, 33, wood)
            draw_circle(center, 25, rings)
            draw_arc(center, 13, 0, TAU, 16, wood, 3)
    draw_colored_polygon(Draw2D.dome(Vector2(0, -116), 110, 34), WinterTheme.SNOW)
    draw_colored_polygon(Draw2D.ellipse(Vector2(0, 40), 200, 22), Color(0.98, 0.99, 1.0))


func _draw_yurt() -> void:
    var felt := Color(0.96, 0.94, 0.88)
    var red := Color(0.8, 0.2, 0.2)
    draw_colored_polygon(Draw2D.ellipse(Vector2(10, 36), 200, 26), Color(WinterTheme.SHADOW, 0.5))
    draw_rect(Rect2(-160, -70, 320, 104), felt)
    draw_colored_polygon(
        PackedVector2Array([Vector2(-170, -66), Vector2(0, -170), Vector2(170, -66)]),
        felt.darkened(0.05)
    )
    draw_colored_polygon(Draw2D.dome(Vector2(0, -150), 46, 22), WinterTheme.SNOW)
    # The ornament bands of the felt, and the door
    draw_rect(Rect2(-160, -70, 320, 14), red)
    for k in range(-4, 5):
        draw_colored_polygon(
            PackedVector2Array(
                [Vector2(k * 34 - 10, -56), Vector2(k * 34, -44), Vector2(k * 34 + 10, -56)]
            ),
            red
        )
    draw_rect(Rect2(-34, -40, 68, 74), Color(0.85, 0.55, 0.2))
    draw_rect(Rect2(-26, -32, 52, 66), red)
    draw_colored_polygon(Draw2D.ellipse(Vector2(0, 36), 200, 22), Color(0.98, 0.99, 1.0))
