extends Node3D

const TILE_SIZE: float = 0.9
const PANEL_THICKNESS_M: float = 0.003
const VEHICLE_WIDTH_M: float = 0.1776
const TIRE_WIDTH_M: float = 0.027
const VISUAL_CHASSIS_LENGTH_M: float = 0.252 # provisional body length from reference mesh layout
const CAMERA_HEIGHT_M: float = 0.09900903
const CAMERA_HEIGHT_PHOTO_ESTIMATE_M: float = 0.075
const CAMERA_SETBACK_FROM_FRONT_M: float = 0.053
const LIDAR_SETBACK_FROM_FRONT_M: float = 0.150
const ADJACENT_CAMERA_SPACING_M: float = 0.029
const FRONT_EDGE_FROM_REAR_AXLE_M: float = 0.18869332307
const LIDAR_HEIGHT_M: float = 0.075
const CAMERA_WIDTH: int = 640
const CAMERA_HEIGHT_PX: int = 400
const CAMERA_COUNT: int = 3
const SENSOR_SAMPLE_INTERVAL_S: float = 0.05
const LIDAR_MIN_M: float = 0.05
const LIDAR_MAX_M: float = 12.0
const UI_TEXT_PRIMARY := Color("dce5eb")
const UI_TEXT_MUTED := Color("a8bac5")
const UI_ACCENT := Color("82bfb4")
const UI_DANGER := Color("d79488")

const PYTHON_SCRIPT := "res://python_bridge/run_python_controller.py"
const NOTEBOOK_HOST_SCRIPT := "res://python_bridge/notebook_host.py"

@onready var course: GridMap = $World/Course
@onready var vehicle: CharacterBody3D = $World/Vehicle
@onready var camera_rig: Node3D = $World/Vehicle/SensorRig
@onready var camera_center: Camera3D = $World/Vehicle/SensorRig/Viewport_Center/CameraCenter
@onready var camera_left: Camera3D = $World/Vehicle/SensorRig/Viewport_Left/CameraLeft
@onready var camera_right: Camera3D = $World/Vehicle/SensorRig/Viewport_Right/CameraRight
@onready var dashboard: SimulatorDashboard = $CanvasLayer/HUD
@onready var telemetry_label: Label = dashboard.telemetry_label
@onready var calibration_label: Label = dashboard.calibration_label
@onready var status_label: Label = dashboard.status_label
@onready var lidar_view: Control = dashboard.lidar_view

var steering_input: float = 0.0
var target_steering: float = 0.0
var speed_request_mps: float = 0.0
var commanded_speed_mps: float = 0.0
var steering_limit_deg: float = 28.0
var wheelbase_m: float = 0.183
var speed_cap_mps: float = 0.6156
var acceleration_mps2: float = 0.60
var braking_mps2: float = 1.50
var sim_time_s: float = 0.0
var frame_id: int = 0
var sensor_timer: float = 0.0
var sensor_frame: Dictionary = {}
var camera_images: Dictionary = {}
var camera_mount_transforms: Array[Transform3D] = []
var camera_output_viewports: Dictionary = {}
var camera_lens_materials: Array[ShaderMaterial] = []
var depth_image: Image
var depth_validity_image: Image
var lidar_angles_deg := PackedFloat32Array()
var lidar_ranges_mm := PackedFloat32Array()
var lidar_hits: Array[Vector3] = []
var py_tcp := StreamPeerTCP.new()
var py_socket_state: int = StreamPeerTCP.STATUS_NONE
var py_input := StreamPeerBuffer.new()
var py_output := StreamPeerBuffer.new()
var py_read_buffer := PackedByteArray()
var py_expected_packet_size: int = -1
var python_running: bool = false
var python_process_id: int = -1
var python_override: bool = false
var python_command_count: int = 0
var python_display_count: int = 0
var manual_mode: bool = true
var emergency_stopped: bool = false
var lidar_angle_arc: float = 0.0
var obstacle_root: Node3D
var main_camera: Camera3D
var orbit_yaw: float = 0.0
var orbit_pitch: float = -1.05
var orbit_distance: float = 6.6
var orbit_target := Vector3(0.45, 0.0, 0.45)
var camera_view_mode: String = "Orbit"
var mouse_rotating: bool = false
var surface_depth_m: Dictionary = {}
var tile_textures: Dictionary = {}
var event_log: Array[String] = []
var stop_reason: String = ""
var collision_flash: float = 0.0
var lidar_ray_count: int = 409
var sim_paused: bool = false
var step_once: bool = false
var starting_lights_active: bool = false
var starting_light_start_time: float = 0.0
var starting_light_count: int = 0
var starting_light_go_time: float = -1.0
var starting_leds: Array[MeshInstance3D] = []
var sensor_capture_in_progress: bool = false
var notebook_tcp := StreamPeerTCP.new()
var notebook_process_id: int = -1
var notebook_port: int = 0
var notebook_port_file := ""
var notebook_token: String = ""
var notebook_connected := false
var notebook_read_buffer := PackedByteArray()
var notebook_expected_packet_size := -1
var notebook_request_id := 0
var notebook_active_cell_id := -1
var notebook_python_exe := ""
var notebook_pending_code := ""
var notebook_pending_cell_id := -1
var notebook_restart_pending := false
var notebook_restart_timer := 0.0

func _ready() -> void:
	add_to_group("simulator_root")
	_build_environment()
	_build_obstacles()
	_build_vehicle()
	_build_sensors()
	_build_ui()
	_build_lights()
	initialize_course()
	build_terrain_features()
	_build_starting_lights()
	start_position()
	apply_calibration()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Engine.physics_ticks_per_second = 40
	_render_sensor_bundle()
	update_hud()
	log_event("Competition assembly loaded: 41 panels, 900 x 900 x 3 mm each.")
	status_label.text = "Ready. Run the controller or choose Manual drive."
	if OS.get_cmdline_user_args().has("--self-test-lap"):
		call_deferred("_start_packaged_lap_monitor")
	elif OS.get_cmdline_user_args().has("--self-test-controls"):
		call_deferred("_start_packaged_control_smoke")
	elif OS.get_cmdline_user_args().has("--self-test-notebook"):
		call_deferred("_start_packaged_notebook_smoke")
	elif OS.get_cmdline_user_args().has("--self-test"):
		call_deferred("_write_packaged_self_test")


func _start_packaged_lap_monitor() -> void:
	var lap_monitor: Node = (load("res://scripts/lap_monitor_node.gd") as Script).new()
	get_tree().root.add_child(lap_monitor)
	lap_monitor.call("start_for", self)


func _start_packaged_control_smoke() -> void:
	var control_monitor_script := load("res://scripts/control_smoke_monitor.gd") as Script
	if control_monitor_script == null:
		push_error("Could not load the control smoke monitor.")
		get_tree().quit(1)
		return
	var control_monitor: Node = control_monitor_script.new()
	get_tree().root.add_child(control_monitor)
	control_monitor.call("start_for", self)


func _start_packaged_notebook_smoke() -> void:
	var monitor_script := load("res://scripts/notebook_e2e_monitor.gd") as Script
	if monitor_script == null:
		push_error("Could not load the notebook end-to-end monitor.")
		get_tree().quit(1)
		return
	var monitor: Node = monitor_script.new()
	get_tree().root.add_child(monitor)
	monitor.call("start_for", self)


func _write_packaged_self_test() -> void:
	await get_tree().process_frame
	var left_viewport := get_node("World/Vehicle/SensorRig/Viewport_Left") as SubViewport
	var center_viewport := get_node("World/Vehicle/SensorRig/Viewport_Center") as SubViewport
	var right_viewport := get_node("World/Vehicle/SensorRig/Viewport_Right") as SubViewport
	var python_exe := OS.get_environment("JAJUCHA_PYTHON")
	var bundled_notebook := OS.get_executable_path().get_base_dir().path_join("notebooks").path_join("Getting_Started.ipynb")
	var checks := {
		"track_has_41_cells": course.get_used_cells().size() == 41,
		"track_tile_pitch_900_mm": is_equal_approx(course.cell_size.x, 0.9) and is_equal_approx(course.cell_size.z, 0.9),
		"vehicle_starts_on_road": course.get_cell_item(course.local_to_map(course.to_local(vehicle.global_position))) == CourseData.TILE_NAMES.find("D"),
		"three_640x400_cameras": left_viewport.size == Vector2i(640, 400) and center_viewport.size == Vector2i(640, 400) and right_viewport.size == Vector2i(640, 400),
		"lidar_has_409_rays": lidar_ray_count == 409,
		"bundled_python_exists": not python_exe.is_empty() and FileAccess.file_exists(python_exe),
		"starter_notebooks_present": FileAccess.file_exists(bundled_notebook) or FileAccess.file_exists("res://notebooks/Getting_Started.ipynb"),
	}
	var passed := true
	for value: Variant in checks.values():
		passed = passed and bool(value)
	var data_root := OS.get_environment("JAJUCHA_DATA_DIR")
	if data_root.is_empty():
		data_root = OS.get_environment("LOCALAPPDATA").path_join("JajuchaGodotSimulatorData")
	var evidence_dir := data_root.path_join("evidence")
	DirAccess.make_dir_recursive_absolute(evidence_dir)
	var report := {"version": "0.1.0", "passed": passed, "checks": checks, "godot": Engine.get_version_info(), "written_at": Time.get_datetime_string_from_system(true, true)}
	var report_path := evidence_dir.path_join("self-test.json")
	var temporary_path := report_path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
		if FileAccess.file_exists(report_path):
			DirAccess.remove_absolute(report_path)
		DirAccess.rename_absolute(temporary_path, report_path)
	print("SELF_TEST_" + ("OK" if passed else "FAILED") + " " + JSON.stringify(report))
	get_tree().quit(0 if passed else 1)


