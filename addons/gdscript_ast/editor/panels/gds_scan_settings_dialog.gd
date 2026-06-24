# addons/gdscript_ast/editor/panels/gds_scan_settings_dialog.gd
# 扫描目录管理弹窗 — 浏览添加/删除 include/exclude 目录，读写 ProjectSettings (PackedStringArray)

class_name GDSScanSettingsDialog
extends AcceptDialog

var _enabled_check: CheckBox = null
var _include_tree: Tree = null
var _exclude_tree: Tree = null
var _file_dialog: FileDialog = null
var _editing_include := true

func _ready() -> void:
	title = "Project Scan Settings"
	var vbox = VBoxContainer.new()
	add_child(vbox)
	set_ok_button_text("Save")

	# Enable 开关
	_enabled_check = CheckBox.new()
	_enabled_check.text = "Enable Project Scan"
	_enabled_check.button_pressed = GDSScanConfig.is_enabled()
	vbox.add_child(_enabled_check)

	# Include 区
	vbox.add_child(_make_section_label("Include Directories (scan these):"))
	_include_tree = _make_dir_tree()
	vbox.add_child(_include_tree)
	var inc_btns = HBoxContainer.new()
	var inc_add = Button.new()
	inc_add.text = "Browse..."
	inc_add.pressed.connect(func(): _editing_include = true; _file_dialog.popup_centered())
	inc_btns.add_child(inc_add)
	var inc_del = Button.new()
	inc_del.text = "Remove"
	inc_del.pressed.connect(func(): _remove_selected(_include_tree))
	inc_btns.add_child(inc_del)
	vbox.add_child(inc_btns)

	# Exclude 区
	vbox.add_child(_make_section_label("Exclude Directories (skip these):"))
	_exclude_tree = _make_dir_tree()
	vbox.add_child(_exclude_tree)
	var exc_btns = HBoxContainer.new()
	var exc_add = Button.new()
	exc_add.text = "Browse..."
	exc_add.pressed.connect(func(): _editing_include = false; _file_dialog.popup_centered())
	exc_btns.add_child(exc_add)
	var exc_del = Button.new()
	exc_del.text = "Remove"
	exc_del.pressed.connect(func(): _remove_selected(_exclude_tree))
	exc_btns.add_child(exc_del)
	vbox.add_child(exc_btns)

	# 加载现有配置
	_populate_include_tree()
	_populate_exclude_tree()

	confirmed.connect(_on_save)

	# 隐藏的 FileDialog — 浏览目录
	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_file_dialog.access = FileDialog.ACCESS_RESOURCES
	_file_dialog.dir_selected.connect(_on_dir_selected)
	add_child(_file_dialog)
	min_size = Vector2(600, 500)

func _make_section_label(p_text: String) -> Label:
	var l = Label.new()
	l.text = p_text
	l.add_theme_font_size_override("font_size", 13)
	return l

func _make_dir_tree() -> Tree:
	var t = Tree.new()
	t.size_flags_vertical = Control.SIZE_EXPAND_FILL
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.hide_root = true
	t.columns = 1
	t.set_column_title(0, "Directory")
	t.select_mode = Tree.SELECT_ROW
	return t

func _populate_include_tree() -> void:
	_include_tree.clear()
	var root = _include_tree.create_item()
	for path in GDSScanConfig.get_include_dirs():
		if path != "":
			var item = _include_tree.create_item(root)
			item.set_text(0, path)

func _populate_exclude_tree() -> void:
	_exclude_tree.clear()
	var root = _exclude_tree.create_item()
	for path in GDSScanConfig.get_exclude_dirs():
		if path != "":
			var item = _exclude_tree.create_item(root)
			item.set_text(0, path)

func _on_dir_selected(p_path: String) -> void:
	var tree = _include_tree if _editing_include else _exclude_tree
	var root = tree.get_root()
	if root == null:
		root = tree.create_item()
	var item = tree.create_item(root)
	item.set_text(0, p_path)

func _remove_selected(p_tree: Tree) -> void:
	var item = p_tree.get_selected()
	if item:
		item.free()

func _on_save() -> void:
	# 收集 include → PackedStringArray
	var inc_arr := PackedStringArray()
	var inc_root = _include_tree.get_root()
	if inc_root:
		var item = inc_root.get_first_child()
		while item:
			inc_arr.append(item.get_text(0))
			item = item.get_next()
	ProjectSettings.set_setting(GDSScanConfig.SETTING_INCLUDE, inc_arr)

	# 收集 exclude → PackedStringArray
	var exc_arr := PackedStringArray()
	var exc_root = _exclude_tree.get_root()
	if exc_root:
		var item = exc_root.get_first_child()
		while item:
			exc_arr.append(item.get_text(0))
			item = item.get_next()
	ProjectSettings.set_setting(GDSScanConfig.SETTING_EXCLUDE, exc_arr)

	# Enable
	ProjectSettings.set_setting(GDSScanConfig.SETTING_ENABLED, _enabled_check.button_pressed)

	if _enabled_check.button_pressed:
		print("[GDScriptUtil] Project scan enabled with %d include, %d exclude dirs." % [inc_arr.size(), exc_arr.size()])
	else:
		print("[GDScriptUtil] Project scan OFF.")
