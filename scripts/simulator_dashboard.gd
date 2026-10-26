class_name SimulatorDashboard
extends Control

signal action_requested(action: String)
signal camera_requested(mode: String)
signal world_input(event: InputEvent)

const BACKGROUND := Color("101820")
const SURFACE := Color("192630")
const BORDER := Color("30434f")
const TEXT := Color("e3edf2")
const MUTED := Color("9db1be")
const ACCENT := Color("85cabb")
const BLUE := Color("9abce7")
const DANGER := Color("e3aaa3")

var status_label: Label
var calibration_label: Label
var telemetry_label: Label
var lidar_view: Control
var python_output: TextureRect
var depth_view: TextureRect
var validity_view: TextureRect
var camera_views: Dictionary = {}
var world_viewport: SubViewport
var world_camera: Camera3D
var tabs: TabContainer
var event_view: RichTextLabel
var controls: Dictionary = {}
var view_buttons: Dictionary = {}
var camera_strip: HBoxContainer
var sidebar: TabContainer
var mode_label: Label
var mode_panel: PanelContainer
var speed_value: Label
var steering_value: Label
var time_value: Label
var bridge_value: Label
var sensor_summary: Label
var python_placeholder: Label
var shortcut_hint: Label
var strong_font: SystemFont
var workspace_tabs: TabContainer
var notebook_workspace: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ui_theme := Theme.new()
	var body_font := SystemFont.new()
	body_font.font_names = PackedStringArray(["Segoe UI", "Inter", "Arial"])
	strong_font = SystemFont.new()
	strong_font.font_names = body_font.font_names
	strong_font.font_weight = 600
	ui_theme.default_font = body_font
	ui_theme.default_font_size = 14
	ui_theme.set_color("font_color", "Label", TEXT)
	ui_theme.set_constant("separation", "VBoxContainer", 10)
	ui_theme.set_constant("separation", "HBoxContainer", 10)
	ui_theme.set_stylebox("panel", "TabContainer", _style(SURFACE.darkened(0.12), BORDER, 12, 10))
	ui_theme.set_stylebox("tab_selected", "TabContainer", _style(SURFACE, BORDER, 8, 10))
	ui_theme.set_stylebox("tab_unselected", "TabContainer", _style(BACKGROUND, BACKGROUND, 8, 10))
	ui_theme.set_stylebox("tab_hovered", "TabContainer", _style(SURFACE.lightened(0.06), BORDER, 8, 10))
	ui_theme.set_color("font_selected_color", "TabContainer", ACCENT)
	ui_theme.set_color("font_unselected_color", "TabContainer", MUTED)
	ui_theme.set_color("font_hovered_color", "TabContainer", TEXT)
	ui_theme.set_font("font", "TabContainer", strong_font)
	ui_theme.set_font_size("font_size", "TabContainer", 14)
	theme = ui_theme
	var backdrop := ColorRect.new()
	backdrop.color = BACKGROUND
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	var layout := _vbox(12)
	margin.add_child(layout)
	_build_header(layout)
	_build_toolbar(layout)
	var body := _hbox(14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(body)
	var workspace := _vbox(12)
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(workspace)
	workspace_tabs = TabContainer.new()
	workspace_tabs.name = "WorkspaceTabs"
	workspace_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_child(workspace_tabs)
	var drive_page := _vbox(12)
	drive_page.name = "Drive"
	workspace_tabs.add_child(drive_page)
	_build_track(drive_page)
	_build_camera_strip(drive_page)
	var code_page := VBoxContainer.new()
	code_page.name = "Code"
	code_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace_tabs.add_child(code_page)
	notebook_workspace = Control.new()
	notebook_workspace.set_script(load("res://scripts/notebook_workspace.gd"))
	notebook_workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	code_page.add_child(notebook_workspace)
	sidebar = TabContainer.new()
	sidebar.name = "InspectorTabs"
	sidebar.custom_minimum_size.x = 342
	sidebar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.tab_alignment = TabBar.ALIGNMENT_LEFT
	body.add_child(sidebar)
	tabs = sidebar
	_build_overview(_tab("Overview"))
	_build_vision(_tab("Vision"))
	_build_setup(_tab("Setup"))
	_build_footer(layout)
	resized.connect(_layout_sizes)
	_layout_sizes()
	select_camera("Orbit")


func _build_header(parent: VBoxContainer) -> void:
	var row := _hbox(12)
	row.custom_minimum_size.y = 48
	parent.add_child(row)
	var monogram := _label("J", 24, ACCENT)
	monogram.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	monogram.add_theme_font_override("font", strong_font)
	var mark := _panel(monogram, false, 6)
	mark.custom_minimum_size = Vector2(44, 44)
	row.add_child(mark)
	var brand := _vbox(0)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(brand)
	var title := _label("JAJUCHA", 21)
	title.add_theme_font_override("font", strong_font)
	brand.add_child(title)
	brand.add_child(_label("Autonomous driving simulator", 12, MUTED))
	mode_label = _label("MANUAL", 12, ACCENT)
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_label.add_theme_font_override("font", strong_font)
	mode_panel = _panel(mode_label, true, 10)
	mode_panel.custom_minimum_size.x = 104
	mode_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mode_panel)


