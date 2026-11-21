extends SceneTree
## Development helper: the Fish sheets are painted on the pack's flat water
## colour with no alpha. This copies them into sprites/custom with the water
## colour keyed out so the animated river shows through.
##   godot --headless --path . --script res://tools/make_fish_sheets.gd

const SHEETS := {
	"fishes_1": "res://sprites/exteriors_48x48/animated/sheets/Fishes_1_48x48gif.png",
	"fishes_2": "res://sprites/exteriors_48x48/animated/sheets/Fishes_2_48x48.png",
	"fishes_3": "res://sprites/exteriors_48x48/animated/sheets/Fishes_3_48x48.png",
}


func _initialize() -> void:
	for name: String in SHEETS:
		var img := Image.load_from_file(ProjectSettings.globalize_path(String(SHEETS[name])))
		var water := img.get_pixel(0, 0)
		var kept := 0
		for y in img.get_height():
			for x in img.get_width():
				var color := img.get_pixel(x, y)
				if absf(color.r - water.r) < 0.002 and absf(color.g - water.g) < 0.002 \
						and absf(color.b - water.b) < 0.002:
					color.a = 0.0
					img.set_pixel(x, y, color)
				else:
					kept += 1
		var out := "res://sprites/custom/%s.png" % name
		var err := img.save_png(out)
		print("%s: err=%d kept=%d" % [out, err, kept])
	quit(0)
