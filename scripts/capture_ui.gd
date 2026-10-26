extends SceneTree

var simulator: Node
var output_dir := "res://.cache/ui"

func _initialize() -> void:
	call_deferred("capture")

func settle() -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw

func save_view(name: String) -> void:
	await settle()
	root.get_texture().get_image().save_png(output_dir + "/" + name + ".png")

func capture() -> void:
	root.content_scale_size = Vector2i(1440, 900)
	root.size = Vector2i(1440, 900)
	simulator = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(simulator)
	DirAccess.make_dir_recursive_absolute(output_dir)
	await settle()
	var ui: SimulatorDashboard = simulator.dashboard
	assert(ui.camera_views.size() == 3)
	assert(ui.world_viewport.world_3d == simulator.get_world_3d())
	for resolution: Vector2i in [Vector2i(1440, 900), Vector2i(1280, 720), Vector2i(1080, 680)]:
		root.size = resolution
		root.content_scale_size = resolution
		for tab in 3:
			ui.tabs.current_tab = tab
			await settle()
			assert(ui.get_global_rect().size == Vector2(resolution))
			for camera: TextureRect in ui.camera_views.values():
				assert(camera.is_visible_in_tree())
				assert(Rect2(Vector2.ZERO, Vector2(resolution)).encloses(camera.get_global_rect()))
			for button: Button in ui.controls.values():
				assert(Rect2(Vector2.ZERO, Vector2(resolution)).encloses(button.get_global_rect()))
			await save_view("%s_%dx%d" % [["overview", "vision", "setup"][tab], resolution.x, resolution.y])
	root.size = Vector2i(1440, 900)
	root.content_scale_size = root.size
	ui.tabs.current_tab = 0
	ui.controls.Pause.pressed.emit()
	assert(simulator.sim_paused and ui.controls.Pause.text == "Resume" and not ui.controls.Step.disabled)
	await save_view("paused")
	var paused_at: float = simulator.sim_time_s
	ui.controls.Step.pressed.emit()
	await settle()
	assert(simulator.sim_time_s > paused_at and simulator.sim_time_s - paused_at < 0.03)
	ui.controls.Pause.pressed.emit()
	assert(not simulator.sim_paused and ui.controls.Step.disabled)
	ui.view_buttons.Follow.pressed.emit()
	assert(simulator.camera_view_mode == "Follow")
	await save_view("follow")
	ui.view_buttons.Top.pressed.emit()
	await settle()
	assert(ui.world_camera.projection == Camera3D.PROJECTION_ORTHOGONAL)
	await save_view("top")
	ui.view_buttons.Fit.pressed.emit()
	assert(simulator.camera_view_mode == "Orbit")
	await settle()
	var track_rect: Rect2 = (ui.world_viewport.get_parent() as Control).get_global_rect()
	var pointer := track_rect.get_center()
	var drag_start := InputEventMouseButton.new()
	drag_start.position = pointer
	drag_start.global_position = pointer
	drag_start.button_index = MOUSE_BUTTON_RIGHT
	drag_start.pressed = true
	root.push_input(drag_start)
	var motion := InputEventMouseMotion.new()
	motion.position = pointer + Vector2(40, 0)
	motion.global_position = motion.position
	motion.relative = Vector2(40, 0)
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	root.push_input(motion)
	await settle()
	assert(absf(simulator.orbit_yaw) > 0.05, "right-drag on the track must orbit the camera")
	drag_start.pressed = false
	root.push_input(drag_start)
	var before_zoom: float = simulator.orbit_distance
	var wheel := InputEventMouseButton.new()
	wheel.position = pointer
	wheel.global_position = pointer
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	root.push_input(wheel)
	await settle()
	assert(simulator.orbit_distance < before_zoom, "scroll over the track must zoom")
	ui.view_buttons.Fit.pressed.emit()
	ui.controls["E-Stop"].pressed.emit()
	assert(simulator.emergency_stopped and ui.controls.Python.disabled)
	await save_view("emergency_stop")
	ui.controls.Reset.pressed.emit()
	assert(not simulator.emergency_stopped and not ui.controls.Python.disabled)
	await save_view("overview")
	print("UI_LAYOUT_OK resolutions=1440x900,1280x720,1080x680 tabs=3 cameras=3 actions=pause,resume,step,follow,top,fit,drag,zoom,emergency_stop,reset")
	if "--controller" in OS.get_cmdline_user_args():
		ui.controls.Python.pressed.emit()
		for attempt in 100:
			if simulator.py_socket_state == StreamPeerTCP.STATUS_CONNECTED and ui.python_output.texture != null:
				break
			await create_timer(0.1).timeout
		assert(simulator.python_command_count > 0 and ui.python_output.texture != null)
		ui.tabs.current_tab = 0
		await save_view("controller_overview")
		ui.tabs.current_tab = 1
		await save_view("controller_vision")
		print("UI_CONTROLLER_OK commands=%d displays=%d" % [simulator.python_command_count, simulator.python_display_count])
	simulator.queue_free()
	await process_frame
	quit()