func _build_toolbar(parent: VBoxContainer) -> void:
	var row := _hbox(8)
	var panel := _panel(row, false, 8)
	parent.add_child(panel)
	for entry in [["Python", "Run controller", "Start the supplied autonomous controller."], ["Keyboard", "Manual drive", "Drive with WASD or arrow keys."], ["Pause", "Pause", "Pause or resume simulation."], ["Step", "Step", "Advance one physics tick while paused."], ["Reset", "Reset car", "Return to the start. Clears emergency stop."]]:
		var button := _button(entry[1], entry[0] == "Python")
		button.tooltip_text = entry[2]
		button.pressed.connect(func(): action_requested.emit(entry[0]))
		controls[entry[0]] = button
		row.add_child(button)
	_spacer(row)
	var stop := _button("Emergency stop", false, true)
	stop.tooltip_text = "Stop the car immediately. Shortcut: Space."
	stop.pressed.connect(func(): action_requested.emit("E-Stop"))
	controls["E-Stop"] = stop
	row.add_child(stop)


func _build_track(parent: VBoxContainer) -> void:
	var content := _vbox(10)
	var card := _panel(content)
	card.name = "TrackCard"
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var heading := _hbox(8)
	content.add_child(heading)
	var title := _label("Track view", 15)
	title.add_theme_font_override("font", strong_font)
	heading.add_child(title)
	_spacer(heading)
	for mode in ["Orbit", "Follow", "Top", "Fit"]:
		var button := _button(mode)
		button.custom_minimum_size.y = 28
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(func(): camera_requested.emit(mode))
		view_buttons[mode] = button
		heading.add_child(button)
	var world_surface := SubViewportContainer.new()
	world_surface.name = "TrackViewportContainer"
	world_surface.size_flags_vertical = Control.SIZE_EXPAND_FILL
	world_surface.custom_minimum_size.y = 180
	world_surface.stretch = true
	world_surface.mouse_filter = Control.MOUSE_FILTER_STOP
	world_surface.tooltip_text = "Right-drag to orbit. Scroll to zoom. Fit restores the full track."
	world_surface.gui_input.connect(func(event: InputEvent): world_input.emit(event))
	content.add_child(world_surface)
	world_viewport = SubViewport.new()
	world_viewport.name = "TrackViewport"
	world_viewport.size = Vector2i(960, 480)
	world_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world_surface.add_child(world_viewport)
	world_camera = Camera3D.new()
	world_camera.name = "DashboardCamera"
	world_camera.current = true
	world_viewport.add_child(world_camera)