func _physics_process(delta: float) -> void:
	if sim_paused and not step_once:
		return
	step_once = false
	if emergency_stopped:
		speed_request_mps = 0.0
		commanded_speed_mps = move_toward(commanded_speed_mps, 0.0, braking_mps2 * delta)
	elif not python_override and not _notebook_editor_focused():
		read_keyboard_input(delta)
	if Input.is_action_just_pressed("stop") and not _notebook_editor_focused():
		_notebook_interrupt()
		emergency_stop("Manual emergency stop")
	commanded_speed_mps = move_toward(
		commanded_speed_mps, speed_request_mps,
		(braking_mps2 if absf(speed_request_mps) < absf(commanded_speed_mps) else acceleration_mps2) * delta
	)
	if absf(commanded_speed_mps) < 0.002:
		commanded_speed_mps = 0.0
	var steering_angle: float = deg_to_rad(target_steering * steering_limit_deg)
	var turn_rate: float = commanded_speed_mps / wheelbase_m * tan(steering_angle)
	vehicle.rotation.y += turn_rate * delta
	var forward: Vector3 = -vehicle.global_basis.z.normalized()
	# Apply track slope to front wheel contact and follow a flat/ramped tile.
	var slope: float = track_forward_slope(forward)
	# Vehicle-local X is its axle axis; pitch the nose along the travel path.
	vehicle.rotation.x = lerp_angle(vehicle.rotation.x, slope, 8.0 * delta)
	vehicle.velocity = forward * commanded_speed_mps
	vehicle.move_and_slide()
	vehicle.global_position.y = track_surface_height(vehicle.global_position.x, vehicle.global_position.z)
	vehicle.rotation.x = clampf(vehicle.rotation.x, -0.30, 0.30)
	vehicle.rotation.z = clampf(vehicle.rotation.z, -0.30, 0.30)
	_sync_sensor_transforms()
	_update_starting_lights()
	if absf(commanded_speed_mps) > 0.06:
		for collision_index in vehicle.get_slide_collision_count():
			var collision := vehicle.get_slide_collision(collision_index)
			# The track includes traversable ramps. Treat upward-facing contacts
			# as road support; only wall-like contacts trigger the safety stop.
			if collision.get_normal().dot(Vector3.UP) < cos(deg_to_rad(35.0)):
				var collider := collision.get_collider() as Node
				var collider_name: String = str(collider.get_path()) if collider != null else "unknown collider"
				emergency_stop("Chassis collision with %s at %s (normal %s)" % [collider_name, collision.get_position(), collision.get_normal()])
				break
	sim_time_s += delta
	sensor_timer += delta
	if sensor_timer >= SENSOR_SAMPLE_INTERVAL_S:
		sensor_timer -= SENSOR_SAMPLE_INTERVAL_S
		_render_sensor_bundle()
		_poll_python()
		update_hud()
	if collision_flash > 0.0:
		collision_flash = maxf(0.0, collision_flash - delta)
	_update_lidar_view()


func _process(delta: float) -> void:
	if main_camera != null:
		_update_orbit_camera()
		if dashboard != null and dashboard.world_camera != null:
			dashboard.sync_world_camera(main_camera)
	if python_running:
		_poll_python()
		if py_socket_state == StreamPeerTCP.STATUS_CONNECTED and py_tcp.get_available_bytes() >= 4:
			_receive_python_packets()
	_poll_notebook()


func _exit_tree() -> void:
	if python_process_id > 0 and OS.is_process_running(python_process_id):
		OS.kill(python_process_id)
	python_process_id = -1
	if notebook_connected:
		_send_notebook_message({"type": "shutdown"})
	if notebook_process_id > 0 and OS.is_process_running(notebook_process_id):
		OS.delay_msec(1600)
		if OS.is_process_running(notebook_process_id):
			OS.kill(notebook_process_id)
	notebook_process_id = -1


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if dashboard != null and dashboard.notebook_workspace != null:
			dashboard.notebook_workspace.save_recovery_now()
		_notebook_interrupt()
		if notebook_connected:
			_send_notebook_message({"type": "shutdown"})
		get_tree().quit()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		_notebook_interrupt()
		emergency_stop("F8 emergency stop")
		get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		mouse_rotating = false


func _handle_track_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			mouse_rotating = event.pressed
			if event.pressed:
				_select_track_camera("Orbit")
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			orbit_distance = maxf(1.2, orbit_distance * 0.90)
			_select_track_camera("Orbit")
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			orbit_distance = minf(20.0, orbit_distance * 1.10)
			_select_track_camera("Orbit")
	elif event is InputEventMouseMotion and mouse_rotating:
		orbit_yaw -= event.relative.x * 0.004
		orbit_pitch = clampf(orbit_pitch + event.relative.y * 0.004, -1.42, -0.08)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and not _notebook_editor_focused():
			get_tree().quit()
		elif event.keycode == KEY_SPACE and dashboard.workspace_tabs.current_tab == 0:
			emergency_stop("Space key")
		elif event.keycode == KEY_F and not _notebook_editor_focused():
			_notebook_interrupt()
			restart_run()
		elif event.keycode == KEY_V and not _notebook_editor_focused():
			cycle_camera()


func _notebook_editor_focused() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is CodeEdit or focus is TextEdit or (dashboard != null and dashboard.workspace_tabs.current_tab == 1)


func _build_environment() -> void:
	var world: WorldEnvironment = $World/WorldEnvironment
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0b1118")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b8c2ce")
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = env
	main_camera = Camera3D.new()
	main_camera.name = "OrbitCamera"
	main_camera.fov = 52.0
	main_camera.near = 0.02
	main_camera.far = 100.0
	$World.add_child(main_camera)
	main_camera.owner = self
	obstacle_root = $World/Obstacles


func _build_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-49.0, -28.0, 0.0)
	sun.light_energy = 0.90
	sun.shadow_enabled = true
	$World.add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-2.5, 6.0, -5.0)
	fill.light_color = Color("cbd6df")
	fill.light_energy = 0.35
	fill.omni_range = 16.0
	$World.add_child(fill)


func _build_starting_lights() -> void:
	var unit: Node3D = $World/Obstacles/StartingLightBody_80x160mm
	var shield := Node3D.new()
	shield.name = "LightShield_70x130x40mm"
	shield.position = Vector3(0, 0, 0.025)
	unit.add_child(shield)
	for side: int in [-1, 1]:
		var wall := MeshInstance3D.new()
		wall.name = "ShieldSide_%d" % side
		var wall_mesh := BoxMesh.new()
		wall_mesh.size = Vector3(0.004, 0.130, 0.040)
		wall.mesh = wall_mesh
		wall.position.x = side * 0.033
		wall.material_override = _material(Color("11151a"), 0.9)
		shield.add_child(wall)
	for edge_y: float in [0.025, 0.155]:
		var edge := MeshInstance3D.new()
		edge.name = "ShieldEdge_%03d" % roundi(edge_y * 1000.0)
		var edge_mesh := BoxMesh.new()
		edge_mesh.size = Vector3(0.070, 0.004, 0.040)
		edge.mesh = edge_mesh
		edge.position.y = edge_y
		edge.material_override = _material(Color("11151a"), 0.9)
		shield.add_child(edge)
	for index in 4:
		var led := MeshInstance3D.new()
		led.name = "LED_%02d" % index
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.010, 0.018, 0.004)
		led.mesh = mesh
		led.position = Vector3(0, 0.053 + index * 0.024, 0.025)
		var material := _material(Color("371717"), 0.3)
		material.emission_enabled = true
		material.emission = Color("e6312d")
		material.emission_energy_multiplier = 0.0
		led.material_override = material
		unit.add_child(led)
		starting_leds.append(led)


func toggle_starting_light() -> void:
	starting_lights_active = not starting_lights_active
	starting_light_start_time = sim_time_s
	starting_light_count = 0
	starting_light_go_time = -1.0
	if not starting_lights_active:
		_set_lights_on(0)
		log_event("Starting sequence cancelled.")
	else:
		log_event("Starting signal: four lamps 1.5 s apart, random 3-6 s go.")


func _set_lights_on(count: int) -> void:
	for i in starting_leds.size():
		var material: StandardMaterial3D = starting_leds[i].material_override as StandardMaterial3D
		if material != null:
			material.emission_energy_multiplier = 1.0 if i < count else 0.0


func _update_starting_lights() -> void:
	if not starting_lights_active:
		return
	var elapsed: float = sim_time_s - starting_light_start_time
	starting_light_count = mini(4, 1 + int(elapsed / 1.5))
	_set_lights_on(starting_light_count)
	if starting_light_count == 4 and starting_light_go_time < 0.0:
		starting_light_go_time = sim_time_s + randf_range(3.0, 6.0)
	if starting_light_go_time > 0.0 and sim_time_s >= starting_light_go_time:
		starting_lights_active = false
		_set_lights_on(0)
		log_event("Starting signal GO. Motion remains under keyboard or Python control.")


func initialize_course() -> void:
	if course.mesh_library == null:
		course.mesh_library = load("res://assets/jajucha_panels.tres") as MeshLibrary
	course.add_to_group("course_grid")
	if course.get_used_cells().size() != 41:
		push_error("The saved manual GridMap must contain 41 occupied cells; found %d." % course.get_used_cells().size())
	for letter: String in CourseData.TILE_NAMES:
		tile_textures[letter] = load("res://assets/panels/%s.png" % letter)
	var panel_counts := {}
	for row: String in CourseData.ROWS_FROM_TOP:
		for i in row.length():
			var panel: String = row.substr(i, 1)
			if panel != ".":
				panel_counts[panel] = int(panel_counts.get(panel, 0)) + 1
	var inventory_differences: Array[String] = []
	for panel: String in CourseData.TILE_NAMES:
		if int(panel_counts.get(panel, 0)) != int(CourseData.INVENTORY_TILE_COUNTS.get(panel, 0)):
			inventory_differences.append("%s %d/%d" % [panel, panel_counts.get(panel, 0), CourseData.INVENTORY_TILE_COUNTS.get(panel, 0)])
	if inventory_differences.is_empty():
		log_event("Assembly inventory matches the 41-panel manual.")
	else:
		log_event("Assembly inventory conflict: %s." % ", ".join(inventory_differences))


