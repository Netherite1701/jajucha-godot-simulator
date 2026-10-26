extends SceneTree

func _initialize() -> void:
	call_deferred("_start")

func _start() -> void:
	var simulator := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(simulator)
	var monitor: Node = (load("res://scripts/lap_monitor_node.gd") as Script).new()
	root.add_child(monitor)
	monitor.call("start_for", simulator)
