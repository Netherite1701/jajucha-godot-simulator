extends Node

const LAP_TIMEOUT_S := 240.0
const FINISH_LATERAL_TOLERANCE_M := 0.22
const FINISH_HEADING_TOLERANCE_DEG := 30.0
const GATES := ["right_side", "upper_right", "top_straight", "left_side", "lower_left_hairpin", "inner_upper_turn", "inner_s_bends"]

var output_dir: String
var run_log: FileAccess
var trajectory: FileAccess
var gates_passed: Array[String] = []

var _simulator: Node

func start_for(target: Node) -> void:
	_simulator = target
	call_deferred("run_attempt")

func log_line(value: String) -> void:
	print(value)
	if run_log != null:
		run_log.store_line(value)
		run_log.flush()

func run_attempt() -> void:
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "")
	var data_dir := OS.get_environment("JAJUCHA_DATA_DIR")
	if data_dir.is_empty():
		output_dir = "res://.cache/planning/fullcamera/run_" + stamp
	else:
		output_dir = data_dir.path_join("evidence").path_join("laps").path_join("run_" + stamp)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	run_log = FileAccess.open(output_dir + "/run.log", FileAccess.WRITE)
	trajectory = FileAccess.open(output_dir + "/trajectory.jsonl", FileAccess.WRITE)
	if OS.get_environment("JAJUCHA_CAPTURE_FRAMES") == "0":
		OS.set_environment("JAJUCHA_CAPTURE_DIR", "")
	else:
		OS.set_environment("JAJUCHA_CAPTURE_DIR", ProjectSettings.globalize_path(output_dir))
	var simulator := _simulator
	for i in 5:
		await get_tree().process_frame
	var vehicle: CharacterBody3D = simulator.vehicle
	var start_position := Vector2(vehicle.position.x, vehicle.position.z)
	var start_heading: float = vehicle.rotation.y
	var start_forward := Vector2(-sin(start_heading), -cos(start_heading))
	var user_source := FileAccess.get_file_as_string("res://python_bridge/user_supplied_controller.py")
	var controller_source := _verified_notebook_code()
	if controller_source.is_empty():
		finish(simulator, "LAP_VERIFIED_NOTEBOOK_MISSING", {})
		return
	var notebook_path := OS.get_executable_path().get_base_dir().path_join("notebooks/Verified_Lap_Controller.ipynb")
	if not FileAccess.file_exists(notebook_path):
		notebook_path = "res://notebooks/Verified_Lap_Controller.ipynb"
	var manifest := FileAccess.open(output_dir + "/run_manifest.json", FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"godot": Engine.get_version_info(), "execution_backend": "bundled IPython notebook kernel", "user_supplied_controller_sha256": _sha256_text(user_source), "verified_controller_sha256": _sha256_text(controller_source), "verified_notebook_path": notebook_path, "verified_notebook_cell_sha256": _sha256_text(controller_source), "calibration_sha256": _sha256_text(FileAccess.get_file_as_string("res://calibration.json")), "course_layout_sha256": _sha256_course_layout(), "panel_artwork_sha256": _sha256_panel_artwork(simulator), "start_xz_m": [start_position.x, start_position.y], "start_heading_rad": start_heading, "finish_rule": "Cross the start line in the forward direction after all seven ordered course gates and more than 30 m, within 0.22 m laterally and 30 degrees of start heading", "camera_channels": 3, "resolution_px": [640, 400]}, "\t"))
	_save_camera_bundle(simulator, "start")
	simulator.call("_notebook_execute", 7, controller_source)
	var connected := false
	for attempt in 300:
		if simulator.notebook_connected and int(simulator.notebook_active_cell_id) == 7:
			connected = true
			break
		await get_tree().create_timer(0.1).timeout
	if not connected:
		finish(simulator, "LAP_CONNECTION_FAILED", {})
		return
	log_line("LAP_ATTEMPT_STARTED backend=IPython output=%s start=%s heading=%.1fdeg" % [output_dir, start_position, rad_to_deg(start_heading)])
	var started_at: float = simulator.sim_time_s
	var previous_position := start_position
	var traveled := 0.0
	var next_report := 1.0
	var last_motion_at := 0.0
	while simulator.sim_time_s - started_at < LAP_TIMEOUT_S:
		await get_tree().create_timer(0.1).timeout
		var elapsed: float = simulator.sim_time_s - started_at
		var position := Vector2(vehicle.position.x, vehicle.position.z)
		var previous_along := (previous_position - start_position).dot(start_forward)
		var along := (position - start_position).dot(start_forward)
		var lateral := absf((position - start_position).cross(start_forward))
		if position.distance_to(previous_position) > 0.002:
			last_motion_at = elapsed
		traveled += position.distance_to(previous_position)
		previous_position = position
		if gates_passed.size() < GATES.size() and passed_gate(GATES[gates_passed.size()], position):
			gates_passed.append(GATES[gates_passed.size()])
			log_line("LAP_GATE %s elapsed=%.2fs" % [gates_passed[-1], elapsed])
		var state := {"elapsed_s": elapsed, "sim_time_s": simulator.sim_time_s, "x_m": position.x, "z_m": position.y, "yaw_deg": rad_to_deg(vehicle.rotation.y), "speed_mps": simulator.commanded_speed_mps, "steering": simulator.target_steering, "commands": simulator.python_command_count, "distance_m": traveled, "gates_passed": gates_passed.size()}
		trajectory.store_line(JSON.stringify(state))
		trajectory.flush()
		if elapsed >= next_report:
			var checkpoint := "%03d" % roundi(elapsed)
			_save_camera_bundle(simulator, checkpoint)
			log_line("LAP_PROGRESS " + JSON.stringify(state))
			next_report += 1.0
		if simulator.emergency_stopped:
			state["reason"] = simulator.stop_reason
			finish(simulator, "LAP_STOPPED", state)
			return
		if elapsed - last_motion_at > 10.0:
			finish(simulator, "LAP_STALLED", state)
			return
		if position.x < -4.7 or position.x > 5.5 or position.y < -2.4 or position.y > 3.3:
			finish(simulator, "LAP_OFF_COURSE", state)
			return
		var heading_error := absf(wrapf(vehicle.rotation.y - start_heading, -PI, PI))
		if gates_passed.size() == GATES.size() and traveled > 30.0 and previous_along < 0.0 and along >= 0.0 and lateral < FINISH_LATERAL_TOLERANCE_M and rad_to_deg(heading_error) < FINISH_HEADING_TOLERANCE_DEG:
			state["heading_error_deg"] = rad_to_deg(heading_error)
			state["finish_line_forward_m"] = along
			state["finish_line_lateral_m"] = lateral
			finish(simulator, "LAP_SUCCESS", state)
			return
	finish(simulator, "LAP_TIMEOUT", {"distance_m": traveled})

