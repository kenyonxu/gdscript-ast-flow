# addons/gdscript_util/editor/graphs/gds_project_graph_view.gd
# 项目级图 builder — 文件/类为节点，CrossFileEdge 汇总为边（粗细按边数=耦合强度）

class_name GDSProjectGraphView
extends RefCounted

# 传统 build：直接 add_child 到 GraphEdit（小图兼容）
func build(p_graph: GraphEdit, p_project: GDScriptProjectResult, p_graph_kind: int, p_min_degree: int = 0) -> void:
	var logical = build_logical(p_project, p_graph_kind, p_min_degree)
	# 直接实例化所有节点（小图行为不变）
	for name in logical.nodes:
		var info = logical.nodes[name]
		var node = GDSGraphNode.new()
		node.configure(info.kind, info.title, info.subtitle, info.degree, info.get("signature", ""), info.get("location", ""))
		node.name = info.node_name
		node.position_offset = info.pos
		if info.has("jump") and not info.jump.file.is_empty():
			node.set_meta("jump", info.jump)
		if info.has("slot_config"):
			var sc = info.slot_config
			node.set_slot(0, true, sc.left[0], sc.left[1], true, sc.right[0], sc.right[1])
		p_graph.add_child(node)
	for edge in logical.edges:
		p_graph.connect_node(edge[0], 0, edge[1], 0)

# 产出逻辑节点/边表（供虚拟化使用）
func build_logical(p_project: GDScriptProjectResult, p_graph_kind: int, p_min_degree: int = 0) -> Dictionary:
	var nodes: Dictionary = {}
	var edges: Array = []
	if p_project == null:
		return {"nodes": nodes, "edges": edges}
	
	if p_graph_kind == 1:
		_build_signal_logical(nodes, edges, p_project, p_min_degree)
	else:
		_build_call_logical(nodes, edges, p_project, p_min_degree)
	
	return {"nodes": nodes, "edges": edges}

# Call 视图: 文件耦合（文件节点 + 跨文件 CALL 边）
func _build_call_logical(p_nodes: Dictionary, p_edges: Array, p_project: GDScriptProjectResult, p_min_degree: int = 0) -> void:
	# 聚合: {(source_file, target_file) → edge_count}，仅 CALL 边
	var pair_counts: Dictionary = {}
	for edge in p_project.cross_edges:
		if edge.kind != GDSCrossFileEdge.Kind.CALL:
			continue
		var key = [edge.source_file, edge.target_file]
		pair_counts[key] = pair_counts.get(key, 0) + 1
	
	# 文件节点
	var col := 0
	var row := 0
	for path in p_project.files:
		var short = path.get_file()
		var refs = p_project.get_files_referencing(path).size()
		if refs < p_min_degree:
			continue
		var file_result = p_project.files[path]
		var funcs_n = file_result.get_all_functions().size()
		var sigs_n = file_result.get_all_signals().size()
		
		var node_name = "file_" + path.get_file().get_basename()
		p_nodes[path] = {
			"node_name": node_name,
			"kind": "file",
			"title": short,
			"subtitle": "[color=lime]← %d ref[/color] | [color=dodger_blue]%d functions[/color] · [color=red]%d signals[/color]" % [refs, funcs_n, sigs_n],
			"degree": refs,
			"signature": "",
			"location": path,
			"pos": Vector2(col * 200, row * 120),
			"jump": {"file": path, "line": 0},
		}
		col += 1
		if col >= 4:
			col = 0
			row += 1
	
	# 边
	for key in pair_counts:
		var from_node = p_nodes.get(key[0])
		var to_node = p_nodes.get(key[1])
		if from_node and to_node:
			p_edges.append([from_node.node_name, to_node.node_name])

# Signal 视图: 信号中心节点 + 跨文件 emit/connect 边
func _build_signal_logical(p_nodes: Dictionary, p_edges: Array, p_project: GDScriptProjectResult, p_min_degree: int = 0) -> void:
	# 预扫: 每个源文件的边种类
	var file_kinds: Dictionary = {}  # file → {emit: bool, connect: bool}
	for edge in p_project.cross_edges:
		if edge.kind not in [GDSCrossFileEdge.Kind.SIGNAL_EMIT, GDSCrossFileEdge.Kind.SIGNAL_CONNECT]:
			continue
		if not file_kinds.has(edge.source_file):
			file_kinds[edge.source_file] = {"emit": false, "connect": false}
		if edge.kind == GDSCrossFileEdge.Kind.SIGNAL_EMIT:
			file_kinds[edge.source_file].emit = true
		else:
			file_kinds[edge.source_file].connect = true
	
	var row := 0
	for edge in p_project.cross_edges:
		if edge.kind not in [GDSCrossFileEdge.Kind.SIGNAL_EMIT, GDSCrossFileEdge.Kind.SIGNAL_CONNECT]:
			continue
		
		# 信号节点（居中列）
		if not p_nodes.has(edge.target_symbol):
			var snode_name = "sig_" + edge.target_symbol
			p_nodes[edge.target_symbol] = {
				"node_name": snode_name,
				"kind": "signal",
				"title": edge.target_symbol,
				"subtitle": "cross-file",
				"degree": 0,
				"signature": "",
				"location": edge.target_symbol,
				"pos": Vector2(600, row * 110),
				"jump": {"file": "", "line": 0},
			}
			row += 1
		
		# 源文件节点（左侧）
		if not p_nodes.has(edge.source_file):
			var fnode_name = "src_" + edge.source_file.get_file().get_basename()
			var kinds = file_kinds[edge.source_file]
			var out_col = Color.DODGER_BLUE
			if kinds.emit and kinds.connect:
				out_col = Color.MEDIUM_PURPLE
			elif kinds.emit:
				out_col = Color.RED
			
			p_nodes[edge.source_file] = {
				"node_name": fnode_name,
				"kind": "file",
				"title": edge.source_file.get_file(),
				"subtitle": "",
				"degree": 0,
				"signature": "",
				"location": edge.source_file,
				"pos": Vector2(150, row * 110),
				"jump": {"file": edge.source_file, "line": 0},
				"slot_config": {"left": [0, Color.DODGER_BLUE], "right": [1, out_col]},
			}
			row += 1
		
		# 边: 文件 → 信号
		var fn = p_nodes[edge.source_file]
		var sn = p_nodes[edge.target_symbol]
		p_edges.append([fn.node_name, sn.node_name])
