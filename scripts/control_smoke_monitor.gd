extends Node

var _simulator: Node


func start_for(target: Node) -> void:
	_simulator = target
	call_deferred("run_checks")


func run_checks() -> void:
	var simulator := _simulator
	var dashboard: Node = simulator.get("dashboard")
	var tabs: TabContainer = dashboard.get("workspace_tabs")
	var workspace: Node = dashboard.get("notebook_workspace")
	var vehicle: Node3D = simulator.get("vehicle")
	if not _check(tabs != null and workspace != null and vehicle != null, "dashboard and vehicle initialize"):
		_finish(simulator, 1)
		return

	tabs.current_tab = 1
	var cells: Array = workspace.get("cells")
	var editor: CodeEdit = cells[0].get("editor") if not cells.is_empty() else null
	if not _check(editor != null, "Code workspace editor initializes"):
		_finish(simulator, 1)
		return
	editor.grab_focus()
	await get_tree().process_frame
	var editor_focused: bool = get_viewport().gui_get_focus_owner() == editor
	var start_position := vehicle.global_position
	var start_camera_mode: String = simulator.get("camera_view_mode")
	Input.action_press("accelerate")
	await get_tree().physics_frame
	Input.action_release("accelerate")
	var editor_control_blocked: bool = editor_focused and simulator.get("speed_request_mps") == 0.0 and vehicle.global_position.distance_to(start_position) < 0.001
	if not _check(editor_control_blocked, "accelerate input cannot move the vehicle while a Code editor is focused"):
		_finish(simulator, 1)
		return

	_call_key(simulator, KEY_F)
	_call_key(simulator, KEY_V)
	_call_key(simulator, KEY_SPACE)
	await get_tree().process_frame
	var shortcuts_blocked: bool = vehicle.global_position.distance_to(start_position) < 0.001 and simulator.get("camera_view_mode") == start_camera_mode and not simulator.get("emergency_stopped")
	if not _check(shortcuts_blocked, "reset, camera, and Space-stop shortcuts are isolated in Code workspace"):
		_finish(simulator, 1)
		return

	if OS.get_environment("JAJUCHA_PYTHON").is_empty():
		push_error("CONTROL_INPUT_SMOKE_FAILED: JAJUCHA_PYTHON must point at the bundled runtime")
		_finish(simulator, 1)
		return
	simulator.call("_notebook_execute", 7, "while True: pass")
	var startup_deadline := Time.get_ticks_msec() + 30000
	while int(simulator.get("notebook_active_cell_id")) != 7 and Time.get_ticks_msec() < startup_deadline:
		await get_tree().create_timer(0.05).timeout
	var host_pid: int = simulator.get("notebook_process_id")
	var port_file: String = simulator.get("notebook_port_file")
	var port_info: Variant = JSON.parse_string(FileAccess.get_file_as_string(port_file)) if FileAccess.file_exists(port_file) else null
	var kernel_pid: int = int(port_info.get("kernel_pid", 0)) if port_info is Dictionary else 0
	if not _check(simulator.get("notebook_connected") and host_pid > 0 and OS.is_process_running(host_pid) and kernel_pid > 0 and _python_process_exists(kernel_pid), "notebook host starts the real IPython kernel"):
		_finish(simulator, 1)
		return
	await get_tree().create_timer(0.5).timeout
	workspace.set("run_all_active", true)
	workspace.get("run_all_queue").append(8)
	simulator.set("python_override", true)
	simulator.set("speed_request_mps", 0.5)
	_call_input_key(simulator, KEY_F8)
	var emergency_stop_works: bool = simulator.get("emergency_stopped") and simulator.get("stop_reason") == "F8 emergency stop" and simulator.get("speed_request_mps") == 0.0 and not simulator.get("python_override") and not workspace.get("run_all_active") and workspace.get("run_all_queue").is_empty()
	if not _check(emergency_stop_works, "global F8 stops motion and clears queued notebook execution during a live cell"):
		_finish(simulator, 1)
		return
	var interrupt_deadline := Time.get_ticks_msec() + 10000
	while int(simulator.get("notebook_active_cell_id")) >= 0 and Time.get_ticks_msec() < interrupt_deadline:
		await get_tree().create_timer(0.05).timeout
	if not _check(int(simulator.get("notebook_active_cell_id")) == -1, "F8 interrupts the live infinite-loop cell"):
		_finish(simulator, 1)
		return

	simulator.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	var host_and_kernel_stopped: bool = not OS.is_process_running(host_pid) and not _python_process_exists(kernel_pid)
	if not _check(host_and_kernel_stopped, "application exit closes the notebook host and IPython kernel processes"):
		get_tree().quit(1)
		return
	print("CONTROL_INPUT_SMOKE_OK code_workspace_input_isolated=1 shortcuts_isolated=1 live_kernel_f8=1 queue_cleared=1 host_exit=1 kernel_exit=1")
	get_tree().quit(0)


func _call_key(target: Node, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	target.call("_unhandled_input", event)


func _call_input_key(target: Node, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	target.call("_input", event)


func _python_process_exists(pid: int) -> bool:
	var python_exe := OS.get_environment("JAJUCHA_PYTHON")
	if python_exe.is_empty() or pid <= 0:
		return false
	var output := []
	var code := OS.execute(python_exe, ["-c", "import psutil, sys; sys.exit(0 if psutil.pid_exists(int(sys.argv[1])) else 1)", str(pid)], output, true)
	return code == 0


func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("CONTROL_INPUT_SMOKE_FAILED: " + message)
	return false


func _finish(simulator: Node, code: int) -> void:
	simulator.queue_free()
	await get_tree().process_frame
	get_tree().quit(code)
