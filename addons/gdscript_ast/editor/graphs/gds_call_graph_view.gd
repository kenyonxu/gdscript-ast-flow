# addons/gdscript_ast/editor/graphs/gds_call_graph_view.gd
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

const CrossFileKinds = preload("res://addons/gdscript_ast/editor/graphs/gds_cross_file_kinds.gd")

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
func build_logical(p_result: GDScriptAnalysisResult, p_min_degree: int = 0, p_project: GDScriptProjectResult = null) -> Dictionary:
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

	# === 跨文件边 ===
	if p_project != null:
		_add_cross_file_edges(nodes, edges, p_result, p_project)

	return {"nodes": nodes, "edges": edges}

# 跨文件边：当前文件相关的 cross_edges → 外部文件节点 + 出入边（按 Kind 分色 + port）
func _add_cross_file_edges(p_nodes: Dictionary, p_edges: Array, p_result: GDScriptAnalysisResult, p_project: GDScriptProjectResult) -> void:
	var cur_file = p_result.file_path
	for xedge in p_project.cross_edges:
		if xedge.kind not in CrossFileKinds.CALL_GRAPH_KINDS:
			continue
		var is_out = xedge.source_file == cur_file
		var is_in = xedge.target_file == cur_file
		if not is_out and not is_in:
			continue
		var external_file = xedge.source_file if is_in else xedge.target_file
		var local_fn = xedge.source_symbol if is_out else xedge.target_symbol
		if local_fn == "":
			local_fn = "<class>"  # EXTENDS 等类级边
		# 确保本地函数节点存在（可能不在 call_graph 中，但仍需展示）
		_ensure_fn_node(p_nodes, local_fn, p_result)
		# 外部文件节点 key 是 ext_name
		var ext_name = "ext_" + external_file.get_file().get_basename()
		if not p_nodes.has(ext_name):
			p_nodes[ext_name] = {
				"node_name": ext_name, "kind": "external_file",
				"title": external_file.get_file(), "subtitle": "external",
				"degree": 0, "signature": "", "location": external_file,
				"pos": Vector2(900, p_nodes.size() * 90),
				"jump": {"file": external_file, "line": 0},
			}
		var port = CrossFileKinds.KIND_PORT[xedge.kind]
		var fn_node = "fn_" + local_fn
		# p_nodes key: 函数用 local_fn（函数名），外部节点用 ext_name
		_add_kind_slot(p_nodes, local_fn, xedge.kind)
		_add_kind_slot(p_nodes, ext_name, xedge.kind)
		if is_out:
			p_edges.append([fn_node, ext_name, port, port])
		else:
			p_edges.append([ext_name, fn_node, port, port])

func _ensure_fn_node(p_nodes: Dictionary, p_name: String, p_result: GDScriptAnalysisResult) -> void:
	if p_nodes.has(p_name):
		return
	p_nodes[p_name] = {
		"node_name": "fn_" + p_name, "kind": "function",
		"title": p_name, "subtitle": "", "degree": 0,
		"signature": "", "location": "@%s" % p_result.file_path.get_file(),
		"pos": Vector2(150, p_nodes.size() * 90),
		"jump": {"file": p_result.file_path, "line": 0},
	}

# 给节点设 slot_config（全 4 Kind enabled，密集 = KIND_PORT；Godot port 按 enabled 密集编号）。
# p_kind 忽略（总全 4），保留签名兼容调用方。
func _add_kind_slot(p_nodes: Dictionary, p_node_key: String, p_kind: int) -> void:
	var node = p_nodes.get(p_node_key)
	if node == null:
		return
	if not node.has("slot_config") or node.slot_config.slots.size() < CrossFileKinds.CALL_GRAPH_KINDS.size():
		node["slot_config"] = CrossFileKinds.make_slot_config(CrossFileKinds.CALL_GRAPH_KINDS)

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
