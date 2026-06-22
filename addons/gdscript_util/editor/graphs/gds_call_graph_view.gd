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

func build(p_graph: GraphEdit, p_result: GDScriptAnalysisResult, p_min_degree: int = 0) -> void:
	if p_result == null or p_result.call_graph == null:
		return
	# 收集所有函数名 + 从 symbol_table 取 FunctionNode（拿签名/行号）
	var func_nodes: Dictionary = {}  # name → FunctionNode
	if p_result.symbol_table != null:
		for sym_name in p_result.symbol_table.symbols:
			var sym = p_result.symbol_table.symbols[sym_name]
			if sym.kind == GDScriptSymbol.Kind.FUNCTION and sym.declaration != null:
				func_nodes[sym.declaration.name] = sym.declaration
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
		var deg = p_result.call_in_degree.get(name, 0) + p_result.call_out_degree.get(name, 0)
		if deg < p_min_degree:
			continue
		var sig := ""
		var loc := ""
		if func_nodes.has(name):
			var fn = func_nodes[name]
			sig = _format_signature(fn)
			loc = "@%s:%d" % [p_result.file_path.get_file(), fn.line]
		var node = GDSGraphNode.new()
		node.configure("function", name, "in:%d out:%d" % [p_result.call_in_degree.get(name, 0), p_result.call_out_degree.get(name, 0)], deg, sig, loc)
		node.name = "fn_" + name
		node.position_offset = Vector2(col * 180, row * 90)
		node.set_meta("jump", {"file": p_result.file_path, "line": func_nodes[name].line if func_nodes.has(name) else 0})
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

func _format_signature(p_fn) -> String:
	# 参数列表
	var params: Array = []
	for p in p_fn.params:
		var pname = p.name
		var ptype = ""
		if p.datatype != null and p.datatype.type_name != "":
			ptype = ": " + p.datatype.type_name
		params.append(pname + ptype)
	var ret = ""
	if p_fn.return_type != null and p_fn.return_type.type_name != "":
		ret = " -> " + p_fn.return_type.type_name
	return "(%s)%s" % [", ".join(params), ret]
