extends SceneTree


func _initialize() -> void:
	call_deferred("run_checks")


func run_checks() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		push_error("CONTROL_INPUT_SMOKE_FAILED: main scene does not load")
		quit(1)
		return
	var simulator := packed.instantiate()
	root.add_child(simulator)
	await process_frame
	var monitor_script := load("res://scripts/control_smoke_monitor.gd") as Script
	if monitor_script == null:
		push_error("CONTROL_INPUT_SMOKE_FAILED: control smoke monitor does not load")
		simulator.queue_free()
		await process_frame
		quit(1)
		return
	var monitor: Node = monitor_script.new()
	root.add_child(monitor)
	monitor.call("start_for", simulator)
