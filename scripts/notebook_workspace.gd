extends Control

signal execute_requested(cell_id: int, code: String)
signal interrupt_requested
signal restart_requested
signal workspace_status(message: String)

const SURFACE := Color("192630")
const BORDER := Color("30434f")
const TEXT := Color("e3edf2")
const MUTED := Color("9db1be")
const ACCENT := Color("85cabb")
const AUTOSAVE_SECONDS := 30.0
const OUTPUT_LIMIT_CHARS := 1_000_000

var cells: Array[Dictionary] = []
var next_cell_id := 1
var active_path := ""
var dirty := false
var autosave_elapsed := 0.0
var status_label: Label
var cell_list: VBoxContainer
var scroll: ScrollContainer
var run_all_queue: Array[int] = []
var run_all_active := false
var pending_after_save: Callable


func _ready() -> void:
	workspace_status.connect(_show_workspace_status)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 6)
	root.add_child(toolbar)
	_add_button(toolbar, "New", _request_new_notebook)
	_add_button(toolbar, "Open .ipynb", _open_dialog)
	_add_button(toolbar, "Import .py", _import_dialog)
	_add_button(toolbar, "Save", _save_notebook)
	_add_button(toolbar, "Add code", func(): _add_cell("code", ""))
	_add_button(toolbar, "Add Markdown", func(): _add_cell("markdown", ""))
	_add_button(toolbar, "Run cell", _run_selected)
	_add_button(toolbar, "Run all", _run_all)
	_add_button(toolbar, "Stop", _interrupt)
	_add_button(toolbar, "Restart kernel", func(): restart_requested.emit())
	_add_button(toolbar, "Clear outputs", _clear_outputs)
	status_label = Label.new()
	status_label.text = "Notebook ready · code runs only when you press Run"
	status_label.add_theme_color_override("font_color", MUTED)
	root.add_child(status_label)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	cell_list = VBoxContainer.new()
	cell_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell_list.add_theme_constant_override("separation", 10)
	scroll.add_child(cell_list)
	_add_cell("code", "# Jajucha simulator notebook\n# Example: print(1 + 1)\n")
	_offer_recovery()


func _show_workspace_status(message: String) -> void:
	status_label.text = message
	status_label.add_theme_color_override("font_color", MUTED)


func _process(delta: float) -> void:
	if not dirty:
		return
	autosave_elapsed += delta
	if autosave_elapsed >= AUTOSAVE_SECONDS:
		autosave_elapsed = 0.0
		_save_recovery()


func _add_button(parent: Control, caption: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 32
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)


func _add_cell(kind: String, source: String, insert_after: int = -1) -> int:
	var cell_id := next_cell_id
	next_cell_id += 1
	var panel := PanelContainer.new()
	panel.name = "Cell_%d" % cell_id
	panel.add_theme_stylebox_override("panel", _panel_style())
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	panel.add_child(body)
	var header := HBoxContainer.new()
	body.add_child(header)
	var title := Label.new()
	title.text = ("PYTHON" if kind == "code" else "MARKDOWN") + "  ·  Cell %02d" % cell_id
	title.add_theme_color_override("font_color", ACCENT)
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var run := Button.new()
	run.text = "Run"
	run.pressed.connect(func(): _run_cell(cell_id))
	header.add_child(run)
	var up := Button.new()
	up.text = "↑"
	up.tooltip_text = "Move cell up"
	up.pressed.connect(func(): _move_cell(cell_id, -1))
	header.add_child(up)
	var down := Button.new()
	down.text = "↓"
	down.tooltip_text = "Move cell down"
	down.pressed.connect(func(): _move_cell(cell_id, 1))
	header.add_child(down)
	var duplicate := Button.new()
	duplicate.text = "Duplicate"
	duplicate.pressed.connect(func(): _duplicate_cell(cell_id))
	header.add_child(duplicate)
	var remove := Button.new()
	remove.text = "Delete"
	remove.pressed.connect(func(): _delete_cell(cell_id))
	header.add_child(remove)
	var editor: Control
	if kind == "code":
		var code := CodeEdit.new()
		code.custom_minimum_size = Vector2(0, 112)
		code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		code.gutters_draw_line_numbers = true
		code.draw_tabs = true
		code.indent_size = 4
		code.indent_automatic = true
		code.indent_use_spaces = true
		code.auto_brace_completion_enabled = true
		code.code_completion_enabled = true
		code.code_completion_prefixes = PackedStringArray(["."])
		code.syntax_highlighter = _python_highlighter()
		code.text = source
		code.text_changed.connect(_mark_dirty)
		code.code_completion_requested.connect(func(): _offer_python_completions(code))
		editor = code
	else:
		var markdown := TextEdit.new()
		markdown.custom_minimum_size = Vector2(0, 88)
		markdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		markdown.text = source
		markdown.text_changed.connect(_mark_dirty)
		editor = markdown
	body.add_child(editor)
	var output := RichTextLabel.new()
	output.name = "Output"
	output.custom_minimum_size.y = 0
	output.fit_content = true
	output.scroll_active = true
	output.selection_enabled = true
	output.add_theme_color_override("default_color", MUTED)
	body.add_child(output)
	var item := {"id": cell_id, "kind": kind, "panel": panel, "editor": editor, "output": output, "output_images": [], "outputs": [], "execution_count": null}
	var index := cells.size()
	if insert_after >= 0:
		for i in cells.size():
			if int(cells[i].id) == insert_after:
				index = i + 1
				break
	cells.insert(index, item)
	cell_list.add_child(panel)
	_rebuild_cell_order()
	_mark_dirty()
	return cell_id


