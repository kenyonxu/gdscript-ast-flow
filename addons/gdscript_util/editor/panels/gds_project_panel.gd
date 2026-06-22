# addons/gdscript_util/editor/panels/gds_project_panel.gd
# Project tab — 文件列表 + 引用数 + 跨文件边

class_name GDSProjectPanel
extends VBoxContainer

var _bridge: GDSAnalysisBridge = null
var _tree: Tree = null
var _rebuild_btn: Button = null

func setup(p_bridge: GDSAnalysisBridge) -> void:
	_bridge = p_bridge
	_bridge.project_analysis_completed.connect(_refresh)
	_build_ui()

func _build_ui() -> void:
	var toolbar = HBoxContainer.new()
	add_child(toolbar)

	_rebuild_btn = Button.new()
	_rebuild_btn.text = "Rebuild Project"
	_rebuild_btn.pressed.connect(_on_rebuild)
	toolbar.add_child(_rebuild_btn)

	_tree = Tree.new()
	_tree.size_flags_horizontal = SIZE_EXPAND_FILL
	_tree.size_flags_vertical = SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.columns = 2
	_tree.set_column_title(0, "File / Symbol")
	_tree.set_column_title(1, "Refs")
	add_child(_tree)

func _refresh(p_result: GDScriptProjectResult) -> void:
	_rebuild_btn.disabled = false
	_tree.clear()
	var root = _tree.create_item()
	# 文件列表 + 引用数
	for path in p_result.files:
		var refs = p_result.get_files_referencing(path).size()
		var item = _tree.create_item(root)
		var short = path.get_file()
		item.set_text(0, short)
		item.set_metadata(0, {"kind": "file", "path": path})
		item.set_text(1, str(refs))
		# 展开跨文件边
		_add_cross_edges(item, path, p_result)

func _add_cross_edges(p_parent: TreeItem, p_path: String, p_result: GDScriptProjectResult) -> void:
	for edge in p_result.cross_edges:
		if edge.source_file == p_path:
			var child = _tree.create_item(p_parent)
			var arrow = "→"
			child.set_text(0, "  %s %s.%s (%s)" % [arrow, edge.target_class, edge.target_symbol, edge.target_file.get_file()])
			child.set_custom_color(0, Color.DODGER_BLUE)

func _on_rebuild() -> void:
	_rebuild_btn.disabled = true
	_bridge.run_project_analysis("res://")
	# 完成后通过 project_analysis_completed 重启用按钮
	_rebuild_btn.set_deferred("disabled", false)