func _build_camera_strip(parent: VBoxContainer) -> void:
	camera_strip = _hbox(10)
	camera_strip.name = "CameraStrip"
	camera_strip.custom_minimum_size.y = 210
	parent.add_child(camera_strip)
	for entry in [["left", "Left"], ["center", "Front"], ["right", "Right"]]:
		var content := _vbox(8)
		var card := _panel(content, entry[0] == "center", 10)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		camera_strip.add_child(card)
		var row := _hbox(6)
		content.add_child(row)
		var title := _label(entry[1], 13, ACCENT if entry[0] == "center" else TEXT)
		title.add_theme_font_override("font", strong_font)
		row.add_child(title)
		_spacer(row)
		row.add_child(_label("CONTROLLER INPUT" if entry[0] == "center" else "640 x 400", 10, MUTED))
		var view := _image()
		view.tooltip_text = entry[1] + " camera. Full sensor resolution: 640 x 400."
		content.add_child(view)
		camera_views[entry[0]] = view


func _build_overview(parent: VBoxContainer) -> void:
	var telemetry := _vbox(6)
	parent.add_child(_panel(telemetry))
	telemetry.add_child(_heading("VEHICLE"))
	var speed_row := _hbox(8)
	telemetry.add_child(speed_row)
	speed_value = _label("0.00", 32)
	speed_value.add_theme_font_override("font", strong_font)
	speed_row.add_child(speed_value)
	var unit := _label("m/s", 14, MUTED)
	unit.size_flags_vertical = Control.SIZE_SHRINK_END
	speed_row.add_child(unit)
	_spacer(speed_row)
	var metrics := _hbox(20)
	telemetry.add_child(metrics)
	steering_value = _metric(metrics, "Steering", "0.0°")
	time_value = _metric(metrics, "Elapsed", "00:00")
	telemetry_label = _label("Position -0.45, 2.70 m\nHeading -90°", 12, MUTED, true)
	telemetry.add_child(telemetry_label)
	bridge_value = _label("Controller ready", 12, ACCENT)
	telemetry.add_child(bridge_value)
	var lidar_card := _vbox(8)
	parent.add_child(_panel(lidar_card))
	var lidar_heading := _hbox(8)
	lidar_card.add_child(lidar_heading)
	lidar_heading.add_child(_heading("LIDAR SCAN"))
	_spacer(lidar_heading)
	lidar_heading.add_child(_label("0.05–12 m", 11, MUTED))
	lidar_view = Control.new()
	lidar_view.name = "LidarDisplay"
	lidar_view.custom_minimum_size = Vector2(0, 230)
	lidar_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lidar_view.set_script(load("res://scripts/lidar_display.gd"))
	lidar_card.add_child(lidar_view)
	sensor_summary = _label("409 rays · 3 cameras", 11, MUTED)
	lidar_card.add_child(sensor_summary)
	var activity := _vbox(8)
	parent.add_child(_panel(activity))
	activity.add_child(_heading("RECENT ACTIVITY"))
	event_view = RichTextLabel.new()
	event_view.name = "EventLog"
	event_view.custom_minimum_size.y = 80
	event_view.add_theme_font_size_override("normal_font_size", 12)
	event_view.add_theme_color_override("default_color", MUTED)
	event_view.scroll_active = true
	activity.add_child(event_view)


