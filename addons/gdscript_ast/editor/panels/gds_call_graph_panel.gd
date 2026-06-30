# addons/gdscript_ast/editor/panels/gds_call_graph_panel.gd
# 调用图子面板 — Tree 按 caller 分组 + 右侧详情 + 多选 + 右键菜单
# 参考: project-juicy-godot/addons/fuse/editor/topology/fuse_topology.gd
#        limboai/editor/task_tree.cpp (metadata + multi-select + context menu)

class_name GDSCallGraphPanel
extends HSplitContainer

var _bridge: GDSAnalysisBridge = null
var _l10n: GDSL10n = null
var _tree: Tree = null
var _detail: RichTextLabel = null
var _search_edit: LineEdit = null
var _context_menu: PopupMenu = null

const COLORS := {
	0: Color.GREEN,        # SELF
	1: Color.DODGER_BLUE,  # SUPER
	2: Color.ORANGE,       # EXTERNAL
	3: Color.MEDIUM_PURPLE,# CONNECT
	4: Color.PURPLE,       # SIGNAL_CONNECT
	5: Color.CYAN,         # LAMBDA
	7: Color.RED,          # EMIT
}

func setup(p_bridge: GDSAnalysisBridge, p_l10n: GDSL10n = null) -> void:
	_bridge = p_bridge
	_l10n = p_l10n if p_l10n else GDSL10n.new()
	_bridge.analysis_completed.connect(_refresh)
	_bridge.function_selected.connect(_on_function_selected)
	_build_ui()

func _build_ui() -> void:
	# 左侧容器: 搜索栏 + Tree
	var left = VBoxContainer.new()
	left.size_flags_horizontal = SIZE_EXPAND_FILL
	add_child(left)

	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "搜索函数..."
	_search_edit.text_changed.connect(_on_search_changed)
	left.add_child(_search_edit)

	_tree = Tree.new()
	_tree.size_flags_horizontal = SIZE_EXPAND_FILL
	_tree.size_flags_vertical = SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.columns = 1
	_tree.select_mode = Tree.SELECT_MULTI  # 多选 — 参考 limboai
	_tree.allow_rmb_select = true  # 右键选中 + 触发 item_mouse_selected（否则 RMB 无信号）
	_tree.item_selected.connect(_on_item_selected)
	# Godot 4.3+ item_mouse_selected 信号传 mouse_button_index
	_tree.item_mouse_selected.connect(_on_item_rmb)
	left.add_child(_tree)

	# 右侧详情
	_detail = RichTextLabel.new()
	_detail.size_flags_horizontal = SIZE_EXPAND_FILL
	_detail.bbcode_enabled = true
	_detail.fit_content = true
	_detail.scroll_active = true
	add_child(_detail)

	# 右键上下文菜单
	_context_menu = PopupMenu.new()
	_context_menu.add_item("Jump to Definition", 0)
	_context_menu.add_item("Find Callers", 1)
	_context_menu.add_item("Find Callees", 2)
	_context_menu.id_pressed.connect(_on_context_action)
	add_child(_context_menu)

func _refresh(p_result: GDScriptAnalysisResult) -> void:
	_tree.clear()
	if p_result.call_graph == null or p_result.call_graph.edges.is_empty():
		_detail.clear()
		_detail.append_text("[i]No call graph data available[/i]")
		return

	# 按 caller 分组
	var groups: Dictionary = {}
	for edge in p_result.call_graph.edges:
		if not groups.has(edge.caller):
			groups[edge.caller] = []
		groups[edge.caller].append(edge)

	var root = _tree.create_item()
	for caller in groups:
		var caller_item = _tree.create_item(root)
		caller_item.set_text(0, caller + "()")
		caller_item.set_metadata(0, {"kind": "caller", "name": caller})
		for edge in groups[caller]:
			var child = _tree.create_item(caller_item)
			child.set_text(0, "  → %s()" % edge.callee)
			child.set_metadata(0, {"kind": "edge", "edge": edge})
			if COLORS.has(edge.call_type):
				child.set_custom_color(0, COLORS[edge.call_type])

func _on_item_selected() -> void:
	var item = _tree.get_selected()
	if item == null:
		return
	var meta = item.get_metadata(0)
	if meta == null or meta.get("kind", "") != "edge":
		return
	var edge = meta["edge"]
	_detail.clear()
	_detail.append_text("[b]Caller:[/b] %s()\n" % edge.caller)
	_detail.append_text("[b]Callee:[/b] %s()\n" % edge.callee)
	_detail.append_text("[b]Type:[/b] %d\n" % edge.call_type)
	_detail.append_text("[b]Line:[/b] %d\n" % edge.site_line)
	if edge.target_object != "":
		_detail.append_text("[b]Target:[/b] %s\n" % edge.target_object)
	if edge.arguments.size() > 0:
		_detail.append_text("[b]Args:[/b] %d\n" % edge.arguments.size())
	_bridge.select_function(edge.callee)

func _on_function_selected(p_name: String) -> void:
	# 联动：如果选中项不是当前高亮函数，则清除选择
	# 简单实现：不做额外处理，保持 Tree 已有选择状态
	pass

func _on_item_rmb(_p_position: Vector2, p_mouse_button_index: int) -> void:
	if p_mouse_button_index == MOUSE_BUTTON_RIGHT and _tree.get_selected() != null:
		_context_menu.popup_on_parent(Rect2(get_global_mouse_position(), Vector2.ZERO))

func _on_context_action(p_id: int) -> void:
	var item = _tree.get_selected()
	if item == null:
		return
	var meta = item.get_metadata(0)
	var name = ""
	if meta != null:
		if meta.get("kind", "") == "caller":
			name = meta.get("name", "")
		elif meta.get("kind", "") == "edge":
			var edge = meta.get("edge", null)
			if edge != null:
				name = edge.callee
	match p_id:
		0: _jump_to_definition(name)
		1: _bridge.select_function(name)
		2: _bridge.select_function(name)

func _jump_to_definition(p_func_name: String) -> void:
	if GDSGraphMainScreen.is_locked:
		return
	if p_func_name.is_empty():
		return
	var result = _bridge.get_current_result()
	if result == null or result.file_path.is_empty():
		return
	for func_node in result.get_all_functions():
		if func_node.name == p_func_name:
			EditorInterface.edit_script(load(result.file_path), func_node.line)
			EditorInterface.set_main_screen_editor("Script")
			return
			return

func _on_search_changed(p_text: String) -> void:
	GDSTreeSearch.highlight(_tree, p_text, 0)
