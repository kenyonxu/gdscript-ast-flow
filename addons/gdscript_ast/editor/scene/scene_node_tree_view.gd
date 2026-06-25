# addons/gdscript_ast/editor/scene/scene_node_tree_view.gd
# 节点树视角 — 场景列表 + Tree + 节点详情 + 跳转脚本
# Chunk B

class_name SceneNodeTreeView
extends VBoxContainer

var _bridge: GDSAnalysisBridge = null
var _l10n: GDSL10n = null
var _navigate: Callable = Callable()
var _scene_list: ItemList = null
var _tree: Tree = null
var _detail: VBoxContainer = null
var _current_scene: String = ""

func setup(p_bridge, p_l10n, p_navigate: Callable) -> void:
	_bridge = p_bridge
	_l10n = p_l10n
	_navigate = p_navigate
	_build_ui()

func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL

	var hsplit = HSplitContainer.new()
	hsplit.size_flags_horizontal = SIZE_EXPAND_FILL
	hsplit.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(hsplit)

	# 左侧: 场景列表
	var left_panel = VBoxContainer.new()
	left_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	left_panel.size_flags_vertical = SIZE_EXPAND_FILL
	left_panel.custom_minimum_size = Vector2(200, 0)
	hsplit.add_child(left_panel)

	var left_label = Label.new()
	left_label.text = _l10n.t("scope.project")
	left_panel.add_child(left_label)

	_scene_list = ItemList.new()
	_scene_list.size_flags_horizontal = SIZE_EXPAND_FILL
	_scene_list.size_flags_vertical = SIZE_EXPAND_FILL
	_scene_list.item_selected.connect(_on_scene_selected)
	left_panel.add_child(_scene_list)

	# 中间: Tree
	var center_panel = VBoxContainer.new()
	center_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	center_panel.size_flags_vertical = SIZE_EXPAND_FILL
	hsplit.add_child(center_panel)

	_tree = Tree.new()
	_tree.size_flags_horizontal = SIZE_EXPAND_FILL
	_tree.size_flags_vertical = SIZE_EXPAND_FILL
	_tree.columns = 1
	_tree.item_selected.connect(_on_tree_node_selected)
	center_panel.add_child(_tree)

	# 右侧: 节点详情
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = SIZE_EXPAND_FILL
	_detail.size_flags_vertical = SIZE_EXPAND_FILL
	_detail.custom_minimum_size = Vector2(250, 0)
	hsplit.add_child(_detail)

func rebuild() -> void:
	_scene_list.clear()
	_tree.clear()
	_clear_detail()

	var proj = _bridge.get_project_result()
	if proj == null:
		return

	var scene_paths = proj.scenes.keys()
	scene_paths.sort()
	for spath in scene_paths:
		var idx = _scene_list.add_item(spath)
		var scene = proj.scenes[spath]
		# 解析失败标红
		if scene and scene.errors.size() > 0:
			_scene_list.set_item_custom_fg_color(idx, Color.RED)
			_scene_list.set_item_tooltip(idx, "\n".join(scene.errors))

func _on_scene_selected(_idx: int) -> void:
	var selected = _scene_list.get_selected_items()
	if selected.is_empty():
		return
	var idx = selected[0]
	_current_scene = _scene_list.get_item_text(idx)
	_build_tree()

func _build_tree() -> void:
	_tree.clear()
	_clear_detail()
	var proj = _bridge.get_project_result()
	if proj == null or not proj.scenes.has(_current_scene):
		return
	var scene = proj.scenes[_current_scene]
	var root = _tree.create_item()
	for n in scene.root_nodes:
		_add_tree_node(root, n, "")

# 递归构建 Tree + 记录完整 NodePath
func _add_tree_node(parent: TreeItem, node, parent_path: String) -> void:
	var item = _tree.create_item(parent)
	var label = node.name + " (" + node.type + ")"
	if node.script_resource != "":
		label = "📜 " + label
	item.set_text(0, label)
	var full_path = _node_full_path(node, parent_path)
	item.set_metadata(0, {"path": full_path, "node": node})
	for child in node.children:
		_add_tree_node(item, child, full_path)

# 递归构建完整 NodePath
func _node_full_path(node, parent_path: String) -> String:
	if parent_path == "":
		return node.name
	return parent_path + "/" + node.name

