extends SceneTree


func _initialize() -> void:
	call_deferred("build_resources")


func build_resources() -> void:
	# Wait for Godot's import pipeline so the extracted PNGs are available as
	# Texture2D resources before they are embedded in the MeshLibrary.
	await process_frame
	var data = load("res://scripts/course_data.gd")
	var library: MeshLibrary = data.build_mesh_library()
	var error: Error = ResourceSaver.save(library, "res://assets/jajucha_panels.tres")
	if error != OK:
		push_error("MeshLibrary save failed: %s" % error_string(error))
		quit(1)
		return
	var grid := GridMap.new()
	grid.name = "Course"
	grid.mesh_library = library
	data.fill_grid(grid)
	grid.position = Vector3(-4.5, 0.0, -2.25)
	grid.set_meta("manual_source", "2026 track construction manual page 2")
	grid.set_meta("documented_panel_size_mm", Vector2i(900, 900))
	grid.set_meta("documented_assembly_bounds_m", Vector2(9.9, 5.4))
	var packed := PackedScene.new()
	var pack_error: Error = packed.pack(grid)
	if pack_error != OK:
		push_error("Course scene pack failed: %s" % error_string(pack_error))
		quit(1)
		return
	error = ResourceSaver.save(packed, "res://scenes/course_assembly.tscn")
	if error != OK:
		push_error("Course scene save failed: %s" % error_string(error))
		quit(1)
		return
	print("Created editable 900 mm GridMap MeshLibrary and 41-cell manual assembly.")
	quit(0)
