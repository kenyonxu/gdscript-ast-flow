# addons/gdscript_util/editor/graphs/gds_project_graph_view.gd
# 项目级图 builder — 文件/类为节点，CrossFileEdge 汇总为边（粗细按边数=耦合强度）

class_name GDSProjectGraphView
extends RefCounted

func build(p_graph: GraphEdit, p_project: GDScriptProjectResult, p_graph_kind: int, p_min_degree: int = 0) -> void:
	if p_project == null:
		return
	if p_graph_kind == 1:
		_build_signal_view(p_graph, p_project, p_min_degree)
	else:
		_build_call_view(p_graph, p_project, p_min_degree)


# Call 视图: 文件耦合（文件节点 + 跨文件 CALL 边，粗细按边数）
func _build_call_view(p_graph: GraphEdit, p_project: GDScriptProjectResult, p_min_degree: int = 0) -> void:
	# 聚合: {(source_file, target_file) → edge_count}，仅 CALL 边
	var pair_counts: Dictionary = {}
	for edge in p_project.cross_edges:
		if edge.kind != GDSCrossFileEdge.Kind.CALL:
			continue
		var key = [edge.source_file, edge.target_file]
		pair_counts[key] = pair_counts.get(key, 0) + 1
	# 文件节点
	var nodes: Dictionary = {}
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
		var node = GDSGraphNode.new()
		node.configure("file", short, "refs:%d | %d fn, %d sig" % [refs, funcs_n, sigs_n], refs, "", path)
		node.name = "file_" + path.get_file().get_basename()
		node.position_offset = Vector2(col * 200, row * 120)
		node.set_meta("jump", {"file": path, "line": 0})
		p_graph.add_child(node)
		nodes[path] = node
		col += 1
		if col >= 4:
			col = 0
			row += 1
	# 边
	for key in pair_counts:
		var from_node = nodes.get(key[0])
		var to_node = nodes.get(key[1])
		if from_node and to_node:
			p_graph.connect_node(from_node.name, 0, to_node.name, 0)


# Signal 视图: 信号中心节点 + 跨文件 emit/connect 边（emit 红 / connect 蓝）
func _build_signal_view(p_graph: GraphEdit, p_project: GDScriptProjectResult, p_min_degree: int = 0) -> void:
	var sig_nodes: Dictionary = {}   # signal name -> node
	var file_nodes: Dictionary = {}  # source file -> node
	# 预扫: 每个源文件的边种类（emit / connect / both），决定其出 slot 色
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
		if not sig_nodes.has(edge.target_symbol):
			var snode = GDSGraphNode.new()
			snode.configure("signal", edge.target_symbol, "cross-file", 0, "", edge.target_symbol)
			snode.name = "sig_" + edge.target_symbol
			snode.position_offset = Vector2(600, row * 110)
			snode.set_meta("jump", {"file": "", "line": 0})
			p_graph.add_child(snode)
			sig_nodes[edge.target_symbol] = snode
			row += 1
		# 源文件节点（左侧）— 按 emit/connect 着色出 slot（连线色 = from-slot 色）
		if not file_nodes.has(edge.source_file):
			var fnode = GDSGraphNode.new()
			fnode.configure("file", edge.source_file.get_file(), "", 0, "", edge.source_file)
			fnode.name = "src_" + edge.source_file.get_file().get_basename()
			fnode.position_offset = Vector2(150, row * 110)
			fnode.set_meta("jump", {"file": edge.source_file, "line": 0})
			# 出 slot 颜色: 仅 emit→红, 仅 connect→蓝, 两者→紫
			var kinds = file_kinds[edge.source_file]
			var out_col = Color.DODGER_BLUE
			if kinds.emit and kinds.connect:
				out_col = Color.MEDIUM_PURPLE
			elif kinds.emit:
				out_col = Color.RED
			fnode.set_slot(0, true, 0, Color.DODGER_BLUE, true, 1, out_col)
			p_graph.add_child(fnode)
			file_nodes[edge.source_file] = fnode
		# 边: 文件 → 信号
		var fn = file_nodes[edge.source_file]
		var sn = sig_nodes[edge.target_symbol]
		p_graph.connect_node(fn.name, 0, sn.name, 0)