func _on_tree_node_selected() -> void:
	var selected = _tree.get_selected()
	if selected == null:
		return
	var meta = selected.get_metadata(0)
	if meta == null or not meta.has("node"):
		return
	_show_detail(meta.node, meta.get("path", ""))

func _show_detail(node, node_path: String = "") -> void:
	_clear_detail()

	_add_detail_line(_l10n.t("detail.name") + ": " + node.name)
	_add_detail_line(_l10n.t("detail.type") + ": " + node.type)
	_add_detail_line(_l10n.t("detail.parent") + ": " + node.parent_path)

	# groups
	var groups_str = ""
	if node.groups and node.groups.size() > 0:
		groups_str = ", ".join(node.groups)
	else:
		groups_str = "(none)"
	_add_detail_line(_l10n.t("detail.groups") + ": " + groups_str)

	# 分隔
	_add_detail_line("---")

	# script_resource — 做成 Button 跳转
	var script_label = Label.new()
	script_label.text = _l10n.t("detail.script") + ":"
	_detail.add_child(script_label)

	if node.script_resource != "" and ResourceLoader.exists(node.script_resource):
		var script_btn = Button.new()
		script_btn.text = node.script_resource
		script_btn.flat = true
		script_btn.pressed.connect(_on_jump_script.bind(node.script_resource))
		_detail.add_child(script_btn)
	elif node.script_resource != "":
		_add_detail_line(node.script_resource + " (not found)")
	else:
		_add_detail_line("(none)")

	# 分隔
	_add_detail_line("---")

	# 信号连接
	var sig_label = Label.new()
	sig_label.text = _l10n.t("detail.signal_connections") + ":"
	_detail.add_child(sig_label)

	var proj = _bridge.get_project_result()
	if proj and proj.scenes.has(_current_scene):
		var scene = proj.scenes[_current_scene]
		var conns = scene.get_connections_for_node(node_path)
		if conns.size() > 0:
			for c in conns:
				var conn_text = "%s: %s → %s.%s" % [c.signal_name, c.from_node, c.to_node, c.method]
				_add_detail_line("  " + conn_text)
		else:
			_add_detail_line("  (none)")

func _add_detail_line(p_text: String) -> void:
	var label = Label.new()
	label.text = p_text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	_detail.add_child(label)

func _clear_detail() -> void:
	for c in _detail.get_children():
		c.queue_free()

func _on_jump_script(path: String) -> void:
	if path == "" or not ResourceLoader.exists(path):
		return
	var scr = load(path)
	if scr:
		EditorInterface.edit_script(scr)

# 供联动调用：选场景→展开树到 node_path→选中
func focus_node(scene_path: String, node_path: String) -> void:
	# 选中对应场景
	var item_count = _scene_list.get_item_count()
	for i in range(item_count):
		if _scene_list.get_item_text(i) == scene_path:
			_scene_list.select(i)
			_current_scene = scene_path
			_build_tree()
			# 展开树到目标节点
			_expand_to_node(node_path)
			return

func _expand_to_node(node_path: String) -> void:
	var parts = node_path.split("/")
	var root = _tree.get_root()
	if root == null:
		return
	if parts.size() > 1:
		# 完整路径: 逐层展开
		_walk_and_expand(root, parts, 0)
	else:
		# 单节点名: 递归搜索整棵树
		_search_and_expand(root, node_path)

func _walk_and_expand(item: TreeItem, parts: Array, depth: int) -> void:
	if depth >= parts.size() or item == null:
		return
	var target = parts[depth]
	var child = item.get_first_child()
	while child:
		var meta = child.get_metadata(0)
		if meta and meta.has("node") and meta.node.name == target:
			child.collapsed = false
			if depth == parts.size() - 1:
				child.select(0)
				_tree.scroll_to_item(child)
			_walk_and_expand(child, parts, depth + 1)
			return
		child = child.get_next()

# 递归搜索：按节点名在整棵树中查找（用于反查联动，短名匹配）
func _search_and_expand(item: TreeItem, target_name: String) -> bool:
	var meta = item.get_metadata(0)
	if meta and meta.has("node") and meta.node.name == target_name:
		item.select(0)
		_tree.scroll_to_item(item)
		# 展开所有祖先节点
		var p = item.get_parent()
		while p:
			p.collapsed = false
			p = p.get_parent()
		return true
	var child = item.get_first_child()
	while child:
		if _search_and_expand(child, target_name):
			return true
		child = child.get_next()
	return false
