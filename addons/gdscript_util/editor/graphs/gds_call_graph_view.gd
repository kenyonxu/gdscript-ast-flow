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
		p_graph.connect_node(edge[0], 0, edge[1], 0)

# 产出逻辑节点/边表（供虚拟化使用）
func build_logical(p_result: GDScriptAnalysisResult, p_min_degree: int = 0) -> Dictionary:
	var nodes: Dictionary = {}
	var edges: Array = []
	if p_result == null or p_result.call_graph == null:
		return {"nodes": nodes, "edges": edges}
	
	# 收集所有函数名 + 从 symbol_table 取 FunctionNode（拿签名/行号）
	var func_nodes: Dictionary = {}  # name → FunctionNode
	if p_result.symbol_table != null:
		for sym_name in p_result.symbol_table.symbols:
			var sym = p_result.symbol_table.symbols[sym_name]
			if sym.kind == GDScriptSymbol.Kind.FUNCTION and sym.declaration != null:
				func_nodes[sym.declaration.name] = sym.declaration
	
	# 节点：所有出现过的 caller/callee
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
		var line := 0
		if func_nodes.has(name):
			var fn = func_nodes[name]
			sig = _format_signature(fn)
			loc = "@%s:%d" % [p_result.file_path.get_file(), fn.line]
			line = fn.line
		
		var node_name = "fn_" + name
		nodes[name] = {
			"node_name": node_name,
			"kind": "function",
			"title": name,
			"subtitle": "in:%d out:%d" % [p_result.call_in_degree.get(name, 0), p_result.call_out_degree.get(name, 0)],
			"degree": deg,
			"signature": sig,
			"location": loc,
			"pos": Vector2(col * 180, row * 90),
			"jump": {"file": p_result.file_path, "line": line},
		}
		col += 1
		if col >= 5:
			col = 0
			row += 1
	
	# 边
	for edge in p_result.call_graph.edges:
		var from_name = "fn_" + edge.caller
		var to_name = "fn_" + edge.callee
		if nodes.has(edge.caller) and nodes.has(edge.callee):
			edges.append([from_name, to_name])
	
	return {"nodes": nodes, "edges": edges}

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