func _build_vehicle() -> void:
	var body := BoxMesh.new()
	body.size = Vector3(VEHICLE_WIDTH_M, 0.052, VISUAL_CHASSIS_LENGTH_M)
	var body_visual := MeshInstance3D.new()
	body_visual.name = "Chassis"
	body_visual.mesh = body
	body_visual.position = Vector3(0, 0.074, -(FRONT_EDGE_FROM_REAR_AXLE_M - VISUAL_CHASSIS_LENGTH_M * 0.5))
	body_visual.material_override = _material(Color("182638"), 0.28)
	vehicle.add_child(body_visual)
	_add_box_vehicle("Deck", Vector3(0.154, 0.014, 0.161), Vector3(0, 0.107, -0.004), Color("273c54"))
	_add_box_vehicle("ComputeBoard", Vector3(0.082, 0.012, 0.062), Vector3(0, 0.121, -0.018), Color("263f36"))
	_add_box_vehicle("FrontFace", Vector3(0.165, 0.045, 0.012), Vector3(0, 0.054, -(FRONT_EDGE_FROM_REAR_AXLE_M - 0.006)), Color("1a2735"))
	for axle_z: float in [0.091, -0.086]:
		var axle := MeshInstance3D.new()
		axle.name = "Axle"
		var axle_mesh := CylinderMesh.new()
		axle_mesh.top_radius = 0.005
		axle_mesh.bottom_radius = 0.005
		axle_mesh.height = 0.145
		axle.mesh = axle_mesh
		axle.rotation.z = PI * 0.5
		axle.position = Vector3(0, 0.040, axle_z)
		axle.material_override = _material(Color("aab3bd"), 0.8)
		vehicle.add_child(axle)
		for side: int in [-1, 1]:
			var tire := MeshInstance3D.new()
			tire.name = "Tire_%s_%s" % [axle_z, side]
			var tire_mesh := CylinderMesh.new()
			tire_mesh.top_radius = 0.040
			tire_mesh.bottom_radius = 0.040
			tire_mesh.height = TIRE_WIDTH_M
			tire.mesh = tire_mesh
			tire.rotation.z = PI * 0.5
			tire.position = Vector3(side * (VEHICLE_WIDTH_M * 0.5 - TIRE_WIDTH_M * 0.5), 0.040, axle_z)
			tire.material_override = _material(Color("202329"), 0.96)
			vehicle.add_child(tire)
			var rim := MeshInstance3D.new()
			var rim_mesh := CylinderMesh.new()
			rim_mesh.top_radius = 0.021
			rim_mesh.bottom_radius = 0.021
			rim_mesh.height = 0.002
			rim.mesh = rim_mesh
			rim.rotation.z = PI * 0.5
			rim.position = Vector3(side * (VEHICLE_WIDTH_M * 0.5 - 0.001), 0.040, axle_z)
			rim.material_override = _material(Color("858b93"), 0.42)
			vehicle.add_child(rim)
	var lidar_local_z: float = -(FRONT_EDGE_FROM_REAR_AXLE_M - LIDAR_SETBACK_FROM_FRONT_M)
	var lidar_shell := _add_box_vehicle("RPLidarTopShell", Vector3(0.064, 0.040, 0.064), Vector3(0, 0.133, lidar_local_z), Color("161b22"))
	lidar_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var lens := MeshInstance3D.new()
	lens.name = "LidarTransparentCover"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.025
	cylinder.bottom_radius = 0.025
	cylinder.height = 0.022
	lens.mesh = cylinder
	lens.position = Vector3(0, 0.165, lidar_local_z)
	lens.material_override = _material(Color("11161d"), 0.16, 0.3)
	vehicle.add_child(lens)
	var collision := CollisionShape3D.new()
	collision.name = "VehicleFootprint"
	var shape := BoxShape3D.new()
	shape.size = Vector3(VEHICLE_WIDTH_M, 0.065, VISUAL_CHASSIS_LENGTH_M)
	collision.shape = shape
	collision.position = Vector3(0, 0.045, -(FRONT_EDGE_FROM_REAR_AXLE_M - VISUAL_CHASSIS_LENGTH_M * 0.5))
	vehicle.add_child(collision)
	vehicle.floor_max_angle = deg_to_rad(35.0)
	vehicle.floor_snap_length = 0.065
	vehicle.safe_margin = 0.005
	vehicle.collision_layer = 2
	vehicle.collision_mask = 1 | 4
	vehicle.up_direction = Vector3.UP
	# Physics collision layers do not assign rendering layers to child meshes.
	# Sensor cameras exclude layer 2 so their own chassis cannot cover the lens.
	for child: Node in vehicle.find_children("*", "GeometryInstance3D", true, false):
		(child as GeometryInstance3D).layers = 2
	_build_controls()


func _build_sensors() -> void:
	camera_rig.position = Vector3(0, 0, 0)
	var front_from_rear: float = FRONT_EDGE_FROM_REAR_AXLE_M - CAMERA_SETBACK_FROM_FRONT_M
	var vehicle_camera_z: float = -front_from_rear
	var baseline: float = 2.0 * ADJACENT_CAMERA_SPACING_M
	var centers: Array[Camera3D] = [camera_left, camera_center, camera_right]
	var offsets: Array[float] = [baseline * 0.5, 0.0, -baseline * 0.5]
	camera_mount_transforms.clear()
	for i in centers.size():
		var camera: Camera3D = centers[i]
		camera.position = Vector3(-offsets[i], CAMERA_HEIGHT_M, vehicle_camera_z)
		camera.basis = _camera_basis_from_calibration()
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = rad_to_deg(2.0 * atan(CAMERA_HEIGHT_PX / (2.0 * 309.58)))
		camera.set_cull_mask_value(2, false)
		camera.set_cull_mask_value(3, true)
		camera.current = false
		camera.keep_aspect = Camera3D.KEEP_HEIGHT
		camera_mount_transforms.append(camera.transform)
		var viewport: SubViewport = camera.get_parent() as SubViewport
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_build_camera_output(camera, viewport)
	var lidar := $World/Vehicle/SensorRig/LidarSensor
	lidar.position = Vector3(0.0, LIDAR_HEIGHT_M, -(FRONT_EDGE_FROM_REAR_AXLE_M - LIDAR_SETBACK_FROM_FRONT_M))
	_build_lidar_visual()
	_sync_sensor_transforms()


func _build_camera_output(camera: Camera3D, source_viewport: SubViewport) -> void:
	var output := SubViewport.new()
	output.name = "LensOutput_" + camera.name
	output.size = Vector2i(CAMERA_WIDTH, CAMERA_HEIGHT_PX)
	output.disable_3d = true
	output.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	camera_rig.add_child(output)
	var image_rect := TextureRect.new()
	image_rect.size = Vector2(CAMERA_WIDTH, CAMERA_HEIGHT_PX)
	image_rect.texture = source_viewport.get_texture()
	var lens := ShaderMaterial.new()
	lens.shader = load("res://assets/shaders/camera_lens.gdshader") as Shader
	image_rect.material = lens
	output.add_child(image_rect)
	camera_output_viewports[camera.name] = output
	camera_lens_materials.append(lens)


func _sync_sensor_transforms() -> void:
	var sensors: Array[Camera3D] = [camera_left, camera_center, camera_right]
	for index in camera_mount_transforms.size():
		sensors[index].global_transform = camera_rig.global_transform * camera_mount_transforms[index]


func _camera_basis_from_calibration() -> Basis:
	var rvec := Vector3(1.203605, -1.24103, 1.213053)
	var config_file := FileAccess.open("res://calibration.json", FileAccess.READ)
	if config_file != null:
		var parsed: Variant = JSON.parse_string(config_file.get_as_text())
		if parsed is Dictionary:
			var raw_rvec: Array = parsed.get("camera", {}).get("orientation_rvec_rad", [])
			if raw_rvec.size() == 3:
				rvec = Vector3(float(raw_rvec[0]), float(raw_rvec[1]), float(raw_rvec[2]))
	var cv_from_ground := Basis(Quaternion(rvec.normalized(), rvec.length()))
	# Ground axes: forward, left, up. Vehicle-local axes: right, up, back.
	var ground_from_vehicle := Basis(Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0))
	# OpenCV camera axes are right, down, forward; Godot camera axes are
	# right, up, back. Convert the calibrated rotation into the Godot basis.
	var cv_from_godot_camera := Basis(Vector3.RIGHT, Vector3.DOWN, Vector3.FORWARD)
	return (ground_from_vehicle.transposed() * cv_from_ground.transposed() * cv_from_godot_camera).orthonormalized()


func apply_calibration() -> void:
	var config: Dictionary = {}
	var config_file := FileAccess.open("res://calibration.json", FileAccess.READ)
	if config_file != null:
		var parsed: Variant = JSON.parse_string(config_file.get_as_text())
		if parsed is Dictionary:
			config = parsed
	var camera: Dictionary = config.get("camera", {})
	var k: Array = camera.get("K", [[310.70, 0.0, 309.52], [0.0, 309.58, 222.31], [0.0, 0.0, 1.0]])
	var dist: Array = camera.get("dist", [0.084568, -0.072728, -0.000606, 0.004212, 0.0])
	var rig: Dictionary = config.get("rig", {})
	wheelbase_m = _calibration_value(rig, "wheelbase_m", wheelbase_m)
	steering_limit_deg = _calibration_value(rig, "steering_limit_deg", steering_limit_deg)
	speed_cap_mps = _calibration_value(rig, "speed_cap_mps", speed_cap_mps)
	acceleration_mps2 = _calibration_value(rig, "acceleration_mps2", acceleration_mps2)
	braking_mps2 = _calibration_value(rig, "braking_mps2", braking_mps2)
	var focal_y: float = k[1][1]
	var principal_x: float = k[0][2]
	var principal_y: float = k[1][2]
	for cam: Camera3D in [camera_left, camera_center, camera_right]:
		# h_offset/v_offset translate the optical center in world space. Use an
		# off-axis projection instead, keeping the calibrated sensor placement.
		cam.h_offset = 0.0
		cam.v_offset = 0.0
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		var near_m := 0.01
		var offset := Vector2(CAMERA_WIDTH * 0.5 - principal_x, principal_y - CAMERA_HEIGHT_PX * 0.5) * near_m / focal_y
		cam.set_frustum(CAMERA_HEIGHT_PX * near_m / focal_y, offset, near_m, 30.0)
	for lens: ShaderMaterial in camera_lens_materials:
		lens.set_shader_parameter("focal_length", Vector2(k[0][0], focal_y))
		lens.set_shader_parameter("principal_point", Vector2(principal_x, principal_y))
		lens.set_shader_parameter("radial", Vector3(dist[0], dist[1], dist[4]))
		lens.set_shader_parameter("tangential", Vector2(dist[2], dist[3]))
	calibration_label.text = _calibration_summary(config, dist)


