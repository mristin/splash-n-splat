#!/usr/bin/env -S godot --headless --script
extends SceneTree

## Write the license of Godot Engine and the notices of its third-party
## components into licenses/godot/, as the Godot binary reports them.
##
## We distribute Godot Engine with every exported game, so the release packages
## carry its license and the notices of the components it includes. Only
## the Godot binary knows them exactly, through its Engine API.
##
## Run it whenever we upgrade Godot. If godot is on your path, simply:
##
##   dev/write_godot_licenses.gd
##
## Otherwise:
##
##   $GODOT --headless --script dev/write_godot_licenses.gd
##
## Set OUT_DIR to write somewhere else.


func _initialize() -> void:
    # NOTE (mristin):
    # We write next to this script, into the repository's licenses/godot/,
    # unless OUT_DIR says otherwise.
    var out := OS.get_environment("OUT_DIR")
    if out.is_empty():
        var script_path := ProjectSettings.globalize_path((get_script() as Script).resource_path)
        out = script_path.get_base_dir().get_base_dir().path_join("licenses").path_join("godot")
    DirAccess.make_dir_recursive_absolute(out)
    var license := FileAccess.open(out + "/LICENSE.txt", FileAccess.WRITE)
    license.store_string(Engine.get_license_text())
    license.close()

    var lines: PackedStringArray = []
    lines.append("Godot Engine includes the following third-party components.")
    lines.append("Generated from Engine.get_copyright_info() and Engine.get_license_info()")
    lines.append("of Godot " + Engine.get_version_info()["string"] + ".")
    lines.append("")
    for component in Engine.get_copyright_info():
        lines.append("Component: " + component["name"])
        for part in component["parts"]:
            for file in part["files"]:
                lines.append("  Files: " + file)
            for holder in part["copyright"]:
                lines.append("  Copyright: " + holder)
            lines.append("  License: " + part["license"])
        lines.append("")
    var licenses: Dictionary = Engine.get_license_info()
    var names := licenses.keys()
    names.sort()
    for name in names:
        lines.append("License: " + name)
        lines.append("")
        lines.append(licenses[name])
        lines.append("")
    var copyright := FileAccess.open(out + "/COPYRIGHT.txt", FileAccess.WRITE)
    copyright.store_string("\n".join(lines))
    copyright.close()
    quit(0)