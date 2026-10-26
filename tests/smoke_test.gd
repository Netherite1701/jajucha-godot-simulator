extends SceneTree


func _initialize() -> void:
	call_deferred("run_checks")


func run_checks() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	assert(packed != null, "main scene must load")
	var simulator := packed.instantiate()
	root.add_child(simulator)
	await process_frame
	var course := simulator.get_node("World/Course") as GridMap
	if not _check(course != null, "manual GridMap must be present"):
		return
	var start_cell := course.local_to_map(course.to_local(simulator.vehicle.global_position))
	if not _check(start_cell == Vector3i(4, 0, 5) and course.get_cell_item(start_cell) == CourseData.TILE_NAMES.find("D"), "vehicle must start centered on the lower straight road tile"):
		return
	if not _check(course.get_used_cells().size() == 41, "assembly must occupy 41 cells"):
		return
	var actual_inventory := {}
	for cell: Vector3i in course.get_used_cells():
		var tile_name: String = CourseData.TILE_NAMES[course.get_cell_item(cell)]
		actual_inventory[tile_name] = int(actual_inventory.get(tile_name, 0)) + 1
	if not _check(actual_inventory == CourseData.INVENTORY_TILE_COUNTS, "manual tile locations must match the printed 41-panel inventory"):
		return
	if not _check(course.cell_size.is_equal_approx(Vector3(0.9, 0.003, 0.9)), "panel pitch must be 900 mm with 3 mm substrate"):
		return
	if not _check(course.mesh_library != null and course.mesh_library.get_item_list().size() == 16, "all 16 panel types must be paintable"):
		return
	for item_id: int in course.mesh_library.get_item_list():
		var tile_mesh: Mesh = course.mesh_library.get_item_mesh(item_id)
		var tile_material := tile_mesh.surface_get_material(0) as StandardMaterial3D
		if not _check(tile_material != null and tile_material.albedo_texture != null, "every tile must have its manual artwork"):
			return
	if not _check(is_equal_approx(course.cell_size.x * 11.0, 9.9) and is_equal_approx(course.cell_size.z * 6.0, 5.4), "assembly bounds must be 9.9 x 5.4 m"):
		return
	var cameras: Array[String] = [
		"World/Vehicle/SensorRig/Viewport_Left",
		"World/Vehicle/SensorRig/Viewport_Center",
		"World/Vehicle/SensorRig/Viewport_Right",
	]
	for path in cameras:
		var viewport := simulator.get_node(path) as SubViewport
		if not _check(viewport.size == Vector2i(640, 400), "%s must be 640x400" % path):
			return
	if not _check(is_equal_approx(simulator.camera_mount_transforms[0].origin.x, -0.029) and is_equal_approx(simulator.camera_mount_transforms[2].origin.x, 0.029), "outer cameras must keep the derived 58 mm baseline"):
		return
	if not _check(is_equal_approx(simulator.camera_mount_transforms[1].origin.y, 0.09900903), "center-camera height must use the saved working-run calibration"):
		return
	for mesh: GeometryInstance3D in simulator.vehicle.find_children("*", "GeometryInstance3D", true, false):
		if not _check(mesh.layers == 2, "vehicle geometry must be excluded from its own camera feeds: " + str(mesh.name)):
			return
	for camera: Camera3D in [simulator.camera_left, simulator.camera_center, simulator.camera_right]:
		if not _check(not camera.get_cull_mask_value(2), "sensor cameras must exclude vehicle render layer"):
			return
		if not _check(camera.projection == Camera3D.PROJECTION_FRUSTUM and is_zero_approx(camera.h_offset) and is_zero_approx(camera.v_offset), "principal point must use an off-axis frustum without translating the lens"):
			return
		if not _check(simulator.camera_output_viewports.has(camera.name), "each sensor must have its calibrated lens output"):
			return
	simulator.vehicle.global_position = Vector3(1.35, 0, -1.8)
	if not _check(is_zero_approx(simulator.track_forward_slope(Vector3.RIGHT)), "flat top straight must not inherit the ramp pitch"):
		return
	simulator.vehicle.global_position = Vector3(1.2, 0, 2.7)
	if not _check(simulator.track_forward_slope(Vector3.RIGHT) > 0.05 and simulator.track_forward_slope(Vector3.LEFT) < -0.05, "axle contact pitch must follow the physical ramp in both directions"):
		return
	simulator._sync_sensor_transforms()
	if not _check(simulator.camera_center.global_transform.is_equal_approx(simulator.camera_rig.global_transform * simulator.camera_mount_transforms[1]), "camera transforms must follow vehicle movement between sensor captures"):
		return
	simulator.start_position()
	var vehicle_footprint := simulator.get_node("World/Vehicle/VehicleFootprint") as CollisionShape3D
	if not _check(is_equal_approx((vehicle_footprint.shape as BoxShape3D).size.x, 0.1776), "vehicle outer width must match 177.6 mm"):
		return
	var tunnel: Node3D = simulator.get_node("World/CompetitionTunnel_390mmWide_220mmHigh")
	var roof: CollisionShape3D = _first_collision_shape(tunnel.get_node("RoofSheet_260x98mm_00"))
	if not _check(roof != null and (roof.shape as BoxShape3D).size.is_equal_approx(Vector3(0.260, 0.005, 0.098)), "tunnel sheet dimensions must match 260 x 98 mm and 5T material"):
		return
	var cube_shape := _first_collision_shape(simulator.get_node("World/Obstacles/ObstacleCube_150mm"))
	if not _check(cube_shape != null and (cube_shape.shape as BoxShape3D).size.is_equal_approx(Vector3(0.15, 0.15, 0.15)), "obstacle cube must be 150 mm per side"):
		return
	if not _check(simulator.get_node("World/Obstacles/StartingLightBody_80x160mm") != null, "starting light must be present"):
		return
	if not _check(simulator.get_node("World/Obstacles/StartingLightBody_80x160mm/LightShield_70x130x40mm") != null, "light shield must match the manual"):
		return
	var start_body_shape := _first_collision_shape(simulator.get_node("World/Obstacles/StartingLightBody_80x160mm"))
	if not _check(start_body_shape != null and (start_body_shape.shape as BoxShape3D).size.is_equal_approx(Vector3(0.08, 0.16, 0.04)), "starting-light body must be 80 x 160 mm"):
		return
	var sign_shape := _first_collision_shape(simulator.get_node("World/Obstacles/PitSign_320x130mm"))
	if not _check(sign_shape != null and is_equal_approx((sign_shape.shape as BoxShape3D).size.x, 0.32) and is_equal_approx((sign_shape.shape as BoxShape3D).size.y, 0.13), "pit sign must be 320 x 130 mm"):
		return
	if not _check(simulator.lidar_ray_count == 409, "LiDAR must emit 409 samples"):
		return
	simulator.cast_lidar_rays()
	if not _check(simulator.lidar_ranges_mm.size() == 409, "LiDAR arrays must have matching sample count"):
		return
	if not _check(simulator.lidar_angles_deg[0] == 0.0 and simulator.lidar_angles_deg[408] > 359.0, "LiDAR scan must span the full circle instead of repeating the forward ray"):
		return
	if not _check(simulator.calibration_label.text.contains("TRACK") and simulator.calibration_label.text.contains("TUNNEL") and simulator.calibration_label.text.contains("SENSORS"), "track, tunnel, and sensor dimension summaries must be displayed"):
		return
	print("SMOKE_TEST_OK cells=41 tile=900x900mm library=16 cameras=3x640x400 lidar=409")
	simulator.queue_free()
	await process_frame
	quit(0)


func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("SMOKE_TEST_FAILED: %s" % message)
	quit(1)
	return false


func _first_collision_shape(node: Node) -> CollisionShape3D:
	for child: Node in node.get_children():
		if child is CollisionShape3D:
			return child as CollisionShape3D
	return null