func _calibration_summary(config: Dictionary, distortion: Array) -> String:
	var rig: Dictionary = config.get("rig", {})
	var optical_height_m: float = _calibration_value(rig, "camera_height_calibrated_m", CAMERA_HEIGHT_M)
	var photo_height_m: float = _calibration_value(rig, "camera_height_photo_estimate_m", CAMERA_HEIGHT_PHOTO_ESTIMATE_M)
	return "TRACK\n" + \
		"900 x 900 x 3 mm panels · 11 x 6\n" + \
		"9.9 x 5.4 m full layout (manual)\n\n" + \
		"TUNNEL\n" + \
		"Portal 390 x 220 mm · roof 260 x 98 mm\n\n" + \
		"VEHICLE\n" + \
		"Width 177.6 mm · tire width 27 mm\n" + \
		"Wheelbase %.0f mm (unconfirmed)\n\n" % [wheelbase_m * 1000.0] + \
		"SENSORS\n" + \
		"3 cameras · 640 x 400 px\n" + \
		"Stereo baseline 58 mm (derived)\n" + \
		"Height %.1f mm calibrated; %.1f mm\n" % [optical_height_m * 1000.0, photo_height_m * 1000.0] + \
		"photo estimate (conflict)\n" + \
		"LiDAR: 409 rays · 0.05–12 m\n" + \
		"Scan height 75 mm (provisional)\n\n" + \
		"Tuned steering limit: %.0f deg (simulation)\n" % [steering_limit_deg] + \
		"Hardware steering and speed remain unverified."


func _calibration_value(register: Dictionary, key: String, fallback: float) -> float:
	var entry: Variant = register.get(key, fallback)
	if entry is Dictionary:
		entry = entry.get("value", fallback)
	if entry is int or entry is float:
		return entry
	return fallback


func build_terrain_features() -> void:
	var ground := _static_body("Ground", 1, 0)
	$World.add_child(ground)
	var ground_mesh := BoxMesh.new()
	ground_mesh.size = Vector3(20.0, 0.10, 14.0)
	var floor_visual := MeshInstance3D.new()
	floor_visual.name = "DarkStudioFloor"
	floor_visual.mesh = ground_mesh
	floor_visual.position = Vector3(0, -0.13, 0)
	floor_visual.material_override = _material(Color("161e28"), 0.9)
	ground.add_child(floor_visual)
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = ground_mesh.size
	floor_collision.shape = floor_shape
	floor_collision.position = floor_visual.position
	ground.add_child(floor_collision)
	# Gridded board-base ribbon mirrors the 11 x 6 real panel assembly.
	var board_outline := MeshInstance3D.new()
	board_outline.name = "DocumentedFootprint"
	var outline_mesh := BoxMesh.new()
	outline_mesh.size = Vector3(9.94, 0.010, 5.44)
	board_outline.mesh = outline_mesh
	board_outline.position = Vector3(0.0, -0.045, 0.0)
	board_mesh_material(board_outline, Color("4f5a69"))
	$World.add_child(board_outline)
	build_ramps_and_tunnel()
	build_mission_objects()


func build_ramps_and_tunnel() -> void:
	# 900 mm tread, 100 mm elevation: ramp run is explicitly provisional.
	# The supplied manual states the raised-block height but not the exact
	# slope-block run, so use a visibly labeled 900 mm rise/run estimate.
	_build_ramp("UphillSlopeBlock", Vector3(1.35, 0.0, 2.70), Vector3(1, 0, 0), true)
	_build_ramp("DownhillSlopeBlock", Vector3(2.25, 0.0, 2.70), Vector3(1, 0, 0), false)
	_add_ramp_panel_overlay(Vector3i(6, 0, 5), true)
	_add_ramp_panel_overlay(Vector3i(7, 0, 5), false)
	_build_tunnel(Vector3(0.8, 0.001, 1.45))


func _add_ramp_panel_overlay(cell: Vector3i, uphill: bool) -> void:
	var tile_id := course.get_cell_item(cell)
	if tile_id < 0:
		return
	var tile_mesh := course.mesh_library.get_item_mesh(tile_id) as PlaneMesh
	if tile_mesh == null:
		return
	var orientation := course.get_cell_item_orientation(cell)
	var panel := MeshInstance3D.new()
	panel.name = "TrackPanelOverRamp_%02d_%02d" % [cell.x, cell.z]
	panel.mesh = tile_mesh
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var grade := atan(0.1 / 0.9) * (1.0 if uphill else -1.0)
	var slope_basis := Basis(Vector3.BACK, grade)
	var panel_basis := course.get_basis_with_orthogonal_index(orientation)
	# Lift the printed foamboard above its supporting wedge. Coplanar faces
	# alternate in the depth buffer and erase lane markings in the camera.
	panel.transform = Transform3D(slope_basis * panel_basis, course.map_to_local(cell) + Vector3(0.0, 0.05 + PANEL_THICKNESS_M, 0.0))
	course.add_child(panel)


func _build_ramp(label: String, origin: Vector3, direction: Vector3, uphill: bool) -> void:
	var path := StaticBody3D.new()
	path.name = label
	path.position = origin
	path.rotation.y = atan2(-direction.z, direction.x)
	path.collision_layer = 4
	path.collision_mask = 0
	$World.add_child(path)
	var run: float = 0.9 # documented 900 mm square block cut into a 100 mm slope
	var rise: float = 0.1
	var end_height: float = rise if uphill else 0.0
	var start_height: float = 0.0 if uphill else rise
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	var normal := Vector3.UP
	var y_delta: float = end_height - start_height
	var normal_pitch: Vector3 = Vector3(-y_delta, run, 0).normalized()
	var vertices := PackedVector3Array([
		Vector3(-run * 0.5, start_height, -0.45), Vector3(run * 0.5, end_height, -0.45),
		Vector3(run * 0.5, end_height, 0.45), Vector3(-run * 0.5, start_height, 0.45),
	])
	var normals := PackedVector3Array([normal_pitch, normal_pitch, normal_pitch, normal_pitch])
	var uv := PackedVector2Array([Vector2(0,1), Vector2(1,1), Vector2(1,0), Vector2(0,0)])
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,2,1,0,3,2])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var view := MeshInstance3D.new()
	view.name = "SlopeSurface"
	view.mesh = mesh
	view.material_override = _material(Color("24292e"), 0.94)
	path.add_child(view)
	var collision := CollisionShape3D.new()
	var wedge := ConvexPolygonShape3D.new()
	wedge.points = PackedVector3Array([
		Vector3(-run * 0.5, start_height, -0.45), Vector3(run * 0.5, end_height, -0.45),
		Vector3(run * 0.5, end_height, 0.45), Vector3(-run * 0.5, start_height, 0.45),
		Vector3(-run * 0.5, 0, -0.45), Vector3(run * 0.5, 0, -0.45),
		Vector3(-run * 0.5, 0, 0.45), Vector3(run * 0.5, 0, 0.45),
	])
	collision.shape = wedge
	path.add_child(collision)


func _build_tunnel(origin: Vector3) -> void:
	var tunnel := StaticBody3D.new()
	tunnel.name = "CompetitionTunnel_390mmWide_220mmHigh"
	tunnel.position = origin
	tunnel.collision_layer = 4
	tunnel.collision_mask = 0
	$World.add_child(tunnel)
	var half_w: float = 0.195
	var height: float = 0.220
	var length: float = 0.260 # reconstructed orientation of the documented upper sheet
	var roof_thickness: float = 0.005 # manual 5T corrugated plastic
	var side_thickness: float = 0.005
	for roof_index in 4:
		var segment_z: float = -0.14625 + roof_index * 0.0975
		_add_static_box(tunnel, "RoofSheet_260x98mm_%02d" % roof_index, Vector3(0, height - roof_thickness * 0.5, segment_z), Vector3(length, roof_thickness, 0.098), Color("111216"), 4)
	_add_static_box(tunnel, "LeftWall_5mm", Vector3(0, height * 0.5, -half_w + side_thickness * 0.5), Vector3(length, height, side_thickness), Color("101115"), 4)
	_add_static_box(tunnel, "RightWall_5mm", Vector3(0, height * 0.5, half_w - side_thickness * 0.5), Vector3(length, height, side_thickness), Color("101115"), 4)
	# Dark floor hides the lane art under the cover while the GridMap itself
	# still retains the actual printed panel visible when the roof is removed.
	_add_static_box(tunnel, "TunnelBlackLiner", Vector3(0, 0.001, 0), Vector3(length, 0.002, 0.384), Color("08090b"), 0)