func _python_highlighter() -> CodeHighlighter:
	var highlighter := CodeHighlighter.new()
	highlighter.number_color = Color("87b9d6")
	highlighter.symbol_color = Color("c6d2dc")
	highlighter.function_color = Color("8ac7bd")
	highlighter.member_variable_color = Color("a6c9ef")
	for keyword in ["import", "from", "as", "def", "class", "return", "if", "elif", "else", "for", "while", "in", "try", "except", "finally", "with", "True", "False", "None", "and", "or", "not", "break", "continue", "pass"]:
		highlighter.add_keyword_color(keyword, Color("d8b8ec"))
	highlighter.add_color_region("#", "", Color("8c9d9f"), true)
	return highlighter


func _offer_python_completions(code: CodeEdit) -> void:
	# CodeEdit marks the caret with U+FFFF in its completion text. Remove that
	# sentinel before matching words, otherwise "pri" is treated as "pri\uFFFF".
	var fragment := code.get_text_for_code_completion().replace(String.chr(0xFFFF), "").to_lower()
	var options := ["jchm", "camera", "lidar", "control", "get_image", "get_depth", "get_lidar", "show_image", "show_lidar", "set_motor", "numpy", "cv2", "print", "range", "enumerate"]
	for word in options:
		if fragment.is_empty() or word.begins_with(fragment):
			code.add_code_completion_option(CodeEdit.KIND_PLAIN_TEXT, word, word, ACCENT)
	code.update_code_completion_options(true)


func _run_selected() -> void:
	var selected := _focused_code_cell()
	if selected >= 0:
		_run_cell(selected)
	elif not cells.is_empty():
		_run_cell(int(cells[0].id))


func _run_cell(cell_id: int) -> void:
	var index := _index_of(cell_id)
	if index < 0 or str(cells[index].kind) != "code":
		return
	var code := cells[index].editor as CodeEdit
	if code.text.strip_edges().is_empty():
		return
	_clear_cell_output(index)
	status_label.text = "Running cell %d…" % cell_id
	execute_requested.emit(cell_id, code.text)


func complete_cell(cell_id: int, output: String, success: bool, execution_count: int) -> void:
	var index := _index_of(cell_id)
	if index >= 0:
		var view := cells[index].output as RichTextLabel
		view.text = output
		cells[index].execution_count = execution_count
	status_label.text = "Cell %d complete" % cell_id if success else "Cell %d failed" % cell_id
	status_label.add_theme_color_override("font_color", ACCENT if success else Color("e3aaa3"))
	if run_all_active:
		if not success:
			run_all_active = false
			run_all_queue.clear()
			return
		_run_next_queued()


