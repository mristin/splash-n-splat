class_name GameSettings
extends RefCounted

## The settings given on the command line after [code]--[/code]:
##
## [code]--no-camera[/code]: do not open the camera (for the automatic tests,
## which drive the game themselves).[br]
## [code]--debug[/code]: show the debug overlay.[br]
## [code]--no-mirror[/code]: do not mirror the camera horizontally.[br]
## [code]--camera=N[/code]: use the N-th compatible camera.[br]
## [code]--windowed[/code]: start in a 1280x720 window instead of the full screen.[br]
## [code]--vision-config=PATH[/code]: load the vision settings from a JSON file
## (default: user://vision.json if it exists).[br]
## [code]--seed=N[/code]: make the critters deterministic.[br]
## [code]--level=N[/code]: start at the N-th level (1: the North Pole, 2: Greenland,
## 3 to 13: the countries from Iceland to Kazakhstan, 14: Zurich).[br]
## [code]--record-play[=DIR][/code]: record the frames, the hands and the game events
## while playing (default DIR: user://gameplay/<time>), for the automatic labeling
## with dev/computer_vision/auto_label_gameplay.py.[br]
## [code]--benchmark=SECONDS[/code]: play by itself for the given time, print the
## render rate and the vision latencies, and quit.

var use_camera := true
var debug := false
var mirror := true
var camera_index := 0
var windowed := false
var vision_config_path := "user://vision.json"
var seed_value := -1
var level := 1
var benchmark_seconds := 0.0
var record_play_dir := ""


static func from_command_line() -> GameSettings:
    var settings := GameSettings.new()
    for arg in OS.get_cmdline_user_args():
        if arg == "--no-camera":
            settings.use_camera = false
        elif arg == "--debug":
            settings.debug = true
        elif arg == "--no-mirror":
            settings.mirror = false
        elif arg == "--windowed":
            settings.windowed = true
        elif arg.begins_with("--camera="):
            settings.camera_index = int(arg.trim_prefix("--camera="))
        elif arg.begins_with("--vision-config="):
            settings.vision_config_path = arg.trim_prefix("--vision-config=")
        elif arg == "--record-play":
            settings.record_play_dir = (
                "user://gameplay/" + Time.get_datetime_string_from_system().replace(":", "")
            )
        elif arg.begins_with("--record-play="):
            settings.record_play_dir = arg.trim_prefix("--record-play=")
        elif arg.begins_with("--benchmark="):
            settings.benchmark_seconds = float(arg.trim_prefix("--benchmark="))
        elif arg.begins_with("--level="):
            settings.level = int(arg.trim_prefix("--level="))
        elif arg.begins_with("--seed="):
            settings.seed_value = int(arg.trim_prefix("--seed="))
        else:
            push_warning("Unknown argument: %s" % arg)
    return settings
