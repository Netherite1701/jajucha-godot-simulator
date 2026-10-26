extends SceneTree

var notebook: Control
var execute_requests := 0


func _initialize() -> void:
	call_deferred("run_checks")


func run_checks() -> void:
	notebook = Control.new()
	notebook.set_script(load("res://scripts/notebook_workspace.gd"))
	notebook.execute_requested.connect(func(_cell_id: int, _code: String): execute_requests += 1)
	root.add_child(notebook)
	await process_frame
	var cell: Dictionary = notebook.cells[0]
	cell.editor.text = "answer = 42\nprint('안녕', answer)"
	cell.execution_count = 7
	cell.outputs = [{"output_type": "stream", "name": "stdout", "text": "안녕 42\n"}]
	var markdown_id: int = notebook.call("_add_cell", "markdown", "# 노트\n두 번째 줄")
	var path := "user://notebook-roundtrip-한글.ipynb"
	notebook.call("_save_to", path)
	notebook.call("_save_to", path) # replacing an existing file must work atomically
	if not _check(FileAccess.file_exists(path), "notebook save creates the .ipynb file"):
		_finish(1)
		return
	notebook.call("_load_notebook", ProjectSettings.globalize_path(path))
	if not _check(notebook.cells.size() == 2, "reload restores code and Markdown cells"):
		_finish(1)
		return
	if not _check((notebook.cells[0].editor as CodeEdit).text == "answer = 42\nprint('안녕', answer)", "multi-line Korean Python source survives a save and reload"):
		_finish(1)
		return
	if not _check(int(notebook.cells[0].execution_count) == 7 and notebook.cells[0].outputs.size() == 1, "execution count and text output survive a save and reload"):
		_finish(1)
		return
	if not _check(notebook.cells[0].output.get_parsed_text().contains("안녕 42"), "saved output is rendered after reload"):
		_finish(1)
		return
	if not _check(notebook.cells[1].kind == "markdown" and notebook.cells[1].editor.text == "# 노트\n두 번째 줄", "multi-line Markdown survives a save and reload"):
		_finish(1)
		return
	if not _check(execute_requests == 0, "opening a notebook does not autorun"):
		_finish(1)
		return
	var duplicate_id: int = notebook.call("_add_cell", "code", "duplicate = True", int(notebook.cells[0].id))
	if not _check(int(notebook.cells[1].id) == duplicate_id and notebook.cells[1].editor.text == "duplicate = True", "cells can be inserted in order"):
		_finish(1)
		return
	notebook.call("_move_cell", duplicate_id, 1)
	if not _check(int(notebook.cells[2].id) == duplicate_id, "cell reordering updates the notebook order"):
		_finish(1)
		return
	notebook.call("_delete_cell", duplicate_id)
	if not _check(notebook.cells.size() == 2, "cell deletion removes the cell"):
		_finish(1)
		return
	notebook.dirty = true
	notebook.call("save_recovery_now")
	var recovery := OS.get_environment("LOCALAPPDATA").path_join("JajuchaGodotSimulatorData").path_join("notebook_recovery.ipynb")
	if not _check(FileAccess.file_exists(recovery) and notebook.dirty, "autosave writes recovery without dismissing the unsaved marker"):
		_finish(1)
		return
	print("NOTEBOOK_WORKSPACE_OK multiline_roundtrip=1 outputs_roundtrip=1 markdown=1 cell_order=1 no_autorun=1 recovery=1")
	_finish(0, path, recovery)


func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("NOTEBOOK_WORKSPACE_FAILED: " + message)
	return false


func _finish(code: int, notebook_path: String = "", recovery_path: String = "") -> void:
	for path in [notebook_path, recovery_path]:
		if not path.is_empty() and FileAccess.file_exists(path):
			DirAccess.remove_absolute(path if path.is_absolute_path() else ProjectSettings.globalize_path(path))
	if is_instance_valid(notebook):
		notebook.queue_free()
	await process_frame
	quit(code)
