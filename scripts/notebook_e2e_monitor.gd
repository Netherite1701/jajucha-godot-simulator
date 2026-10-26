extends Node

const TEST_TIMEOUT_MS := 45000

var simulator: Node
var workspace: Control
var executed_cells: Array[Dictionary] = []
var failures: Array[String] = []
var recovery_path := ""
var had_recovery := false
var recovery_backup := PackedByteArray()
var test_root := ""
var notebook_path := ""
var python_path := ""
var check_results: Dictionary = {}


func start_for(target: Node) -> void:
	simulator = target
	call_deferred("run_checks")


func run_checks() -> void:
	var dashboard: Node = simulator.get("dashboard")
	workspace = dashboard.get("notebook_workspace") as Control if dashboard != null else null
	if workspace == null:
		_finish(false, "notebook workspace was not constructed")
		return
	for dialog in simulator.find_children("*", "ConfirmationDialog", true, false):
		if dialog.title == "Notebook recovery found":
			dialog.canceled.emit()
	workspace.execute_requested.connect(func(cell_id: int, code: String): executed_cells.append({"cell_id": cell_id, "code": code}))
	var data_root := OS.get_environment("JAJUCHA_DATA_DIR")
	if data_root.is_empty():
		data_root = OS.get_environment("LOCALAPPDATA").path_join("JajuchaGodotSimulatorData")
	test_root = data_root.path_join("evidence").path_join("notebook-e2e-temp")
	DirAccess.make_dir_recursive_absolute(test_root)
	notebook_path = test_root.path_join("notebook-roundtrip-한글.ipynb")
	python_path = test_root.path_join("import-source-한글.py")
	recovery_path = OS.get_environment("LOCALAPPDATA").path_join("JajuchaGodotSimulatorData").path_join("notebook_recovery.ipynb")
	had_recovery = FileAccess.file_exists(recovery_path)
	if had_recovery:
		var old_recovery := FileAccess.open(recovery_path, FileAccess.READ)
		recovery_backup = old_recovery.get_buffer(old_recovery.get_length())
		old_recovery.close()

	workspace.call("_new_notebook")
	workspace.dirty = false
	var first_id := int(workspace.cells[0].id)
	_click_toolbar("Add code")
	var second_id := int(workspace.cells[1].id)
	_click_toolbar("Add Markdown")
	var markdown_id := int(workspace.cells[2].id)
	if not _check(workspace.cells.size() == 3 and workspace.cells[2].kind == "markdown", "toolbar adds code and Markdown cells"):
		_finish(false, "cell creation")
		return
	var code_editor := _cell(first_id).editor as CodeEdit
	var highlighter := code_editor.syntax_highlighter as CodeHighlighter
	if not _check(code_editor.gutters_draw_line_numbers and code_editor.indent_automatic and code_editor.indent_use_spaces and highlighter != null, "Python editor has line numbers, indentation, and syntax highlighting"):
		_finish(false, "Python editor features")
		return
	code_editor.text = "pri"
	code_editor.grab_focus()
	code_editor.set_caret_column(3)
	code_editor.request_code_completion(true)
	await get_tree().process_frame
	var completion_found := false
	for option in code_editor.get_code_completion_options():
		if str(option.get("display_text", "")) == "print":
			completion_found = true
	if not _check(code_editor.code_completion_enabled and completion_found, "Python completion suggests print"):
		_finish(false, "Python completion")
		return
	workspace.call("_duplicate_cell", second_id)
	var duplicate_id := int(workspace.cells[2].id)
	workspace.call("_move_cell", duplicate_id, -1)
	if not _check(int(workspace.cells[1].id) == duplicate_id, "duplicate and move preserve cell order"):
		_finish(false, "cell ordering")
		return
	workspace.call("_delete_cell", duplicate_id)
	if not _check(workspace.cells.size() == 3 and int(workspace.cells[1].id) == second_id, "delete removes only the selected cell"):
		_finish(false, "cell deletion")
		return

	_cell(first_id).editor.text = "shared_value = 21\nprint('Korean: 안녕', shared_value)"
	_cell(second_id).editor.text = "shared_value *= 2\nprint('PERSISTENT', shared_value)"
	_cell(markdown_id).editor.text = "# 한글 Markdown\nSecond line"
	if not await _run_cell_and_wait(first_id, true):
		_finish(false, "first persistent-state cell failed")
		return
	if not _check(_cell(first_id).output.get_parsed_text().contains("Korean: 안녕 21"), "Korean text output is rendered"):
		_finish(false, "Korean output")
		return
	if not await _run_cell_and_wait(second_id, true):
		_finish(false, "second persistent-state cell failed")
		return
	if not _check(_cell(second_id).output.get_parsed_text().contains("PERSISTENT 42"), "variables persist between notebook cells"):
		_finish(false, "persistent execution state")
		return

	var input_id := int(workspace.call("_add_cell", "code", "answer = input('Name? ')\nprint('INPUT_OK', answer)"))
	workspace.call("_run_cell", input_id)
	var input_dialog := await _wait_for_dialog("Notebook input", TEST_TIMEOUT_MS)
	if not _check(input_dialog != null, "standard input prompt appears in the app"):
		_finish(false, "input prompt")
		return
	var fields := input_dialog.find_children("*", "LineEdit", true, false)
	if not _check(not fields.is_empty(), "input prompt contains an editable field"):
		_finish(false, "input field")
		return
	(fields[0] as LineEdit).text = "Jajucha"
	input_dialog.confirmed.emit()
	if not await _wait_for_cell(input_id, true, TEST_TIMEOUT_MS):
		_finish(false, "input cell did not complete")
		return
	if not _check(_cell(input_id).output.get_parsed_text().contains("INPUT_OK Jajucha"), "submitted input reaches Python and its output returns"):
		_finish(false, "input round trip")
		return

	var image_code := "from IPython.display import display, Image\nimport cv2, numpy as np\nok, encoded = cv2.imencode('.png', np.full((8, 8, 3), 120, np.uint8))\ndisplay(Image(data=encoded.tobytes(), format='png'))"
	var image_id := int(workspace.call("_add_cell", "code", image_code))
	if not await _run_cell_and_wait(image_id, true):
		_finish(false, "image output cell failed")
		return
	if not _check(_cell(image_id).output_images.size() == 1, "live PNG output is rendered in its cell"):
		_finish(false, "live image output")
		return

	var error_id := int(workspace.call("_add_cell", "code", "raise RuntimeError('EXPECTED_NOTEBOOK_ERROR')"))
	if not await _run_cell_and_wait(error_id, false):
		_finish(false, "exception cell did not report failure")
		return
	if not _check(_cell(error_id).output.get_parsed_text().contains("EXPECTED_NOTEBOOK_ERROR"), "Python traceback is rendered in the output"):
		_finish(false, "exception output")
		return

	var order_code_id := int(workspace.call("_add_cell", "code", "run_order = ['first']\nprint('ORDER_FIRST')"))
	var order_code_second_id := int(workspace.call("_add_cell", "code", "run_order.append('second')\nprint('ORDER_SECOND')"))
	for item in workspace.cells:
		if item.kind == "code" and int(item.id) not in [order_code_id, order_code_second_id]:
			item.editor.text = ""
	workspace.call("_run_all")
	if not await _wait_for_workspace_status("Run all complete", TEST_TIMEOUT_MS):
		_finish(false, "Run all did not complete")
		return
	if not _check(_cell(order_code_id).output.get_parsed_text().contains("ORDER_FIRST") and _cell(order_code_second_id).output.get_parsed_text().contains("ORDER_SECOND"), "Run all executes cells in notebook order"):
		_finish(false, "Run all order")
		return

	_cell(first_id).editor.text = "while True: pass"
	_cell(second_id).editor.text = "must_not_run = True"
	_cell(second_id).execution_count = null
	for cell_id in [order_code_id, order_code_second_id]:
		_cell(cell_id).editor.text = ""
	workspace.call("_run_all")
	if not await _wait_for_active_cell(first_id, TEST_TIMEOUT_MS):
		_finish(false, "Run all did not enter its first cell")
		return
	_click_toolbar("Stop")
	if not await _wait_for_idle(TEST_TIMEOUT_MS):
		_finish(false, "Stop did not interrupt the running cell")
		return
	if not _check(not workspace.run_all_active and workspace.run_all_queue.is_empty() and _cell(second_id).execution_count == null, "Stop clears the Run all queue before the next cell starts"):
		_finish(false, "Run all cancellation")
		return

	workspace.restart_requested.emit()
	if not await _wait_for_workspace_status("Kernel restarted; variables were cleared.", TEST_TIMEOUT_MS):
		_finish(false, "Restart kernel did not report completion")
		return
	var reset_check_id := int(workspace.call("_add_cell", "code", "print('STATE_CLEARED', 'shared_value' not in globals())"))
	if not await _run_cell_and_wait(reset_check_id, true):
		_finish(false, "cell after kernel restart failed")
		return
	if not _check(_cell(reset_check_id).output.get_parsed_text().contains("STATE_CLEARED True"), "kernel restart clears variables"):
		_finish(false, "kernel state reset")
		return

	var saved_source := "multiline_value = 9\nprint('SAVED', multiline_value)"
	_cell(first_id).editor.text = saved_source
	_cell(markdown_id).editor.text = "# 한글 Markdown\nSecond line"
	workspace.call("_save_to", notebook_path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(notebook_path))
	var executions_before_open := executed_cells.size()
	workspace.call("_load_notebook", notebook_path)
	if not _check(str(workspace.cells[0].editor.text) == saved_source and str(workspace.cells[2].editor.text) == "# 한글 Markdown\nSecond line", "standard ipynb preserves multi-line code and Markdown"):
		_finish(false, "notebook source round trip")
		return
	if not _check(executed_cells.size() == executions_before_open, "opening an ipynb never executes its cells"):
		_finish(false, "no-auto-run behavior")
		return
	if not _check(parsed is Dictionary and parsed.get("nbformat") == 4, "saved file uses the standard notebook format"):
		_finish(false, "notebook format")
		return
	if not _check(not workspace.cells[4].output_images.is_empty(), "saved image output is restored on reopen"):
		_finish(false, "saved image output restoration")
		return

	workspace.dirty = false
	_click_toolbar("Open .ipynb")
	var open_dialog := await _wait_for_file_dialog("*.ipynb", TEST_TIMEOUT_MS)
	if not _check(open_dialog != null, "Open .ipynb toolbar opens a file picker"):
		_finish(false, "open notebook picker")
		return
	open_dialog.file_selected.emit(notebook_path)
	await get_tree().process_frame
	if not _check(str(workspace.cells[0].editor.text) == saved_source, "Open .ipynb loads the selected notebook"):
		_finish(false, "open notebook action")
		return

	var imported := FileAccess.open(python_path, FileAccess.WRITE)
	imported.store_string("imported_value = 5\nprint('imported')\n")
	imported.close()
	workspace.dirty = false
	_click_toolbar("Import .py")
	var import_dialog := await _wait_for_file_dialog("*.py", TEST_TIMEOUT_MS)
	if not _check(import_dialog != null, "Import .py toolbar opens a source picker"):
		_finish(false, "import Python picker")
		return
	import_dialog.file_selected.emit(python_path)
	await get_tree().process_frame
	if not _check(workspace.cells.size() == 1 and workspace.cells[0].editor.text == "imported_value = 5\nprint('imported')\n", "Python source imports as one code cell"):
		_finish(false, "Python import")
		return

	workspace.dirty = true
	workspace.autosave_elapsed = 0.0
	workspace.call("_process", 31.0)
	if not _check(FileAccess.file_exists(recovery_path), "autosave writes a recovery notebook"):
		_finish(false, "autosave")
		return
	var recovery: Variant = JSON.parse_string(FileAccess.get_file_as_string(recovery_path))
	if not _check(recovery is Dictionary and recovery.get("cells", []).size() == 1, "recovery file is valid notebook JSON"):
		_finish(false, "recovery content")
		return
	var executions_before_recovery := executed_cells.size()
	workspace.call("_offer_recovery")
	var recovery_dialog := await _wait_for_dialog("Notebook recovery found", TEST_TIMEOUT_MS) as ConfirmationDialog
	if not _check(recovery_dialog != null and recovery_dialog.dialog_text.contains("will not run automatically"), "startup offers recovery without running code"):
		_finish(false, "recovery prompt")
		return
	recovery_dialog.confirmed.emit()
	await get_tree().process_frame
	if not _check(workspace.cells.size() == 1 and str(workspace.cells[0].editor.text) == "imported_value = 5\nprint('imported')\n", "accepting recovery restores the saved notebook"):
		_finish(false, "recovery restoration")
		return
	if not _check(executed_cells.size() == executions_before_recovery, "recovery restoration never executes cells"):
		_finish(false, "recovery execution")
		return
	(workspace.cells[0].editor as CodeEdit).text = "unsaved_recovery_test = True"
	workspace.call("_mark_dirty")
	_click_toolbar("New")
	var unsaved_dialog := await _wait_for_dialog("Unsaved notebook", TEST_TIMEOUT_MS) as ConfirmationDialog
	if not _check(unsaved_dialog != null and unsaved_dialog.get_ok_button().text == "Save" and unsaved_dialog.get_cancel_button().text == "Cancel", "New prompts with Save and Cancel before discarding unsaved edits"):
		_finish(false, "unsaved changes prompt")
		return
	unsaved_dialog.custom_action.emit("discard")
	await get_tree().process_frame
	if not _check(workspace.cells.size() == 1 and str(workspace.cells[0].editor.text).is_empty(), "discard action opens a clean notebook"):
		_finish(false, "unsaved discard action")
		return

	workspace.call("_clear_outputs")
	if not _check(_cell(int(workspace.cells[0].id)).output.get_parsed_text().is_empty(), "Clear outputs removes cell output"):
		_finish(false, "clear outputs")
		return
	_finish(true, "Notebook workspace and IPython end-to-end checks passed")


