# addons/gdscript_util/editor/graphs/gds_signal_graph_view.gd
# 信号流 builder — 信号为中心节点，emit(红)/connect(蓝) 为边

class_name GDSSignalGraphView
extends RefCounted

# 传统 build：直接 add_child 到 GraphEdit（小图兼容）
func build(p_graph: GraphEdit, p_result: GDScriptAnalysisResult, p_min_degree: int = 0) -> void:
	var logical = build_logical(p_result, p_min_degree)
	# 直接实例化所有节点（小图行为不变）
	for name in logical.nodes:
		var info = logical.nodes[name]
		var node = GDSGraphNode.new()
		node.configure(info.kind, info.title, info.subtitle, info.degree, info.get("signature", ""), info.get("location", ""))
		node.name = info.node_name
		node.position_offset = info.pos
		if info.has("jump") and not info.jump.file.is_empty():
			node.set_meta("jump", info.jump)
		p_graph.add_child(node)
	for edge in logical.edges:
		p_graph.connect_node(edge[0], edge[2], edge[1], edge[3])

# 产出逻辑节点/边表（供虚拟化使用）
func build_logical(p_result: GDScriptAnalysisResult, p_min_degree: int = 0) -> Dictionary:
	var nodes: Dictionary = {}
	var edges: Array = []
	if p_result == null or p_result.signal_graph == null:
		return {"nodes": nodes, "edges": edges}
	
	var row := 0
	# 信号节点：居中列
	for sig_name in p_result.signal_graph.signals:
		var info = p_result.signal_graph.signals[sig_name]
		var total_deg = info.emit_sites.size() + info.connect_sites.size()
		if total_deg < p_min_degree:
			continue
		# 信号参数列表
		var params: Array = []
		for p in info.params:
			params.append(str(p))
		var sig_str = "(%s)" % [", ".join(params)] if not params.is_empty() else "()"
		
		var node_name = "sig_" + sig_name
		nodes[sig_name] = {
			"node_name": node_name,
			"kind": "signal",
			"title": sig_name,
			"subtitle": "emits:%d conns:%d" % [info.emit_sites.size(), info.connect_sites.size()],
			"degree": total_deg,
			"signature": sig_str,
			"location": "@%s" % p_result.file_path.get_file(),
			"pos": Vector2(500, row * 100),
			"jump": {"file": p_result.file_path, "line": 0},
			"slot_config": {"left": [0, Color.DODGER_BLUE], "right": [1, Color.RED]},
		}
		row += 1
	
	# emit/connect 站点 → 函数节点 + 边
	var i := 0
	for sig_name in p_result.signal_graph.signals:
		var info = p_result.signal_graph.signals[sig_name]
		var total_deg = info.emit_sites.size() + info.connect_sites.size()
		if total_deg < p_min_degree:
			continue
		
		for site in info.emit_sites:
			var fn_name = site.enclosing_function if site.enclosing_function != "" else "<class>"
			var fn_node_name = _ensure_fn_logical(nodes, fn_name, 150, i * 90, p_result, true)
			edges.append([fn_node_name, "sig_" + sig_name, 0, 0])
			i += 1
		
		for site in info.connect_sites:
			var fn_name = site.enclosing_function if site.enclosing_function != "" else "<class>"
			var fn_node_name = _ensure_fn_logical(nodes, fn_name, 850, i * 90, p_result, false)
			edges.append([fn_node_name, "sig_" + sig_name, 0, 0])
			i += 1
	
	return {"nodes": nodes, "edges": edges}

func _ensure_fn_logical(p_nodes: Dictionary, p_name: String, p_x: int, p_y: int, p_result: GDScriptAnalysisResult, p_is_emit: bool) -> String:
	var name = p_name if p_name != "" else "<class>"
	var node_name = "fn_" + name
	if p_nodes.has(name):
		return node_name
	
	var slot_config = {"left": [0, Color.DODGER_BLUE], "right": [1 if p_is_emit else 0, Color.RED if p_is_emit else Color.DODGER_BLUE]}
	p_nodes[name] = {
		"node_name": node_name,
		"kind": "function",
		"title": name,
		"subtitle": "",
		"degree": 0,
		"signature": "",
		"location": "@%s" % p_result.file_path.get_file(),
		"pos": Vector2(p_x, p_y),
		"jump": {"file": p_result.file_path, "line": 0},
		"slot_config": slot_config,
	}
	return node_name