func build_mission_objects() -> void:
	_add_static_box($World/Obstacles, "ObstacleCube_150mm", Vector3(1.7, 0.075, -1.6), Vector3(0.15, 0.15, 0.15), Color("d27135"), 4)
	_add_static_box($World/Obstacles, "PitSign_320x130mm", Vector3(3.35, 0.065, 0.75), Vector3(0.32, 0.13, 0.008), Color("ebbd32"), 4)
	_add_static_box($World/Obstacles, "YellowFlag_Editable", Vector3(2.9, 0.12, -1.4), Vector3(0.12, 0.24, 0.008), Color("f3c944"), 4)
	_add_static_box($World/Obstacles, "StartingLightBody_80x160mm", Vector3(-0.9, 0.08, -0.1), Vector3(0.08, 0.16, 0.04), Color("171c25"), 4)
	var surprise := MeshInstance3D.new()
	surprise.name = "SurpriseObstacleTrigger_Editable"
	var surprise_mesh := BoxMesh.new()
	surprise_mesh.size = Vector3(0.13, 0.19, 0.012)
	surprise.mesh = surprise_mesh
	surprise.position = Vector3(0.7, 0.095, -0.6)
	surprise.material_override = _material(Color("e15b42"), 0.55)
	$World/Obstacles.add_child(surprise)
	var crossing := Area3D.new()
	crossing.name = "SurpriseObstacleActivation"
	crossing.collision_layer = 0
	crossing.collision_mask = 2
	var area_shape := CollisionShape3D.new()
	var area_box := BoxShape3D.new()
	area_box.size = Vector3(0.55, 0.45, 0.55)
	area_shape.shape = area_box
	crossing.add_child(area_shape)
	crossing.body_entered.connect(_surprise_obstacle_reached)
	crossing.position = surprise.position - Vector3(0, 0, -0.35)
	$World/Obstacles.add_child(crossing)


func _surprise_obstacle_reached(body: Node3D) -> void:
	if body != vehicle:
		return
	var obstacle: Node3D = $World/Obstacles/SurpriseObstacleTrigger_Editable
	if obstacle.visible:
		obstacle.hide()
		log_event("Surprise obstacle withdrawn after the approach trigger.")
		await get_tree().create_timer(2.0).timeout
		if is_instance_valid(obstacle):
			obstacle.show()
			log_event("Surprise obstacle returned for another run.")


func _build_obstacles() -> void:
	pass


func _build_controls() -> void:
	var controls := InputMap
	for action: String in ["accelerate", "brake", "steer_left", "steer_right", "stop"]:
		if not controls.has_action(action):
			controls.add_action(action)
	_bind_key("accelerate", KEY_W)
	_bind_key("accelerate", KEY_UP)
	_bind_key("brake", KEY_S)
	_bind_key("brake", KEY_DOWN)
	_bind_key("steer_left", KEY_A)
	_bind_key("steer_left", KEY_LEFT)
	_bind_key("steer_right", KEY_D)
	_bind_key("steer_right", KEY_RIGHT)
	_bind_key("stop", KEY_SPACE)


func _bind_key(action: String, key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)


func read_keyboard_input(delta: float) -> void:
	if Input.is_action_pressed("accelerate"):
		speed_request_mps = speed_cap_mps
	elif Input.is_action_pressed("brake"):
		speed_request_mps = -minf(0.2052, speed_cap_mps * 0.5)
	else:
		speed_request_mps = 0.0
	var steering_sign: float = int(Input.is_action_pressed("steer_right")) - int(Input.is_action_pressed("steer_left"))
	if steering_sign != 0.0:
		target_steering = move_toward(target_steering, steering_sign, delta * 4.0)
	else:
		target_steering = move_toward(target_steering, 0.0, delta * 3.5)


func emergency_stop(reason: String) -> void:
	emergency_stopped = true
	python_override = false
	manual_mode = false
	speed_request_mps = 0.0
	target_steering = 0.0
	stop_reason = reason
	if is_instance_valid(vehicle):
		vehicle.velocity = Vector3.ZERO
	collision_flash = 0.45
	if status_label != null:
		status_label.text = "EMERGENCY STOP | %s | press F to restart" % reason.to_upper()
		status_label.add_theme_color_override("font_color", UI_DANGER)
	log_event("Emergency stop: %s" % reason)


func restart_run() -> void:
	emergency_stopped = false
	python_override = false
	manual_mode = true
	target_steering = 0.0
	speed_request_mps = 0.0
	commanded_speed_mps = 0.0
	vehicle.velocity = Vector3.ZERO
	start_position()
	status_label.text = "Keyboard drive  |  WASD / arrows move  |  Space stops"
	status_label.add_theme_color_override("font_color", UI_ACCENT)


func start_position() -> void:
	# Start at the center of the lower straight's D panel, inside its lane.
	vehicle.global_position = course.to_global(course.map_to_local(Vector3i(4, 0, 5)))
	vehicle.rotation = Vector3(0.0, -PI * 0.5, 0.0)
	commanded_speed_mps = 0.0
	vehicle.velocity = Vector3.ZERO
	_sync_sensor_transforms()
	main_camera.make_current()


func set_control_mode(manual: bool) -> void:
	manual_mode = manual
	python_override = not manual
	if manual:
		emergency_stopped = false
		stop_reason = ""
		speed_request_mps = 0.0
		target_steering = 0.0
		status_label.text = "Keyboard drive  |  WASD / arrows move  |  Space stops"
	else:
		speed_request_mps = 0.0
		target_steering = 0.0
		status_label.text = "Starting controller. Waiting for camera frames…"
	if status_label != null:
		status_label.add_theme_color_override("font_color", UI_ACCENT)
	update_hud()


func _build_ui() -> void:
	dashboard.world_viewport.world_3d = get_world_3d()
	dashboard.action_requested.connect(_on_control_button)
	dashboard.camera_requested.connect(_select_track_camera)
	dashboard.world_input.connect(_handle_track_input)
	dashboard.notebook_workspace.execute_requested.connect(_notebook_execute)
	dashboard.notebook_workspace.interrupt_requested.connect(_notebook_interrupt)
	dashboard.notebook_workspace.restart_requested.connect(_notebook_restart)
	dashboard.select_camera(camera_view_mode)


func _select_track_camera(mode: String) -> void:
	if mode == "Fit":
		camera_view_mode = "Orbit"
		orbit_target = Vector3(0.45, 0.0, 0.45)
		orbit_distance = 6.6
		orbit_pitch = -1.05
		orbit_yaw = 0.0
	else:
		camera_view_mode = mode
	dashboard.select_camera(camera_view_mode)


func _on_control_button(caption: String) -> void:
	match caption:
		"Keyboard":
			_notebook_interrupt()
			set_control_mode(true)
		"Python": start_python_bridge()
		"E-Stop":
			_notebook_interrupt()
			emergency_stop("UI emergency stop")
		"Reset":
			_notebook_interrupt()
			restart_run()
		"Pause":
			sim_paused = not sim_paused
			status_label.text = "SIMULATION PAUSED" if sim_paused else "SIMULATION RUNNING"
		"Step":
			sim_paused = true
			step_once = true
		"Lights": toggle_starting_light()
		"CheckUpdates": _request_update_check()
	update_hud()


func _request_update_check() -> void:
	var launcher := OS.get_environment("JAJUCHA_LAUNCHER")
	if launcher.is_empty() or not FileAccess.file_exists(launcher):
		dashboard.status_label.text = "Update checks are available from the installed launcher tray icon."
		return
	var error := OS.create_process(launcher, PackedStringArray(["--check-updates"]), false)
	dashboard.status_label.text = "Could not contact update service." if error < 0 else "Checking stable GitHub releases…"


func _runtime_python_script(filename: String) -> String:
	var app_directory := OS.get_executable_path().get_base_dir()
	var bundled := app_directory.path_join("python_bridge").path_join(filename)
	if FileAccess.file_exists(bundled):
		return bundled
	return ProjectSettings.globalize_path("res://python_bridge/" + filename)


func update_hud() -> void:
	var flat_speed: float = Vector2(vehicle.velocity.x, vehicle.velocity.z).length()
	var forward: Vector3 = -vehicle.global_basis.z
	var lidar_hits_count: int = 0
	for r: float in lidar_ranges_mm:
		if r < LIDAR_MAX_M * 1000.0:
			lidar_hits_count += 1
	var mode_name: String = "PYTHON" if python_override else "KEYBOARD" if manual_mode else "STOPPED"
	var bridge_status := "connected" if py_socket_state == StreamPeerTCP.STATUS_CONNECTED else "starting" if python_running else "ready"
	dashboard.update_telemetry({"speed": commanded_speed_mps, "steering_deg": target_steering * steering_limit_deg, "time": sim_time_s, "x": vehicle.position.x, "z": vehicle.position.z, "heading": rad_to_deg(vehicle.rotation.y), "frame": frame_id, "hits": lidar_hits_count, "rays": lidar_ray_count, "connected": py_socket_state == StreamPeerTCP.STATUS_CONNECTED, "python_running": python_running, "paused": sim_paused, "stopped": emergency_stopped, "autonomous": python_override})
	dashboard.event_view.text = "\n\n".join(event_log)
	if emergency_stopped:
		status_label.text = "Emergency stop. Reset the car to drive again."
	elif sim_paused:
		status_label.text = "Paused. Resume to drive, or Step through one physics tick."
	elif python_override and not python_running:
		status_label.text = "Python controller stopped  |  E-Stop remains latched"
	elif python_override and py_socket_state != StreamPeerTCP.STATUS_CONNECTED:
		status_label.text = "Starting controller. Waiting for camera frames…"
	elif python_override:
		status_label.text = "Controller driving. Space stops the car."
	elif manual_mode and not emergency_stopped:
		status_label.text = "Manual drive. Use WASD or the arrow keys."
	if emergency_stopped:
		status_label.add_theme_color_override("font_color", UI_DANGER)
	elif collision_flash > 0.0:
		status_label.add_theme_color_override("font_color", Color("d7a77e"))
	else:
		status_label.add_theme_color_override("font_color", UI_ACCENT)
	lidar_view.queue_redraw()


func cycle_camera() -> void:
	var modes := ["Orbit", "Follow", "Top"]
	_select_track_camera(modes[(modes.find(camera_view_mode) + 1) % modes.size()])


