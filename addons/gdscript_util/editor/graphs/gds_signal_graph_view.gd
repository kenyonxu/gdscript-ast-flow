# addons/gdscript_util/editor/graphs/gds_signal_graph_view.gd
# 信号流 builder — 信号为中心节点，emit(红)/connect(蓝) 为边

class_name GDSSignalGraphView
extends RefCounted

func build(p_graph: GraphEdit, p_result: GDScriptAnalysisResult) -> void:
	if p_result == null or p_result.signal_graph == null:
		return
	var nodes: Dictionary = {}
	var row := 0
	# 信号节点（居中一列）
	for sig_name in p_result.signal_graph.signals:
		var info = p_result.signal_graph.signals[sig_name]
		var node = GDSGraphNode.new()
		node.configure("signal", sig_name, "emits:%d conns:%d" % [info.emit_sites.size(), info.connect_sites.size()], info.emit_sites.size() + info.connect_sites.size())
		node.name = "sig_" + sig_name
		node.position_offset = Vector2(400, row * 100)
		p_graph.add_child(node)
		nodes[sig_name] = node
		row += 1
	# emit/connect 站点 → 函数节点 + 边
	for sig_name in p_result.signal_graph.signals:
		var info = p_result.signal_graph.signals[sig_name]
		var sig_node = nodes[sig_name]
		var i := 0
		for site in info.emit_sites:
			var fn = _ensure_fn_node(p_graph, nodes, site.enclosing_function, 100, i * 90)
			p_graph.connect_node(fn.name, 0, sig_node.name, 0)
			i += 1
		for site in info.connect_sites:
			var fn = _ensure_fn_node(p_graph, nodes, site.enclosing_function, 700, i * 90)
			p_graph.connect_node(fn.name, 0, sig_node.name, 0)
			i += 1

func _ensure_fn_node(p_graph: GraphEdit, p_nodes: Dictionary, p_name: String, p_x: int, p_y: int) -> GraphNode:
	if p_nodes.has(p_name):
		return p_nodes[p_name]
	var node = GDSGraphNode.new()
	node.configure("function", p_name, "", 0)
	node.name = "fn_" + p_name
	node.position_offset = Vector2(p_x, p_y)
	p_graph.add_child(node)
	p_nodes[p_name] = node
	return node
