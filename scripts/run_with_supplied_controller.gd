extends SceneTree


func _initialize() -> void:
	call_deferred("launch_simulator")


func launch_simulator() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		push_error("Could not load the simulator main scene.")
		quit(1)
		return
	var simulator := packed.instantiate()
	root.add_child(simulator)
	await process_frame
	simulator.start_python_bridge()
	for attempt in 100:
		if simulator.py_socket_state == StreamPeerTCP.STATUS_CONNECTED:
			print("SUPPLIED_CONTROLLER_RUNNING frames are being sent on 127.0.0.1:8765")
			return
		await create_timer(0.1).timeout
	push_error("The supplied controller did not connect to the simulator bridge.")