func _render_sensor_bundle() -> void:
	if sensor_capture_in_progress:
		return
	sensor_capture_in_progress = true
	var sensors: Array[Camera3D] = [camera_left, camera_center, camera_right]
	_sync_sensor_transforms()
	for cam: Camera3D in sensors:
		cam.make_current()
	await RenderingServer.frame_post_draw
	frame_id += 1
	for cam: Camera3D in sensors:
		var texture: ViewportTexture = _camera_texture(cam)
		if texture != null:
			var image: Image = texture.get_image()
			if image != null and not image.is_empty():
				if image.get_width() != CAMERA_WIDTH or image.get_height() != CAMERA_HEIGHT_PX:
					image.resize(CAMERA_WIDTH, CAMERA_HEIGHT_PX, Image.INTERPOLATE_LANCZOS)
				var camera_key: String = cam.name.to_lower().replace("camera", "")
				camera_images["%s_rgb" % camera_key] = image
				dashboard.camera_views[camera_key].texture = ImageTexture.create_from_image(image)
	var left: Image = camera_images.get("left_rgb", Image.create(CAMERA_WIDTH, CAMERA_HEIGHT_PX, false, Image.FORMAT_RGB8))
	var right: Image = camera_images.get("right_rgb", Image.create(CAMERA_WIDTH, CAMERA_HEIGHT_PX, false, Image.FORMAT_RGB8))
	compute_stereo_depth(left, right)
	cast_lidar_rays()
	sensor_frame = {
		"frame_id": frame_id,
		"timestamp_s": sim_time_s,
		"camera_left_rgb": camera_images.get("left_rgb"),
		"camera_center_rgb": camera_images.get("center_rgb"),
		"camera_right_rgb": camera_images.get("right_rgb"),
		"depth_gray": depth_image,
		"depth_valid": depth_validity_image,
		"lidar_angles_deg": lidar_angles_deg.duplicate(),
		"lidar_ranges_mm": lidar_ranges_mm.duplicate(),
		"camera_size_wh": [CAMERA_WIDTH, CAMERA_HEIGHT_PX],
		"center_calibration": _center_calibration_dict(),
		"coordinate_frame": {"origin": "ground point under the rear axle", "x": "forward", "y": "left", "z": "up", "distance_unit": "m"},
	}
	_emit_python_packet(sensor_frame)
	_emit_notebook_sensor_frame(sensor_frame)
	sensor_capture_in_progress = false


func _camera_texture(camera: Camera3D) -> ViewportTexture:
	var viewport: SubViewport = camera_output_viewports.get(camera.name, camera.get_parent())
	return viewport.get_texture() if viewport != null else null


func compute_stereo_depth(left: Image, right: Image) -> void:
	const SAMPLE_STEP: int = 8
	const SEARCH_DISPARITY: int = 16
	const sample_width: int = CAMERA_WIDTH / SAMPLE_STEP
	const sample_height: int = CAMERA_HEIGHT_PX / SAMPLE_STEP
	var left_gray_image: Image = left.duplicate()
	var right_gray_image: Image = right.duplicate()
	left_gray_image.convert(Image.FORMAT_L8)
	right_gray_image.convert(Image.FORMAT_L8)
	var left_gray: PackedByteArray = left_gray_image.get_data()
	var right_gray: PackedByteArray = right_gray_image.get_data()
	var small_depth := PackedByteArray()
	var small_validity := PackedByteArray()
	small_depth.resize(sample_width * sample_height)
	small_validity.resize(sample_width * sample_height)
	for sy in range(1, sample_height - 1):
		var y: int = sy * SAMPLE_STEP
		for sx in range(SEARCH_DISPARITY + 1, sample_width - 1):
			var x: int = sx * SAMPLE_STEP
			var best: int = 0x7fffffff
			var second_best: int = 0x7fffffff
			var best_disparity: int = 0
			for disparity in range(1, SEARCH_DISPARITY + 1):
				var cost: int = 0
				var pixel_disparity: int = disparity * SAMPLE_STEP
				for dy in [-SAMPLE_STEP, 0, SAMPLE_STEP]:
					var offset: int = (y + dy) * CAMERA_WIDTH
					cost += absi(int(left_gray[offset + x]) - int(right_gray[offset + x - pixel_disparity]))
					cost += absi(int(left_gray[offset + x - SAMPLE_STEP]) - int(right_gray[offset + x - pixel_disparity - SAMPLE_STEP]))
					cost += absi(int(left_gray[offset + x + SAMPLE_STEP]) - int(right_gray[offset + x - pixel_disparity + SAMPLE_STEP]))
				if cost < best:
					second_best = best
					best = cost
					best_disparity = disparity
				elif cost < second_best:
					second_best = cost
			if best_disparity > 0 and best < 700 and second_best > best + 18:
				var distance_m: float = clampf((310.70 * 0.058) / (best_disparity * SAMPLE_STEP), 0.10, 12.0)
				small_depth[sy * sample_width + sx] = clampi(roundi(255.0 * 0.4 / distance_m), 1, 255)
				small_validity[sy * sample_width + sx] = 255
	var depth_bytes := PackedByteArray()
	var valid_bytes := PackedByteArray()
	depth_bytes.resize(CAMERA_WIDTH * CAMERA_HEIGHT_PX * 3)
	valid_bytes.resize(CAMERA_WIDTH * CAMERA_HEIGHT_PX)
	for y in CAMERA_HEIGHT_PX:
		for x in CAMERA_WIDTH:
			var sample: int = mini(sample_height - 1, y / SAMPLE_STEP) * sample_width + mini(sample_width - 1, x / SAMPLE_STEP)
			var index: int = y * CAMERA_WIDTH + x
			var brightness: int = small_depth[sample]
			depth_bytes[index * 3] = brightness
			depth_bytes[index * 3 + 1] = brightness
			depth_bytes[index * 3 + 2] = brightness
			valid_bytes[index] = small_validity[sample]
	depth_image = Image.create_from_data(CAMERA_WIDTH, CAMERA_HEIGHT_PX, false, Image.FORMAT_RGB8, depth_bytes)
	depth_validity_image = Image.create_from_data(CAMERA_WIDTH, CAMERA_HEIGHT_PX, false, Image.FORMAT_L8, valid_bytes)
	dashboard.depth_view.texture = ImageTexture.create_from_image(depth_image)
	dashboard.validity_view.texture = ImageTexture.create_from_image(depth_validity_image)


func cast_lidar_rays() -> void:
	lidar_angles_deg.resize(lidar_ray_count)
	lidar_ranges_mm.resize(lidar_ray_count)
	lidar_hits.clear()
	var lidar: Node3D = $World/Vehicle/SensorRig/LidarSensor
	var state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	for index in lidar_ray_count:
		var fraction: float = float(index) / float(lidar_ray_count)
		var angle_deg: float = fraction * 360.0
		var local_angle: float = deg_to_rad(angle_deg)
		var local_dir := Vector3(sin(local_angle), 0, -cos(local_angle))
		var direction: Vector3 = (lidar.global_basis * local_dir).normalized()
		var origin: Vector3 = lidar.global_position
		var params := PhysicsRayQueryParameters3D.create(origin, origin + direction * LIDAR_MAX_M)
		params.collision_mask = 1 | 4
		params.exclude = [vehicle.get_rid()]
		params.collide_with_areas = false
		var hit: Dictionary = state.intersect_ray(params)
		var range_m: float = LIDAR_MAX_M
		if not hit.is_empty():
			var point: Vector3 = hit.position
			var raw_distance: float = origin.distance_to(point)
			# The scanner emits in the plane parallel to the fitted deck. The
			# transform rotates that plane with the vehicle over the grade.
			if raw_distance >= LIDAR_MIN_M and raw_distance <= LIDAR_MAX_M:
				range_m = raw_distance
				lidar_hits.append(point)
		lidar_angles_deg[index] = angle_deg
		lidar_ranges_mm[index] = range_m * 1000.0


func _build_lidar_visual() -> void:
	var laser := MeshInstance3D.new()
	laser.name = "ScanPlaneVisual"
	var ring := TorusMesh.new()
	ring.inner_radius = 0.025
	ring.outer_radius = 0.027
	ring.rings = 48
	ring.ring_segments = 8
	laser.mesh = ring
	laser.layers = 2
	laser.material_override = _material(Color("5be1c4"), 0.35, 0.7)
	laser.position = Vector3(0, 0.018, 0)
	$World/Vehicle/SensorRig/LidarSensor.add_child(laser)


func _center_calibration_dict() -> Dictionary:
	return {
		"size_wh_px": [640, 400],
		"K": [[310.70, 0.0, 309.52], [0.0, 309.58, 222.31], [0.0, 0.0, 1.0]],
		"dist": [0.084568, -0.072728, -0.000606, 0.004212, 0.0],
		"center_camera_height_calibrated_m": CAMERA_HEIGHT_M,
		"photo_camera_height_estimate_m": CAMERA_HEIGHT_PHOTO_ESTIMATE_M,
		"side_intrinsics_status": "provisional copy of center; no side calibration supplied",
		"stereo_baseline_m": 0.058,
	}


func _build_python_listeners() -> void:
	pass


func start_python_bridge() -> void:
	if python_running:
		set_control_mode(false)
		return
	var exe: String = OS.get_environment("JAJUCHA_PYTHON")
	if exe.is_empty():
		exe = "python"
	var script_path: String = _runtime_python_script("run_python_controller.py")
	var log_root := OS.get_environment("JAJUCHA_DATA_DIR")
	if log_root.is_empty():
		log_root = OS.get_environment("LOCALAPPDATA").path_join("JajuchaGodotSimulatorData")
	var log_path := log_root.path_join("logs").path_join("controller.log")
	var args: PackedStringArray = PackedStringArray([script_path, "--host", "127.0.0.1", "--port", "8765", "--log-file", log_path])
	python_process_id = OS.create_process(exe, args, false)
	if python_process_id == -1:
		status_label.text = "Could not start Python. See README for JAJUCHA_PYTHON."
		log_event("Python startup failed; set JAJUCHA_PYTHON to a Python 3.12 executable.")
		return
	py_tcp = StreamPeerTCP.new()
	py_socket_state = StreamPeerTCP.STATUS_NONE
	python_running = true
	set_control_mode(false)
	status_label.text = "Starting controller…"


func _notebook_execute(cell_id: int, code: String) -> void:
	if emergency_stopped:
		status_label.text = "Reset the car before running notebook code."
		return
	if python_running and python_override:
		status_label.text = "Stop the supplied controller before using notebook code."
		return
	if not notebook_connected:
		notebook_pending_code = code
		notebook_pending_cell_id = cell_id
		_start_notebook_host()
		return
	notebook_request_id += 1
	notebook_active_cell_id = cell_id
	_send_notebook_message({"type": "execute", "request_id": notebook_request_id, "cell_id": cell_id, "code": code})