func passed_gate(gate: String, p: Vector2) -> bool:
	match gate:
		"right_side": return p.x > 4.5 and p.y < 1.8
		"upper_right": return p.x > 3.0 and p.y < -1.3
		"top_straight": return p.x < 0.0 and p.y < -1.3
		"left_side": return p.x < -3.7 and p.y > 0.0
		"lower_left_hairpin": return p.x < -3.0 and p.y > 2.5
		"inner_upper_turn": return p.x > -3.0 and p.y < 0.5
		"inner_s_bends": return p.x > -2.0 and p.y > 1.0
	return false


func _verified_notebook_code() -> String:
	var packaged_path := OS.get_executable_path().get_base_dir().path_join("notebooks/Verified_Lap_Controller.ipynb")
	var notebook_text := ""
	if FileAccess.file_exists(packaged_path):
		notebook_text = FileAccess.get_file_as_string(packaged_path)
	elif FileAccess.file_exists("res://notebooks/Verified_Lap_Controller.ipynb"):
		notebook_text = FileAccess.get_file_as_string("res://notebooks/Verified_Lap_Controller.ipynb")
	if notebook_text.is_empty():
		return ""
	var document: Variant = JSON.parse_string(notebook_text)
	if not document is Dictionary or not document.get("cells", []) is Array:
		return ""
	for cell: Variant in document.cells:
		if not cell is Dictionary or cell.get("cell_type", "") != "code":
			continue
		var source: Variant = cell.get("source", [])
		if source is String:
			return source
		if source is Array:
			var code := ""
			for segment: Variant in source:
				code += str(segment)
			return code
	return ""

func finish(simulator: Node, result: String, state: Dictionary) -> void:
	simulator.call("_notebook_interrupt")
	simulator.speed_request_mps = 0.0
	simulator.commanded_speed_mps = 0.0
	simulator.target_steering = 0.0
	if trajectory != null:
		trajectory.close()
	var coverage := _measure_road_coverage(simulator)
	var coverage_file := FileAccess.open(output_dir + "/road_coverage.json", FileAccess.WRITE)
	if coverage_file != null:
		coverage_file.store_string(JSON.stringify(coverage, "\t"))
		coverage_file.close()
	state["result"] = result
	state["gates"] = gates_passed
	state["output_dir"] = ProjectSettings.globalize_path(output_dir)
	log_line(result + " " + JSON.stringify(state))
	var summary := FileAccess.open(output_dir + "/result.json", FileAccess.WRITE)
	summary.store_string(JSON.stringify(state, "\t"))
	_save_camera_bundle(simulator, "finish")
	simulator.get_node("CanvasLayer/HUD").hide()
	simulator.set_process(false)
	simulator.set_physics_process(false)
	simulator.main_camera.global_position = Vector3(0.45, 12.0, 0.45)
	simulator.main_camera.rotation_degrees = Vector3(-90, 0, 0)
	simulator.main_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	simulator.main_camera.keep_aspect = Camera3D.KEEP_WIDTH
	simulator.main_camera.size = 11.5
	simulator.main_camera.make_current()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output_dir + "/overview.png")
	simulator.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if result == "LAP_SUCCESS" else 1)


func _sha256_text(value: String) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(value.to_utf8_buffer())
	return context.finish().hex_encode()