func append_cell_output(cell_id: int, text: String, is_error: bool = false) -> void:
	var index := _index_of(cell_id)
	if index < 0:
		return
	var view := cells[index].output as RichTextLabel
	var remaining := OUTPUT_LIMIT_CHARS - view.get_total_character_count()
	if remaining <= 0:
		return
	var displayed := text
	if displayed.length() > remaining:
		displayed = displayed.substr(0, remaining) + "\n[output truncated after 1,000,000 characters]\n"
	view.append_text(displayed.replace("\n", "[br]"))
	if is_error:
		(cells[index].outputs as Array).append({"output_type": "error", "ename": "ExecutionError", "evalue": displayed, "traceback": displayed.split("\n", false)})
	else:
		(cells[index].outputs as Array).append({"output_type": "stream", "name": "stdout", "text": displayed})
	dirty = true


func append_cell_image(cell_id: int, mime: String, encoded: String) -> void:
	var index := _index_of(cell_id)
	if index < 0:
		return
	var raw := Marshalls.base64_to_raw(encoded)
	var image := Image.new()
	var err := image.load_png_from_buffer(raw) if mime == "image/png" else image.load_jpg_from_buffer(raw)
	if err != OK:
		append_cell_output(cell_id, "[image could not be decoded]\n")
		return
	for previous in cells[index].output_images:
		(previous as Control).queue_free()
	cells[index].output_images.clear()
	var saved_outputs: Array = cells[index].outputs
	for output_index in range(saved_outputs.size() - 1, -1, -1):
		var prior: Dictionary = saved_outputs[output_index]
		if prior.get("output_type") == "display_data" and (prior.get("data", {}).has("image/png") or prior.get("data", {}).has("image/jpeg")):
			saved_outputs.remove_at(output_index)
	var texture_view := TextureRect.new()
	texture_view.custom_minimum_size = Vector2(320, 180)
	texture_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texture_view.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	texture_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_view.texture = ImageTexture.create_from_image(image)
	(cells[index].panel.get_child(0) as VBoxContainer).add_child(texture_view)
	cells[index].output_images.append(texture_view)
	(cells[index].outputs as Array).append({"output_type": "display_data", "data": {mime: encoded}, "metadata": {}})
	dirty = true


func _run_all() -> void:
	run_all_queue.clear()
	for item in cells:
		if item.kind == "code" and not (item.editor as CodeEdit).text.strip_edges().is_empty():
			run_all_queue.append(int(item.id))
	run_all_active = not run_all_queue.is_empty()
	_run_next_queued()


func _run_next_queued() -> void:
	if run_all_queue.is_empty():
		run_all_active = false
		status_label.text = "Run all complete"
		return
	var next_id: int = run_all_queue.pop_front()
	_run_cell(next_id)


func _interrupt() -> void:
	run_all_active = false
	run_all_queue.clear()
	interrupt_requested.emit()
	status_label.text = "Stopping execution…"


func _restart_after_stop() -> void:
	run_all_active = false
	run_all_queue.clear()
	restart_requested.emit()


func _focused_code_cell() -> int:
	var focus := get_viewport().gui_get_focus_owner()
	for item in cells:
		if item.editor == focus:
			return int(item.id)
	return -1


func _move_cell(cell_id: int, direction: int) -> void:
	var index := _index_of(cell_id)
	var target := index + direction
	if index < 0 or target < 0 or target >= cells.size():
		return
	var item: Dictionary = cells.pop_at(index)
	cells.insert(target, item)
	_rebuild_cell_order()
	_mark_dirty()


func _duplicate_cell(cell_id: int) -> void:
	var index := _index_of(cell_id)
	if index < 0:
		return
	var item: Dictionary = cells[index]
	_add_cell(str(item.kind), str(item.editor.text), cell_id)


func _delete_cell(cell_id: int) -> void:
	var index := _index_of(cell_id)
	if index < 0:
		return
	(cells[index].panel as Control).queue_free()
	cells.remove_at(index)
	_mark_dirty()


func _rebuild_cell_order() -> void:
	for child in cell_list.get_children():
		cell_list.remove_child(child)
	for item in cells:
		cell_list.add_child(item.panel)


func _index_of(cell_id: int) -> int:
	for i in cells.size():
		if int(cells[i].id) == cell_id:
			return i
	return -1


func _mark_dirty() -> void:
	dirty = true
	status_label.text = "Unsaved changes"
	status_label.add_theme_color_override("font_color", Color("e2c08a"))


func _clear_outputs() -> void:
	for index in cells.size():
		_clear_cell_output(index)
	_mark_dirty()


func _clear_cell_output(index: int) -> void:
	(cells[index].output as RichTextLabel).clear()
	for view in cells[index].output_images:
		(view as Control).queue_free()
	cells[index].output_images.clear()
	(cells[index].outputs as Array).clear()


