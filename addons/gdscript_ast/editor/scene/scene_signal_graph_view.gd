# addons/gdscript_ast/editor/scene/scene_signal_graph_view.gd
# 信号图视角 — 合并场景内+跨场景信号，GraphEdit 渲染 + 联动
# Chunk D

class_name SceneSignalGraphView
extends VBoxContainer

var _bridge: GDSAnalysisBridge = null
var _l10n: GDSL10n = null
var _navigate: Callable = Callable()
var _graph_edit = null  # GDSVirtualGraphEdit
var _filter_box: LineEdit = null
# nkey → {scene, node} 映射，供联动导航
var _nkey_to_nav: Dictionary = {}

func setup(p_bridge, p_l10n, p_navigate: Callable) -> void:
	_bridge = p_bridge
	_l10n = p_l10n
	_navigate = p_navigate
	_build_ui()

func _build_ui() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL

	# 顶部过滤
	var toolbar = HBoxContainer.new()
	toolbar.size_flags_horizontal = SIZE_EXPAND_FILL
	add_child(toolbar)

	_filter_box = LineEdit.new()
	_filter_box.placeholder_text = "Filter by signal name or scene..."
	_filter_box.size_flags_horizontal = SIZE_EXPAND_FILL
	_filter_box.text_changed.connect(_on_filter_changed)
	toolbar.add_child(_filter_box)

	# GraphEdit
	_graph_edit = preload("res://addons/gdscript_ast/editor/graphs/gds_virtual_graph_edit.gd").new()
	_graph_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	_graph_edit.size_flags_vertical = SIZE_EXPAND_FILL
	_graph_edit.custom_minimum_size = Vector2(800, 500)
	_graph_edit.node_selected.connect(_on_graph_node_selected)
	add_child(_graph_edit)

# 合并信号数据 → {nodes, edges} 供 set_graph
# edge 带 same_scene bool 供着色
func build_logical(proj) -> Dictionary:
	var nodes: Dictionary = {}  # key "scene/node" → {id, label, ...}
	var edges: Array = []

	# 跨场景连接（scene_signal_connections）
	for c in proj.scene_signal_connections:
		var fk = c["from_scene"] + "/" + c["from_node"]
		var tk = c["to_scene"] + "/" + c["to_node"]
		nodes[fk] = _make_node(fk)
		nodes[tk] = _make_node(tk)
		edges.append({
			"from": fk, "to": tk,
			"signal": c["signal"],
			"same_scene": false,
			"label": c["signal"],
		})

	# 场景内连接（各 scene.signal_connections）
	for spath in proj.scenes:
		var scene = proj.scenes[spath]
		for conn in scene.signal_connections:
			var fk2 = spath + "/" + conn.from_node
			var tk2 = spath + "/" + conn.to_node
			nodes[fk2] = _make_node(fk2)
			nodes[tk2] = _make_node(tk2)
			edges.append({
				"from": fk2, "to": tk2,
				"signal": conn.signal_name,
				"same_scene": true,
				"label": conn.signal_name,
			})

	return {"nodes": nodes, "edges": edges}

func _make_node(key: String) -> Dictionary:
	return {
		"id": key,
		"label": key,
	}

# 解析 nkey（"scene.tscn/node/path"）→ {"scene": ..., "node": ...}
func _parse_nkey(nkey: String) -> Dictionary:
	var result = {"scene": "", "node": ""}
	# 查找 scene 路径的结尾（.tscn/ 或 .tres/）
	var tscn_pos = nkey.find(".tscn/")
	var tres_pos = nkey.find(".tres/")
	var ext_pos = max(tscn_pos, tres_pos)
	if ext_pos == -1:
		return result
	# .tscn 和 .tres 都是 5 字符
	var scene_path = nkey.substr(0, ext_pos + 5)
	var node_name = nkey.substr(ext_pos + 6)  # 跳过 ".tscn/"
	result.scene = scene_path
	result.node = node_name
	return result

func rebuild() -> void:
	var proj = _bridge.get_project_result()
	if proj == null:
		_graph_edit.set_graph({}, [])
		return

	var logical = build_logical(proj)
	# 应用过滤
	if _filter_box and _filter_box.text.strip_edges() != "":
		var filter_text = _filter_box.text.strip_edges().to_lower()
		var filtered_edges = []
		for e in logical.edges:
			if e.signal.to_lower().contains(filter_text) or \
			   e.from.to_lower().contains(filter_text) or \
			   e.to.to_lower().contains(filter_text):
				filtered_edges.append(e)
		# 保留关联节点
		var kept_nodes = {}
		for e in filtered_edges:
			if logical.nodes.has(e.from):
				kept_nodes[e.from] = logical.nodes[e.from]
			if logical.nodes.has(e.to):
				kept_nodes[e.to] = logical.nodes[e.to]
		logical.edges = filtered_edges
		logical.nodes = kept_nodes

	# 转换为 GDSVirtualGraphEdit 所需格式
	var ges_nodes: Dictionary = {}
	var ges_edges: Array = []
	_nkey_to_nav.clear()

	var col := 0
	var row := 0
	for nkey in logical.nodes:
		var info = logical.nodes[nkey]
		var nav = _parse_nkey(nkey)
		_nkey_to_nav[nkey] = nav

		# 构造唯一 slug
		var node_name_slug = "sig_" + info.label.replace("/", "_").replace(".", "_")
		var slug = node_name_slug
		var counter = 0
		while ges_nodes.has(slug):
			counter += 1
			slug = node_name_slug + "_" + str(counter)

		ges_nodes[slug] = {
			"node_name": slug,
			"kind": "signal",
			"title": info.label,
			"subtitle": nkey,
			"degree": 0,
			"signature": "",
			"location": nkey,
			"pos": Vector2(col * 200, row * 80),
			"jump": {"file": "", "line": 0},
		}
		# 存储 nav 数据供联动查询
		_nkey_to_nav[nkey] = nav
		col += 1
		if col >= 5:
			col = 0
			row += 1

	# slug → nkey 反向映射
	var slug_to_nkey: Dictionary = {}
	for slug in ges_nodes:
		slug_to_nkey[slug] = ges_nodes[slug].location

	for e in logical.edges:
		var from_slug = ""
		var to_slug = ""
		for slug in slug_to_nkey:
			if slug_to_nkey[slug] == e.from:
				from_slug = slug
			if slug_to_nkey[slug] == e.to:
				to_slug = slug
		if from_slug != "" and to_slug != "":
			ges_edges.append([from_slug, to_slug, 0, 0])

	_graph_edit.set_graph(ges_nodes, ges_edges)

func _on_filter_changed(_new_text: String) -> void:
	rebuild()

func _on_graph_node_selected(p_node) -> void:
	if p_node == null or not (p_node is GraphNode):
		return
	# 从 title 恢复 nkey（title 即 info.label = nkey）
	var nkey = str(p_node.title)
	var nav = _nkey_to_nav.get(nkey, {})
	if nav.has("scene") and nav.scene != "" and nav.has("node") and nav.node != "":
		if _navigate.is_valid():
			_navigate.call(nav.scene, nav.node)

func focus_node(_scene_path: String, _node_path: String) -> void:
	# 信号图视角不支持焦点定位（联动目标始终是节点树视角）
	pass
