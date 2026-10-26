extends SceneTree


func _initialize() -> void:
	var root_path := OS.get_user_data_dir().path_join("notebook-atomic-smoke")
	var target := root_path.path_join("test.ipynb")
	var temporary := target + ".tmp"
	DirAccess.make_dir_recursive_absolute(root_path)
	var file := FileAccess.open(target, FileAccess.WRITE)
	file.store_string("old")
	file.close()
	file = FileAccess.open(temporary, FileAccess.WRITE)
	file.store_string("new")
	file.close()
	var err := DirAccess.rename_absolute(temporary, target)
	var saved := FileAccess.open(target, FileAccess.READ)
	var content := saved.get_as_text() if saved else ""
	if err == OK and content == "new":
		print("ATOMIC_REPLACE_OK")
		DirAccess.remove_absolute(target)
		DirAccess.remove_absolute(root_path)
		quit(0)
	else:
		push_error("ATOMIC_REPLACE_FAILED err=%d content=%s" % [err, content])
		quit(1)
