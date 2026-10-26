extends Control


func _draw() -> void:
	var root: Node = get_tree().get_first_node_in_group("simulator_root")
	var center := size * 0.5
	var radius: float = minf(size.x, size.y) * 0.42
	draw_rect(Rect2(Vector2.ZERO, size), Color("17232d"), true)
	for fraction: float in [0.25, 0.5, 0.75, 1.0]:
		draw_arc(center, radius * fraction, 0.0, TAU, 100, Color("405362"), 1.0, true)
	for degrees: int in range(0, 360, 30):
		var direction := Vector2(sin(deg_to_rad(degrees)), -cos(deg_to_rad(degrees)))
		draw_line(center, center + direction * radius, Color("2b3b48"), 1.0)
	if root != null:
		var angles: PackedFloat32Array = root.lidar_angles_deg
		var ranges: PackedFloat32Array = root.lidar_ranges_mm
		for i in mini(angles.size(), ranges.size()):
			var range_m: float = ranges[i] / 1000.0
			if range_m >= 12.0 or range_m < 0.05:
				continue
			var direction := Vector2(sin(deg_to_rad(angles[i])), -cos(deg_to_rad(angles[i])))
			draw_circle(center + direction * radius * range_m / 12.0, 2.1, Color("d7aa70"))
	draw_circle(center, 5.0, Color("82bfb4"))
	draw_line(center, center + Vector2(0, -radius * 0.14), Color("cbd7de"), 2.0)
