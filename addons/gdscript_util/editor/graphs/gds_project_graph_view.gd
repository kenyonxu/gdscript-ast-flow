# addons/gdscript_util/editor/graphs/gds_project_graph_view.gd
# 项目级图 builder — 文件/类为节点，CrossFileEdge 汇总为边（粗细按边数=耦合强度）

class_name GDSProjectGraphView
extends RefCounted

func build(p_graph: GraphEdit, p_project: GDScriptProjectResult, p_graph_kind: int) -> void:
	print("[D project_view] build called, project=%s kind=%d" % [p_project, p_graph_kind])
	if p_project == null:
		print("[D project_view] project null — abort")
		return
	print("[D project_view] files=%d cross_edges=%d" % [p_project.files.size(), p_project.cross_edges.size()])
	if p_graph_kind == 1:
		_build_signal_view(p_graph, p_project)
	else:
		_build_call_view(p_graph, p_project)


# Call 视图: 文件耦合（文件节点 + 跨文件 CALL 边，粗细按边数）
func _build_call_view(p_graph: GraphEdit, p_project: GDScriptProjectResult) -> void:
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
		var node = GDSGraphNode.new()
		node.configure("file", short, "refs:%d" % refs, refs)
		node.name = "file_" + path.get_file().get_basename()
		node.position_offset = Vector2(col * 200, row * 120)
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
	print("[D project_view] call view: %d file nodes" % [nodes.size()])


# Signal 视图: 信号中心节点 + 跨文件 emit/connect 边
func _build_signal_view(p_graph: GraphEdit, p_project: GDScriptProjectResult) -> void:
	var sig_nodes: Dictionary = {}   # signal name -> node
	var file_nodes: Dictionary = {}  # source file -> node
	var row := 0
	for edge in p_project.cross_edges:
		if edge.kind not in [GDSCrossFileEdge.Kind.SIGNAL_EMIT, GDSCrossFileEdge.Kind.SIGNAL_CONNECT]:
			continue
		# 信号节点（居中列）
		if not sig_nodes.has(edge.target_symbol):
			var snode = GDSGraphNode.new()
			snode.configure("signal", edge.target_symbol, "cross-file", 0)
			snode.name = "sig_" + edge.target_symbol
			snode.position_offset = Vector2(600, row * 110)
			p_graph.add_child(snode)
			sig_nodes[edge.target_symbol] = snode
			row += 1
		# 源文件节点（左侧）
		if not file_nodes.has(edge.source_file):
			var fnode = GDSGraphNode.new()
			fnode.configure("file", edge.source_file.get_file(), "", 0)
			fnode.name = "src_" + edge.source_file.get_file().get_basename()
			fnode.position_offset = Vector2(150, row * 110)
			p_graph.add_child(fnode)
			file_nodes[edge.source_file] = fnode
		# 边: 文件 → 信号
		var fn = file_nodes[edge.source_file]
		var sn = sig_nodes[edge.target_symbol]
		p_graph.connect_node(fn.name, 0, sn.name, 0)
	print("[D project_view] signal view: %d signals, %d source files" % [sig_nodes.size(), file_nodes.size()])