func _sha256_course_layout() -> String:
	var definition := {
		"tile_size_m": CourseData.TILE_SIZE,
		"panel_thickness_m": CourseData.PANEL_THICKNESS,
		"rows_from_top": CourseData.ROWS_FROM_TOP,
		"rotations_from_top": CourseData.ROTATIONS_FROM_TOP,
	}
	return _sha256_text(JSON.stringify(definition))


func _sha256_panel_artwork(simulator: Node) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	for letter: String in CourseData.TILE_NAMES:
		var texture: Texture2D = simulator.tile_textures.get(letter)
		if texture == null:
			return ""
		context.update(letter.to_utf8_buffer())
		context.update(texture.get_image().get_data())
	return context.finish().hex_encode()


func _measure_road_coverage(simulator: Node) -> Dictionary:
	var samples := 0
	var center_off_road: Array[float] = []
	var footprint_off_road: Array[float] = []
	var texture_images := {}
	for letter: String in simulator.tile_textures:
		var texture: Texture2D = simulator.tile_textures[letter]
		texture_images[letter] = texture.get_image() if texture != null else null
	if trajectory == null or not FileAccess.file_exists(output_dir + "/trajectory.jsonl"):
		return {"samples": 0, "center_off_road_samples": 0, "footprint_touching_grass_or_red_curb_samples": 0, "method": "Recorded ground-truth trajectory sampled against the actual panel artwork and rotations."}
	var recorded := FileAccess.get_file_as_string(output_dir + "/trajectory.jsonl")
	for line: String in recorded.split("\n", false):
		var state: Variant = JSON.parse_string(line)
		if not state is Dictionary or not state.has("x_m") or not state.has("z_m"):
			continue
		samples += 1
		var x := float(state.x_m)
		var z := float(state.z_m)
		var yaw := deg_to_rad(float(state.get("yaw_deg", 0.0)))
		if not _sample_road_artwork(x, z, texture_images):
			center_off_road.append(float(state.get("elapsed_s", 0.0)))
		var footprint_ok := true
		for forward: float in [-0.06331, 0.0, 0.18869]:
			for lateral: float in [-0.0888, 0.0, 0.0888]:
				var sample_x := x - sin(yaw) * forward + cos(yaw) * lateral
				var sample_z := z - cos(yaw) * forward - sin(yaw) * lateral
				if not _sample_road_artwork(sample_x, sample_z, texture_images):
					footprint_ok = false
		if not footprint_ok:
			footprint_off_road.append(float(state.get("elapsed_s", 0.0)))
	return {
		"samples": samples,
		"center_off_road_samples": center_off_road.size(),
		"footprint_touching_grass_or_red_curb_samples": footprint_off_road.size(),
		"center_off_road_times_s": center_off_road,
		"footprint_touch_times_s": footprint_off_road,
		"method": "Recorded ground-truth trajectory sampled against the actual 900 mm panel artwork and rotations; used for verification only.",
	}


func _sample_road_artwork(x: float, z: float, texture_images: Dictionary) -> bool:
	var column := floori((x + 4.5) / 0.9)
	var row := floori((z + 2.25) / 0.9)
	if column < 0 or column >= CourseData.BOARD_COLUMNS or row < 0 or row >= CourseData.BOARD_ROWS:
		return false
	var letter := CourseData.ROWS_FROM_TOP[row].substr(column, 1)
	if letter == "." or not texture_images.has(letter):
		return false
	var image: Image = texture_images[letter]
	if image == null or image.is_empty():
		return false
	var dx := x - (-4.5 + (column + 0.5) * 0.9)
	var dz := z - (-2.25 + (row + 0.5) * 0.9)
	var angle := int(CourseData.ROTATIONS_FROM_TOP[row].substr(column, 1)) * PI / 2.0
	var local_x := cos(angle) * dx - sin(angle) * dz
	var local_z := sin(angle) * dx + cos(angle) * dz
	var u := clampi(roundi((local_x / 0.9 + 0.5) * (image.get_width() - 1)), 0, image.get_width() - 1)
	var v := clampi(roundi((local_z / 0.9 + 0.5) * (image.get_height() - 1)), 0, image.get_height() - 1)
	var color := image.get_pixel(u, v) * 255.0
	var grass := color.g > color.r * 1.15 + 6.0 and color.g > color.b * 1.15 + 6.0
	var curb_red := color.r > color.g * 1.5 + 30.0 and color.r > color.b * 1.5 + 30.0
	return not grass and not curb_red

func _save_camera_bundle(simulator: Node, label: String) -> void:
	for camera_name in ["left", "center", "right"]:
		var camera_image: Image = simulator.camera_images.get("%s_rgb" % camera_name)
		if camera_image != null and not camera_image.is_empty():
			camera_image.save_png("%s/%s_%s.png" % [output_dir, label, camera_name])
	var python_output := simulator.dashboard.python_output as TextureRect
	if python_output.texture != null:
		python_output.texture.get_image().save_png("%s/%s_bev.png" % [output_dir, label])
