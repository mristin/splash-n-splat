class_name CountryTheme
extends LevelTheme

## The palette of a winter country, from its description in [Countries].


func _init(country: Dictionary = {}) -> void:
    var sky: Array = country.get("sky", [Color(0.42, 0.68, 0.94), Color(0.84, 0.92, 1.0)])
    var ground: Array = country.get("ground", [Color(0.86, 0.91, 0.97), Color(0.985, 0.99, 1.0)])
    sky_top = sky[0]
    sky_horizon = sky[1]
    ground_far = ground[0]
    ground_near = ground[1]
    projectile = ProjectileStyle.snowball()