func _build_vision(parent: VBoxContainer) -> void:
	var perception := _vbox(10)
	parent.add_child(_panel(perception))
	perception.add_child(_heading("CONTROLLER VISION"))
	perception.add_child(_label("Bird’s-eye view, lane edges and planned path", 12, MUTED, true))
	var preview := Control.new()
	preview.custom_minimum_size.y = 330
	perception.add_child(preview)
	python_output = _image()
	python_output.name = "PythonOutput"
	preview.add_child(python_output)
	python_output.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	python_placeholder = _label("Start the controller to see its planned path.", 14, MUTED, true)
	python_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	python_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview.add_child(python_placeholder)
	python_placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var stereo := _vbox(8)
	parent.add_child(_panel(stereo))
	stereo.add_child(_heading("STEREO DIAGNOSTICS"))
	var pair := _hbox(10)
	stereo.add_child(pair)
	for title in ["Depth", "Match validity"]:
		var cell := _vbox(6)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pair.add_child(cell)
		cell.add_child(_label(title, 12, TEXT))
		var view := _image()
		view.custom_minimum_size.y = 100
		cell.add_child(view)
		if title == "Depth":
			depth_view = view
		else:
			validity_view = view
	stereo.add_child(_label("Depth: brighter means nearer.\nValidity: white means a stereo match.", 11, MUTED, true))


func _build_setup(parent: VBoxContainer) -> void:
	var guide := _vbox(10)
	parent.add_child(_panel(guide))
	guide.add_child(_heading("QUICK CONTROLS"))
	for entry in [["WASD / arrows", "Drive manually"], ["Space", "Emergency stop"], ["F", "Reset the car"], ["V", "Cycle track views"], ["Right-drag", "Orbit the track"], ["Scroll", "Zoom the track"]]:
		var row := _hbox(10)
		guide.add_child(row)
		var key := _label(entry[0], 12, BLUE)
		key.custom_minimum_size.x = 108
		row.add_child(key)
		row.add_child(_label(entry[1], 12, MUTED))
	var lights := _button("Run starting lights")
	lights.tooltip_text = "Run the competition's four-stage light sequence."
	lights.pressed.connect(func(): action_requested.emit("Lights"))
	guide.add_child(lights)
	var updates := _button("Check for updates")
	updates.tooltip_text = "Ask the Jajucha launcher to check its stable GitHub release feed."
	updates.pressed.connect(func(): action_requested.emit("CheckUpdates"))
	guide.add_child(updates)
	guide.add_child(_label("Automatic checks run every six hours. Updates install only after you choose Update and restart.", 11, MUTED, true))
	var dimensions := _vbox(10)
	parent.add_child(_panel(dimensions))
	dimensions.add_child(_heading("DIMENSIONS & CALIBRATION"))
	calibration_label = _label("", 12, MUTED, true)
	calibration_label.name = "Calibration"
	dimensions.add_child(calibration_label)


func _build_footer(parent: VBoxContainer) -> void:
	var footer := _hbox(16)
	parent.add_child(footer)
	status_label = _label("Ready to drive", 12, MUTED)
	status_label.clip_text = true
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(status_label)
	shortcut_hint = _label("Space to stop   ·   Right-drag to orbit", 12, MUTED)
	footer.add_child(shortcut_hint)


func update_telemetry(state: Dictionary) -> void:
	speed_value.text = "%.2f" % state.speed
	steering_value.text = "%+.1f°" % state.steering_deg
	var seconds := int(state.time)
	time_value.text = "%02d:%02d" % [seconds / 60, seconds % 60]
	telemetry_label.text = "Position  %.2f, %.2f m\nHeading  %+.1f°  ·  Frame %d" % [state.x, state.z, state.heading, state.frame]
	bridge_value.text = "Controller connected" if state.connected else "Controller starting…" if state.python_running else "Controller ready"
	bridge_value.add_theme_color_override("font_color", ACCENT if state.connected else MUTED)
	sensor_summary.text = "%d / %d LiDAR returns  ·  3 cameras" % [state.hits, state.rays]
	var mode := "STOPPED" if state.stopped else "PAUSED" if state.paused else "AUTONOMOUS" if state.autonomous else "MANUAL"
	mode_label.text = mode
	var color := DANGER if state.stopped else Color("e1c28c") if state.paused else ACCENT if state.autonomous else BLUE
	mode_label.add_theme_color_override("font_color", color)
	mode_panel.add_theme_stylebox_override("panel", _style(SURFACE, color.darkened(0.55), 10, 10))
	controls.Pause.text = "Resume" if state.paused else "Pause"
	controls.Step.disabled = not state.paused
	controls.Python.disabled = state.stopped or (state.python_running and state.autonomous)
	controls.Python.text = "Controller running" if state.connected and state.autonomous else "Starting controller…" if state.python_running and state.autonomous else "Run controller"
	controls.Keyboard.disabled = state.stopped
	controls.Keyboard.add_theme_stylebox_override("normal", _style(Color("273c4d"), Color("526f88"), 8, 10) if not state.autonomous and not state.stopped else _button_style(false, false))
	python_placeholder.visible = python_output.texture == null


