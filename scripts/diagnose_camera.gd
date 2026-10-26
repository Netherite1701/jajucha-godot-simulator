extends SceneTree


func _initialize() -> void:
	call_deferred("capture")


func capture() -> void:
	var simulator := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(simulator)
	simulator.set_physics_process(false)
	simulator.set_process(false)
	for i in 4:
		await process_frame
	var output_dir := "res://.cache/planning/camera_diagnosis"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	simulator.vehicle.global_position = Vector3(3.738, 0.0, 2.76651)
	simulator.vehicle.rotation = Vector3(0, deg_to_rad(-89.63914), 0)
	await simulator._render_sensor_bundle()
	simulator.camera_images.center_rgb.save_png(output_dir + "/original.png")
	simulator.vehicle.position.x += 0.055
	await RenderingServer.frame_post_draw
	simulator.camera_center.get_parent().get_texture().get_image().save_png(output_dir + "/lagging_camera.png")
	simulator.vehicle.visible = false
	await RenderingServer.frame_post_draw
	simulator.camera_center.get_parent().get_texture().get_image().save_png(output_dir + "/lagging_camera_no_vehicle.png")
	simulator.vehicle.position.x -= 0.055
	simulator.vehicle.visible = false
	await simulator._render_sensor_bundle()
	simulator.camera_images.center_rgb.save_png(output_dir + "/without_vehicle.png")
	simulator.camera_center.h_offset = 0.0
	simulator.camera_center.v_offset = 0.0
	await simulator._render_sensor_bundle()
	simulator.camera_images.center_rgb.save_png(output_dir + "/without_vehicle_or_translation.png")
	simulator.vehicle.visible = true
	await simulator._render_sensor_bundle()
	simulator.camera_images.center_rgb.save_png(output_dir + "/vehicle_with_zero_translation.png")
	simulator.get_node("CanvasLayer/HUD").hide()
	simulator.main_camera.global_position = Vector3(0, 12, 0.45)
	simulator.main_camera.rotation_degrees = Vector3(-90, 0, 0)
	simulator.main_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	simulator.main_camera.size = 11.5
	simulator.main_camera.keep_aspect = Camera3D.KEEP_WIDTH
	simulator.main_camera.make_current()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output_dir + "/overview.png")
	print("CAMERA_DIAGNOSIS_SAVED " + output_dir)
	simulator.queue_free()
	await process_frame
	quit()