func _cell(cell_id: int) -> Dictionary:
	for item in workspace.cells:
		if int(item.id) == cell_id:
			return item
	return {}


func _click_toolbar(label: String) -> bool:
	for candidate in workspace.find_children("*", "Button", true, false):
		var button := candidate as Button
		if button != null and button.text == label:
			button.pressed.emit()
			return true
	return false


func _run_cell_and_wait(cell_id: int, success: bool) -> bool:
	workspace.call("_run_cell", cell_id)
	return await _wait_for_cell(cell_id, success, TEST_TIMEOUT_MS)


func _wait_for_cell(cell_id: int, success: bool, timeout_ms: int) -> bool:
	var status := "Cell %d complete" % cell_id if success else "Cell %d failed" % cell_id
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if workspace.status_label.text == status and int(simulator.get("notebook_active_cell_id")) == -1:
			return true
		await get_tree().create_timer(0.05).timeout
	return false


func _wait_for_active_cell(cell_id: int, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if int(simulator.get("notebook_active_cell_id")) == cell_id:
			return true
		await get_tree().create_timer(0.05).timeout
	return false


func _wait_for_idle(timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if int(simulator.get("notebook_active_cell_id")) == -1:
			return true
		await get_tree().create_timer(0.05).timeout
	return false


func _wait_for_workspace_status(expected: String, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if workspace.status_label.text == expected:
			return true
		await get_tree().create_timer(0.05).timeout
	return false


func _wait_for_dialog(title: String, timeout_ms: int) -> AcceptDialog:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		for dialog in simulator.find_children("*", "AcceptDialog", true, false):
			if dialog.title == title:
				return dialog as AcceptDialog
		await get_tree().create_timer(0.05).timeout
	return null


func _wait_for_file_dialog(filter: String, timeout_ms: int) -> FileDialog:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		for dialog in workspace.find_children("*", "FileDialog", true, false):
			for file_filter in dialog.filters:
				if str(file_filter).contains(filter):
					return dialog as FileDialog
		await get_tree().create_timer(0.05).timeout
	return null


func _check(condition: bool, message: String) -> bool:
	check_results[message] = condition
	if condition:
		return true
	push_error("NOTEBOOK_E2E_FAILED: " + message)
	return false


func _finish(passed: bool, message: String) -> void:
	var diagnostics := ""
	if workspace != null:
		var port_info := ""
		var port_file := str(simulator.get("notebook_port_file"))
		if not port_file.is_empty() and FileAccess.file_exists(port_file):
			port_info = FileAccess.get_file_as_string(port_file).strip_edges()
		diagnostics = " | status=%s connected=%s active_cell=%s host_pid=%s port=%s port_file=%s" % [
			workspace.status_label.text,
			str(simulator.get("notebook_connected")),
			str(simulator.get("notebook_active_cell_id")),
			str(simulator.get("notebook_process_id")),
			str(simulator.get("notebook_port")),
			port_info
		]
	if not recovery_path.is_empty():
		if had_recovery:
			var recovery_file := FileAccess.open(recovery_path, FileAccess.WRITE)
			if recovery_file != null:
				recovery_file.store_buffer(recovery_backup)
				recovery_file.close()
		else:
			DirAccess.remove_absolute(recovery_path)
	var report_root := OS.get_environment("JAJUCHA_DATA_DIR")
	if report_root.is_empty():
		report_root = OS.get_environment("LOCALAPPDATA").path_join("JajuchaGodotSimulatorData")
	var report_dir := report_root.path_join("evidence")
	DirAccess.make_dir_recursive_absolute(report_dir)
	var report := {"test": "Installed notebook UI end-to-end", "passed": passed, "message": message + diagnostics, "check_results": check_results, "verified_on": Time.get_date_string_from_system()}
	var report_file := FileAccess.open(report_dir.path_join("notebook-e2e.json"), FileAccess.WRITE)
	if report_file != null:
		report_file.store_string(JSON.stringify(report, "\t"))
		report_file.close()
	if DirAccess.dir_exists_absolute(test_root):
		DirAccess.remove_absolute(notebook_path)
		DirAccess.remove_absolute(python_path)
		DirAccess.remove_absolute(test_root)
	if passed:
		print("NOTEBOOK_E2E_OK " + message)
	else:
		push_error("NOTEBOOK_E2E_FAILED " + message)
	simulator.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if passed else 1)
