# addons/gdscript_util/editor/graphs/gds_call_graph_view.gd
# 调用图 builder — 函数为节点，调用为有向边，按 call_type 着色

class_name GDSCallGraphView
extends RefCounted

const COLORS := {
	0: Color.GREEN,          # SELF
	1: Color.DODGER_BLUE,    # SUPER
	2: Color.ORANGE,         # EXTERNAL
	4: Color.MEDIUM_PURPLE,  # SIGNAL_CONNECT
	7: Color.RED,            # EMIT
}

func build(p_graph: GraphEdit, p_result: GDScriptAnalysisResult) -> void:
	if p_result == null or p_result.call_graph == null:
		return
	# 节点：所有出现过的 caller/callee 各一个 GraphNode
	var nodes: Dictionary = {}  # name → GDSGraphNode
	var all_names: Dictionary = {}
	for edge in p_result.call_graph.edges:
		all_names[edge.caller] = true
		all_names[edge.callee] = true
	var col := 0
	var row := 0
	for name in all_names:
		if name == "" or name == "<class>":
			continue
		var node = GDSGraphNode.new()
		var deg = p_result.call_in_degree.get(name, 0) + p_result.call_out_degree.get(name, 0)
		node.configure("function", name, "in:%d out:%d" % [p_result.call_in_degree.get(name, 0), p_result.call_out_degree.get(name, 0)], deg)
		node.name = "fn_" + name
		node.position_offset = Vector2(col * 180, row * 90)
		p_graph.add_child(node)
		nodes[name] = node
		col += 1
		if col >= 5:
			col = 0
			row += 1
	# 边：每条 CallEdge 一条 connection
	for edge in p_result.call_graph.edges:
		var from_node = nodes.get(edge.caller)
		var to_node = nodes.get(edge.callee)
		if from_node == null or to_node == null:
			continue
		p_graph.connect_node(from_node.name, 0, to_node.name, 0)
