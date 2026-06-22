# addons/gdscript_util/editor/graphs/gds_project_graph_view.gd
# 项目级图 builder — 文件/类为节点，CrossFileEdge 汇总为边（粗细按边数=耦合强度）

class_name GDSProjectGraphView
extends RefCounted

func build(p_graph: GraphEdit, p_project: GDScriptProjectResult, p_graph_kind: int) -> void:
	if p_project == null:
		return
	# 聚合: {(source_file, target_file) → edge_count}
	var pair_counts: Dictionary = {}
	for edge in p_project.cross_edges:
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
		var src = key[0]
		var dst = key[1]
		var from_node = nodes.get(src)
		var to_node = nodes.get(dst)
		if from_node and to_node:
			p_graph.connect_node(from_node.name, 0, to_node.name, 0)