func sync_world_camera(source: Camera3D) -> void:
	world_camera.global_transform = source.global_transform
	world_camera.projection = source.projection
	world_camera.fov = source.fov
	world_camera.near = source.near
	world_camera.far = source.far
	world_camera.keep_aspect = source.keep_aspect
	world_camera.size = maxf(source.size, 6.0 * world_viewport.size.x / maxf(world_viewport.size.y, 1)) if source.projection == Camera3D.PROJECTION_ORTHOGONAL else source.size


func select_camera(selected: String) -> void:
	for mode: String in view_buttons:
		view_buttons[mode].add_theme_stylebox_override("normal", _button_style(mode == selected, false))


func _layout_sizes() -> void:
	if sidebar != null:
		sidebar.custom_minimum_size.x = clampf(size.x * 0.255, 304, 374)
		camera_strip.custom_minimum_size.y = clampf(size.y * 0.245, 164, 220)
		lidar_view.custom_minimum_size.y = clampf(size.y * 0.225, 144, 204)
		shortcut_hint.visible = size.x >= 1100


func _tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar.add_child(scroll)
	var content := _vbox(12)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return content


func _metric(parent: HBoxContainer, caption: String, value: String) -> Label:
	var column := _vbox(2)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	column.add_child(_label(caption, 11, MUTED))
	var label := _label(value, 18)
	column.add_child(label)
	return label


func _heading(text: String) -> Label:
	var label := _label(text, 11, MUTED)
	label.add_theme_font_override("font", strong_font)
	return label


func _label(text: String, font_size: int = 14, color: Color = TEXT, wrap: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	label.clip_text = false
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _image() -> TextureRect:
	var view := TextureRect.new()
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	return view


func _button(caption: String, primary: bool = false, danger: bool = false) -> Button:
	var button := Button.new()
	button.text = caption
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 36
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", DANGER if danger else TEXT)
	button.add_theme_color_override("font_hover_color", TEXT)
	button.add_theme_color_override("font_disabled_color", MUTED.darkened(0.25))
	button.add_theme_stylebox_override("normal", _button_style(primary, danger))
	button.add_theme_stylebox_override("hover", _button_style(primary, danger, true))
	button.add_theme_stylebox_override("pressed", _button_style(true, danger))
	button.add_theme_stylebox_override("disabled", _style(SURFACE.darkened(0.15), BORDER.darkened(0.15), 8, 10))
	return button


func _button_style(selected: bool, danger: bool, hovered: bool = false) -> StyleBoxFlat:
	var fill := Color("294b47") if selected else Color("22323e")
	var border := Color("527d73") if selected else BORDER
	if danger:
		fill = Color("4c3335")
		border = Color("80575a")
	return _style(fill.lightened(0.08) if hovered else fill, border, 8, 10)


func _panel(child: Control, emphasis: bool = false, padding: int = 14) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(SURFACE, Color("426b63") if emphasis else BORDER, 12, padding))
	panel.add_child(child)
	return panel


func _style(fill: Color, border: Color, radius: int, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(padding)
	return style


func _vbox(spacing: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", spacing)
	return box


func _hbox(spacing: int) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", spacing)
	return box


func _spacer(parent: HBoxContainer) -> void:
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(spacer)