func _start_notebook_host() -> void:
	if notebook_process_id > 0 and OS.is_process_running(notebook_process_id):
		status_label.text = "Notebook kernel is starting…"
		return
	notebook_python_exe = OS.get_environment("JAJUCHA_PYTHON")
	if notebook_python_exe.is_empty():
		notebook_python_exe = "python"
	var crypto := Crypto.new()
	notebook_token = Marshalls.raw_to_base64(crypto.generate_random_bytes(32)).replace("+", "-").replace("/", "_").replace("=", "")
	notebook_port = 0
	var data_root := OS.get_environment("JAJUCHA_DATA_DIR")
	if data_root.is_empty():
		data_root = OS.get_environment("LOCALAPPDATA").path_join("JajuchaGodotSimulatorData")
	notebook_port_file = data_root.path_join("notebook_port_%s.json" % notebook_token.substr(0, 12))
	DirAccess.make_dir_recursive_absolute(data_root)
	if FileAccess.file_exists(notebook_port_file):
		DirAccess.remove_absolute(notebook_port_file)
	var host_script := _runtime_python_script("notebook_host.py")
	var args := PackedStringArray([host_script, "--port", "0", "--port-file", notebook_port_file, "--token", notebook_token])
	notebook_process_id = OS.create_process(notebook_python_exe, args, false)
	if notebook_process_id < 0:
		dashboard.notebook_workspace.complete_cell(notebook_pending_cell_id, "Could not start bundled Python/IPython kernel.", false, 0)
		notebook_pending_cell_id = -1
		return
	status_label.text = "Starting isolated notebook kernel…"


func _poll_notebook() -> void:
	if notebook_restart_pending:
		notebook_restart_timer -= get_process_delta_time()
		if notebook_restart_timer <= 0.0:
			notebook_restart_pending = false
			_send_notebook_message({"type": "restart"})
	if notebook_process_id <= 0:
		return
	if notebook_port == 0 and FileAccess.file_exists(notebook_port_file):
		var port_document: Variant = JSON.parse_string(FileAccess.get_file_as_string(notebook_port_file))
		if port_document is Dictionary:
			notebook_port = int(port_document.get("port", 0))
		if notebook_port <= 0 or notebook_port > 65535:
			notebook_port = 0
			return
	if notebook_port <= 0:
		return
	if not notebook_connected:
		if notebook_tcp.get_status() == StreamPeerTCP.STATUS_NONE:
			notebook_tcp.connect_to_host("127.0.0.1", notebook_port)
		notebook_tcp.poll()
		if notebook_tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			notebook_connected = true
			_send_notebook_message({"type": "hello", "token": notebook_token})
		return
	notebook_tcp.poll()
	if notebook_tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		notebook_connected = false
		if not dashboard.notebook_workspace.is_queued_for_deletion():
			dashboard.notebook_workspace.workspace_status.emit("Notebook host disconnected; the kernel was closed.")
		if python_override:
			emergency_stop("Notebook kernel disconnected")
		return
	var available := notebook_tcp.get_available_bytes()
	if available > 0:
		notebook_read_buffer.append_array(notebook_tcp.get_data(available)[1])
	while true:
		if notebook_expected_packet_size < 0:
			if notebook_read_buffer.size() < 4:
				break
			notebook_expected_packet_size = _decode_network_u32(notebook_read_buffer)
			notebook_read_buffer = notebook_read_buffer.slice(4)
			if notebook_expected_packet_size <= 0 or notebook_expected_packet_size > 16_000_000:
				emergency_stop("Invalid notebook output packet")
				return
		if notebook_read_buffer.size() < notebook_expected_packet_size:
			break
		var bytes := notebook_read_buffer.slice(0, notebook_expected_packet_size)
		notebook_read_buffer = notebook_read_buffer.slice(notebook_expected_packet_size)
		notebook_expected_packet_size = -1
		var message: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		if message is Dictionary:
			_handle_notebook_message(message)


func _handle_notebook_message(message: Dictionary) -> void:
	match str(message.get("type", "")):
		"ready":
			if not notebook_pending_code.is_empty():
				var code := notebook_pending_code
				var cell_id := notebook_pending_cell_id
				notebook_pending_code = ""
				notebook_pending_cell_id = -1
				_notebook_execute(cell_id, code)
		"cell_output":
			var output_text := str(message.get("text", ""))
			var output_error := bool(message.get("error", false))
			dashboard.notebook_workspace.append_cell_output(int(message.get("cell_id", -1)), output_text, output_error)
			if int(message.get("cell_id", -1)) == 7:
				_record_controller_capture("controller_log.jsonl", {"timestamp_s": sim_time_s, "text": output_text, "error": output_error})
		"cell_image":
			dashboard.notebook_workspace.append_cell_image(int(message.get("cell_id", -1)), str(message.get("mime", "image/png")), str(message.get("data", "")))
		"execution_done":
			dashboard.notebook_workspace.complete_cell(int(message.get("cell_id", -1)), str(message.get("output", "")), bool(message.get("success", false)), int(message.get("execution_count", 0)))
			notebook_active_cell_id = -1
			if not bool(message.get("success", false)):
				stop_vehicle_safely("Notebook cell failed")
		"safe_stop":
			stop_vehicle_safely("Notebook cell failed or was interrupted")
		"notebook_control":
			if notebook_active_cell_id >= 0 and not emergency_stopped:
				python_command_count += 1
				python_override = true
				manual_mode = false
				var left := clampf(float(message.get("left_servo", 0.0)), -10.0, 10.0)
				var right := clampf(float(message.get("right_servo", 0.0)), -10.0, 10.0)
				var motor := clampf(float(message.get("motor", 0.0)), -30.0, 30.0)
				target_steering = clampf(-(left + right) / 20.0, -1.0, 1.0)
				speed_request_mps = clampf(motor * 0.0513, -speed_cap_mps, speed_cap_mps)
				_record_controller_capture("commands.jsonl", {"timestamp_s": sim_time_s, "left_servo": left, "right_servo": right, "motor": motor})
		"notebook_display":
			var png := Marshalls.base64_to_raw(str(message.get("display_png_b64", "")))
			var display_image := Image.new()
			var mime := str(message.get("mime", "image/png"))
			var err := display_image.load_png_from_buffer(png) if mime == "image/png" else display_image.load_jpg_from_buffer(png)
			if err == OK:
				dashboard.python_output.texture = ImageTexture.create_from_image(display_image)
				python_display_count += 1
		"input_request":
			_show_notebook_input(int(message.get("request_id", -1)), str(message.get("prompt", "")), bool(message.get("password", false)))
		"restarted":
			dashboard.notebook_workspace.workspace_status.emit("Kernel restarted; variables were cleared.")
		"kernel_killed":
			notebook_active_cell_id = -1
			dashboard.notebook_workspace.workspace_status.emit(str(message.get("message", "Kernel terminated; variables were cleared.")))
		"error":
			dashboard.notebook_workspace.workspace_status.emit(str(message.get("message", "Notebook runtime error")))


func _send_notebook_message(message: Dictionary) -> void:
	if notebook_tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	message["token"] = notebook_token
	var data := JSON.stringify(message).to_utf8_buffer()
	var packet := PackedByteArray()
	packet.resize(4)
	packet[0] = (data.size() >> 24) & 255
	packet[1] = (data.size() >> 16) & 255
	packet[2] = (data.size() >> 8) & 255
	packet[3] = data.size() & 255
	packet.append_array(data)
	notebook_tcp.put_data(packet)


func _record_controller_capture(filename: String, value: Dictionary) -> void:
	var capture_dir := OS.get_environment("JAJUCHA_CAPTURE_DIR")
	if capture_dir.is_empty():
		return
	var path := capture_dir.path_join(filename)
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line(JSON.stringify(value))
	file.close()


func _emit_notebook_sensor_frame(bundle: Dictionary) -> void:
	if not notebook_connected:
		return
	var images := {}
	for name: String in ["left_rgb", "center_rgb", "right_rgb"]:
		var image: Image = camera_images.get(name)
		if image != null and not image.is_empty():
			images[name] = Marshalls.raw_to_base64(image.save_png_to_buffer())
	_send_notebook_message({
		"type": "sensor_frame",
		"frame_id": int(bundle.get("frame_id", frame_id)),
		"timestamp_s": float(bundle.get("timestamp_s", sim_time_s)),
		"images_png_b64": images,
		"depth_gray_png_b64": Marshalls.raw_to_base64((depth_image if depth_image != null else Image.create(640, 400, false, Image.FORMAT_RGB8)).save_png_to_buffer()),
		"depth_valid_png_b64": Marshalls.raw_to_base64((depth_validity_image if depth_validity_image != null else Image.create(640, 400, false, Image.FORMAT_L8)).save_png_to_buffer()),
		"lidar_angles_deg": Array(lidar_angles_deg),
		"lidar_ranges_mm": Array(lidar_ranges_mm),
		"sensor_spec": bundle.get("center_calibration", {}),
	})


func _notebook_interrupt() -> void:
	dashboard.notebook_workspace.run_all_active = false
	dashboard.notebook_workspace.run_all_queue.clear()
	if notebook_connected:
		_send_notebook_message({"type": "interrupt", "request_id": notebook_request_id, "cell_id": notebook_active_cell_id})
	stop_vehicle_safely("Notebook execution stopped")


func _notebook_restart() -> void:
	if not notebook_connected:
		_start_notebook_host()
		return
	if notebook_active_cell_id >= 0:
		_notebook_interrupt()
		notebook_restart_pending = true
		notebook_restart_timer = 2.1
	else:
		_send_notebook_message({"type": "restart"})


func stop_vehicle_safely(reason: String) -> void:
	speed_request_mps = 0.0
	commanded_speed_mps = move_toward(commanded_speed_mps, 0.0, braking_mps2 * 0.1)
	target_steering = 0.0
	python_override = false
	manual_mode = true
	log_event(reason)