func _new_notebook() -> void:
	if dirty:
		_save_recovery()
	for item in cells:
		(item.panel as Control).queue_free()
	cells.clear()
	active_path = ""
	_add_cell("code", "")


func _open_dialog() -> void:
	if dirty:
		_prompt_unsaved(func(): _show_open_dialog())
		return
	_show_open_dialog()


func _show_open_dialog() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.add_filter("*.ipynb", "Jupyter notebook")
	dialog.current_dir = _documents_notebooks()
	add_child(dialog)
	dialog.file_selected.connect(func(path: String): _load_notebook(path); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(0.72)


func _import_dialog() -> void:
	if dirty:
		_prompt_unsaved(func(): _show_import_dialog())
		return
	_show_import_dialog()


func _show_import_dialog() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.add_filter("*.py", "Python source")
	dialog.current_dir = _documents_notebooks()
	add_child(dialog)
	dialog.file_selected.connect(func(path: String):
		_new_notebook()
		var file := FileAccess.open(path, FileAccess.READ)
		if file:
			(cells[0].editor as CodeEdit).text = file.get_as_text()
		active_path = ""
		_mark_dirty()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(0.72)


func _load_notebook(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		workspace_status.emit("Could not open notebook: " + path)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or not parsed.get("cells", []) is Array:
		workspace_status.emit("This file is not a valid notebook JSON document.")
		return
	for item in cells:
		(item.panel as Control).queue_free()
	cells.clear()
	for notebook_cell in parsed.cells:
		var kind := "markdown" if notebook_cell.get("cell_type", "code") == "markdown" else "code"
		var raw_source: Variant = notebook_cell.get("source", "")
		var source := _source_to_text(raw_source)
		var cell_id := _add_cell(kind, source)
		var index := _index_of(cell_id)
		if index >= 0 and kind == "code":
			cells[index].execution_count = notebook_cell.get("execution_count")
			_restore_cell_outputs(index, notebook_cell.get("outputs", []))
	active_path = path
	dirty = false
	status_label.text = "Opened %s · cells were not executed" % path.get_file()


func _save_notebook() -> void:
	if active_path.is_empty():
		var dialog := FileDialog.new()
		dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		dialog.access = FileDialog.ACCESS_FILESYSTEM
		dialog.add_filter("*.ipynb", "Jupyter notebook")
		dialog.current_dir = _documents_notebooks()
		add_child(dialog)
		dialog.file_selected.connect(func(path: String):
			active_path = path if path.to_lower().ends_with(".ipynb") else path + ".ipynb"
			_save_to(active_path)
			dialog.queue_free())
		dialog.canceled.connect(func(): pending_after_save = Callable(); dialog.queue_free())
		dialog.popup_centered_ratio(0.72)
	else:
		_save_to(active_path)


func _save_recovery() -> void:
	DirAccess.make_dir_recursive_absolute(_local_data_root())
	_save_to(_local_data_root().path_join("notebook_recovery.ipynb"), true)


func save_recovery_now() -> void:
	if dirty:
		_save_recovery()


func _save_to(path: String, is_recovery: bool = false) -> void:
	var notebook_cells: Array[Dictionary] = []
	for item in cells:
		var source := str(item.editor.text)
		var entry := {"cell_type": "markdown" if item.kind == "markdown" else "code", "metadata": {}, "source": _source_to_lines(source)}
		if item.kind == "code":
			entry["execution_count"] = item.execution_count
			entry["outputs"] = item.outputs
		notebook_cells.append(entry)
	var document := {"cells": notebook_cells, "metadata": {"kernelspec": {"display_name": "Python 3 (Jajucha)", "language": "python", "name": "python3"}, "language_info": {"name": "python", "version": "3.12.15"}}, "nbformat": 4, "nbformat_minor": 5}
	var absolute := path if path.is_absolute_path() else ProjectSettings.globalize_path(path)
	var temporary := absolute + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		workspace_status.emit("Could not write notebook: " + path)
		return
	file.store_string(JSON.stringify(document, "\t"))
	file.close()
	var err := DirAccess.rename_absolute(temporary, absolute)
	if err != OK:
		DirAccess.remove_absolute(temporary)
		workspace_status.emit("Notebook save failed (error %d)." % err)
		return
	if not is_recovery:
		dirty = false
		autosave_elapsed = 0.0
		status_label.text = "Saved %s" % path.get_file()
		status_label.add_theme_color_override("font_color", ACCENT)
		var recovery := _local_data_root().path_join("notebook_recovery.ipynb")
		if path != recovery and FileAccess.file_exists(recovery):
			DirAccess.remove_absolute(recovery)
	if not is_recovery and pending_after_save.is_valid():
		var continuation := pending_after_save
		pending_after_save = Callable()
		continuation.call()


func _source_to_lines(source: String) -> Array[String]:
	var lines: Array[String] = []
	var parts := source.split("\n", true)
	for index in parts.size():
		var line := str(parts[index])
		if index < parts.size() - 1:
			line += "\n"
		lines.append(line)
	return lines


func _source_to_text(raw_source: Variant) -> String:
	if not raw_source is Array:
		return str(raw_source)
	var source := ""
	for index in raw_source.size():
		var line := str(raw_source[index])
		source += line
		if index < raw_source.size() - 1 and not line.ends_with("\n"):
			source += "\n"
	return source


func _restore_cell_outputs(cell_index: int, saved_outputs: Variant) -> void:
	if not saved_outputs is Array:
		return
	var item: Dictionary = cells[cell_index]
	var view := item.output as RichTextLabel
	view.clear()
	item.output_images.clear()
	item.outputs = saved_outputs.duplicate(true)
	for output in saved_outputs:
		if not output is Dictionary:
			continue
		var output_type := str(output.get("output_type", ""))
		if output_type == "stream":
			var stream_text := str(output.get("text", ""))
			view.append_text(stream_text.replace("\n", "[br]"))
		elif output_type == "error":
			var error_text := "\n".join(output.get("traceback", []))
			if error_text.is_empty():
				error_text = str(output.get("evalue", "Notebook error"))
			view.append_text(error_text.replace("\n", "[br]"))
		elif output_type in ["display_data", "execute_result"]:
			var data: Variant = output.get("data", {})
			if data is Dictionary:
				for mime in ["image/png", "image/jpeg"]:
					if data.has(mime):
						append_cell_image(int(item.id), mime, str(data[mime]))
						item.outputs = saved_outputs.duplicate(true)
						break
				if data.has("text/plain"):
					view.append_text(str(data["text/plain"]).replace("\n", "[br]"))


func _local_data_root() -> String:
	var local_app_data := OS.get_environment("LOCALAPPDATA")
	if local_app_data.is_empty():
		local_app_data = OS.get_user_data_dir().get_base_dir()
	return local_app_data.path_join("JajuchaGodotSimulatorData")


func _documents_notebooks() -> String:
	var documents := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if documents.is_empty():
		documents = OS.get_environment("USERPROFILE").path_join("Documents")
	var notebooks := documents.path_join("JajuchaSimulator").path_join("Notebooks")
	DirAccess.make_dir_recursive_absolute(notebooks)
	return notebooks


func _offer_recovery() -> void:
	var path := _local_data_root().path_join("notebook_recovery.ipynb")
	if not FileAccess.file_exists(path):
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Notebook recovery found"
	dialog.dialog_text = "A recovered notebook is available from the last session. Restore it? It will not run automatically."
	add_child(dialog)
	dialog.confirmed.connect(func(): _load_notebook(path); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(500, 180))


func _request_new_notebook() -> void:
	if dirty:
		_prompt_unsaved(func(): _new_notebook())
	else:
		_new_notebook()


func _prompt_unsaved(continuation: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Unsaved notebook"
	dialog.dialog_text = "Save the current notebook before continuing?"
	dialog.get_ok_button().text = "Save"
	dialog.get_cancel_button().text = "Cancel"
	dialog.add_button("Discard changes", true, "discard")
	add_child(dialog)
	dialog.popup_centered(Vector2i(480, 160))
	dialog.confirmed.connect(func():
		pending_after_save = continuation
		_save_notebook()
		dialog.queue_free())
	dialog.custom_action.connect(func(action: String):
		if action == "discard":
			dirty = false
			var recovery := _local_data_root().path_join("notebook_recovery.ipynb")
			if FileAccess.file_exists(recovery):
				DirAccess.remove_absolute(recovery)
			continuation.call()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = SURFACE
	style.border_color = BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	return style
