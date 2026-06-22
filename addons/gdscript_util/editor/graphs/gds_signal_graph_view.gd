# addons/gdscript_util/editor/graphs/gds_signal_graph_view.gd
# 信号流 builder — 信号为中心节点，emit(红)/connect(蓝) 为边

class_name GDSSignalGraphView
extends RefCounted

func build(p_graph: GraphEdit, p_result: GDScriptAnalysisResult, p_min_degree: int = 0) -> void:
	if p_result == null or p_result.signal_graph == null:
		return
	var nodes: Dictionary = {}
	var row := 0
	# 信号节点：左 slot=connect(蓝 type0)，右 slot=emit(红 type1)
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
		var node = GDSGraphNode.new()
		node.configure("signal", sig_name, "emits:%d conns:%d" % [info.emit_sites.size(), info.connect_sites.size()], total_deg, sig_str, "@%s" % p_result.file_path.get_file())
		node.name = "sig_" + sig_name
		node.position_offset = Vector2(500, row * 100)
		# 关键：双 slot — 左(connect,蓝)，右(emit,红)
		node.set_slot(0, true, 0, Color.DODGER_BLUE, true, 1, Color.RED)
		node.set_meta("jump", {"file": p_result.file_path, "line": 0})
		p_graph.add_child(node)
		nodes[sig_name] = node
		row += 1
	# emit/connect 站点 → 函数节点 + 边
	var i := 0
	for sig_name in p_result.signal_graph.signals:
		var info = p_result.signal_graph.signals[sig_name]
		var sig_node = nodes[sig_name]
		for site in info.emit_sites:
			var fn = _ensure_fn_node(p_graph, nodes, site.enclosing_function, 150, i * 90, p_result)
			# emit: fn 出 → 信号入。连到信号节点的"入"端。
			# GraphEdit 连线色 = from-port 色。要让 emit 边红，需 fn 用红 slot。
			fn.set_slot(0, true, 0, Color.DODGER_BLUE, true, 1, Color.RED)
			p_graph.connect_node(fn.name, 0, sig_node.name, 0)
			i += 1
		for site in info.connect_sites:
			var fn = _ensure_fn_node(p_graph, nodes, site.enclosing_function, 850, i * 90, p_result)
			# connect: fn 蓝 slot
			fn.set_slot(0, true, 0, Color.DODGER_BLUE, true, 0, Color.DODGER_BLUE)
			p_graph.connect_node(fn.name, 0, sig_node.name, 0)
			i += 1

func _ensure_fn_node(p_graph: GraphEdit, p_nodes: Dictionary, p_name: String, p_x: int, p_y: int, p_result: GDScriptAnalysisResult) -> GraphNode:
	if p_name == "":
		p_name = "<class>"
	if p_nodes.has(p_name):
		return p_nodes[p_name]
	var node = GDSGraphNode.new()
	node.configure("function", p_name, "", 0, "", "@%s" % p_result.file_path.get_file())
	node.name = "fn_" + p_name
	node.position_offset = Vector2(p_x, p_y)
	node.set_meta("jump", {"file": p_result.file_path, "line": 0})
	p_graph.add_child(node)
	p_nodes[p_name] = node
	return node
