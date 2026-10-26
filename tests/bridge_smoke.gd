extends SceneTree


func _initialize() -> void:
	call_deferred("run_checks")


func run_checks() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if not _check(packed != null, "main scene must load"):
		return
	var simulator := packed.instantiate()
	root.add_child(simulator)
	await process_frame
	simulator.start_python_bridge()
	await create_timer(4.0).timeout
	if not _check(simulator.python_running, "Python bridge process must remain active"):
		print("BRIDGE_DIAGNOSTIC pid=%d running=%s socket=%d status=%s events=%s" % [simulator.python_process_id, OS.is_process_running(simulator.python_process_id) if simulator.python_process_id > 0 else false, simulator.py_socket_state, simulator.status_label.text, JSON.stringify(simulator.event_log)])
		_finish(simulator, 1)
		return
	if not _check(simulator.py_socket_state == StreamPeerTCP.STATUS_CONNECTED, "Python must connect to the loopback socket"):
		_finish(simulator, 1)
		return
	if not _check(simulator.frame_id > 1, "the renderer must deliver successive sensor bundles"):
		_finish(simulator, 1)
		return
	if not _check(simulator.camera_images.has("center_rgb"), "center camera frames must reach Python"):
		_finish(simulator, 1)
		return
	var saw_supplied_controller := false
	for entry: String in simulator.event_log:
		if entry.contains("user_supplied_controller.py"):
			saw_supplied_controller = true
	if not _check(saw_supplied_controller, "the supplied BEV code must start through the bridge"):
		_finish(simulator, 1)
		return
	if not _check(simulator.python_command_count > 0, "the supplied code must send a motor command"):
		_finish(simulator, 1)
		return
	if not _check(simulator.python_display_count > 0, "the supplied code must send its BEV/edge visualization"):
		_finish(simulator, 1)
		return
	print("BRIDGE_SMOKE_OK loopback=127.0.0.1:8765 supplied_controller=started rendered_frames=%d motor_commands=%d displays=%d speed=%.3f pose=(%.2f,%.2f)" % [simulator.frame_id, simulator.python_command_count, simulator.python_display_count, simulator.commanded_speed_mps, simulator.vehicle.global_position.x, simulator.vehicle.global_position.z])
	_finish(simulator, 0)


func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("BRIDGE_SMOKE_FAILED: %s" % message)
	return false


func _finish(simulator: Node, code: int) -> void:
	if simulator.python_process_id > 0 and OS.is_process_running(simulator.python_process_id):
		OS.kill(simulator.python_process_id)
	simulator.queue_free()
	await process_frame
	quit(code)