func _show_notebook_input(request_id: int, prompt: String, password: bool) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Notebook input"
	var row := HBoxContainer.new()
	var caption := Label.new()
	caption.text = prompt
	row.add_child(caption)
	var field := LineEdit.new()
	field.secret = password
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	dialog.add_child(row)
	add_child(dialog)
	dialog.confirmed.connect(func():
		_send_notebook_message({"type": "input_reply", "request_id": request_id, "value": field.text})
		dialog.queue_free())
	dialog.canceled.connect(func():
		_send_notebook_message({"type": "input_reply", "request_id": request_id, "value": ""})
		dialog.queue_free())
	dialog.popup_centered(Vector2i(560, 140))


func _poll_python() -> void:
	if python_running and py_socket_state != StreamPeerTCP.STATUS_CONNECTED:
		if py_socket_state == StreamPeerTCP.STATUS_NONE:
			py_tcp.connect_to_host("127.0.0.1", 8765)
		py_tcp.poll()
		py_socket_state = py_tcp.get_status()
		if py_socket_state == StreamPeerTCP.STATUS_CONNECTED:
			status_label.text = "Controller connected. Camera feeds are live."
	if python_running and py_socket_state == StreamPeerTCP.STATUS_CONNECTED:
		_receive_python_packets()


func _receive_python_packets() -> void:
	py_tcp.poll()
	py_socket_state = py_tcp.get_status()
	if py_socket_state != StreamPeerTCP.STATUS_CONNECTED:
		python_failed("Controller connection closed")
		emergency_stop("Controller connection closed")
		return
	while py_tcp.get_available_bytes() > 0:
		var available: int = py_tcp.get_available_bytes()
		var chunk: PackedByteArray = py_tcp.get_data(available)[1]
		py_read_buffer.append_array(chunk)
		if py_read_buffer.size() > 12_000_000:
			emergency_stop("Python packet exceeded 2 MB")
			return
		while true:
			if py_expected_packet_size < 0:
				if py_read_buffer.size() < 4:
					break
				py_expected_packet_size = _decode_network_u32(py_read_buffer)
				py_read_buffer = py_read_buffer.slice(4)
				if py_expected_packet_size <= 0 or py_expected_packet_size > 8_000_000:
					emergency_stop("Invalid Python command packet size")
					return
			if py_read_buffer.size() < py_expected_packet_size:
				break
			var payload: PackedByteArray = py_read_buffer.slice(0, py_expected_packet_size)
			py_read_buffer = py_read_buffer.slice(py_expected_packet_size)
			py_expected_packet_size = -1
			var command: Variant = JSON.parse_string(payload.get_string_from_utf8())
			if command is Dictionary:
				apply_python_command(command)
	if py_tcp.get_status() == StreamPeerTCP.STATUS_ERROR:
		python_failed("Loopback connection failed")


func apply_python_command(command: Dictionary) -> void:
	if command.get("type", "") == "model_log":
		log_event(str(command.get("text", "Python log")))
		return
	if command.get("type", "") == "model_display":
		var png: PackedByteArray = Marshalls.base64_to_raw(str(command.get("display_png_b64", "")))
		var display_image := Image.new()
		if not png.is_empty() and display_image.load_png_from_buffer(png) == OK:
			dashboard.python_output.texture = ImageTexture.create_from_image(display_image)
			python_display_count += 1
		return
	if command.get("stop", false):
		emergency_stop("Python requested emergency stop")
		return
	if not python_running or not python_override or emergency_stopped:
		return
	if not command.has("left_servo") or not command.has("right_servo") or not command.has("motor"):
		return
	python_command_count += 1
	var left: float = clampf(command["left_servo"], -10.0, 10.0)
	var right: float = clampf(command["right_servo"], -10.0, 10.0)
	var motor: float = clampf(command["motor"], -30.0, 30.0)
	# The supplied Jajucha controller uses negative servo values for a left
	# turn. Convert that actuator convention to positive Godot yaw on left turns.
	target_steering = clampf(-(left + right) / 20.0, -1.0, 1.0)
	speed_request_mps = clampf(motor * 0.0513, -speed_cap_mps, speed_cap_mps)


func _emit_python_packet(bundle: Dictionary) -> void:
	if not python_running or py_socket_state != StreamPeerTCP.STATUS_CONNECTED:
		return
	var images := {}
	for name: String in ["left_rgb", "center_rgb", "right_rgb"]:
		var image: Image = camera_images.get(name)
		if image != null and not image.is_empty():
			images[name] = Marshalls.raw_to_base64(image.save_png_to_buffer())
	var payload: Dictionary = {
		"type": "sensor_frame",
		"frame_id": int(bundle["frame_id"]),
		"timestamp_s": bundle["timestamp_s"],
		"images_png_b64": images,
		"depth_gray_png_b64": Marshalls.raw_to_base64((depth_image if depth_image != null else Image.create(640,400,false,Image.FORMAT_RGB8)).save_png_to_buffer()),
		"depth_valid_png_b64": Marshalls.raw_to_base64((depth_validity_image if depth_validity_image != null else Image.create(640,400,false,Image.FORMAT_L8)).save_png_to_buffer()),
		"lidar_angles_deg": Array(lidar_angles_deg),
		"lidar_ranges_mm": Array(lidar_ranges_mm),
		"sensor_spec": bundle.get("center_calibration", {}),
		"vehicle_pose": {"x_m": vehicle.position.x, "y_m": vehicle.position.y, "z_m": vehicle.position.z, "yaw_rad": vehicle.rotation.y, "speed_mps": commanded_speed_mps, "steering": target_steering},
	}
	var bytes: PackedByteArray = JSON.stringify(payload).to_utf8_buffer()
	py_output.clear()
	py_output.big_endian = true
	py_output.put_u32(bytes.size())
	py_output.put_data(bytes)
	py_tcp.put_data(py_output.data_array)
	py_tcp.poll()


func _decode_network_u32(buffer: PackedByteArray) -> int:
	return (int(buffer[0]) << 24) | (int(buffer[1]) << 16) | (int(buffer[2]) << 8) | int(buffer[3])


func python_failed(reason: String) -> void:
	python_running = false
	py_socket_state = StreamPeerTCP.STATUS_NONE
	py_tcp.disconnect_from_host()
	if python_process_id > 0 and OS.is_process_running(python_process_id):
		OS.kill(python_process_id)
	python_process_id = -1
	speed_request_mps = 0.0
	target_steering = 0.0
	python_override = false
	manual_mode = true
	status_label.text = "Python stopped safely | %s | manual mode" % reason
	log_event("Python stopped safely: %s" % reason)


func build_lidar_samples(count: int) -> void:
	lidar_ray_count = count
	cast_lidar_rays()
	_update_lidar_view()


func _update_lidar_view() -> void:
	lidar_view.queue_redraw()


func track_forward_slope(direction: Vector3) -> float:
	var flat_forward := Vector3(direction.x, 0, direction.z).normalized()
	var rear := vehicle.global_position
	var front := rear + flat_forward * wheelbase_m
	# Pitch follows the two axle contact heights. The old x-only lookup
	# incorrectly tilted the car on flat panels elsewhere in the course.
	return atan2(track_surface_height(front.x, front.z) - track_surface_height(rear.x, rear.z), wheelbase_m)


func track_surface_height(x: float, z: float) -> float:
	if absf(z - 2.70) > 0.46:
		return 0.0
	if x >= 0.9 and x < 1.8:
		return PANEL_THICKNESS_M + 0.1 * (x - 0.9) / 0.9
	if x >= 1.8 and x < 2.7:
		return PANEL_THICKNESS_M + 0.1 * (2.7 - x) / 0.9
	return 0.0


func track_surface_slope(x: float) -> float:
	var run := 0.9
	if x >= 0.9 and x < 1.8:
		return atan(0.1 / run)
	if x >= 1.8 and x < 2.7:
		return -atan(0.1 / run)
	return 0.0


func _update_orbit_camera() -> void:
	main_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	main_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	if camera_view_mode == "Follow":
		main_camera.global_position = vehicle.global_position + vehicle.global_basis * Vector3(0.45, 0.85, 1.35)
		main_camera.look_at(vehicle.global_position - vehicle.global_basis.z * 0.5, Vector3.UP)
	elif camera_view_mode == "Top":
		main_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		main_camera.keep_aspect = Camera3D.KEEP_WIDTH
		main_camera.size = 11.5
		main_camera.global_position = Vector3(0.45, 12, 0.45)
		main_camera.rotation_degrees = Vector3(-90, 0, 0)
	else:
		var look := Basis(Vector3.UP, orbit_yaw) * Basis(Vector3.RIGHT, orbit_pitch)
		main_camera.global_position = orbit_target + look * Vector3(0, 0, orbit_distance)
		main_camera.look_at(orbit_target, Vector3.UP)


func _add_box_vehicle(label: String, size: Vector3, local_pos: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = local_pos
	node.material_override = _material(color, 0.4)
	vehicle.add_child(node)
	return node


func _static_body(node_name: String, layer: int, mask: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = layer
	body.collision_mask = mask
	return body


func _add_static_box(parent: Node, node_name: String, pos: Vector3, size: Vector3, color: Color, layer: int) -> Node3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	body.collision_layer = layer
	body.collision_mask = 0
	parent.add_child(body)
	var mesh := BoxMesh.new()
	mesh.size = size
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	visual.mesh = mesh
	visual.material_override = _material(color, 0.72)
	body.add_child(visual)
	if layer > 0:
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)
	return body


func _material(color: Color, roughness: float, transparency: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if transparency > 0.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color.a = 1.0 - transparency
		material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return material


func board_mesh_material(mesh: MeshInstance3D, color: Color) -> void:
	mesh.material_override = _material(color, 0.95)


func log_event(message: String) -> void:
	event_log.push_front("%05.2fs  %s" % [sim_time_s, message])
	if event_log.size() > 8:
		event_log.resize(8)
	if dashboard != null and dashboard.event_view != null:
		dashboard.event_view.text = "\n\n".join(event_log)


func get_latest_sensor_frame() -> Dictionary:
	return sensor_frame.duplicate(true)
